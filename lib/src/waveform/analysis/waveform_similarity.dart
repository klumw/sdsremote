/// Comparison methods of the waveform classification engine.
///
/// Combines normalised cross-correlation, banded dynamic time warping,
/// frequency-domain comparison and weighted feature similarity. Every method
/// returns a percentage in [0, 100] and is combined by the classifier with the
/// configurable [SimilarityWeights].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';
import 'waveform_math.dart';

/// Result of the shape comparison of a capture and a reference.
class ShapeSimilarity {
  /// Correlation of the standardised shapes, in percent.
  final double percent;

  /// Raw Pearson correlation coefficient in [-1, 1].
  final double coefficient;

  /// Lag of the reference relative to the capture in seconds.
  final double? lagSeconds;

  /// Lag in samples of the resampled comparison grid.
  final int lagSamples;

  /// DTW similarity in percent.
  final double dtwPercent;

  /// Path-normalised DTW distance.
  final double dtwDistance;

  const ShapeSimilarity({
    required this.percent,
    required this.coefficient,
    required this.lagSeconds,
    required this.lagSamples,
    required this.dtwPercent,
    required this.dtwDistance,
  });
}

/// Compares the shapes of a capture and a reference.
///
/// Both arrays are standardised, resampled to a common grid and aligned with
/// a lag search. DTW handles small timing variations.
ShapeSimilarity compareShapes(
  Float64List capture,
  Float64List reference, {
  double durationSeconds = 0,
}) {
  if (capture.length < 8 || reference.length < 8) {
    return const ShapeSimilarity(
      percent: 0,
      coefficient: 0,
      lagSeconds: null,
      lagSamples: 0,
      dtwPercent: 0,
      dtwDistance: 1,
    );
  }
  final correlationLength = math.min(
    512,
    math.min(capture.length, reference.length),
  );
  final a = zScore(resampleValues(capture, correlationLength));
  final b = zScore(resampleValues(reference, correlationLength));
  final minimumOverlap = math.max(8, (correlationLength / 3).round());
  final correlation = maxNormalizedCrossCorrelation(
    a,
    b,
    maxLag: correlationLength - minimumOverlap,
    minimumOverlap: minimumOverlap,
  );
  final percent = clamp01(correlation.coefficient) * 100;
  final lagSeconds = durationSeconds > 0 && correlationLength > 1
      ? correlation.lagSamples / correlationLength * durationSeconds
      : null;

  final dtwLength = math.min(192, math.min(capture.length, reference.length));
  final dtw = bandedDtw(
    zScore(resampleValues(capture, dtwLength)),
    zScore(resampleValues(reference, dtwLength)),
  );

  return ShapeSimilarity(
    percent: percent,
    coefficient: correlation.coefficient,
    lagSeconds: lagSeconds,
    lagSamples: correlation.lagSamples,
    dtwPercent: clamp01(dtw.similarity) * 100,
    dtwDistance: dtw.distance,
  );
}

/// Frequency-domain similarity of two feature sets in percent.
double frequencyDomainSimilarity(
  WaveformFeatures capture,
  WaveformFeatures reference,
) {
  final captureFrequency = capture.frequencyHz;
  final referenceFrequency = reference.frequencyHz;
  if (captureFrequency == null && referenceFrequency == null) {
    return 80;
  }
  if (captureFrequency == null ||
      referenceFrequency == null ||
      captureFrequency <= 0 ||
      referenceFrequency <= 0) {
    return 20;
  }

  final logRatio = (math.log(captureFrequency / referenceFrequency) / math.ln10)
      .abs();
  final frequencyScore = math.exp(-logRatio * logRatio * 4);

  final captureHarmonics = _relativeHarmonics(capture);
  final referenceHarmonics = _relativeHarmonics(reference);
  double harmonicScore;
  if (captureHarmonics.isEmpty && referenceHarmonics.isEmpty) {
    harmonicScore = 1;
  } else if (captureHarmonics.isEmpty || referenceHarmonics.isEmpty) {
    harmonicScore = 0.4;
  } else {
    harmonicScore = _cosineSimilarity(captureHarmonics, referenceHarmonics);
  }

  final captureThd = capture.thdPercent;
  final referenceThd = reference.thdPercent;
  double thdScore;
  if (captureThd == null && referenceThd == null) {
    thdScore = 1;
  } else if (captureThd == null || referenceThd == null) {
    thdScore = 0.4;
  } else {
    thdScore = math.exp(
      -math.pow((captureThd - referenceThd) / 15, 2).toDouble(),
    );
  }

  final centroidScore = _logCloseness(
    capture.spectralCentroidHz,
    reference.spectralCentroidHz,
    toleranceLog10: 0.3,
  );

  final score =
      0.45 * frequencyScore +
      0.25 * harmonicScore +
      0.20 * thdScore +
      0.10 * centroidScore;
  return clamp01(score) * 100;
}

