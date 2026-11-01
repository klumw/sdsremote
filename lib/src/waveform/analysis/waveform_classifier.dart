/// Waveform classification against the ten reference signal types.
///
/// The classifier preprocesses the capture, extracts its features, generates
/// matching reference variants, compares every candidate with four independent
/// methods, applies signal-specific detection rules and returns a ranked,
/// explained result. Similarity scores are descriptive, not calibrated
/// probabilities.
library;

import 'waveform_analysis_models.dart';
import 'waveform_anomaly_detector.dart';
import 'waveform_feature_extractor.dart';
import 'waveform_preprocessor.dart';
import 'reference_waveform_generator.dart';
import 'waveform_similarity.dart';

/// Runs the complete classification pipeline.
class WaveformClassifier {
  const WaveformClassifier({
    this.generator = const ReferenceWaveformGenerator(),
    this.anomalyDetector = const WaveformAnomalyDetector(),
  });

  final ReferenceWaveformGenerator generator;
  final WaveformAnomalyDetector anomalyDetector;

  /// Classifies [trace] against the enabled reference types.
  WaveformClassification classify(
    WaveformTrace trace, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channel,
  }) {
    final channelName = channel ?? trace.channel;
    final preprocessed = preprocessWaveform(
      trace,
      maxAnalysisPoints: options.maxAnalysisPoints,
      smoothing: options.smoothing,
    );

    if (!preprocessed.sufficient || preprocessed.analysis.isEmpty) {
      return _insufficientResult(
        channelName: channelName,
        preprocessed: preprocessed,
        options: options,
      );
    }

    final features = extractWaveformFeatures(
      preprocessed,
      harmonicCount: options.harmonicCount,
    );
    final weights = options.weights.normalized();
    final evaluations = <_TypeEvaluation>[];

    for (final type in options.enabledTypes) {
      final variants = generator.variantsFor(
        type: type,
        preprocessed: preprocessed,
        features: features,
        maxVariants: options.maxReferenceVariants,
      );
      _TypeEvaluation? best;
      for (final reference in variants) {
        final referencePreprocessed = preprocessedReference(
          reference,
          maxAnalysisPoints: preprocessed.analysis.length,
        );
        final referenceFeatures = extractWaveformFeatures(
          referencePreprocessed,
          harmonicCount: options.harmonicCount,
        );
        final shape = compareShapes(
          preprocessed.normalized,
          referencePreprocessed.normalized,
          durationSeconds: preprocessed.analysis.durationSeconds,
        );
        final featureScore = featureSimilarity(
          features,
          referenceFeatures,
          type,
        );
        final frequencyScore = frequencyDomainSimilarity(
          features,
          referenceFeatures,
        );
        final ruleScore = detectionRuleScore(type, features) * 100;

        var score =
            (weights.shape * shape.percent +
                    weights.feature * featureScore +
                    weights.frequency * frequencyScore +
                    weights.dtw * shape.dtwPercent +
                    weights.rule * ruleScore)
                .clamp(0.0, 100.0);
        // An exponential classification requires a measurable exponential
        // model: without curvature and an observable time constant the shape
        // is indistinguishable from a straight ramp. Gate the score on the
        // exponential detection rule instead of letting the generic shape
        // comparison dominate.
        if (type == WaveformSignalType.exponentialDecay) {
          final gate = (ruleScore / 100 / 0.15).clamp(0.0, 1.0);
          score *= gate;
        }

        final breakdown = SimilarityBreakdown(
          shapeSimilarity: shape.percent,
          featureSimilarity: featureScore,
          frequencySimilarity: frequencyScore,
          dtwSimilarity: shape.dtwPercent,
          ruleSimilarity: ruleScore,
          rawCorrelation: shape.coefficient,
          lagSamples: shape.lagSamples,
          lagSeconds: shape.lagSeconds,
          score: score,
          weights: weights,
        );
        final candidate = ClassificationCandidate(
          type: type,
          score: score,
          confidence: ClassificationConfidence.fromScore(score),
          breakdown: breakdown,
          referenceParameters: reference.parameters,
          notes: ['weakest component: ${_weakestComponent(breakdown)}'],
        );
        if (best == null || score > best.candidate.score) {
          best = _TypeEvaluation(
            candidate: candidate,
            reference: reference,
            referenceFeatures: referenceFeatures,
            shape: shape,
          );
        }
      }
      if (best != null) evaluations.add(best);
    }

    evaluations.sort((a, b) => b.candidate.score.compareTo(a.candidate.score));
    final candidates = [
      for (final evaluation in evaluations) evaluation.candidate,
    ];

    final bestScore = candidates.isEmpty ? 0.0 : candidates.first.score;
    final secondScore = candidates.length > 1 ? candidates[1].score : 0.0;
    var maxShapeCorrelation = 0.0;
    for (final value in [
      features.sineCorrelation,
      features.squareCorrelation,
      features.triangleCorrelation,
      features.sawtoothCorrelation,
    ]) {
      if (value != null && value > maxShapeCorrelation) {
        maxShapeCorrelation = value;
      }
    }
    // A broadband capture without a fundamental, without a monotonic
    // exponential envelope and without any strong shape correlation cannot be
    // assigned to a reference merely because one candidate scores slightly
    // above the low-similarity threshold.
    final noiseLike =
        preprocessed.estimatedFundamentalHz == null &&
        (features.monotonicFraction ?? 0) < 0.75 &&
        maxShapeCorrelation < 0.75 &&
        (features.envelopeDecayR2 ?? 0) < 0.6 &&
        (features.twoLevelRatio ?? 0) < 0.7;
    final uncertain =
        candidates.isEmpty ||
        bestScore < options.minConfidentScore ||
        noiseLike;
    final ambiguous =
        !uncertain &&
        candidates.length > 1 &&
        (bestScore - secondScore) < options.ambiguityMargin &&
        bestScore < 75;

    final primary = uncertain || candidates.isEmpty
        ? null
        : candidates.first.type;
    final label = uncertain
        ? 'Unknown or mixed waveform'
        : ambiguous
        ? '${primary!.label} (mixed result)'
        : primary!.label;
    final bestConfidence = ClassificationConfidence.fromScore(bestScore);
    final highConfidence =
        !uncertain &&
        (bestConfidence == ClassificationConfidence.veryHigh ||
            bestConfidence == ClassificationConfidence.high);
    final closeAlternatives =
        candidates.length > 1 &&
        (bestScore - secondScore) < options.ambiguityMargin;
    final mentionAlternatives = !highConfidence || closeAlternatives;

    final warnings = <String>[...preprocessed.warnings];
    if (noiseLike) {
      warnings.add(
        'no stable periodic fundamental, exponential envelope or strong '
        'shape correlation was found; the capture is likely noise-dominated',
      );
    }
    if (uncertain && candidates.isNotEmpty) {
      warnings.add(
        'the best candidate (${candidates.first.type.label}) reached only '
        '${bestScore.toStringAsFixed(1)} % similarity',
      );
    }
    if (ambiguous) {
      warnings.add(
        'the top two candidates are within '
        '${(bestScore - secondScore).toStringAsFixed(1)} percentage points',
      );
    }

    final secondary = _secondaryCharacteristics(features, primary);

    var anomalies = const <WaveformAnomaly>[];
    if (evaluations.isNotEmpty) {
      final best = evaluations.first;
      final analysis = preprocessed.analysis;
      final duration = analysis.durationSeconds;
      final lagSamples = best.shape.lagSeconds == null || duration <= 0
          ? 0
          : (best.shape.lagSeconds! / duration * analysis.length).round();
      anomalies = anomalyDetector.detect(
        features: features,
        primaryType: best.candidate.type,
        captureVolts: analysis.volts,
        referenceVolts: best.reference.trace.volts,
        durationSeconds: duration,
        startTimeSeconds: analysis.times.isEmpty ? 0 : analysis.times.first,
        lagSamples: lagSamples,
      );
    }

    final explanation = _buildExplanation(
      label: label,
      score: bestScore,
      confidence: bestConfidence,
      candidates: candidates,
      features: features,
      anomalies: anomalies,
      uncertain: uncertain,
      ambiguous: ambiguous,
      mentionAlternatives: mentionAlternatives,
    );

    return WaveformClassification(
      channel: channelName,
      primaryType: primary,
      primaryLabel: label,
      score: bestScore,
      confidence: bestConfidence,
      uncertain: uncertain,
      ambiguous: ambiguous,
      mentionAlternatives: mentionAlternatives,
      topCandidates: candidates.take(3).toList(),
      allCandidates: candidates,
      features: features,
      anomalies: anomalies,
      secondaryCharacteristics: secondary,
      explanation: explanation,
      warnings: warnings,
      referenceParameters: candidates.isEmpty
          ? null
          : candidates.first.referenceParameters,
      sampleCount: features.sampleCount,
      durationSeconds: features.durationSeconds,
      weights: weights,
    );
  }

  WaveformClassification _insufficientResult({
    required String? channelName,
    required PreprocessedWaveform preprocessed,
    required WaveformAnalysisOptions options,
  }) {
    final features = preprocessed.analysis.isEmpty
        ? const WaveformFeatures(sampleCount: 0, durationSeconds: 0)
        : extractWaveformFeatures(
            preprocessed,
            harmonicCount: options.harmonicCount,
          );
    final warnings = [...preprocessed.warnings];
    if (warnings.isEmpty) {
      warnings.add('insufficient data for reliable classification');
    }
    return WaveformClassification(
      channel: channelName,
      primaryType: null,
      primaryLabel: 'Unknown or mixed waveform',
      score: 0,
      confidence: ClassificationConfidence.uncertain,
      uncertain: true,
      ambiguous: false,
      mentionAlternatives: true,
      topCandidates: const [],
      allCandidates: const [],
      features: features,
      anomalies: const [],
      secondaryCharacteristics: const [],
      explanation:
          'The captured waveform could not be analysed reliably: '
          '${warnings.join('; ')}. Acquire a longer record with a stable '
          'trigger before requesting a classification.',
      warnings: warnings,
      sampleCount: features.sampleCount,
      durationSeconds: features.durationSeconds,
      weights: options.weights.normalized(),
    );
  }
}

