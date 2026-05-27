/// Background service for the Data Logger feature.
///
/// Manages a periodic timer that queries the oscilloscope for peak-to-peak
/// voltage and frequency measurements on the selected channels via SCPI
/// commands, and emits [DataLoggerPoint] objects on a broadcast stream.
///
/// SCPI queries use async I/O which yields to the Dart event loop during
/// network waits, keeping UI animations responsive.

import 'dart:async';

import 'data_logger_models.dart';
import '../logger.dart';
import '../dart_vxi11.dart';

/// Service that performs periodic SCPI measurements for the Data Logger.
class DataLoggerService {
  /// Async factory function that returns a connected [Vxi11Instrument].
  final Future<Vxi11Instrument?> Function() _getInstrument;

  Timer? _timer;
  Timer? _finalTimer;
  int _pointCount = 0;
  DateTime? _startTime;
  bool _hasStopped = false;
  double _probeDividerCh1 = 1.0;
  double _probeDividerCh2 = 1.0;

  /// Counter for ASET (auto-setup) commands sent during the current
  /// recording session. Constrained to a maximum of 4 over the entire
  /// recording to prevent excessive auto-setup cycles.
  int _asetCount = 0;

  /// Maximum number of ASET commands allowed per recording session.
  static const int _maxAsetCommands = 4;

