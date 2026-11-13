/// Bode sweep orchestration.
///
/// Drives the configured signal generator (JDS6600 or FY6900) frequency by
/// frequency, reads Vin/Vout/phase from the [BodeScope] and publishes progress
/// through [ChangeNotifier].
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
import 'vxi11_bode_scope.dart';

class BodePlotService extends ChangeNotifier {
  BodePlotService({
    required this.signalGenerator,
    required this.scope,
    this.skipSettling = false,
  }) {
    // The input channel's V/div is changed while the generator drive is
    // paused; the SDS1104X-E can freeze CH1 on a V/div write during an active
    // drive. Only the VXI-11 scope implements this pause hook.
    final bodeScope = scope;
    if (bodeScope is Vxi11BodeScope) {
      bodeScope.pauseSignal = _pauseGeneratorForScaleChange;
    }
  }

  Future<void> _pauseGeneratorForScaleChange(bool enabled) async {
    final config = _config;
    if (config == null || config.mode != BodeMode.amplitudeSweep) return;
    await signalGenerator.setOutput(config.generatorChannel, enabled);
  }

  final SignalGeneratorService signalGenerator;
  final BodeScope scope;

  /// Test seam: skip the per-point settle delays.
  final bool skipSettling;

  final List<BodePoint> _points = <BodePoint>[];
  BodeStatus _status = BodeStatus.idle;
  BodeConfig? _config;

  /// Input V/div fixed for the current amplitude sweep, if any.
  double? _fixedInputVdiv;

  /// Peak-to-peak noise floor of the input channel at the fixed scale.
  double? _vinNoiseVpp;

  /// Raw measured Vin of the previous amplitude point, for clipping checks.
  double? _lastMeasuredVinVpp;
  double _lastAmplitudeVpp = 0;
  int _completedPoints = 0;
  double? _currentFrequencyHz;
  double? _currentAmplitudeVpp;
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

  /// Generator amplitude of the point currently being measured, in Vpp.
  ///
  /// Only set while an amplitude sweep is running.
  double? get currentAmplitudeVpp => _currentAmplitudeVpp;

  String? get errorMessage => _errorMessage;

  bool get isRunning => _running;