class _TypeEvaluation {
  final ClassificationCandidate candidate;
  final ReferenceWaveform reference;
  final WaveformFeatures referenceFeatures;
  final ShapeSimilarity shape;

  const _TypeEvaluation({
    required this.candidate,
    required this.reference,
    required this.referenceFeatures,
    required this.shape,
  });
}

String _weakestComponent(SimilarityBreakdown breakdown) {
  final components = <String, double>{
    'shape correlation': breakdown.shapeSimilarity,
    'feature similarity': breakdown.featureSimilarity,
    'frequency-domain similarity': breakdown.frequencySimilarity,
    'DTW similarity': breakdown.dtwSimilarity,
    'detection rules': breakdown.ruleSimilarity,
  };
  final weakest = components.entries.reduce(
    (a, b) => a.value <= b.value ? a : b,
  );
  return '${weakest.key} (${weakest.value.toStringAsFixed(1)} %)';
}

double _componentValue(SimilarityBreakdown breakdown, String label) {
  return switch (label) {
    'shape correlation' => breakdown.shapeSimilarity,
    'feature similarity' => breakdown.featureSimilarity,
    'frequency-domain similarity' => breakdown.frequencySimilarity,
    'DTW similarity' => breakdown.dtwSimilarity,
    'detection rules' => breakdown.ruleSimilarity,
    _ => 0,
  };
}