  /// Expose probe divider values for UI display.
  double get probeDividerCh1 => _probeDividerCh1;
  double get probeDividerCh2 => _probeDividerCh2;

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
      'ch1Vpp=${cfg.ch1VppEnabled}, ch1Freq=${cfg.ch1FreqEnabled}, '
      'ch2Vpp=${cfg.ch2VppEnabled}, ch2Freq=${cfg.ch2FreqEnabled}',
    );
  }

  /// Schedule a sample at exactly [elapsedTarget] seconds from start.
  /// Uses a single-shot Timer to prevent overlaps.
  void _scheduleAt(DataLoggerConfig cfg, int elapsedTarget) {
    if (_hasStopped) return;
    final now = DateTime.now();
    final delay = (elapsedTarget * 1000 - now.difference(_startTime!).inMilliseconds) / 1000.0;
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
    // Fire-and-forget the async SCPI work — the next sample is scheduled
    // synchronously based on elapsedTarget, not on SCPI completion.
    _doSample(cfg, elapsedTarget);

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
  /// On the first call, also queries probe attenuation (C<ch>:ATTN?)
  /// via the same connection so there's no race condition.
  Future<void> _doSample(DataLoggerConfig cfg, int elapsedTarget) async {
    if (_hasStopped) return;

    try {
      final instr = await _getInstrument();
      if (instr == null) {
        AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
          'Instrument not available, skipping sample',
        );
        return;
      }

      // Query probe dividers on first sample via the same connection,
      // avoiding a race on _getInstrument().
      if (!_probeDividersQueried) {
        _probeDividersQueried = true;
        if (_asetCount < _maxAsetCommands) {
          _asetCount++;
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'Sending ASET command (${_asetCount}/$_maxAsetCommands) '
            'to auto-setup the instrument...',
          );
          await instr.writeString('ASET');
          // Wait for the auto-setup to settle on the device.
          await Future.delayed(const Duration(seconds: 5));
        } else {
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'ASET limit reached ($_maxAsetCommands), skipping initial auto-setup.',
          );
        }

        if (cfg.ch1Enabled) {
          final v = await _queryDouble(instr, 'C1:ATTN?');
          if (v != null && v > 0) _probeDividerCh1 = v;
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'Probe divider CH1: C1:ATTN? => $_probeDividerCh1',
          );
        }
        if (cfg.ch2Enabled) {
          final v = await _queryDouble(instr, 'C2:ATTN?');
          if (v != null && v > 0) _probeDividerCh2 = v;
          AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
            'Probe divider CH2: C2:ATTN? => $_probeDividerCh2',
          );
        }

        // Store probe dividers back into the config so the UI can display them.
        config = config?.copyWith(
          probeDividerCh1: _probeDividerCh1,
          probeDividerCh2: _probeDividerCh2,
        );
        // Notify the panel to update its config reference so the dialog
        // shows the real probe values during recording.
        onProbeDividersUpdated?.call();
      }

      double? ch1Vpp;
      double? ch1Freq;
      double? ch2Vpp;
      double? ch2Freq;

      // Check _hasStopped between each query — if stop() was called
      // (e.g. user switched panels), abandon this sample immediately.
      // Only query each measurement if enabled in the configuration.
      if (cfg.ch1VppEnabled) {
        ch1Vpp = await _queryPava(instr, 'C1:PAVA? PKPK');
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
      if (cfg.ch2FreqEnabled) {
        ch2Freq = await _queryPava(instr, 'C2:PAVA? FREQ');
        if (_hasStopped) return;
      }

      if (ch1Vpp != null) ch1Vpp = ch1Vpp * _probeDividerCh1;
      if (ch2Vpp != null) ch2Vpp = ch2Vpp * _probeDividerCh2;

      final point = DataLoggerPoint(
        timestamp: DateTime.now(),
        elapsedSeconds: elapsedTarget.toDouble(),
        ch1Vpp: ch1Vpp,
        ch1Freq: ch1Freq,
        ch2Vpp: ch2Vpp,
        ch2Freq: ch2Freq,
      );

      _pointController.add(point);
      _pointCount++;
      // Stop immediately after emitting the final point at t=duration.
      if (_lastSampleDispatched) {
        stop();
      }
    } catch (e) {
      AppLogger(agentName: 'DataLogger', toolName: '_doSample').log(
        'Sample error: $e',
      );
    }
  }

  /// Send a SCPI query and extract the numeric value from the response.
  ///
  /// Handles formats with or without a comma separator:
  ///   "C1:PAVA PKPK,5.368E+00V"  → 5.368
  ///   "C1:PAVA PKPK 5.368E+00V"  → 5.368
  ///   "C1:ATTN 10"               → 10.0
  ///
  /// Uses a regex to find the LAST floating-point number in the response
  /// string, which is always the measured value.
  Future<double?> _queryDouble(Vxi11Instrument instr, String cmd) async {
    try {
      await instr.writeString(cmd);
      final rawResponse = (await instr.readString()).trim();
      // Find the last number in the response (value is always at the end).
      // Matches: sign, digits, optional decimal, optional exponent.
      final numberRegex =
          RegExp(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', caseSensitive: false);
      final matches = numberRegex.allMatches(rawResponse).toList();
      if (matches.isNotEmpty) {
        return double.tryParse(matches.last.group(0)!);
      }
      return null;
    } catch (e) {
      AppLogger(agentName: 'DataLogger', toolName: '_queryDouble').log(
        'SCPI query failed: $cmd → $e',
      );
      return null;
    }
  }

  /// Send a PAVA? query and handle `***` (out-of-range) responses.
  ///
  /// When the device returns `***` it means the signal is out of range.
  /// In that case an `ASET` (auto-setup) command is sent, the instrument
  /// is given time to settle (5 seconds), and the query is retried **once**.
  Future<double?> _queryPava(Vxi11Instrument instr, String cmd) async {
    try {
      // --- First attempt ---
      await instr.writeString(cmd);
      String rawResponse = (await instr.readString()).trim();

      // If the signal is out of range, auto-setup and retry once.
      if (rawResponse.contains('***')) {
        if (_asetCount < _maxAsetCommands) {
          _asetCount++;
          AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
            'PAVA query returned out-of-range (***): $cmd. '
            'Sending ASET (${_asetCount}/$_maxAsetCommands)...',
          );
          // Send auto-setup and wait for the instrument to settle.
          await instr.writeString('ASET');
          await Future.delayed(const Duration(seconds: 5));
          // Retry the PAVA query exactly once.
          AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
            'Retrying PAVA query after ASET: $cmd',
          );
        } else {
          AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
            'ASET limit reached ($_maxAsetCommands), cannot auto-setup '
            'for out-of-range response: $cmd.',
          );
        }
        await instr.writeString(cmd);
        rawResponse = (await instr.readString()).trim();
        AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
          'PAVA retry response: $cmd → $rawResponse',
        );
      }

      // Parse the last number from the response (value is always at the end).
      final numberRegex =
          RegExp(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', caseSensitive: false);
      final matches = numberRegex.allMatches(rawResponse).toList();
      if (matches.isNotEmpty) {
        return double.tryParse(matches.last.group(0)!);
      }

      return null;
    } catch (e) {
      AppLogger(agentName: 'DataLogger', toolName: '_queryPava').log(
        'PAVA query failed: $cmd → $e',
      );
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
    AppLogger(agentName: 'DataLogger', toolName: 'stop').log(
      'Data Logger stopped. Points collected: $_pointCount',
    );
  }

  /// Dispose all resources (timers, stream controller).
  void dispose() {
    stop();
    _pointController.close();
  }
}