/// Weighted feature similarity of a capture and a type-specific reference.
double featureSimilarity(
  WaveformFeatures capture,
  WaveformFeatures reference,
  WaveformSignalType type,
) {
  return _weightedFeatureScore(capture, reference, _featureSpecsFor(type));
}

/// Type-independent feature similarity of two captures.
///
/// Used by `compareWaveforms` when no reference type is involved. Amplitude,
/// timing, spectral and shape features contribute with lower weights so the
/// comparison remains descriptive.
double generalFeatureSimilarity(
  WaveformFeatures capture,
  WaveformFeatures reference,
) {
  final specs = [
    _spec('vppVolts', 2, (f) => f.vPp, 0.5, logarithmic: true),
    _spec('rmsVolts', 1, (f) => f.vRms, 0.5, logarithmic: true),
    _spec('crestFactor', 1, (f) => f.crestFactor, 0.3),
    _spec('frequencyHz', 2, (f) => f.frequencyHz, 0.4, logarithmic: true),
    _spec('dutyPercent', 1, (f) => f.dutyPercent, 15),
    _spec(
      'riseTimeSeconds',
      1,
      (f) => f.riseTimeSeconds,
      0.6,
      logarithmic: true,
    ),
    _spec(
      'fallTimeSeconds',
      1,
      (f) => f.fallTimeSeconds,
      0.6,
      logarithmic: true,
    ),
    _spec('thdPercent', 1, (f) => f.thdPercent, 10),
    _spec('snrDb', 1, (f) => f.snrDb, 10),
    _spec('sineCorrelation', 1, (f) => f.sineCorrelation, 0.2),
    _spec('squareCorrelation', 1, (f) => f.squareCorrelation, 0.2),
    _spec('triangleCorrelation', 1, (f) => f.triangleCorrelation, 0.2),
    _spec('sawtoothCorrelation', 1, (f) => f.sawtoothCorrelation, 0.2),
    _spec('twoLevelRatio', 1, (f) => f.twoLevelRatio, 0.2),
    _spec('plateauStability', 1, (f) => f.plateauStability, 0.2),
    _spec('rampLinearity', 1, (f) => f.rampLinearity, 0.2),
    _spec('symmetry', 1, (f) => f.symmetry, 0.2),
  ];
  return _weightedFeatureScore(capture, reference, specs);
}

double _weightedFeatureScore(
  WaveformFeatures capture,
  WaveformFeatures reference,
  List<_FeatureSpec> specs,
) {
  var weighted = 0.0;
  var totalWeight = 0.0;
  for (final spec in specs) {
    final captureValue = spec.value(capture);
    final referenceValue = spec.value(reference);
    final score = _compareFeature(
      captureValue,
      referenceValue,
      tolerance: spec.tolerance,
      logarithmic: spec.logarithmic,
    );
    weighted += score * spec.weight;
    totalWeight += spec.weight;
  }
  if (totalWeight <= 0) return 50;
  return clamp01(weighted / totalWeight) * 100;
}