  /// Starts a sweep. Returns when the sweep finishes, is cancelled or fails.
  Future<void> start(BodeConfig config) async {
    if (_running || _disposed) return;

    final validation = validateBodeConfig(config, signalGenerator.deviceInfo);
    if (validation != null) {
      AppLogger(
        agentName: 'Bode',
        toolName: 'validate',
      ).error('Sweep rejected: $validation');
      _errorMessage = validation;
      _status = BodeStatus.error;
      _notify();
      return;
    }
    if (!signalGenerator.isConnected) {
      const message = 'Signal generator is not connected.';
      AppLogger(
        agentName: 'Bode',
        toolName: 'validate',
      ).error('Sweep rejected: $message');
      _errorMessage = message;
      _status = BodeStatus.error;
      _notify();
      return;
    }

    _config = config;
    if (config.mode != BodeMode.amplitudeSweep) _fixedInputVdiv = null;
    _vinNoiseVpp = null;
    _lastMeasuredVinVpp = null;
    _lastAmplitudeVpp = 0;
    _points.clear();
    _completedPoints = 0;
    _currentFrequencyHz = null;
    _currentAmplitudeVpp = null;
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
      AppLogger(agentName: 'Bode', toolName: 'run').error('Sweep failed: $e');
    } finally {
      await _safeGeneratorState();
      try {
        await scope.restore();
      } catch (e) {
        AppLogger(
          agentName: 'Bode',
          toolName: 'restore',
        ).error('Scope restore failed: $e');
      }
      _currentFrequencyHz = null;
      _currentAmplitudeVpp = null;
      _running = false;
      _notify();
    }
  }

  Future<void> _run(BodeConfig config) async {
    if (config.mode == BodeMode.amplitudeSweep) {
      await _runAmplitudeSweep(config);
      return;
    }
    // A cancellation can arrive before the first point. Do not touch the
    // generator or the scope in that case.
    _throwIfStopped();
    final frequencies = buildFrequencyPoints(config);
    final generator = signalGenerator;
    final channel = config.generatorChannel;
    final first = frequencies.first;
    AppLogger(agentName: 'Bode', toolName: 'run').log(
      'Generator config: channel=$channel, waveform=${config.waveform.name}, '
      'amplitude=${config.amplitudeVpp} Vpp, offset=${config.offsetV} V, '
      'useCurrentGeneratorSettings=${config.useCurrentGeneratorSettings}, '
      'range=${config.startFrequencyHz}..${config.stopFrequencyHz} Hz, '
      'points=${frequencies.length}',
    );

    // The generator is configured before ASET. When the current settings are
    // kept, only the frequency is stepped.
    if (!config.useCurrentGeneratorSettings) {
      await generator.setWaveform(channel, config.waveform);
      await generator.setAmplitude(channel, config.amplitudeVpp);
      await generator.setOffset(channel, config.offsetV);
    }
    await generator.setFrequency(channel, first);
    await generator.setOutput(channel, true);
    await _settle(effectiveSettling(config, first));
    _throwIfStopped();

    await scope.prepare(
      vinChannel: config.vinChannel,
      voutChannel: config.voutChannel,
      measurePhase: config.measurePhase,
    );
    _throwIfStopped();

    // The generator is switched on and configured at the first frequency
    // here. A fresh ASET scales and triggers the scope for the actual signal
    // before the first measurement point.
    await scope.autoSet();
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

      final belowThreshold = bodeBelowThresholdNote(
        reading.vinRms,
        reading.voutRms,
      );
      final suspicious = _isSuspiciousVin(reading, referenceVin, config);
      if (!suspicious && belowThreshold == null && reading.vinRms != null) {
        referenceVin = referenceVin == null
            ? reading.vinRms
            : referenceVin * 0.8 + reading.vinRms! * 0.2;
      }

      // Below 5 mV on either channel the reading is dominated by noise, so
      // no gain is recorded and the point is not drawn in the chart.
      final gain = belowThreshold == null
          ? bodeGainDb(reading.vinRms, reading.voutRms)
          : null;
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
        note:
            reading.error ??
            belowThreshold ??
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

  /// Sweeps the generator amplitude at a fixed frequency.
  Future<void> _runAmplitudeSweep(BodeConfig config) async {
    _throwIfStopped();
    final amplitudes = buildAmplitudePoints(config);
    final generator = signalGenerator;
    final channel = config.generatorChannel;
    final frequency = config.sweepFrequencyHz;
    AppLogger(agentName: 'Bode', toolName: 'run').log(
      'Amplitude sweep: channel=$channel, waveform=${config.waveform.name}, '
      'frequency=$frequency Hz, amplitude=${amplitudes.first}..'
      '${amplitudes.last} Vpp, offset=${config.offsetV} V, '
      'points=${amplitudes.length}',
    );

    // The fixed frequency, waveform and offset are configured once; only the
    // amplitude is stepped during the sweep.
    await generator.setWaveform(channel, config.waveform);
    await generator.setFrequency(channel, frequency);
    await generator.setOffset(channel, config.offsetV);
    await generator.setAmplitude(channel, amplitudes.first);
    await generator.setOutput(channel, true);
    await _settle(effectiveSettling(config, frequency));
    _throwIfStopped();

    await scope.prepare(
      vinChannel: config.vinChannel,
      voutChannel: config.voutChannel,
      measurePhase: false,
    );
    _throwIfStopped();
    await scope.autoSet();
    _throwIfStopped();

    // Fix the input scale once for the largest sweep amplitude and keep it
    // for every point. Changing CH1's V/div mid-sweep can freeze the input
    // channel on the SDS1104X-E. The fixed scale resolves only the upper part
    // of a wide amplitude sweep; points whose input stays below its
    // resolution are marked invalid instead of recording a distorted gain.
    final bodeScope = scope;
    final maxVpp = amplitudes.last;
    final fixedVdiv = amplitudeSweepVdiv(maxVpp);
    _fixedInputVdiv = fixedVdiv;
    if (bodeScope is Vxi11BodeScope) {
      await bodeScope.lockInputScaleFor(fixedVdiv, verifyVpp: amplitudes.first);
      _fixedInputVdiv = bodeScope.inputVdiv ?? fixedVdiv;
      // The fixed scale adds its noise peaks to every Vin PKPK measurement;
      // measure that floor once so each point can be corrected.
      _vinNoiseVpp = await bodeScope.measureVinNoiseVpp();
      // The noise measurement switches the generator off and on again; let
      // the first amplitude settle before the sweep starts.
      await Future<void>.delayed(const Duration(seconds: 2));
      _throwIfStopped();
    }

    var autoSetCount = 0;
    for (var index = 0; index < amplitudes.length; index++) {
      _throwIfStopped();
      final amplitude = amplitudes[index];
      _currentFrequencyHz = frequency;
      _currentAmplitudeVpp = amplitude;

      if (index > 0) {
        await generator.setAmplitude(channel, amplitude);
        await _settle(effectiveSettling(config, frequency));
        _throwIfStopped();
      }

      // Predict the output level from the previous point so the output
      // channel is scaled before the reading. The input channel keeps its
      // fixed scale; the output scale follows the sweep. Without the
      // prediction a signal that outgrows its V/div between two points is
      // clipped and can still report a plausible peak-to-peak value.
      double? expectedVoutVpp;
      final lastPoint = _points.isEmpty ? null : _points.last;
      final lastAmplitude = lastPoint?.amplitudeVpp;
      final lastVout = lastPoint?.voutVpp;
      if (index > 0 &&
          lastPoint != null &&
          lastPoint.valid &&
          lastAmplitude != null &&
          lastAmplitude > 0 &&
          lastVout != null &&
          lastVout > 0) {
        expectedVoutVpp = lastVout * amplitude / lastAmplitude;
      }

      var reading = await _readStableAmplitude(
        config,
        frequency,
        amplitude,
        expectedVoutVpp,
      );

      if (reading.outOfRange && autoSetCount < 2) {
        autoSetCount++;
        AppLogger(agentName: 'Bode', toolName: 'autoSet').log(
          'Amplitude=${formatAmplitudeVpp(amplitude)} out of range; '
          'ASET retry $autoSetCount/2',
        );
        await scope.autoSet();
        await _settle(effectiveSettling(config, frequency));
        _throwIfStopped();
        final recovered = scope;
        if (recovered is Vxi11BodeScope) {
          // ASET changed the input scale; restore the locked scale the sweep
          // derives its gain from.
          final locked = _fixedInputVdiv;
          if (locked != null) {
            await recovered.lockInputScaleFor(locked, verifyVpp: amplitude);
          }
          _fixedInputVdiv = recovered.inputVdiv ?? _fixedInputVdiv;
        }
        reading = await _readStableAmplitude(
          config,
          frequency,
          amplitude,
          expectedVoutVpp,
        );
      }

      // The fixed scale's noise peaks add a constant amount to the Vin PKPK;
      // remove that floor before the value is displayed and used for the
      // clipping checks.
      final correctedVinVpp = reading.vinVpp == null
          ? null
          : noiseCorrectedVpp(reading.vinVpp!, _vinNoiseVpp);
      // A fixed input scale can only resolve the upper part of a wide
      // amplitude sweep. Below about half a division the RMS value is
      // dominated by the scope's noise and quantisation: its ratio bends
      // upwards and would fake a level-dependent gain at the sweep start.
      final measuredDivisions =
          _fixedInputVdiv == null || correctedVinVpp == null
          ? null
          : correctedVinVpp / _fixedInputVdiv!;
      final resolvable =
          _fixedInputVdiv == null ||
          (amplitude / _fixedInputVdiv! >= 0.2 &&
              (measuredDivisions == null || measuredDivisions >= 0.5));
      // A measured input that stops growing while the generator amplitude
      // rises is clipped by the fixed scale (or otherwise unusable).
      final stuckVin =
          _lastMeasuredVinVpp != null &&
          correctedVinVpp != null &&
          correctedVinVpp <= _lastMeasuredVinVpp! * 1.02 &&
          amplitude > _lastAmplitudeVpp * 1.05 &&
          correctedVinVpp < amplitude * 0.9;
      final measuredVinUsable =
          resolvable &&
          !stuckVin &&
          correctedVinVpp != null &&
          correctedVinVpp > 0;
      _lastMeasuredVinVpp = correctedVinVpp;
      _lastAmplitudeVpp = amplitude;
      // The peak-to-peak values are recorded for diagnostics. The gain itself
      // is derived from the RMS values: unlike peak-to-peak they are not
      // inflated by the noise peaks of a channel's V/div, so a through
      // connection measures the same gain at every amplitude even though the
      // input and output channels run on different scales.
      final effectiveVinVpp = measuredVinUsable ? correctedVinVpp : amplitude;
      final effectiveVoutVpp =
          reading.voutVpp ??
          (reading.voutRms == null
              ? null
              : reading.voutRms! * 2 * math.sqrt(2));
      final expectedVinRms = _expectedVinRms(config, amplitude);
      final effectiveVinRms = measuredVinUsable
          ? reading.vinRms
          : expectedVinRms;
      final effectiveVoutRms = reading.voutRms;
      final belowThreshold = bodeBelowThresholdNote(
        effectiveVinRms,
        effectiveVoutRms,
      );
      // Amplitude-sweep points below 1 Vpp on either channel carry no gain:
      // at that level the fixed input scale's noise and quantisation dominate
      // the ratio. The point stays in the table with a note so the gap is
      // explained, but it is not drawn in the plot.
      final belowAmplitudeSweepMinimum = bodeBelowAmplitudeSweepVppNote(
        correctedVinVpp,
        effectiveVoutVpp,
      );
      final suspicious =
          measuredVinUsable &&
          _isSuspiciousAmplitudeVin(reading, config, amplitude);
      // Only a measured input may form the gain. The generator setpoint is
      // not a substitute: its actual output can differ from the setpoint by a
      // fixed attenuation or offset, which would fake a level-dependent gain
      // at the start of the sweep.
      final gain =
          measuredVinUsable &&
              belowThreshold == null &&
              belowAmplitudeSweepMinimum == null
          ? bodeGainDb(effectiveVinRms, effectiveVoutRms)
          : null;
      final valid = gain != null && !suspicious;
      final point = BodePoint(
        frequencyHz: frequency,
        amplitudeVpp: amplitude,
        vinRms: effectiveVinRms,
        voutRms: effectiveVoutRms,
        vinVpp: effectiveVinVpp,
        voutVpp: effectiveVoutVpp,
        gainDb: gain,
        valid: valid,
        note:
            reading.error ??
            belowThreshold ??
            belowAmplitudeSweepMinimum ??
            (!measuredVinUsable && reading.vinRms != null
                ? 'Vin below the fixed input scale resolution; no gain '
                      'recorded'
                : suspicious
                ? 'Unstable measurement (Vin collapsed to '
                      '${reading.vinRms?.toStringAsFixed(4)} V at '
                      '${formatAmplitudeVpp(amplitude)}); retried'
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

  /// Reads one amplitude-sweep point and retries a collapsed input.
  Future<BodeReading> _readStableAmplitude(
    BodeConfig config,
    double frequency,
    double amplitude,
    double? expectedVoutVpp,
  ) async {
    var reading = await scope.read(
      vinChannel: config.vinChannel,
      voutChannel: config.voutChannel,
      frequencyHz: frequency,
      measurePhase: false,
      measureVpp: true,
      expectedVinVpp: amplitude,
      expectedVoutVpp: expectedVoutVpp,
    );
    var retries = 0;
    while (retries < 2 &&
        _isSuspiciousAmplitudeVin(reading, config, amplitude)) {
      retries++;
      AppLogger(agentName: 'Bode', toolName: 'glitch').log(
        'Amplitude=${formatAmplitudeVpp(amplitude)} suspicious Vin='
        '${reading.vinRms}; retry $retries/2',
      );
      await _settle(const Duration(milliseconds: 300));
      _throwIfStopped();
      reading = await scope.read(
        vinChannel: config.vinChannel,
        voutChannel: config.voutChannel,
        frequencyHz: frequency,
        measurePhase: false,
        measureVpp: true,
        expectedVinVpp: amplitude,
        expectedVoutVpp: expectedVoutVpp,
      );
    }
    return reading;
  }

  /// A reading is implausible when Vin falls far below the RMS value expected
  /// from the generator's amplitude setpoint.
  bool _isSuspiciousAmplitudeVin(
    BodeReading reading,
    BodeConfig config,
    double amplitudeVpp,
  ) {
    if (reading.outOfRange) return false;
    final fixed = _fixedInputVdiv;
    if (fixed != null && amplitudeVpp / fixed < 0.2) return false;
    final vin = reading.vinRms;
    if (vin == null) return true;
    final expected = _expectedVinRms(config, amplitudeVpp);
    return expected != null && vin < expected * 0.1;
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
    while (retries < 2 && _isSuspiciousVin(reading, referenceVin, config)) {
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
    final expected = _expectedVinRms(config, config.amplitudeVpp);
    return expected != null && vin < expected * 0.1;
  }

  /// Expected RMS at the scope input for the configured generator amplitude,
  /// or null for waveforms whose RMS cannot be derived from the Vpp value.
  double? _expectedVinRms(BodeConfig config, double amplitudeVpp) {
    switch (config.waveform.family) {
      case Jds6600WaveformFamily.sine:
        return amplitudeVpp / (2 * math.sqrt(2));
      case Jds6600WaveformFamily.square:
        return amplitudeVpp / 2;
      case Jds6600WaveformFamily.triangle:
        return amplitudeVpp / (2 * math.sqrt(3));
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
    if (_config?.turnOffOutputsAfterSweep ?? true) {
      try {
        await generator.setOutput(1, false);
      } catch (_) {}
      try {
        await generator.setOutput(2, false);
      } catch (_) {}
    }
    try {
      await generator.stopActions();
    } catch (_) {}
  }

  /// Requests cancellation. The current settle delay is interrupted; the
  /// running sweep turns the generator outputs off (unless the configuration
  /// keeps them on) and stops.
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
    _currentAmplitudeVpp = null;
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
