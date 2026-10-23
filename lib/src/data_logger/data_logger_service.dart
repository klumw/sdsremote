/// Background service for the Data Logger feature.
///
/// Manages a periodic timer that queries the oscilloscope for voltage, duty
/// cycle and frequency measurements on the selected channels via SCPI
/// commands, plus the voltage gain in dB from CH1 (reference) to CH2
/// (signal), and emits [DataLoggerPoint] objects on a broadcast stream.
///
/// SCPI queries use async I/O which yields to the Dart event loop during
/// network waits, keeping UI animations responsive.
library;

import 'dart:async';

import 'data_logger_models.dart';
import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';

/// Service that performs periodic SCPI measurements for the Data Logger.
class DataLoggerService {
  /// Async factory function that returns a connected [Vxi11Instrument].
  final Future<Vxi11Instrument?> Function() _getInstrument;

  Timer? _timer;
  Timer? _finalTimer;
  int _pointCount = 0;
  DateTime? _startTime;
  bool _hasStopped = false;

  /// True while a sample's SCPI sequence is still running. The first sample
  /// can take longer than the sampling interval because of ASET and its
  /// settle delay; starting the next sample meanwhile would interleave SCPI
  /// responses.
  bool _sampleInFlight = false;
  double _probeDividerCh1 = 1.0;
  double _probeDividerCh2 = 1.0;
  double _probeDividerCh3 = 1.0;
  double _probeDividerCh4 = 1.0;

  /// Counter for ASET (auto-setup) commands sent during the current
  /// recording session. Constrained to a maximum of 4 over the entire
  /// recording to prevent excessive auto-setup cycles.
  int _asetCount = 0;

  /// Maximum number of ASET commands allowed per recording session.
  static const int _maxAsetCommands = 4;

  /// Time to wait after ASET before the measurements are queried.
  ///
  /// ASET changes the timebase and vertical scale. The scope keeps answering
  /// PAVA queries from the previous acquisition until a new acquisition with
  /// the auto-set timebase has completed. With a slow timebase this takes
  /// longer than a few seconds: measurements taken 6 s after ASET still showed
  /// the old, clipped values, while the values 10 s after ASET were correct.
  static const Duration _asetSettle = Duration(seconds: 10);

  /// Expose probe divider values for UI display.
  double get probeDividerCh1 => _probeDividerCh1;
  double get probeDividerCh2 => _probeDividerCh2;
  double get probeDividerCh3 => _probeDividerCh3;
  double get probeDividerCh4 => _probeDividerCh4;

  final StreamController<DataLoggerPoint> _pointController =
      StreamController<DataLoggerPoint>.broadcast();

  /// Broadcast stream emitting a new [DataLoggerPoint] on each sample.
  Stream<DataLoggerPoint> get pointStream => _pointController.stream;

  /// Whether the service is currently running.
  bool get isRunning => _timer != null && !_hasStopped;

  /// Number of points collected so far in the current session.
  int get pointCount => _pointCount;

  /// The active configuration.
  DataLoggerConfig? config;

  /// Called when probe divider values are queried from the device,
  /// so the UI layer can update its config copy to display the values.
  void Function()? onProbeDividersUpdated;

  DataLoggerService(this._getInstrument);

  /// Start periodic sampling with the given [cfg].
  ///
  /// Takes the first sample at t=0, then schedules the next sample at
  /// exact multiples of [intervalSeconds] from the start time, up to
  /// and including the configured duration. Uses a single-shot Timer
  /// chain (not Timer.periodic) to prevent overlapping async calls.
  /// Whether the probe dividers have been queried from the device.
  bool _probeDividersQueried = false;