/// Signal-specific detection rule score in [0, 1].
///
/// The rules encode the detection criteria from the specification (two-level
/// histogram, ramp linearity, clipping, envelope decay, duty stability, …).
/// They complement the numerical comparison methods so that shapes which are
/// numerically similar but physically distinct (for example a square wave and
/// a 50 % PWM signal) remain distinguishable through their characteristic
/// measurements. When the differential representation is available, it is
/// blended in because template correlations cannot separate sine and triangle
/// reliably.
double detectionRuleScore(WaveformSignalType type, WaveformFeatures features) {
  final base = _baseDetectionRuleScore(type, features);
  final differential = _differentialRuleScore(type, features);
  if (differential == null) return base;
  return clamp01(0.35 * base + 0.65 * differential);
}

/// Differential-domain rule score following Xiao et al., Electronics 2026.
///
/// Only the periodic reference shapes of the paper (sine, square, triangle,
/// sawtooth) use this representation. Asymmetric, distorted and non-stationary
/// types keep their feature-based rules. Damping and the duty cycle act as
/// guards so a damped oscillation cannot gain sine or triangle support and a
/// low-duty pulse cannot gain square support.
double? _differentialRuleScore(
  WaveformSignalType type,
  WaveformFeatures features,
) {
  final differential = features.differential;
  if (differential == null) return null;
  final firstZero = differential.firstZeroFraction;
  final secondZero = differential.secondZeroFraction;
  final balance = differential.firstBalance;

  double ramp(double value, double low, double high) =>
      clamp01((value - low) / (high - low));

  // Flat segments in the first difference identify rectangular waveforms;
  // flat segments in the second difference identify linear (triangular)
  // segments. The first-difference balance measures how one-sided the slope
  // is (sawtooth).
  final firstFlat = ramp(firstZero, 0.10, 0.55);
  final firstSloped = 1 - firstFlat;
  final secondFlat = ramp(secondZero, 0.10, 0.40);
  final secondCurved = 1 - secondFlat;
  final imbalanced = 1 - balance;
  final dampingGuard = 1 - 0.8 * _dampingSignificance(features);
  // The paper shows that the differential representation loses separation
  // between sine and triangle under noise. Frequent reversals of the second
  // difference indicate broadband noise; hand those captures back to the
  // noisy-sine rule instead of boosting the clean sine.
  final reversalGuard =
      1 - 0.8 * ramp(differential.secondSignReversalFraction, 0.08, 0.13);
  final duty = features.dutyPercent;
  final dutySymmetry = duty == null ? 1.0 : clamp01(1 - (duty - 50).abs() / 20);

  switch (type) {
    case WaveformSignalType.sine:
      return clamp01(
        secondCurved * firstSloped * balance * dampingGuard * reversalGuard,
      );
    case WaveformSignalType.square:
      return clamp01(firstFlat * balance * dutySymmetry);
    case WaveformSignalType.triangle:
      return clamp01(secondFlat * firstSloped * balance * dampingGuard);
    case WaveformSignalType.sawtooth:
      return clamp01(imbalanced * firstSloped * dampingGuard);
    case WaveformSignalType.pulse:
    case WaveformSignalType.pwm:
    case WaveformSignalType.clippedSine:
    case WaveformSignalType.noisySine:
    case WaveformSignalType.dampedOscillation:
    case WaveformSignalType.exponentialDecay:
      return null;
  }
}

