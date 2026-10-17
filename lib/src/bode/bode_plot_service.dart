/// Bode sweep orchestration.
///
/// Drives the JDS6600 frequency by frequency, reads Vin/Vout/phase from the
/// [BodeScope] and publishes progress through [ChangeNotifier].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_service.dart';
import 'bode_math.dart';
import 'bode_models.dart';
import 'bode_scope.dart';

class BodePlotService extends ChangeNotifier {
  BodePlotService({
    required this.signalGenerator,
    required this.scope,
    this.skipSettling = false,
  });

  final SignalGeneratorService signalGenerator;
  final BodeScope scope;

  /// Test seam: skip the per-point settle delays.
  final bool skipSettling;

  final List<BodePoint> _points = <BodePoint>[];
  BodeStatus _status = BodeStatus.idle;
  BodeConfig? _config;
  int _completedPoints = 0;
  double? _currentFrequencyHz;
  String? _errorMessage;
  bool _stopRequested = false;
  bool _running = false;
  bool _disposed = false;
  Completer<void>? _settleCompleter;

  BodeStatus get status => _status;

  BodeConfig? get config => _config;

  List<BodePoint> get points => List<BodePoint>.unmodifiable(_points);

  int get completedPoints => _completedPoints;

  int get totalPoints => _config?.pointCount ?? 0;

  double? get currentFrequencyHz => _currentFrequencyHz;

  String? get errorMessage => _errorMessage;

  bool get isRunning => _running;

  /// Starts a sweep. Returns when the sweep finishes, is cancelled or fails.
  Future<void> start(BodeConfig config) async {
    if (_running || _disposed) return;

    final validation = validateBodeConfig(config, signalGenerator.deviceInfo);
    if (validation != null) {
      _errorMessage = validation;
      _status = BodeStatus.error;
      _notify();
      return;
    }
    if (!signalGenerator.isConnected) {
      _errorMessage = 'Signal generator is not connected.';
      _status = BodeStatus.error;
      _notify();
      return;
    }

    _config = config;
    _points.clear();
    _completedPoints = 0;
    _currentFrequencyHz = null;
    _errorMessage = null;
    _stopRequested = false;
    _running = true;
    _status = BodeStatus.running;
    _notify();

    try {
      await _run(config);
    } on _BodeCancelled {
      _status = BodeStatus.cancelled;
    } catch (e) {
      _errorMessage = e.toString();
      _status = BodeStatus.error;
      AppLogger(agentName: 'Bode', toolName: 'run').log('Sweep failed: $e');
    } finally {
      await _safeGeneratorState();
      try {
        await scope.restore();
      } catch (e) {
        AppLogger(agentName: 'Bode', toolName: 'restore')
            .log('Scope restore failed: $e');
      }
      _currentFrequencyHz = null;
      _running = false;
      _notify();
    }
  }

  Future<void> _run(BodeConfig config) async {
    final frequencies = buildFrequencyPoints(config);
    final generator = signalGenerator;
    final channel = config.generatorChannel;
    final first = frequencies.first;

    // A signal must be present before ASET can scale the scope sensibly.
    await generator.setWaveform(channel, config.waveform);
    await generator.setAmplitude(channel, config.amplitudeVpp);
    await generator.setOffset(channel, config.offsetV);
    await generator.setFrequency(channel, first);
    await generator.setOutput(channel, true);
    await _settle(effectiveSettling(config, first));
    _throwIfStopped();

    await scope.prepare(
      vinChannel: config.vinChannel,
      voutChannel: config.voutChannel,
      measurePhase: config.measurePhase,
    );
    await _settle(effectiveSettling(config, first));
    _throwIfStopped();

    var autoSetCount = 0;
    double? referenceVin;
    for (var index = 0; index < frequencies.length; index++) {
      _throwIfStopped();
      final frequency = frequencies[index];
      _currentFrequencyHz = frequency;

      if (index > 0) {
        await generator.setFrequency(channel, frequency);
        await _settle(effectiveSettling(config, frequency));
        _throwIfStopped();
      }

      var reading = await _readStable(config, frequency, referenceVin);

      if (reading.outOfRange && autoSetCount < 2) {
        autoSetCount++;
        AppLogger(agentName: 'Bode', toolName: 'autoSet').log(
          'f=${frequency.toStringAsFixed(1)} Hz out of range; '
          'ASET retry $autoSetCount/2',
        );
        await scope.autoSet();
        await _settle(effectiveSettling(config, frequency));
        _throwIfStopped();
        reading = await _readStable(config, frequency, referenceVin);
      }

      final suspicious = _isSuspiciousVin(reading, referenceVin, config);
      if (!suspicious && reading.vinRms != null) {
        referenceVin = referenceVin == null
            ? reading.vinRms
            : referenceVin * 0.8 + reading.vinRms! * 0.2;
      }

      final gain = bodeGainDb(reading.vinRms, reading.voutRms);
      final valid = gain != null && !suspicious;
      final point = BodePoint(
        frequencyHz: frequency,
        vinRms: reading.vinRms,
        voutRms: reading.voutRms,
        gainDb: gain,
        phaseDeg: reading.phaseDeg,
        delaySeconds: reading.delaySeconds,
        phaseSource: reading.phaseSource,
        valid: valid,
        note: reading.error ??
            (suspicious
                ? 'Unstable measurement (Vin collapsed to '
                    '${reading.vinRms?.toStringAsFixed(4)} V); retried'
                : gain == null
                    ? 'No valid gain (Vin below threshold or missing '
                        'measurement)'
                    : null),
      );
      _points.add(point);
      _completedPoints = index + 1;
      _notify();
    }

    _status = BodeStatus.completed;
  }

