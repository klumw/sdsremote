/// Mathematical reference waveform generator for all ten signal types.
///
/// The generator produces ideal references and configurable non-ideal
/// variants (finite edges, noise, damping, clipping, duty cycle, exponential
/// time constant). The classifier generates variants that match the measured
/// capture parameters and keeps the best-matching one per reference type.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';
import 'waveform_preprocessor.dart';

/// Creates ideal and parameterised reference waveforms.
class ReferenceWaveformGenerator {
  const ReferenceWaveformGenerator();

  /// Generates one reference with the given parameters.
  ReferenceWaveform generate(
    WaveformSignalType type,
    ReferenceParameters parameters,
  ) {
    final count = parameters.sampleCount;
    final sampleRate = parameters.sampleRateHz > 0
        ? parameters.sampleRateHz
        : 1;
    final times = Float64List(count);
    final volts = Float64List(count);
    final duration = parameters.durationSeconds;
    final frequency = parameters.frequencyHz > 0
        ? parameters.frequencyHz
        : (duration > 0 ? 1 / duration : 1.0);
    final random = math.Random(parameters.seed);
    double? gaussianSpare;

    double gaussian() {
      if (gaussianSpare != null) {
        final value = gaussianSpare!;
        gaussianSpare = null;
        return value;
      }
      var u = 0.0;
      var v = 0.0;
      while (u <= 1e-12) {
        u = random.nextDouble();
      }
      v = random.nextDouble();
      final magnitude = math.sqrt(-2 * math.log(u));
      final angle = 2 * math.pi * v;
      gaussianSpare = magnitude * math.sin(angle);
      return magnitude * math.cos(angle);
    }

    final amplitude = parameters.amplitudeVolts;
    final offset = parameters.offsetVolts;
    final duty = parameters.dutyCycle.clamp(0.01, 0.99);
    final edge = parameters.rectangularEdgeFraction;
    final baseTime = count > 1 ? 1 / sampleRate : 0.0;
    final tau = parameters.timeConstantSeconds > 0
        ? parameters.timeConstantSeconds
        : (duration > 0 ? duration / 3 : 1.0);
    final damping = math.max(0, parameters.dampingPerSecond);
    final noiseRms = parameters.noiseLevelPercent / 100 * amplitude.abs();
    final lowerLimit = offset - amplitude * parameters.lowerClipLevel;
    final upperLimit = offset + amplitude * parameters.upperClipLevel;

    for (var i = 0; i < count; i++) {
      final t = i * baseTime;
      times[i] = t;
      final phase = _phase(t, frequency, parameters.phaseRadians);
      double value;
      switch (type) {
        case WaveformSignalType.sine:
          value = math.sin(2 * math.pi * phase);
          break;
        case WaveformSignalType.square:
          value = _rectangular(phase, 0.5, edge);
          break;
        case WaveformSignalType.triangle:
          value = 4 * (phase - 0.5).abs() - 1;
          break;
        case WaveformSignalType.sawtooth:
          value = parameters.directionIsRising ? 2 * phase - 1 : 1 - 2 * phase;
          break;
        case WaveformSignalType.pulse:
          value = _rectangular(phase, duty, edge);
          break;
        case WaveformSignalType.pwm:
          value = _rectangular(phase, duty, edge);
          break;
        case WaveformSignalType.exponentialDecay:
          if (parameters.directionIsRising) {
            value = 1 - math.exp(-t / tau);
          } else {
            value = math.exp(-t / tau);
          }
          break;
        case WaveformSignalType.dampedOscillation:
          value = math.exp(-damping * t) * math.sin(2 * math.pi * phase);
          break;
        case WaveformSignalType.clippedSine:
          value = math.sin(2 * math.pi * phase);
          break;
        case WaveformSignalType.noisySine:
          value = math.sin(2 * math.pi * phase);
          break;
      }
      if (type == WaveformSignalType.noisySine && noiseRms > 0) {
        value +=
            gaussian() *
            noiseRms /
            (amplitude.abs() > 1e-12 ? amplitude.abs() : 1);
      }
      if (type == WaveformSignalType.exponentialDecay) {
        volts[i] = offset + amplitude * value;
      } else if (type == WaveformSignalType.dampedOscillation) {
        volts[i] = offset + amplitude * value;
      } else {
        var scaled = offset + amplitude * value;
        if (type == WaveformSignalType.clippedSine &&
            (parameters.lowerClipLevel < 1 || parameters.upperClipLevel < 1)) {
          scaled = scaled.clamp(lowerLimit, upperLimit);
        }
        volts[i] = scaled;
      }
    }

    return ReferenceWaveform(
      type: type,
      parameters: parameters,
      trace: WaveformTrace(times: times, volts: volts),
    );
  }