double _baseDetectionRuleScore(
  WaveformSignalType type,
  WaveformFeatures features,
) {
  final duty = features.dutyPercent;
  final twoLevel = features.twoLevelRatio ?? 0;
  final plateau = features.plateauStability ?? 0;
  final edge = features.edgeSteepness;
  final sineCorrelation = features.sineCorrelation ?? 0;
  final clipping = features.clippingRatio ?? 0;
  final noiseFraction = _noiseFraction(features);

  double dutyNear50() {
    if (duty == null) return 0;
    return clamp01(1 - (duty - 50).abs() / 15);
  }

  double edgeScore() {
    if (edge == null || !edge.isFinite) return 0;
    return clamp01((edge - 8) / 25);
  }

  double twoLevelScore() => clamp01((twoLevel - 0.55) / 0.4);

  double pulseDutyScore() {
    if (duty == null) return 0;
    return clamp01((20 - duty) / 18);
  }

  switch (type) {
    case WaveformSignalType.sine:
      final clippingPenalty = clamp01((clipping - 0.01) / 0.05);
      final noisePenalty = clamp01(noiseFraction / 0.08);
      final twoLevelPenalty = clamp01((twoLevel - 0.25) / 0.5);
      final dampingPenalty = _dampingSignificance(features);
      return clamp01(
        sineCorrelation *
            (1 - 0.75 * clippingPenalty) *
            (1 - 0.7 * noisePenalty) *
            (1 - 0.8 * twoLevelPenalty) *
            (1 - 0.8 * dampingPenalty),
      );
    case WaveformSignalType.square:
      return clamp01(
        0.40 * twoLevelScore() +
            0.25 * clamp01(plateau * 1.2) +
            0.20 * edgeScore() +
            0.15 * dutyNear50(),
      );
    case WaveformSignalType.triangle:
      return clamp01(
        0.35 * (features.rampLinearity ?? 0) +
            0.25 * (features.slopeSymmetry ?? 0) +
            0.25 * (features.triangleCorrelation ?? 0) +
            0.15 * (1 - clamp01(twoLevel / 0.8)),
      );
    case WaveformSignalType.sawtooth:
      final reset = features.resetRatio;
      final resetScore = reset == null ? 0.0 : clamp01((reset - 1.5) / 4);
      final asymmetry = features.slopeSymmetry == null
          ? 0.0
          : clamp01((1 - features.slopeSymmetry!) / 0.5);
      return clamp01(
        0.35 * resetScore +
            0.25 * (features.rampLinearity ?? 0) +
            0.25 * (features.sawtoothCorrelation ?? 0) +
            0.15 * asymmetry,
      );
    case WaveformSignalType.pulse:
      final count = features.pulseCount;
      final countScore = count <= 2
          ? 1.0
          : count <= 4
          ? 0.65
          : 0.3;
      return clamp01(
        0.40 * pulseDutyScore() +
            0.20 * countScore +
            0.20 * edgeScore() +
            0.20 * (1 - (features.dutyCycleVariation ?? 0).clamp(0.0, 1.0)),
      );
    case WaveformSignalType.exponentialDecay:
      final exponential = features.exponentialFitR2 ?? 0;
      final linear = features.linearFitR2 ?? 0;
      final monotonic = features.monotonicFraction ?? 0;
      final advantage = exponential - linear;
      final tau = features.exponentialTauSeconds;
      final duration = features.durationSeconds;
      // A straight ramp can be fitted by an exponential with a very large
      // time constant. Require real curvature and a time constant that is
      // observable inside the record; this separates exponential decay from
      // a linear ramp.
      final curvature = clamp01(advantage / 0.05);
      final tauSignificance = tau != null && tau > 0 && duration > 0
          ? clamp01(duration / tau)
          : 0.0;
      return clamp01(
        exponential *
            clamp01((monotonic - 0.55) / 0.4) *
            curvature *
            tauSignificance,
      );
    case WaveformSignalType.dampedOscillation:
      final envelopeR2 = features.envelopeDecayR2 ?? 0;
      final significance = _dampingSignificance(features);
      final regularity = features.oscillationRegularity ?? 0;
      final oscillation = clamp01((sineCorrelation - 0.55) / 0.4);
      return clamp01(
        (0.5 * envelopeR2 + 0.5 * significance) * oscillation +
            0.1 * regularity,
      );
    case WaveformSignalType.clippedSine:
      final clipPresence = clamp01(clipping / 0.08);
      final plateauPenalty = clamp01((twoLevel - 0.55) / 0.35);
      return clamp01(
        sineCorrelation *
            clipPresence *
            (1 - 0.9 * plateauPenalty) *
            (1 - _dampingSignificance(features) * 0.5),
      );
    case WaveformSignalType.noisySine:
      final noisePresence = clamp01(noiseFraction / 0.08);
      final clippingPenalty = clamp01((clipping - 0.02) / 0.08);
      final dampingPenalty = _dampingSignificance(features);
      return clamp01(
        sineCorrelation *
            noisePresence *
            (1 - 0.8 * clippingPenalty) *
            (1 - 0.85 * dampingPenalty),
      );
    case WaveformSignalType.pwm:
      final twoLevelP = twoLevelScore();
      final plateauP = clamp01(plateau * 1.1);
      final spread = duty == null
          ? 0.0
          : clamp01(math.min(duty, 100 - duty) / 10);
      final periodicity = features.periodCount >= 2 ? 1.0 : 0.35;
      final periodVariationPenalty =
          1 - clamp01((features.periodVariation ?? 0) / 0.3) * 0.5;
      // Proximity to 50 % and a stable duty cycle point to a symmetrical
      // square wave; a duty far from 50 % or a varying duty points to PWM.
      final nearHalf = duty == null ? 0.0 : clamp01(1 - (duty - 50).abs() / 20);
      final dutyVariation = clamp01((features.dutyCycleVariation ?? 0) / 0.08);
      final specificity = clamp01(1 - nearHalf * (1 - dutyVariation));
      // Very low duty cycles with long inactive intervals are pulse-like
      // rather than general PWM.
      final lowDutyFactor = duty == null ? 0.0 : clamp01((duty - 5) / 10);
      return clamp01(
        (0.4 * twoLevelP + 0.3 * plateauP + 0.3 * edgeScore()) *
            spread *
            periodicity *
            periodVariationPenalty *
            specificity *
            lowDutyFactor,
      );
  }
}