  void start(DataLoggerConfig cfg) {
    stop();
    _hasStopped = false;
    _pointCount = 0;
    _asetCount = 0;
    _sampleInFlight = false;
    _startTime = DateTime.now();
    config = cfg;
    _probeDividersQueried = false;

    // Take the first sample immediately (t=0).
    // Probe dividers are queried as part of the first _doSample call,
    // before the regular SCPI queries — this avoids a race condition
    // where _getInstrument() is called twice simultaneously.
    _sampleAtExactTime(cfg, 0);

    AppLogger(agentName: 'DataLogger', toolName: 'start').log(
      'Data Logger started: interval=${cfg.intervalSeconds}s, '
      'duration=${cfg.durationMinutes}min, '
      'ch1Vpp=${cfg.ch1VppEnabled}, ch1Mean=${cfg.ch1MeanEnabled}, ch1Rms=${cfg.ch1RmsEnabled}, ch1Duty=${cfg.ch1DutyEnabled}, ch1Freq=${cfg.ch1FreqEnabled}, '
      'ch2Vpp=${cfg.ch2VppEnabled}, ch2Mean=${cfg.ch2MeanEnabled}, ch2Rms=${cfg.ch2RmsEnabled}, ch2Duty=${cfg.ch2DutyEnabled}, ch2Freq=${cfg.ch2FreqEnabled}, '
      'ch3Vpp=${cfg.ch3VppEnabled}, ch3Mean=${cfg.ch3MeanEnabled}, ch3Rms=${cfg.ch3RmsEnabled}, ch3Duty=${cfg.ch3DutyEnabled}, ch3Freq=${cfg.ch3FreqEnabled}, '
      'ch4Vpp=${cfg.ch4VppEnabled}, ch4Mean=${cfg.ch4MeanEnabled}, ch4Rms=${cfg.ch4RmsEnabled}, ch4Duty=${cfg.ch4DutyEnabled}, ch4Freq=${cfg.ch4FreqEnabled}, '
      'gainDb=${cfg.gainDbEnabled}',
    );
  }

