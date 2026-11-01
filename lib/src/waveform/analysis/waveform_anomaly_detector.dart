/// Distortion and anomaly detection against the best-matching reference.
///
/// The detector reports every anomaly with its severity, affected time
/// interval, the measured value and, where meaningful, the ideal reference
/// value. It never raises an anomaly without a numerical measurement.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';

/// Detects deviations of a capture from its best matching reference.
class WaveformAnomalyDetector {
  const WaveformAnomalyDetector();

  List<WaveformAnomaly> detect({
    required WaveformFeatures features,
    required WaveformSignalType primaryType,
    required Float64List captureVolts,
    required Float64List referenceVolts,
    required double durationSeconds,
    required double startTimeSeconds,
    int lagSamples = 0,
  }) {
    final anomalies = <WaveformAnomaly>[];
    final amplitude = features.vPp ?? 0;
    if (features.sampleCount < 8 || amplitude <= 0) return anomalies;

    final residual = _alignedResidual(captureVolts, referenceVolts, lagSamples);
    final residualRms = _rms(residual);
    final residualRatio = amplitude > 0 ? residualRms / amplitude : 0.0;

    final startGlobal = startTimeSeconds;
    final endGlobal = startTimeSeconds + durationSeconds;
    _addNoise(anomalies, features, primaryType, startGlobal, endGlobal);
    _addClipping(anomalies, features, primaryType);
    _addOvershoot(anomalies, features, primaryType, startGlobal, endGlobal);
    _addDcOffset(anomalies, features, startGlobal, endGlobal);
    _addTiming(anomalies, features, primaryType, startGlobal, endGlobal);
    _addRectangular(anomalies, features, primaryType);
    _addHarmonics(anomalies, features, primaryType, startGlobal, endGlobal);
    _addRinging(
      anomalies,
      features,
      primaryType,
      residual,
      residualRatio,
      amplitude,
      startTimeSeconds,
    );

    anomalies.sort((a, b) {
      final severity = b.severity.index.compareTo(a.severity.index);
      if (severity != 0) return severity;
      return (a.startSeconds ?? 0).compareTo(b.startSeconds ?? 0);
    });
    return anomalies;
  }

  void _addNoise(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
    double startSeconds,
    double endSeconds,
  ) {
    if (_isRectangular(primaryType)) return;
    final residualRatio = features.sineResidualRmsRatio;
    final harmonicRatio = features.residualHarmonicEnergyRatio ?? 0;
    final flatness = features.residualSpectralFlatness;
    if (residualRatio == null) return;
    final flatnessFactor = flatness == null
        ? 0.0
        : ((flatness - 0.3) / 0.4).clamp(0.0, 1.0);
    final noiseFraction = residualRatio * (1 - harmonicRatio) * flatnessFactor;
    if (noiseFraction < 0.03) return;
    final severity = noiseFraction >= 0.12
        ? AnomalySeverity.severe
        : noiseFraction >= 0.07
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    final snr = features.sineResidualSnrDb;
    anomalies.add(
      WaveformAnomaly(
        type: 'noise',
        label: 'Noise',
        severity: severity,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        measuredValue:
            '${(noiseFraction * 100).toStringAsFixed(1)} % residual noise'
            '${snr != null ? ', sine-fit SNR ${snr.toStringAsFixed(1)} dB' : ''}',
        idealValue: 'less than 3 % residual noise',
        description:
            'Random fluctuations remain after subtracting the fundamental '
            'sine fit. The harmonic contribution of the residual is '
            '${(harmonicRatio * 100).toStringAsFixed(0)} %, so the remainder '
            'is broadband noise rather than deterministic distortion.',
      ),
    );
  }