  /// Generates the variants of [type] that best match the capture.
  ///
  /// The first variant is always the parameter set measured from the capture;
  /// the remaining variants cover plausible variations (duty cycle, direction,
  /// damping, time constant, clipping level) so real-world non-ideal captures
  /// still find a close reference. At most [maxVariants] are returned.
  List<ReferenceWaveform> variantsFor({
    required WaveformSignalType type,
    required PreprocessedWaveform preprocessed,
    required WaveformFeatures features,
    int maxVariants = 3,
  }) {
    final analysis = preprocessed.analysis;
    final count = analysis.length;
    if (count < 2 || analysis.durationSeconds <= 0) return const [];
    final duration = analysis.durationSeconds;
    final sampleRate = (count - 1) / duration;
    final estimatedFrequency =
        preprocessed.estimatedFundamentalHz ?? features.frequencyHz;
    final frequency = _clampFrequency(
      estimatedFrequency ?? 1 / duration,
      duration: duration,
      nyquist: sampleRate / 2,
    );
    final amplitude = (features.vPp ?? 0) > 0 ? features.vPp! / 2 : 1.0;
    final midpoint = (features.vTop != null && features.vBase != null)
        ? (features.vTop! + features.vBase!) / 2
        : (features.vMean ?? 0.0);
    final duty = ((features.dutyPercent ?? 50) / 100).clamp(0.02, 0.98);
    final noisePercent = ((features.sineResidualRmsRatio ?? 0) * 100).clamp(
      0.0,
      80.0,
    );
    final damping = _estimateDamping(features, duration);
    final tau = _estimateTau(features, duration);
    final clipLevel = _estimateClipLevel(features);
    final edge = _estimateEdgeFraction(features, sampleRate, frequency);

    final base = ReferenceParameters(
      frequencyHz: frequency,
      amplitudeVolts: amplitude,
      offsetVolts: midpoint,
      sampleRateHz: sampleRate,
      durationSeconds: duration,
      dutyCycle: duty,
      noiseLevelPercent: noisePercent,
      dampingPerSecond: damping,
      timeConstantSeconds: tau,
      clippingLevel: clipLevel,
      lowerClipLevel: clipLevel,
      upperClipLevel: clipLevel,
      rectangularEdgeFraction: edge,
      directionIsRising: features.exponentialRising,
    );

    final variants = <ReferenceParameters>[];
    switch (type) {
      case WaveformSignalType.sine:
        variants.add(base);
        break;
      case WaveformSignalType.square:
        variants.add(base.copyWith(dutyCycle: 0.5));
        variants.add(
          base.copyWith(dutyCycle: 0.5, rectangularEdgeFraction: edge * 2.5),
        );
        break;
      case WaveformSignalType.triangle:
        variants.add(base);
        variants.add(base.copyWith(dutyCycle: 0.5));
        break;
      case WaveformSignalType.sawtooth:
        variants.add(base.copyWith(directionIsRising: true));
        variants.add(base.copyWith(directionIsRising: false));
        break;
      case WaveformSignalType.pulse:
        final pulseDuty = duty <= 0.2 ? duty : 0.05;
        variants.add(base.copyWith(dutyCycle: pulseDuty));
        variants.add(
          base.copyWith(
            dutyCycle: math.min(0.1, math.max(0.02, pulseDuty * 2)),
          ),
        );
        variants.add(base.copyWith(frequencyHz: 1 / duration, dutyCycle: 0.05));
        break;
      case WaveformSignalType.exponentialDecay:
        final direction = features.exponentialRising;
        variants.add(
          base.copyWith(
            directionIsRising: direction,
            timeConstantSeconds: tau,
            amplitudeVolts: (features.vPp ?? 0) > 0 ? features.vPp : 2,
            offsetVolts: features.vMin ?? 0,
            lowerClipLevel: 1,
            upperClipLevel: 1,
          ),
        );
        variants.add(
          base.copyWith(
            directionIsRising: !direction,
            timeConstantSeconds: tau,
            amplitudeVolts: (features.vPp ?? 0) > 0 ? features.vPp : 2,
            offsetVolts: features.vMin ?? 0,
            lowerClipLevel: 1,
            upperClipLevel: 1,
          ),
        );
        variants.add(
          base.copyWith(
            directionIsRising: direction,
            timeConstantSeconds: tau / 2,
            amplitudeVolts: (features.vPp ?? 0) > 0 ? features.vPp : 2,
            offsetVolts: features.vMin ?? 0,
            lowerClipLevel: 1,
            upperClipLevel: 1,
          ),
        );
        break;
      case WaveformSignalType.dampedOscillation:
        final peak = math.max(
          (features.vMax ?? 0) - (features.vMean ?? 0),
          (features.vMean ?? 0) - (features.vMin ?? 0),
        );
        final dampedBase = base.copyWith(
          amplitudeVolts: peak.abs() > 0 ? peak.abs() : amplitude,
          phaseRadians: math.pi / 2,
          lowerClipLevel: 1,
          upperClipLevel: 1,
        );
        variants.add(dampedBase);
        variants.add(dampedBase.copyWith(dampingPerSecond: damping * 0.5));
        variants.add(dampedBase.copyWith(dampingPerSecond: damping * 2));
        break;
      case WaveformSignalType.clippedSine:
        final guess = _estimateClipLevel(features);
        final level = guess.clamp(0.25, 0.99);
        final compensatedAmplitude = level > 0
            ? (features.vPp ?? 0) / 2 / level
            : amplitude;
        final clippedBase = base.copyWith(
          amplitudeVolts: compensatedAmplitude,
          clippingLevel: level,
          lowerClipLevel: level,
          upperClipLevel: level,
        );
        variants.add(clippedBase);
        variants.add(
          clippedBase.copyWith(
            clippingLevel: (level * 0.75).clamp(0.2, 0.99),
            lowerClipLevel: (level * 0.75).clamp(0.2, 0.99),
            upperClipLevel: (level * 0.75).clamp(0.2, 0.99),
          ),
        );
        if ((features.upperClippingRatio ?? 0) >
            (features.lowerClippingRatio ?? 0) * 1.5) {
          variants.add(
            clippedBase.copyWith(lowerClipLevel: 1, upperClipLevel: level),
          );
        } else if ((features.lowerClippingRatio ?? 0) >
            (features.upperClippingRatio ?? 0) * 1.5) {
          variants.add(
            clippedBase.copyWith(lowerClipLevel: level, upperClipLevel: 1),
          );
        } else {
          variants.add(
            clippedBase.copyWith(
              clippingLevel: (level * 1.25).clamp(0.25, 1.0),
              lowerClipLevel: (level * 1.25).clamp(0.25, 1.0),
              upperClipLevel: (level * 1.25).clamp(0.25, 1.0),
            ),
          );
        }
        break;
      case WaveformSignalType.noisySine:
        final level = noisePercent <= 0 ? 5.0 : noisePercent;
        variants.add(base.copyWith(noiseLevelPercent: level, seed: 1));
        variants.add(
          base.copyWith(
            noiseLevelPercent: (level * 0.5).clamp(0.5, 80),
            seed: 2,
          ),
        );
        variants.add(
          base.copyWith(
            noiseLevelPercent: (level * 1.5).clamp(0.5, 80),
            seed: 3,
          ),
        );
        break;
      case WaveformSignalType.pwm:
        final pwmDuty = duty.clamp(0.05, 0.95);
        variants.add(base.copyWith(dutyCycle: pwmDuty));
        variants.add(
          base.copyWith(dutyCycle: (pwmDuty * 0.75).clamp(0.05, 0.95)),
        );
        variants.add(
          base.copyWith(dutyCycle: (pwmDuty * 1.25).clamp(0.05, 0.95)),
        );
        break;
    }

    final result = <ReferenceWaveform>[];
    final signatures = <String>{};
    for (final parameters in variants) {
      final signature = [
        parameters.frequencyHz.toStringAsFixed(4),
        parameters.dutyCycle.toStringAsFixed(3),
        parameters.noiseLevelPercent.toStringAsFixed(2),
        parameters.dampingPerSecond.toStringAsFixed(4),
        parameters.timeConstantSeconds.toStringAsFixed(6),
        parameters.lowerClipLevel.toStringAsFixed(3),
        parameters.upperClipLevel.toStringAsFixed(3),
        parameters.directionIsRising,
        parameters.seed,
      ].join('|');
      if (!signatures.add(signature)) continue;
      result.add(generate(type, parameters));
      if (result.length >= math.max(1, maxVariants)) break;
    }
    return result;
  }