double _noiseFraction(WaveformFeatures features) {
  final residual = features.sineResidualRmsRatio ?? 0;
  final harmonic = features.residualHarmonicEnergyRatio ?? 0;
  final flatness = features.residualSpectralFlatness;
  // Deterministic distortion produces a line-like residual spectrum with a
  // low spectral flatness; broadband noise has a flat residual spectrum.
  final flatnessFactor = flatness == null
      ? 0.0
      : clamp01((flatness - 0.3) / 0.4);
  return clamp01(residual * (1 - harmonic) * flatnessFactor);
}

double _dampingSignificance(WaveformFeatures features) {
  final rate = features.envelopeDecayRate;
  final envelopeR2 = features.envelopeDecayR2 ?? 0;
  if (rate == null || rate <= 0) return 0;
  final decayOverRecord = rate * features.durationSeconds;
  return clamp01(decayOverRecord / 1.0) * clamp01(envelopeR2 / 0.5);
}

class _FeatureSpec {
  final String name;
  final double weight;
  final double? Function(WaveformFeatures) value;
  final double tolerance;
  final bool logarithmic;

  const _FeatureSpec({
    required this.name,
    required this.weight,
    required this.value,
    required this.tolerance,
    this.logarithmic = false,
  });
}

_FeatureSpec _spec(
  String name,
  double weight,
  double? Function(WaveformFeatures) value,
  double tolerance, {
  bool logarithmic = false,
}) {
  return _FeatureSpec(
    name: name,
    weight: weight,
    value: value,
    tolerance: tolerance,
    logarithmic: logarithmic,
  );
}