String _buildExplanation({
  required String label,
  required double score,
  required ClassificationConfidence confidence,
  required List<ClassificationCandidate> candidates,
  required WaveformFeatures features,
  required List<WaveformAnomaly> anomalies,
  required bool uncertain,
  required bool ambiguous,
  required bool mentionAlternatives,
}) {
  final buffer = StringBuffer();
  if (uncertain) {
    buffer.write(
      'The captured waveform could not be matched to a reference with '
      'sufficient confidence. ',
    );
    if (candidates.isNotEmpty) {
      buffer.write(
        'The best candidate is ${candidates.first.type.label} with '
        '${score.toStringAsFixed(1)} % similarity. ',
      );
    }
  } else {
    buffer.write(
      'The captured waveform is classified as $label with '
      '${score.toStringAsFixed(1)} % similarity '
      '(${confidence.label.toLowerCase()} confidence). ',
    );
    if (ambiguous) {
      buffer.write(
        'The result is ambiguous because the second candidate is nearly as '
        'close. ',
      );
    }
  }

  final measurements = <String>[];
  if (features.frequencyHz != null) {
    measurements.add(
      'fundamental frequency ${_formatHz(features.frequencyHz!)}',
    );
  }
  if (features.vPp != null) {
    measurements.add('Vpp ${_formatVolts(features.vPp!)}');
  }
  if (features.dutyPercent != null) {
    measurements.add(
      'duty cycle ${features.dutyPercent!.toStringAsFixed(1)} %',
    );
  }
  if (features.riseTimeSeconds != null) {
    measurements.add('rise time ${_formatSeconds(features.riseTimeSeconds!)}');
  }
  if (features.thdPercent != null) {
    measurements.add('THD ${features.thdPercent!.toStringAsFixed(1)} %');
  }
  if (features.snrDb != null) {
    measurements.add('spectral SNR ${features.snrDb!.toStringAsFixed(1)} dB');
  }
  if (features.clippingRatio != null && features.clippingRatio! > 0.01) {
    measurements.add(
      'clipped samples ${(features.clippingRatio! * 100).toStringAsFixed(1)} %',
    );
  }
  if (features.exponentialFitR2 != null) {
    measurements.add(
      'exponential fit R² ${features.exponentialFitR2!.toStringAsFixed(3)}',
    );
  }
  if (features.envelopeDecayRate != null) {
    measurements.add(
      'envelope decay ${features.envelopeDecayRate!.toStringAsFixed(1)} 1/s',
    );
  }
  if (measurements.isNotEmpty) {
    buffer.write('${measurements.join(', ')}. ');
  }

  for (final candidate
      in mentionAlternatives
          ? candidates.skip(1).take(2)
          : const <ClassificationCandidate>[]) {
    final weakest = _weakestComponent(candidate.breakdown);
    final weakestLabel = weakest.split(' (').first;
    final selectedValue = _componentValue(
      candidates.first.breakdown,
      weakestLabel,
    );
    buffer.write(
      '${candidate.type.label} reached '
      '${candidate.score.toStringAsFixed(1)} %; its lowest component was '
      '$weakest, compared with '
      '${selectedValue.toStringAsFixed(1)} % for the selected type. ',
    );
  }

  if (anomalies.isEmpty) {
    buffer.write(
      'No significant deviations from the reference were detected. ',
    );
  } else {
    final labels = [
      for (final anomaly in anomalies)
        '${anomaly.label} (${anomaly.severity.label.toLowerCase()})',
    ];
    buffer.write('Detected deviations: ${labels.join(', ')}. ');
  }

  if (uncertain) {
    buffer.write(
      'Conclusion: the signal is unknown or mixed; acquire more periods, '
      'reduce noise or increase the vertical resolution for a reliable '
      'classification.',
    );
  } else if (ambiguous) {
    buffer.write(
      'Conclusion: the signal is best described as $label, but an alternative '
      'reference is nearly equally close.',
    );
  } else {
    buffer.write(
      'Conclusion: the signal is predominantly '
      '${label.replaceAll(' (mixed result)', '').toLowerCase()}.',
    );
  }
  return buffer.toString();
}