  /// Schedule a sample at exactly [elapsedTarget] seconds from start.
  /// Uses a single-shot Timer to prevent overlaps.
  void _scheduleAt(DataLoggerConfig cfg, int elapsedTarget) {
    if (_hasStopped) return;
    final now = DateTime.now();
    final delay =
        (elapsedTarget * 1000 - now.difference(_startTime!).inMilliseconds) /
        1000.0;
    if (delay <= 0) {
      // We're already past this target — take it immediately
      _sampleAtExactTime(cfg, elapsedTarget);
    } else {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: (delay * 1000).round()), () {
        _sampleAtExactTime(cfg, elapsedTarget);
      });
    }
  }

  bool _lastSampleDispatched = false;

  /// Perform a single sample at a known elapsed time and schedule the next.
  void _sampleAtExactTime(DataLoggerConfig cfg, int elapsedTarget) {
    if (_hasStopped) return;
    if (_sampleInFlight) {
      // Do not interleave two sample sequences on the same instrument. The
      // missed target is skipped rather than silently corrupting its values.
      AppLogger(agentName: 'DataLogger', toolName: '_sampleAtExactTime').log(
        'Skipping sample at t=${elapsedTarget}s: the previous sample is '
        'still running.',
      );
    } else {
      _sampleInFlight = true;
      // Fire-and-forget the async SCPI work — the next sample is scheduled
      // synchronously based on elapsedTarget, not on SCPI completion.
      _doSample(cfg, elapsedTarget).whenComplete(() {
        _sampleInFlight = false;
        // A skipped final target never reaches _doSample's stop path.
        if (_lastSampleDispatched && _timer == null && !_hasStopped) {
          stop();
        }
      });
    }

    // Schedule the next sample at the next interval boundary.
    final nextTarget = elapsedTarget + cfg.intervalSeconds;
    final totalDuration = cfg.durationMinutes * 60;
    if (nextTarget <= totalDuration) {
      _scheduleAt(cfg, nextTarget);
    } else {
      // All samples dispatched — stop after the last point emits.
      _lastSampleDispatched = true;
    }
  }

  /// The actual SCPI query work — runs async, emits result on stream.
  /// On the first call, also queries probe attenuation (`C<ch>:ATTN?`)
  /// via the same connection so there's no race condition.
  Future<void> _doSample(DataLoggerConfig cfg, int elapsedTarget) async {
    if (_hasStopped) return;

    try {
      final instr = await _getInstrument();
      if (instr == null) {
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_doSample',
        ).log('Instrument not available, skipping sample');
        return;
      }

      // Query probe dividers on first sample via the same connection,
      // avoiding a race on _getInstrument().
      if (!_probeDividersQueried) {
        _probeDividersQueried = true;
        if (_asetCount < _maxAsetCommands) {
          _asetCount++;
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'Sending ASET command ($_asetCount/$_maxAsetCommands) '
            'to auto-setup the instrument...',
          );
          await instr.writeString('ASET');
          // Wait for the auto-setup and the following acquisition to settle.
          await Future.delayed(_asetSettle);
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'ASET settle complete (${_asetSettle.inSeconds}s); '
            'querying measurements...',
          );
        } else {
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'ASET limit reached ($_maxAsetCommands), skipping initial auto-setup.',
          );
        }

        if (cfg.ch1Enabled) {
          final v = await _queryDouble(instr, 'C1:ATTN?');
          if (v != null && v > 0) _probeDividerCh1 = v;
          AppLogger(
            agentName: 'DataLogger',
            toolName: '_doSample',
          ).log('Probe divider CH1: C1:ATTN? => $_probeDividerCh1');
        }
        if (cfg.ch2Enabled) {
          final v = await _queryDouble(instr, 'C2:ATTN?');
          if (v != null && v > 0) _probeDividerCh2 = v;
          AppLogger(
            agentName: 'DataLogger',
            toolName: '_doSample',
          ).log('Probe divider CH2: C2:ATTN? => $_probeDividerCh2');
        }
        if (cfg.ch3Enabled) {
          final v = await _queryDouble(instr, 'C3:ATTN?');
          if (v != null && v > 0) _probeDividerCh3 = v;
          AppLogger(
            agentName: 'DataLogger',
            toolName: '_doSample',
          ).log('Probe divider CH3: C3:ATTN? => $_probeDividerCh3');
        }
        if (cfg.ch4Enabled) {
          final v = await _queryDouble(instr, 'C4:ATTN?');
          if (v != null && v > 0) _probeDividerCh4 = v;
          AppLogger(
            agentName: 'DataLogger',
            toolName: '_doSample',
          ).log('Probe divider CH4: C4:ATTN? => $_probeDividerCh4');
        }

        // Store probe dividers back into the config so the UI can display them.
        config = config?.copyWith(
          probeDividerCh1: _probeDividerCh1,
          probeDividerCh2: _probeDividerCh2,
          probeDividerCh3: _probeDividerCh3,
          probeDividerCh4: _probeDividerCh4,
        );
        // Notify the panel to update its config reference so the dialog
        // shows the real probe values during recording.
        onProbeDividersUpdated?.call();

        // Discard the first measurement after ASET; otherwise a partial
        // response from the still-settling scope becomes the first data point.
        await _primeMeasurements(instr, cfg);
      }

      double? ch1Vpp;
      double? ch1Mean;
      double? ch1Rms;
      double? ch1Duty;
      double? ch1Freq;
      double? ch2Vpp;
      double? ch2Mean;
      double? ch2Rms;
      double? ch2Duty;
      double? ch2Freq;
      double? ch3Vpp;
      double? ch3Mean;
      double? ch3Rms;
      double? ch3Duty;
      double? ch3Freq;
      double? ch4Vpp;
      double? ch4Mean;
      double? ch4Rms;
      double? ch4Duty;
      double? ch4Freq;
      double? gainDb;

      // Check _hasStopped between each query — if stop() was called
      // (e.g. user switched panels), abandon this sample immediately.
      // Only query each measurement if enabled in the configuration.
      if (cfg.ch1VppEnabled) {
        ch1Vpp = await _queryPava(instr, 'C1:PAVA? PKPK');
        if (_hasStopped) return;
      }
      if (cfg.ch1MeanEnabled) {
        ch1Mean = await _queryPava(instr, 'C1:PAVA? MEAN');
        if (_hasStopped) return;
      }
      if (cfg.ch1RmsEnabled) {
        ch1Rms = await _queryPava(instr, 'C1:PAVA? RMS');
        if (_hasStopped) return;
      }
      if (cfg.ch1DutyEnabled) {
        ch1Duty = await _queryPava(instr, 'C1:PAVA? DUTY');
        if (_hasStopped) return;
      }
      if (cfg.ch1FreqEnabled) {
        ch1Freq = await _queryPava(instr, 'C1:PAVA? FREQ');
        if (_hasStopped) return;
      }
      if (cfg.ch2VppEnabled) {
        ch2Vpp = await _queryPava(instr, 'C2:PAVA? PKPK');
        if (_hasStopped) return;
      }
      if (cfg.ch2MeanEnabled) {
        ch2Mean = await _queryPava(instr, 'C2:PAVA? MEAN');
        if (_hasStopped) return;
      }
      if (cfg.ch2RmsEnabled) {
        ch2Rms = await _queryPava(instr, 'C2:PAVA? RMS');
        if (_hasStopped) return;
      }
      if (cfg.ch2DutyEnabled) {
        ch2Duty = await _queryPava(instr, 'C2:PAVA? DUTY');
        if (_hasStopped) return;
      }
      if (cfg.ch2FreqEnabled) {
        ch2Freq = await _queryPava(instr, 'C2:PAVA? FREQ');
        if (_hasStopped) return;
      }
      if (cfg.ch3VppEnabled) {
        ch3Vpp = await _queryPava(instr, 'C3:PAVA? PKPK');
        if (_hasStopped) return;
      }
      if (cfg.ch3MeanEnabled) {
        ch3Mean = await _queryPava(instr, 'C3:PAVA? MEAN');
        if (_hasStopped) return;
      }
      if (cfg.ch3RmsEnabled) {
        ch3Rms = await _queryPava(instr, 'C3:PAVA? RMS');
        if (_hasStopped) return;
      }
      if (cfg.ch3DutyEnabled) {
        ch3Duty = await _queryPava(instr, 'C3:PAVA? DUTY');
        if (_hasStopped) return;
      }
      if (cfg.ch3FreqEnabled) {
        ch3Freq = await _queryPava(instr, 'C3:PAVA? FREQ');
        if (_hasStopped) return;
      }
      if (cfg.ch4VppEnabled) {
        ch4Vpp = await _queryPava(instr, 'C4:PAVA? PKPK');
        if (_hasStopped) return;
      }
      if (cfg.ch4MeanEnabled) {
        ch4Mean = await _queryPava(instr, 'C4:PAVA? MEAN');
        if (_hasStopped) return;
      }
      if (cfg.ch4RmsEnabled) {
        ch4Rms = await _queryPava(instr, 'C4:PAVA? RMS');
        if (_hasStopped) return;
      }
      if (cfg.ch4DutyEnabled) {
        ch4Duty = await _queryPava(instr, 'C4:PAVA? DUTY');
        if (_hasStopped) return;
      }
      if (cfg.ch4FreqEnabled) {
        ch4Freq = await _queryPava(instr, 'C4:PAVA? FREQ');
        if (_hasStopped) return;
      }

      // Gain (dB): voltage gain from CH1 (reference, DUT input) to CH2
      // (signal, DUT output), i.e. 20*log10(CH2/CH1). Both channels are
      // measured with the same parameter (RMS) so the ratio reflects the true
      // voltage gain of the device under test. Each voltage is scaled by its
      // own probe divider, so differing probe attenuations on the two channels
      // cancel out correctly instead of biasing the result. The noise floor is
      // applied to the scaled voltages, i.e. to what is actually present at the
      // probe tips.
      if (cfg.gainDbEnabled) {
        double? ch1Voltage = await _queryPava(instr, 'C1:PAVA? RMS');
        if (_hasStopped) return;
        double? ch2Voltage = await _queryPava(instr, 'C2:PAVA? RMS');
        if (_hasStopped) return;

        if (ch1Voltage != null) ch1Voltage *= _probeDividerCh1;
        if (ch2Voltage != null) ch2Voltage *= _probeDividerCh2;

        gainDb = computeDataLoggerGainDb(ch1Voltage, ch2Voltage);
        AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
          'Gain (dB): C1 reference RMS=$ch1Voltage, C2 signal RMS=$ch2Voltage '
          '=> ${gainDb == null ? 'invalid (RMS below $gainMinRmsVolts V)' : '$gainDb dB'}',
        );
      }

      if (ch1Vpp != null) ch1Vpp = ch1Vpp * _probeDividerCh1;
      if (ch1Mean != null) ch1Mean = ch1Mean * _probeDividerCh1;
      if (ch1Rms != null) ch1Rms = ch1Rms * _probeDividerCh1;
      if (ch2Vpp != null) ch2Vpp = ch2Vpp * _probeDividerCh2;
      if (ch2Mean != null) ch2Mean = ch2Mean * _probeDividerCh2;
      if (ch2Rms != null) ch2Rms = ch2Rms * _probeDividerCh2;
      if (ch3Vpp != null) ch3Vpp = ch3Vpp * _probeDividerCh3;
      if (ch3Mean != null) ch3Mean = ch3Mean * _probeDividerCh3;
      if (ch3Rms != null) ch3Rms = ch3Rms * _probeDividerCh3;
      if (ch4Vpp != null) ch4Vpp = ch4Vpp * _probeDividerCh4;
      if (ch4Mean != null) ch4Mean = ch4Mean * _probeDividerCh4;
      if (ch4Rms != null) ch4Rms = ch4Rms * _probeDividerCh4;

      if (elapsedTarget == 0) {
        // Makes an incorrect first point visible in the log.
        final values = <String>[
          if (ch1Vpp != null) 'ch1Vpp=$ch1Vpp',
          if (ch1Mean != null) 'ch1Mean=$ch1Mean',
          if (ch1Rms != null) 'ch1Rms=$ch1Rms',
          if (ch1Duty != null) 'ch1Duty=$ch1Duty',
          if (ch1Freq != null) 'ch1Freq=$ch1Freq',
          if (ch2Vpp != null) 'ch2Vpp=$ch2Vpp',
          if (ch2Mean != null) 'ch2Mean=$ch2Mean',
          if (ch2Rms != null) 'ch2Rms=$ch2Rms',
          if (ch2Duty != null) 'ch2Duty=$ch2Duty',
          if (ch2Freq != null) 'ch2Freq=$ch2Freq',
          if (ch3Vpp != null) 'ch3Vpp=$ch3Vpp',
          if (ch3Mean != null) 'ch3Mean=$ch3Mean',
          if (ch3Rms != null) 'ch3Rms=$ch3Rms',
          if (ch3Duty != null) 'ch3Duty=$ch3Duty',
          if (ch3Freq != null) 'ch3Freq=$ch3Freq',
          if (ch4Vpp != null) 'ch4Vpp=$ch4Vpp',
          if (ch4Mean != null) 'ch4Mean=$ch4Mean',
          if (ch4Rms != null) 'ch4Rms=$ch4Rms',
          if (ch4Duty != null) 'ch4Duty=$ch4Duty',
          if (ch4Freq != null) 'ch4Freq=$ch4Freq',
          if (gainDb != null) 'gainDb=$gainDb',
        ];
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_doSample',
        ).log('First sample values: ${values.join(', ')}');
      }

      final point = DataLoggerPoint(
        timestamp: DateTime.now(),
        elapsedSeconds: elapsedTarget.toDouble(),
        ch1Vpp: ch1Vpp,
        ch1Mean: ch1Mean,
        ch1Rms: ch1Rms,
        ch1Duty: ch1Duty,
        ch1Freq: ch1Freq,
        ch2Vpp: ch2Vpp,
        ch2Mean: ch2Mean,
        ch2Rms: ch2Rms,
        ch2Duty: ch2Duty,
        ch2Freq: ch2Freq,
        ch3Vpp: ch3Vpp,
        ch3Mean: ch3Mean,
        ch3Rms: ch3Rms,
        ch3Duty: ch3Duty,
        ch3Freq: ch3Freq,
        ch4Vpp: ch4Vpp,
        ch4Mean: ch4Mean,
        ch4Rms: ch4Rms,
        ch4Duty: ch4Duty,
        ch4Freq: ch4Freq,
        gainDb: gainDb,
      );

      _pointController.add(point);
      _pointCount++;
      // Stop immediately after emitting the final point at t=duration.
      if (_lastSampleDispatched) {
        stop();
      }
    } catch (e) {
      AppLogger(
        agentName: 'DataLogger',
        toolName: '_doSample',
      ).log('Sample error: $e');
    }
  }

  /// Discards the first measurement value per enabled parameter after ASET.
  ///
  /// While the auto-setup is still settling the scope can answer a PAVA query
  /// with a partial response (for example just the command echo). Priming
  /// makes sure such a value never becomes the first logged data point.
  Future<void> _primeMeasurements(
    Vxi11Instrument instr,
    DataLoggerConfig cfg,
  ) async {
    final commands = <String>{};
    void addChannel(
      int channel,
      bool vpp,
      bool mean,
      bool rms,
      bool duty,
      bool freq,
    ) {
      if (vpp) commands.add('C$channel:PAVA? PKPK');
      if (mean) commands.add('C$channel:PAVA? MEAN');
      if (rms) commands.add('C$channel:PAVA? RMS');
      if (duty) commands.add('C$channel:PAVA? DUTY');
      if (freq) commands.add('C$channel:PAVA? FREQ');
    }

    addChannel(
      1,
      cfg.ch1VppEnabled,
      cfg.ch1MeanEnabled,
      cfg.ch1RmsEnabled,
      cfg.ch1DutyEnabled,
      cfg.ch1FreqEnabled,
    );
    addChannel(
      2,
      cfg.ch2VppEnabled,
      cfg.ch2MeanEnabled,
      cfg.ch2RmsEnabled,
      cfg.ch2DutyEnabled,
      cfg.ch2FreqEnabled,
    );
    addChannel(
      3,
      cfg.ch3VppEnabled,
      cfg.ch3MeanEnabled,
      cfg.ch3RmsEnabled,
      cfg.ch3DutyEnabled,
      cfg.ch3FreqEnabled,
    );
    addChannel(
      4,
      cfg.ch4VppEnabled,
      cfg.ch4MeanEnabled,
      cfg.ch4RmsEnabled,
      cfg.ch4DutyEnabled,
      cfg.ch4FreqEnabled,
    );
    // Gain (dB) reads the RMS voltages, even when they are not logged
    // separately; prime those queries as well (the set de-duplicates them).
    if (cfg.gainDbEnabled) {
      commands.add('C1:PAVA? RMS');
      commands.add('C2:PAVA? RMS');
    }

    for (final command in commands) {
      if (_hasStopped) return;
      try {
        await instr.queryString(command);
      } catch (e) {
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_primeMeasurements',
        ).log('Priming measurement failed: $command → $e');
      }
    }
  }

  /// Send a SCPI query and extract the numeric value from the response.
  ///
  /// Handles formats with or without a comma separator:
  ///   "C1:PAVA PKPK,5.368E+00V"  → 5.368
  ///   "C1:PAVA PKPK 5.368E+00V"  → 5.368
  ///   "C1:ATTN 10"               → 10.0
  Future<double?> _queryDouble(Vxi11Instrument instr, String cmd) async {
    try {
      final rawResponse = (await instr.queryString(cmd)).trim();
      final value = parseScpiNumber(rawResponse);
      if (value == null) {
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_queryDouble',
        ).log('No numeric value in response: $cmd → "$rawResponse"');
      }
      return value;
    } catch (e) {
      AppLogger(
        agentName: 'DataLogger',
        toolName: '_queryDouble',
      ).log('SCPI query failed: $cmd → $e');
      return null;
    }
  }

  /// Send a PAVA? query and handle `***` (out-of-range) responses.
  ///
  /// When the device returns `***` it means the signal is out of range.
  /// In that case an `ASET` (auto-setup) command is sent, the instrument
  /// is given [_asetSettle] time to settle, and the query is retried **once**.
  Future<double?> _queryPava(Vxi11Instrument instr, String cmd) async {
    try {
      // --- First attempt ---
      String rawResponse = (await instr.queryString(cmd)).trim();

      // If the signal is out of range, auto-setup and retry once.
      if (rawResponse.contains('***')) {
        if (_asetCount < _maxAsetCommands) {
          _asetCount++;
          AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
            'PAVA query returned out-of-range (***): $cmd. '
            'Sending ASET ($_asetCount/$_maxAsetCommands)...',
          );
          // Send auto-setup and wait for the instrument and its new
          // acquisition to settle.
          await instr.writeString('ASET');
          await Future.delayed(_asetSettle);
          // Retry the PAVA query exactly once.
          AppLogger(
            agentName: 'DataLogger',
            toolName: '_queryPava',
          ).log('Retrying PAVA query after ASET: $cmd');
        } else {
          AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
            'ASET limit reached ($_maxAsetCommands), cannot auto-setup '
            'for out-of-range response: $cmd.',
          );
        }
        rawResponse = (await instr.queryString(cmd)).trim();
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_queryPava',
        ).log('PAVA retry response: $cmd → $rawResponse');
      }

      final value = parseScpiNumber(rawResponse);
      if (value == null) {
        AppLogger(
          agentName: 'DataLogger',
          toolName: '_queryPava',
        ).log('No measurement value in response: $cmd → "$rawResponse"');
      }
      return value;
    } catch (e) {
      AppLogger(
        agentName: 'DataLogger',
        toolName: '_queryPava',
      ).log('PAVA query failed: $cmd → $e');
      return null;
    }
  }

  /// Stop the logger immediately. No more samples will be emitted.
  void stop() {
    _hasStopped = true;
    _timer?.cancel();
    _timer = null;
    _finalTimer?.cancel();
    _finalTimer = null;
    AppLogger(
      agentName: 'DataLogger',
      toolName: 'stop',
    ).log('Data Logger stopped. Points collected: $_pointCount');
  }

  /// Dispose all resources (timers, stream controller).
  void dispose() {
    stop();
    _pointController.close();
  }
}
