/// Background service for the Data Logger feature.
///
/// Manages a periodic timer that queries the oscilloscope for peak-to-peak
/// voltage and frequency measurements on the selected channels via SCPI
/// commands, and emits [DataLoggerPoint] objects on a broadcast stream.

import 'dart:async';

import 'data_logger_models.dart';
import '../logger.dart';
import '../dart_vxi11.dart';

/// Service that performs periodic SCPI measurements for the Data Logger.
///
/// Usage:
/// ```dart
/// final service = DataLoggerService(() => myInstrument);
/// service.pointStream.listen((point) { ... });
/// service.start(config);
/// // ... later ...
/// service.stop();
/// service.dispose();
/// ```
class DataLoggerService {
  /// Async factory function that returns a connected [Vxi11Instrument].
  /// The instrument must be usable for SCPI write/read operations.
  final Future<Vxi11Instrument?> Function() _getInstrument;

  Timer? _timer;
  Timer? _finalTimer;
  int _pointCount = 0;
  DateTime? _startTime;
  DateTime? _endTime;
  bool _hasStopped = false;

  final StreamController<DataLoggerPoint> _pointController =
      StreamController<DataLoggerPoint>.broadcast();

  /// Broadcast stream emitting a new [DataLoggerPoint] on each sample.
  Stream<DataLoggerPoint> get pointStream => _pointController.stream;

  /// Whether the service is currently running.
  bool get isRunning => _timer != null && !_hasStopped;

  /// Number of points collected so far in the current session.
  int get pointCount => _pointCount;

  /// The active configuration, or null if not started.
  DataLoggerConfig? config;

  DataLoggerService(this._getInstrument);

  /// Start periodic sampling with the given [cfg].
  ///
  /// Emits the first sample immediately, then repeats every
  /// [cfg.intervalSeconds] until [stop] is called or the total number
  /// of points is reached.
  void start(DataLoggerConfig cfg) {
    stop();
    _hasStopped = false;
    _pointCount = 0;
    _startTime = DateTime.now();
    _endTime = _startTime!.add(Duration(seconds: cfg.durationMinutes * 60));
    config = cfg;

    _timer = Timer.periodic(
      Duration(seconds: cfg.intervalSeconds),
      (_) => _sample(cfg),
    );

    // Take the first sample immediately (t=0).
    _sample(cfg);

    AppLogger(agentName: 'DataLogger', toolName: 'start').log(
      'Data Logger started: interval=${cfg.intervalSeconds}s, '
      'duration=${cfg.durationMinutes}min, '
      'endTime=${_endTime}, '
      'ch1=${cfg.ch1Enabled}, ch2=${cfg.ch2Enabled}, '
      'probe=${cfg.probeDivider}x, totalPoints=${cfg.totalPoints}',
    );
  }

  /// Take one sample, querying the instrument, and emit a [DataLoggerPoint].
  Future<void> _sample(DataLoggerConfig cfg) async {
    if (_hasStopped) return;

    try {
      final instr = await _getInstrument();
      if (instr == null) {
        AppLogger(agentName: 'DataLogger', toolName: '_sample').log(
          'Instrument not available, skipping sample',
        );
        return;
      }

      double? ch1Vpp;
      double? ch1Freq;
      double? ch2Vpp;
      double? ch2Freq;

      // Query CH1
      if (cfg.ch1Enabled) {
        ch1Vpp = await _queryDouble(instr, 'C1:PAVA? PKPK');
        ch1Freq = await _queryDouble(instr, 'C1:PAVA? FREQ');
      }

      // Query CH2
      if (cfg.ch2Enabled) {
        ch2Vpp = await _queryDouble(instr, 'C2:PAVA? PKPK');
        ch2Freq = await _queryDouble(instr, 'C2:PAVA? FREQ');
      }

      // Apply probe divider to voltage readings
      if (ch1Vpp != null) {
        ch1Vpp = ch1Vpp * cfg.probeDivider;
      }
      if (ch2Vpp != null) {
        ch2Vpp = ch2Vpp * cfg.probeDivider;
      }

      final elapsed = DateTime.now().difference(_startTime!);
      final point = DataLoggerPoint(
        timestamp: DateTime.now(),
        elapsedSeconds: elapsed.inMilliseconds / 1000.0,
        ch1Vpp: ch1Vpp,
        ch1Freq: ch1Freq,
        ch2Vpp: ch2Vpp,
        ch2Freq: ch2Freq,
      );

      _pointController.add(point);
      _pointCount++;

      // Check if we've reached or passed the end time.
      // If so, stop. Otherwise, schedule a final sample at the exact end time
      // if the next periodic tick would overshoot.
      if (_endTime != null) {
        final now = DateTime.now();
        if (now.compareTo(_endTime!) >= 0) {
          // We've reached/passed the end — stop.
          stop();
        } else {
          // Schedule a final sample at the exact end time if the next
          // periodic tick would meet or overshoot the end.
          final nextTick = now.add(Duration(seconds: cfg.intervalSeconds));
          if (nextTick.compareTo(_endTime!) >= 0) {
            _finalTimer?.cancel();
            _finalTimer = Timer(_endTime!.difference(now), () => _sample(cfg));
            _timer?.cancel(); // Cancel periodic — final timer handles it
            _timer = null;
          }
        }
      }
    } catch (e) {
      AppLogger(agentName: 'DataLogger', toolName: '_sample').log(
        'Sample error: $e',
      );
    }
  }

  /// Send a SCPI query and parse the response as a double.
  ///
  /// Handles the Siglent SDS response format:
  ///   "C1:PAVA PKPK,3.45E+00V"  → 3.45   (PKPK, value, V unit)
  ///   "C1:PAVA FREQ,9.9989E+02Hz" → 999.89 (FREQ, value, Hz unit)
  ///
  /// Extracts the numeric value by:
  /// 1. Taking everything after the last comma (strips command echo + param name)
  /// 2. Keeping only digits, decimal point, signs, exponent markers
  /// 3. Parsing as double
  Future<double?> _queryDouble(Vxi11Instrument instr, String cmd) async {
    try {
      await instr.writeString(cmd);
      final rawResponse = (await instr.readString()).trim();

      // Format: "<cmd> <param>,<number><unit>"
      // Take everything after the last comma = value + unit
      final lastComma = rawResponse.lastIndexOf(',');
      final valueWithUnit = lastComma >= 0
          ? rawResponse.substring(lastComma + 1).trim()
          : rawResponse;

      // Strip everything that is NOT part of a valid floating-point number:
      // digits, decimal point, sign (+/-), exponent marker (e/E).
      final numericStr =
          valueWithUnit.replaceAll(RegExp(r'[^0-9eE.+\-]'), '');

      return double.tryParse(numericStr);
    } catch (e) {
      AppLogger(agentName: 'DataLogger', toolName: '_queryDouble').log(
        'SCPI query failed: $cmd → $e',
      );
      return null;
    }
  }

  /// Stop the logger. No more samples will be emitted.
  void stop() {
    if (_hasStopped) return;
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