List<String> _secondaryCharacteristics(
  WaveformFeatures features,
  WaveformSignalType? primary,
) {
  final result = <String>[];
  final rectangular =
      primary == WaveformSignalType.square ||
      primary == WaveformSignalType.pwm ||
      primary == WaveformSignalType.pulse;
  final clipping = features.clippingRatio ?? 0;
  if (clipping > 0.02 &&
      !rectangular &&
      primary != WaveformSignalType.clippedSine) {
    result.add('Clipping');
  }
  final residual = features.sineResidualRmsRatio ?? 0;
  final harmonic = features.residualHarmonicEnergyRatio ?? 0;
  final flatness = features.residualSpectralFlatness;
  final flatnessFactor = flatness == null
      ? 0.0
      : ((flatness - 0.3) / 0.4).clamp(0.0, 1.0);
  if (residual * (1 - harmonic) * flatnessFactor > 0.04 &&
      primary != WaveformSignalType.noisySine) {
    result.add('Noise');
  }
  final decaySignificance = _decaySignificance(features);
  if (decaySignificance > 0.35 &&
      primary != WaveformSignalType.dampedOscillation) {
    result.add('Damped envelope');
  }
  if ((features.dutyCycleVariation ?? 0) > 0.05) {
    result.add('Variable duty cycle');
  }
  final vTop = features.vTop;
  final vBase = features.vBase;
  final vMax = features.vMax;
  final vMin = features.vMin;
  final amplitude = vTop != null && vBase != null ? vTop - vBase : 0.0;
  if (amplitude > 0 && vMax != null && (vMax - vTop!) / amplitude > 0.02) {
    result.add('Overshoot');
  }
  if (amplitude > 0 && vMin != null && (vBase! - vMin) / amplitude > 0.02) {
    result.add('Undershoot');
  }
  if ((features.thdPercent ?? 0) > 5 &&
      !rectangular &&
      (primary == WaveformSignalType.sine ||
          primary == WaveformSignalType.noisySine ||
          primary == WaveformSignalType.dampedOscillation ||
          primary == WaveformSignalType.clippedSine)) {
    result.add('Harmonic distortion');
  }
  if ((features.vPp ?? 0) > 0 &&
      (features.vMean ?? 0).abs() / features.vPp! > 0.05) {
    result.add('DC offset');
  }
  if ((features.periodVariation ?? 0) > 0.02) {
    result.add('Timing jitter');
  }
  if (primary == WaveformSignalType.exponentialDecay &&
      features.exponentialRising) {
    result.add('Exponential rise');
  }
  return result;
}

double _decaySignificance(WaveformFeatures features) {
  final rate = features.envelopeDecayRate;
  final r2 = features.envelopeDecayR2 ?? 0;
  if (rate == null || rate <= 0) return 0;
  return (rate * features.durationSeconds).clamp(0.0, 1.0) *
      (r2 / 0.5).clamp(0.0, 1.0);
}

String _formatHz(double value) {
  final magnitude = value.abs();
  if (magnitude >= 1e9) return '${(value / 1e9).toStringAsFixed(3)} GHz';
  if (magnitude >= 1e6) return '${(value / 1e6).toStringAsFixed(3)} MHz';
  if (magnitude >= 1e3) return '${(value / 1e3).toStringAsFixed(3)} kHz';
  return '${value.toStringAsFixed(3)} Hz';
}

String _formatVolts(double value) {
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(3)} V';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(2)} mV';
  return '${(value * 1e6).toStringAsFixed(1)} µV';
}

String _formatSeconds(double value) {
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(3)} s';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(2)} ms';
  if (magnitude >= 1e-6) return '${(value * 1e6).toStringAsFixed(2)} µs';
  return '${(value * 1e9).toStringAsFixed(1)} ns';
}