  /// Reads one point and retries when the scope returns a transiently
  /// implausible input voltage (the RMS measurements occasionally collapse
  /// to the noise floor for one acquisition).
  Future<BodeReading> _readStable(
    BodeConfig config,
    double frequency,
    double? referenceVin,
  ) async {
    var reading = await scope.read(
      vinChannel: config.vinChannel,
      voutChannel: config.voutChannel,
      frequencyHz: frequency,
      measurePhase: config.measurePhase,
    );
    var retries = 0;
    while (retries < 2 &&
        _isSuspiciousVin(reading, referenceVin, config)) {
      retries++;
      AppLogger(agentName: 'Bode', toolName: 'glitch').log(
        'f=${frequency.toStringAsFixed(1)} Hz suspicious Vin='
        '${reading.vinRms}; retry $retries/2',
      );
      await _settle(const Duration(milliseconds: 300));
      _throwIfStopped();
      reading = await scope.read(
        vinChannel: config.vinChannel,
        voutChannel: config.voutChannel,
        frequencyHz: frequency,
        measurePhase: config.measurePhase,
      );
    }
    return reading;
  }

  /// A reading is implausible when Vin falls far below the running reference
  /// (or, for the first point, far below the expected generator RMS).
  ///
  /// A passive DUT cannot lower the voltage at the scope input by more than
  /// 12 dB in this setup; the observed glitches drop it by ~30 dB.
  bool _isSuspiciousVin(
    BodeReading reading,
    double? referenceVin,
    BodeConfig config,
  ) {
    if (reading.outOfRange) return false;
    final vin = reading.vinRms;
    if (vin == null) return true;
    if (referenceVin != null) {
      return vin < referenceVin * 0.25;
    }
    final expected = _expectedVinRms(config);
    return expected != null && vin < expected * 0.1;
  }

  /// Expected RMS at the scope input for the configured generator amplitude,
  /// or null for waveforms whose RMS cannot be derived from the Vpp value.
  double? _expectedVinRms(BodeConfig config) {
    switch (config.waveform.family) {
      case Jds6600WaveformFamily.sine:
        return config.amplitudeVpp / (2 * math.sqrt(2));
      case Jds6600WaveformFamily.square:
        return config.amplitudeVpp / 2;
      case Jds6600WaveformFamily.triangle:
        return config.amplitudeVpp / (2 * math.sqrt(3));
      case Jds6600WaveformFamily.pulse:
      case Jds6600WaveformFamily.other:
      case Jds6600WaveformFamily.arbitrary:
        return null;
    }
  }

  Future<void> _settle(Duration duration) async {
    if (skipSettling || duration <= Duration.zero || _stopRequested) return;
    final completer = Completer<void>();
    _settleCompleter = completer;
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } finally {
      timer.cancel();
      if (identical(_settleCompleter, completer)) _settleCompleter = null;
    }
  }

  void _throwIfStopped() {
    if (_stopRequested) {
      _status = BodeStatus.cancelled;
      throw const _BodeCancelled();
    }
  }

  Future<void> _safeGeneratorState() async {
    final generator = signalGenerator;
    try {
      await generator.setOutput(1, false);
    } catch (_) {}
    try {
      await generator.setOutput(2, false);
    } catch (_) {}
    try {
      await generator.stopActions();
    } catch (_) {}
  }

  /// Requests cancellation. The current settle delay is interrupted; the
  /// running sweep turns the generator outputs off and stops.
  Future<void> stop() async {
    _stopRequested = true;
    final completer = _settleCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Clears results when no sweep is running.
  void clear() {
    if (_running) return;
    _points.clear();
    _completedPoints = 0;
    _status = BodeStatus.idle;
    _errorMessage = null;
    _currentFrequencyHz = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _stopRequested = true;
    _disposed = true;
    final completer = _settleCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    super.dispose();
  }
}

class _BodeCancelled implements Exception {
  const _BodeCancelled();
}