  /// Normalised ideal shape value in [-1, 1] at a normalised [phase].
  ///
  /// Used by the feature extractor for the sine/square/triangle/sawtooth
  /// correlations and by [idealShapeSamples].
  static double shapeValue(
    WaveformSignalType type,
    double phase, {
    double dutyCycle = 0.5,
    double edgeFraction = 0.02,
    bool directionIsRising = true,
  }) {
    final p = phase - phase.floorToDouble();
    return switch (type) {
      WaveformSignalType.sine => math.sin(2 * math.pi * p),
      WaveformSignalType.square => _rectangular(p, 0.5, edgeFraction),
      WaveformSignalType.triangle => 4 * (p - 0.5).abs() - 1,
      WaveformSignalType.sawtooth => directionIsRising ? 2 * p - 1 : 1 - 2 * p,
      _ => 0,
    };
  }

  /// Normalised ideal shape samples in [-1, 1] for the shape-correlation
  /// features. Phase and amplitude are irrelevant because the correlation
  /// searches the phase shift.
  static Float64List idealShapeSamples(
    WaveformSignalType type,
    int count, {
    double dutyCycle = 0.5,
    double edgeFraction = 0.02,
    bool directionIsRising = true,
  }) {
    final values = Float64List(count);
    if (count <= 0) return values;
    for (var i = 0; i < count; i++) {
      final phase = i / count;
      values[i] = shapeValue(
        type,
        phase,
        dutyCycle: dutyCycle,
        edgeFraction: edgeFraction,
        directionIsRising: directionIsRising,
      );
    }
    return values;
  }