List<_FeatureSpec> _featureSpecsFor(WaveformSignalType type) {
  switch (type) {
    case WaveformSignalType.sine:
      return [
        _spec('sineCorrelation', 3, (f) => f.sineCorrelation, 0.2),
        _spec('thdPercent', 1.5, (f) => f.thdPercent, 10),
        _spec('twoLevelRatio', 1.5, (f) => f.twoLevelRatio, 0.2),
        _spec('crestFactor', 1, (f) => f.crestFactor, 0.3),
        _spec('symmetry', 1, (f) => f.symmetry, 0.2),
        _spec(
          'edgeSteepness',
          0.5,
          (f) => f.edgeSteepness,
          0.5,
          logarithmic: true,
        ),
        _spec('dutyPercent', 0.5, (f) => f.dutyPercent, 15),
        _spec(
          'differentialSecondZeroFraction',
          3,
          (f) => f.differential?.secondZeroFraction,
          0.18,
        ),
        _spec(
          'differentialFirstZeroFraction',
          2,
          (f) => f.differential?.firstZeroFraction,
          0.2,
        ),
        _spec(
          'differentialFirstBalance',
          1,
          (f) => f.differential?.firstBalance,
          0.2,
        ),
      ];
    case WaveformSignalType.square:
      return [
        _spec('twoLevelRatio', 3, (f) => f.twoLevelRatio, 0.15),
        _spec('plateauStability', 2, (f) => f.plateauStability, 0.2),
        _spec(
          'edgeSteepness',
          2,
          (f) => f.edgeSteepness,
          0.5,
          logarithmic: true,
        ),
        _spec('dutyPercent', 1.5, (f) => f.dutyPercent, 15),
        _spec(
          'riseTimeSeconds',
          1,
          (f) => f.riseTimeSeconds,
          0.6,
          logarithmic: true,
        ),
        _spec('symmetry', 0.5, (f) => f.symmetry, 0.2),
        _spec(
          'differentialFirstZeroFraction',
          3,
          (f) => f.differential?.firstZeroFraction,
          0.25,
        ),
        _spec(
          'differentialSecondZeroFraction',
          1.5,
          (f) => f.differential?.secondZeroFraction,
          0.3,
        ),
        _spec(
          'differentialFirstBalance',
          1.5,
          (f) => f.differential?.firstBalance,
          0.2,
        ),
      ];
    case WaveformSignalType.triangle:
      return [
        _spec('rampLinearity', 3, (f) => f.rampLinearity, 0.2),
        _spec('slopeSymmetry', 3, (f) => f.slopeSymmetry, 0.2),
        _spec('twoLevelRatio', 1.5, (f) => f.twoLevelRatio, 0.2),
        _spec(
          'edgeSteepness',
          1,
          (f) => f.edgeSteepness,
          0.5,
          logarithmic: true,
        ),
        _spec('triangleCorrelation', 2, (f) => f.triangleCorrelation, 0.2),
        _spec(
          'differentialSecondZeroFraction',
          3,
          (f) => f.differential?.secondZeroFraction,
          0.45,
        ),
        _spec(
          'differentialFirstZeroFraction',
          2,
          (f) => f.differential?.firstZeroFraction,
          0.2,
        ),
        _spec(
          'differentialFirstBalance',
          1,
          (f) => f.differential?.firstBalance,
          0.2,
        ),
      ];
    case WaveformSignalType.sawtooth:
      return [
        _spec('resetRatio', 3, (f) => f.resetRatio, 0.6, logarithmic: true),
        _spec('rampLinearity', 2, (f) => f.rampLinearity, 0.2),
        _spec('slopeSymmetry', 2, (f) => f.slopeSymmetry, 0.2),
        _spec('sawtoothCorrelation', 2, (f) => f.sawtoothCorrelation, 0.2),
        _spec('dutyPercent', 1, (f) => f.dutyPercent, 20),
        _spec(
          'differentialFirstBalance',
          3,
          (f) => f.differential?.firstBalance,
          0.2,
        ),
        _spec(
          'differentialFirstZeroFraction',
          1.5,
          (f) => f.differential?.firstZeroFraction,
          0.2,
        ),
        _spec(
          'differentialSecondZeroFraction',
          1,
          (f) => f.differential?.secondZeroFraction,
          0.3,
        ),
      ];
    case WaveformSignalType.pulse:
      return [
        _spec('dutyPercent', 3, (f) => f.dutyPercent, 15),
        _spec(
          'pulseCount',
          2,
          (f) => f.pulseCount.toDouble(),
          0.5,
          logarithmic: true,
        ),
        _spec(
          'edgeSteepness',
          2,
          (f) => f.edgeSteepness,
          0.5,
          logarithmic: true,
        ),
        _spec('twoLevelRatio', 2, (f) => f.twoLevelRatio, 0.2),
        _spec('plateauStability', 1, (f) => f.plateauStability, 0.25),
      ];
    case WaveformSignalType.exponentialDecay:
      return [
        _spec('exponentialFitR2', 4, (f) => f.exponentialFitR2, 0.15),
        _spec(
          'exponentialTauSeconds',
          3,
          (f) => f.exponentialTauSeconds,
          0.6,
          logarithmic: true,
        ),
        _spec('monotonicFraction', 2, (f) => f.monotonicFraction, 0.25),
        _spec('linearFitR2', 2, (f) => f.linearFitR2, 0.2),
        _spec('symmetry', 1, (f) => f.symmetry, 0.25),
      ];
    case WaveformSignalType.dampedOscillation:
      return [
        _spec('envelopeDecayR2', 3, (f) => f.envelopeDecayR2, 0.2),
        _spec(
          'envelopeDecayRatePerSecond',
          3,
          (f) => f.envelopeDecayRate,
          0.6,
          logarithmic: true,
        ),
        _spec('oscillationRegularity', 2, (f) => f.oscillationRegularity, 0.2),
        _spec('sineCorrelation', 2, (f) => f.sineCorrelation, 0.2),
        _spec('periodVariation', 1, (f) => f.periodVariation, 0.15),
      ];
    case WaveformSignalType.clippedSine:
      return [
        _spec('clippingRatio', 3, (f) => f.clippingRatio, 0.05),
        _spec('sineCorrelation', 3, (f) => f.sineCorrelation, 0.2),
        _spec('thdPercent', 2, (f) => f.thdPercent, 10),
        _spec('twoLevelRatio', 1, (f) => f.twoLevelRatio, 0.2),
        _spec('plateauStability', 1, (f) => f.plateauStability, 0.25),
      ];
    case WaveformSignalType.noisySine:
      return [
        _spec('sineResidualSnrDb', 3, (f) => f.sineResidualSnrDb, 10),
        _spec(
          'residualSpectralFlatness',
          2,
          (f) => f.residualSpectralFlatness,
          0.2,
        ),
        _spec(
          'residualHarmonicEnergyRatio',
          2,
          (f) => f.residualHarmonicEnergyRatio,
          0.25,
        ),
        _spec('sineCorrelation', 2, (f) => f.sineCorrelation, 0.2),
        _spec('snrDb', 1, (f) => f.snrDb, 10),
      ];
    case WaveformSignalType.pwm:
      return [
        _spec('dutyPercent', 3, (f) => f.dutyPercent, 15),
        _spec('dutyCycleVariation', 2, (f) => f.dutyCycleVariation, 0.15),
        _spec('twoLevelRatio', 2, (f) => f.twoLevelRatio, 0.2),
        _spec(
          'edgeSteepness',
          2,
          (f) => f.edgeSteepness,
          0.5,
          logarithmic: true,
        ),
        _spec('plateauStability', 1, (f) => f.plateauStability, 0.25),
      ];
  }
}