  void _addClipping(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
  ) {
    if (_isRectangular(primaryType)) return;
    final clipping = features.clippingRatio ?? 0;
    if (clipping < 0.02) return;
    final severity = clipping >= 0.25
        ? AnomalySeverity.severe
        : clipping >= 0.1
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    final firstRegion = features.clippedRegions.isEmpty
        ? null
        : features.clippedRegions.first;
    final lastRegion = features.clippedRegions.isEmpty
        ? null
        : features.clippedRegions.last;
    anomalies.add(
      WaveformAnomaly(
        type: 'clipping',
        label: 'Clipping',
        severity: severity,
        startSeconds: firstRegion?.$1,
        endSeconds: lastRegion?.$2,
        measuredValue:
            '${(clipping * 100).toStringAsFixed(1)} % of samples at the rails '
            '(upper ${((features.upperClippingRatio ?? 0) * 100).toStringAsFixed(1)} %, '
            'lower ${((features.lowerClippingRatio ?? 0) * 100).toStringAsFixed(1)} %)',
        idealValue: '0 % of samples at the rails',
        description:
            'The waveform stays flat at its positive or negative extreme for '
            'longer than the reference. This indicates amplitude saturation '
            'in the acquisition or the source.',
      ),
    );
  }

  void _addOvershoot(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
    double startSeconds,
    double endSeconds,
  ) {
    // The 5 %/95 % levels used for the top/base estimate are robust plateau
    // levels for rectangular signals. For sine, triangle and other rounded
    // shapes the extreme naturally lies slightly outside that percentile, so
    // overshoot detection would raise false positives.
    if (!_isRectangular(primaryType)) return;
    final vPp = features.vPp;
    final vTop = features.vTop;
    final vBase = features.vBase;
    final vMax = features.vMax;
    final vMin = features.vMin;
    if (vPp == null || vPp <= 0 || vTop == null || vBase == null) return;
    final amplitude = vTop - vBase;
    if (amplitude <= 0 || vMax == null || vMin == null) return;
    final overshoot = (vMax - vTop) / amplitude * 100;
    if (overshoot > 2) {
      final severity = overshoot >= 15
          ? AnomalySeverity.severe
          : overshoot >= 7
          ? AnomalySeverity.moderate
          : AnomalySeverity.minor;
      anomalies.add(
        WaveformAnomaly(
          type: 'overshoot',
          label: 'Overshoot',
          severity: severity,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          measuredValue:
              '${overshoot.toStringAsFixed(1)} % of the top-base '
              'amplitude',
          idealValue: '0 % overshoot',
          description:
              'The maximum voltage exceeds the estimated high level. This is '
              'typical for fast edges with insufficient damping.',
        ),
      );
    }
    final undershoot = (vBase - vMin) / amplitude * 100;
    if (undershoot > 2) {
      final severity = undershoot >= 15
          ? AnomalySeverity.severe
          : undershoot >= 7
          ? AnomalySeverity.moderate
          : AnomalySeverity.minor;
      anomalies.add(
        WaveformAnomaly(
          type: 'undershoot',
          label: 'Undershoot',
          severity: severity,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          measuredValue:
              '${undershoot.toStringAsFixed(1)} % below the low level',
          idealValue: '0 % undershoot',
          description:
              'The minimum voltage falls below the estimated low level, which '
              'indicates undershoot or ringing on the falling edge.',
        ),
      );
    }
  }

  void _addDcOffset(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    double startSeconds,
    double endSeconds,
  ) {
    final mean = features.vMean;
    final vPp = features.vPp;
    if (mean == null || vPp == null || vPp <= 0) return;
    final ratio = mean.abs() / vPp;
    if (ratio < 0.05) return;
    final severity = ratio >= 0.5
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    anomalies.add(
      WaveformAnomaly(
        type: 'dc_offset',
        label: 'DC offset',
        severity: severity,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        measuredValue:
            '${mean.toStringAsFixed(4)} V mean '
            '(${(ratio * 100).toStringAsFixed(1)} % of Vpp)',
        idealValue: '0 V offset from the reference centre',
        description:
            'The signal is not centred around zero volts. This is not '
            'necessarily a fault, but it shifts the waveform away from an '
            'offset-free reference.',
      ),
    );
  }