  static double _phase(double time, double frequency, double phaseRadians) {
    if (!frequency.isFinite || frequency <= 0) return 0;
    final value = time * frequency + phaseRadians / (2 * math.pi);
    return value - value.floorToDouble();
  }

  /// Trapezoidal periodic rectangle in [-1, 1].
  static double _rectangular(double phase, double duty, double edgeFraction) {
    final clampedDuty = duty.clamp(0.01, 0.99);
    final maxEdge = math.min(
      0.2,
      math.min(clampedDuty * 0.4, (1 - clampedDuty) * 0.4),
    );
    final edge = edgeFraction.clamp(0.0005, math.max(0.0005, maxEdge));
    final p = phase - phase.floorToDouble();
    if (p < edge) return -1 + 2 * (p / edge);
    if (p < clampedDuty) return 1;
    if (p < clampedDuty + edge) {
      return 1 - 2 * ((p - clampedDuty) / edge);
    }
    return -1;
  }

  double _clampFrequency(
    double frequency, {
    required double duration,
    required double nyquist,
  }) {
    if (!frequency.isFinite || frequency <= 0) {
      return duration > 0 ? 1 / duration : 1;
    }
    final minimum = duration > 0 ? 1 / duration : 0.1;
    final maximum = nyquist > 0 ? nyquist / 2.5 : frequency;
    return frequency.clamp(minimum, math.max(minimum, maximum));
  }

  double _estimateDamping(WaveformFeatures features, double duration) {
    final fit = features.envelopeDecayRate;
    if (fit != null && fit.isFinite && fit > 0) {
      return fit.clamp(0.2 / duration, 20 / duration);
    }
    return 3 / duration;
  }

  double _estimateTau(WaveformFeatures features, double duration) {
    final tau = features.exponentialTauSeconds;
    if (tau != null && tau.isFinite && tau > 0) {
      return tau.clamp(duration / 200, duration * 20);
    }
    return duration / 3;
  }

  double _estimateClipLevel(WaveformFeatures features) {
    final ratio = (features.clippingRatio ?? 0).clamp(0.0, 0.95);
    if (ratio <= 0.005) return 0.9;
    // fraction clipped = 1 - (2 / pi) * asin(level)
    final level = math.sin((1 - ratio) * math.pi / 2);
    return level.clamp(0.25, 0.99);
  }

  double _estimateEdgeFraction(
    WaveformFeatures features,
    double sampleRate,
    double frequency,
  ) {
    final rise = features.riseTimeSeconds;
    if (rise != null && rise.isFinite && rise > 0 && frequency > 0) {
      final fraction = rise * frequency;
      return fraction.clamp(0.002, 0.2);
    }
    final samplesPerPeriod = frequency > 0 ? sampleRate / frequency : 20;
    return (2 / math.max(4, samplesPerPeriod)).clamp(0.002, 0.1);
  }
}