double _compareFeature(
  double? capture,
  double? reference, {
  required double tolerance,
  required bool logarithmic,
}) {
  if (capture == null && reference == null) return 1;
  if (capture == null || reference == null) return 0.25;
  if (!capture.isFinite || !reference.isFinite) return 0.25;
  double difference;
  if (logarithmic) {
    if (capture <= 0 && reference <= 0) return 1;
    if (capture <= 0 || reference <= 0) return 0;
    difference =
        (math.log(capture / reference) / math.ln10).abs() /
        (math.log(1 + tolerance) / math.ln10);
  } else {
    difference = (capture - reference).abs() / tolerance;
  }
  return math.exp(-difference * difference);
}

List<double> _relativeHarmonics(WaveformFeatures features) {
  final harmonics = features.harmonicAmplitudes;
  if (harmonics.length < 2) return const [];
  final fundamental = harmonics.first;
  if (fundamental <= 1e-12) return const [];
  final result = <double>[];
  for (var i = 1; i < harmonics.length; i++) {
    result.add(harmonics[i] / fundamental);
  }
  return result;
}

double _cosineSimilarity(List<double> a, List<double> b) {
  final length = math.min(a.length, b.length);
  if (length == 0) return 1;
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA <= 1e-15 && normB <= 1e-15) return 1;
  if (normA <= 1e-15 || normB <= 1e-15) return 0.25;
  return clamp01(dot / math.sqrt(normA * normB));
}

double _logCloseness(double? a, double? b, {required double toleranceLog10}) {
  if (a == null && b == null) return 1;
  if (a == null || b == null || a <= 0 || b <= 0) return 0.4;
  final difference = (math.log(a / b) / math.ln10).abs() / toleranceLog10;
  return math.exp(-difference * difference);
}