  void _addTiming(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
    double startSeconds,
    double endSeconds,
  ) {
    final noiseFraction = _noiseFraction(features);
    final damped =
        primaryType == WaveformSignalType.dampedOscillation &&
        (features.envelopeDecayR2 ?? 0) > 0.5 &&
        (features.envelopeDecayRate ?? 0) > 0;
    final periodVariation = features.periodVariation;
    if (periodVariation != null &&
        periodVariation > 0.02 &&
        noiseFraction < 0.04) {
      final severity = periodVariation >= 0.15
          ? AnomalySeverity.severe
          : periodVariation >= 0.06
          ? AnomalySeverity.moderate
          : AnomalySeverity.minor;
      anomalies.add(
        WaveformAnomaly(
          type: 'jitter',
          label: 'Timing jitter',
          severity: severity,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          measuredValue:
              '${(periodVariation * 100).toStringAsFixed(1)} % period '
              'variation',
          idealValue: 'less than 2 % period variation',
          description:
              'Successive periods differ by more than the reference tolerance, '
              'which indicates jitter in the source or trigger.',
        ),
      );
    }

    final amplitudeVariation = features.amplitudeVariation;
    if (amplitudeVariation != null &&
        amplitudeVariation > 0.03 &&
        !damped &&
        noiseFraction < 0.04) {
      final severity = amplitudeVariation >= 0.15
          ? AnomalySeverity.moderate
          : AnomalySeverity.minor;
      anomalies.add(
        WaveformAnomaly(
          type: 'amplitude_variation',
          label: 'Amplitude variation',
          severity: severity,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          measuredValue:
              '${(amplitudeVariation * 100).toStringAsFixed(1)} % '
              'period-to-period Vpp variation',
          idealValue: 'constant amplitude',
          description:
              'The peak-to-peak voltage changes between periods. This can be '
              'caused by a modulated source or by an unstable gain.',
        ),
      );
    }

    if (!_isRectangular(primaryType)) return;
    final dutyVariation = features.dutyCycleVariation;
    if (dutyVariation != null && dutyVariation > 0.05) {
      final severity = dutyVariation >= 0.2
          ? AnomalySeverity.moderate
          : AnomalySeverity.minor;
      anomalies.add(
        WaveformAnomaly(
          type: 'duty_instability',
          label: 'Duty cycle instability',
          severity: severity,
          startSeconds: startSeconds,
          endSeconds: endSeconds,
          measuredValue:
              '${(dutyVariation * 100).toStringAsFixed(1)} % duty cycle '
              'variation',
          idealValue: 'constant duty cycle',
          description:
              'The high time varies between periods, which is typical for a '
              'modulated PWM signal or an unstable pulse source.',
        ),
      );
    }
  }

  void _addRectangular(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
  ) {
    if (!_isRectangular(primaryType)) return;
    final maxRatio = features.periodMaxRatio;
    if (maxRatio == null || maxRatio <= 1.4) return;
    final periods = features.periods;
    final edges = features.risingEdgeTimes;
    double? start;
    double? end;
    if (periods.length > 1 && edges.length > 1) {
      var maximum = periods.first;
      var maximumIndex = 0;
      for (var i = 1; i < periods.length; i++) {
        if (periods[i] > maximum) {
          maximum = periods[i];
          maximumIndex = i;
        }
      }
      start = edges[math.min(maximumIndex, edges.length - 1)];
      end = start + maximum;
    }
    final severity = maxRatio >= 2.5
        ? AnomalySeverity.severe
        : maxRatio >= 1.8
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    anomalies.add(
      WaveformAnomaly(
        type: 'irregular_pulses',
        label: 'Irregular or missing pulses',
        severity: severity,
        startSeconds: start,
        endSeconds: end,
        measuredValue:
            'longest period ${maxRatio.toStringAsFixed(2)} times the median',
        idealValue: 'equal pulse spacing',
        description:
            'At least one pulse interval is much longer than the median. A '
            'pulse may be missing or the repetition rate may be modulated.',
      ),
    );
  }

  void _addHarmonics(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
    double startSeconds,
    double endSeconds,
  ) {
    final reported =
        primaryType == WaveformSignalType.sine ||
        primaryType == WaveformSignalType.noisySine ||
        primaryType == WaveformSignalType.dampedOscillation ||
        primaryType == WaveformSignalType.clippedSine;
    if (!reported) return;
    final thd = features.thdPercent;
    if (thd == null || thd < 5) return;
    final severity = thd >= 20
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    anomalies.add(
      WaveformAnomaly(
        type: 'harmonic_distortion',
        label: 'Harmonic distortion',
        severity: severity,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        measuredValue: 'THD ${thd.toStringAsFixed(1)} %',
        idealValue: 'THD below 5 %',
        description:
            'The signal contains more harmonic energy than the reference. '
            'This is expected for intentionally non-sinusoidal shapes and '
            'indicates distortion for sine-like waveforms.',
      ),
    );
  }

  void _addRinging(
    List<WaveformAnomaly> anomalies,
    WaveformFeatures features,
    WaveformSignalType primaryType,
    Float64List residual,
    double residualRatio,
    double amplitude,
    double startTimeSeconds,
  ) {
    if (!_isRectangular(primaryType) &&
        primaryType != WaveformSignalType.clippedSine) {
      return;
    }
    if (residual.length < 8 || residualRatio < 0.01) return;
    final flatness = features.residualSpectralFlatness;
    if (flatness != null && flatness > 0.3) return;
    final period = features.periodSeconds;
    if (period == null || period <= 0) return;
    final dt = features.sampleIntervalSeconds;
    if (dt == null || dt <= 0) return;
    final window = math.max(4, (period * 0.2 / dt).round());
    final edges = <double>[
      ...features.risingEdgeTimes,
      ...features.fallingEdgeTimes,
    ]..sort();
    var bestCount = 0;
    double? bestStart;
    for (final edge in edges.take(8)) {
      final startIndex = ((edge - startTimeSeconds) / dt).round().clamp(
        0,
        residual.length - 1,
      );
      final endIndex = math.min(residual.length - 1, startIndex + window);
      if (endIndex - startIndex < 4) continue;
      var localMean = 0.0;
      for (var i = startIndex; i <= endIndex; i++) {
        localMean += residual[i];
      }
      localMean /= endIndex - startIndex + 1;
      final threshold = amplitude * 0.005;
      var crossings = 0;
      var sign = 0;
      for (var i = startIndex; i <= endIndex; i++) {
        final value = residual[i] - localMean;
        if (value.abs() < threshold) continue;
        final current = value > 0 ? 1 : -1;
        if (sign != 0 && current != sign) crossings++;
        sign = current;
      }
      if (crossings > bestCount) {
        bestCount = crossings;
        bestStart = edge;
      }
    }
    if (bestCount < 3) return;
    final severity = bestCount >= 6
        ? AnomalySeverity.moderate
        : AnomalySeverity.minor;
    anomalies.add(
      WaveformAnomaly(
        type: 'ringing',
        label: 'Ringing',
        severity: severity,
        startSeconds: bestStart,
        endSeconds: bestStart == null ? null : bestStart + window * dt,
        measuredValue: '$bestCount residual sign changes after the edge',
        idealValue: 'no oscillation after the edge',
        description:
            'The residual between the capture and the reference oscillates '
            'after a transition, which indicates ringing from parasitic '
            'reactances or probe compensation.',
      ),
    );
  }

  bool _isRectangular(WaveformSignalType type) =>
      type == WaveformSignalType.square ||
      type == WaveformSignalType.pwm ||
      type == WaveformSignalType.pulse;
}

Float64List _alignedResidual(
  Float64List capture,
  Float64List reference,
  int lagSamples,
) {
  final length = math.min(capture.length, reference.length);
  if (length == 0) return Float64List(0);
  final residual = Float64List(length);
  final lag = lagSamples.clamp(-(length - 1), length - 1);
  final referenceTraceLength = reference.length;
  for (var i = 0; i < length; i++) {
    // Positive lag means the reference is delayed relative to the capture:
    // capture[i] matches reference[i + lag] (see maxNormalizedCrossCorrelation).
    final referenceIndex = i + lag;
    residual[i] = referenceIndex >= 0 && referenceIndex < referenceTraceLength
        ? capture[i] - reference[referenceIndex]
        : 0;
  }
  return residual;
}

double _rms(Float64List values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final value in values) {
    sum += value * value;
  }
  return math.sqrt(sum / values.length);
}

double _noiseFraction(WaveformFeatures features) {
  final residual = features.sineResidualRmsRatio ?? 0;
  final harmonic = features.residualHarmonicEnergyRatio ?? 0;
  final flatness = features.residualSpectralFlatness;
  final flatnessFactor = flatness == null
      ? 0.0
      : ((flatness - 0.3) / 0.4).clamp(0.0, 1.0);
  return (residual * (1 - harmonic) * flatnessFactor).clamp(0.0, 1.0);
}
