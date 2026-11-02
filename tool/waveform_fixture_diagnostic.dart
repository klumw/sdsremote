// Diagnostic: evaluate candidate similarity weights against the waveform
// analysis test fixtures used by classification_test.dart.
//
//   dart run tool/waveform_fixture_diagnostic.dart
//
// Prints, per candidate weight vector, the ideal-reference score/margin, the
// sampleRate500k damped-oscillation result and the PWM 58 % alternatives hint.

// ignore_for_file: avoid_print

import 'package:sdsremote/src/waveform/analysis/waveform_analysis_models.dart';
import 'package:sdsremote/src/waveform/analysis/waveform_analysis_service.dart';

import '../test/src/waveform_analysis/signal_fixtures.dart';

const _candidates = <String, SimilarityWeights>{
  'old': SimilarityWeights(
    shape: 0.24,
    feature: 0.24,
    frequency: 0.16,
    dtw: 0.16,
    rule: 0.20,
  ),
  'calibrated': SimilarityWeights(
    shape: 0.65,
    feature: 0.05,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'alt1': SimilarityWeights(
    shape: 0.55,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.15,
  ),
  'alt2': SimilarityWeights(
    shape: 0.50,
    feature: 0.15,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.15,
  ),
  'alt3': SimilarityWeights(
    shape: 0.60,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.10,
    rule: 0.15,
  ),
  'alt4': SimilarityWeights(
    shape: 0.55,
    feature: 0.15,
    frequency: 0.05,
    dtw: 0.10,
    rule: 0.15,
  ),
  'alt5': SimilarityWeights(
    shape: 0.60,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'alt6': SimilarityWeights(
    shape: 0.50,
    feature: 0.15,
    frequency: 0.10,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine1': SimilarityWeights(
    shape: 0.63,
    feature: 0.07,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine2': SimilarityWeights(
    shape: 0.62,
    feature: 0.08,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine3': SimilarityWeights(
    shape: 0.61,
    feature: 0.09,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine4': SimilarityWeights(
    shape: 0.60,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine5': SimilarityWeights(
    shape: 0.63,
    feature: 0.07,
    frequency: 0.05,
    dtw: 0.13,
    rule: 0.12,
  ),
  'fine6': SimilarityWeights(
    shape: 0.62,
    feature: 0.08,
    frequency: 0.05,
    dtw: 0.13,
    rule: 0.12,
  ),
  'fine7': SimilarityWeights(
    shape: 0.58,
    feature: 0.12,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'fine8': SimilarityWeights(
    shape: 0.64,
    feature: 0.06,
    frequency: 0.05,
    dtw: 0.15,
    rule: 0.10,
  ),
  'more1': SimilarityWeights(
    shape: 0.60,
    feature: 0.08,
    frequency: 0.05,
    dtw: 0.13,
    rule: 0.14,
  ),
  'more2': SimilarityWeights(
    shape: 0.58,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.13,
    rule: 0.14,
  ),
  'more3': SimilarityWeights(
    shape: 0.56,
    feature: 0.12,
    frequency: 0.05,
    dtw: 0.13,
    rule: 0.14,
  ),
  'more4': SimilarityWeights(
    shape: 0.60,
    feature: 0.10,
    frequency: 0.05,
    dtw: 0.12,
    rule: 0.13,
  ),
  'more5': SimilarityWeights(
    shape: 0.58,
    feature: 0.12,
    frequency: 0.05,
    dtw: 0.12,
    rule: 0.13,
  ),
  'more6': SimilarityWeights(
    shape: 0.62,
    feature: 0.08,
    frequency: 0.05,
    dtw: 0.12,
    rule: 0.13,
  ),
};

void main() {
  final service = WaveformAnalysisService();
  for (final entry in _candidates.entries) {
    final options = WaveformAnalysisOptions(
      weights: entry.value,
      ambiguityMargin: 3,
    );
    print('\n=== ${entry.key}: ${entry.value.toMap()} ===');
    var idealOk = 0;
    for (final type in WaveformSignalType.values) {
      final result = service.classify(signalWith(type), options: options);
      final margin = result.topCandidates.length > 1
          ? result.score - result.topCandidates[1].score
          : 0.0;
      final ok =
          result.primaryType == type && result.score >= 75 && margin >= 3;
      if (ok) idealOk++;
      print(
        '  ideal ${type.id.padRight(20)} '
        '${(result.primaryType?.id ?? 'unknown').padRight(20)} '
        'score=${result.score.toStringAsFixed(1)} '
        'margin=${margin.toStringAsFixed(1)} '
        'conf=${result.confidence.name} alt=${result.mentionAlternatives} '
        '${ok ? 'OK' : 'FAIL'}',
      );
    }
    final damped = service.classify(
      signalWith(
        WaveformSignalType.dampedOscillation,
        sampleRate: 500000,
        duration: 0.002,
      ),
      options: options,
    );
    print(
      '  damped500k ${(damped.primaryType?.id ?? 'unknown').padRight(20)} '
      'score=${damped.score.toStringAsFixed(1)} '
      'top2=${damped.topCandidates.take(2).map((c) => '${c.type.id}=${c.score.toStringAsFixed(1)}').join(', ')}',
    );
    final pwm = service.classify(
      signalWith(WaveformSignalType.pwm, duty: 0.58, duration: 0.01),
      options: options,
    );
    final pwmMargin = pwm.topCandidates.length > 1
        ? pwm.score - pwm.topCandidates[1].score
        : 0.0;
    print(
      '  pwm58 ${(pwm.primaryType?.id ?? 'unknown').padRight(20)} '
      'score=${pwm.score.toStringAsFixed(1)} '
      'margin=${pwmMargin.toStringAsFixed(1)} '
      'conf=${pwm.confidence.name} alt=${pwm.mentionAlternatives}',
    );
    print('  ideal OK: $idealOk/10');
  }

  final selected = _candidates['more6']!;
  for (final duty in const [0.50, 0.52, 0.54, 0.56, 0.58]) {
    final result = service.classify(
      signalWith(WaveformSignalType.pwm, duty: duty, duration: 0.01),
      options: WaveformAnalysisOptions(weights: selected, ambiguityMargin: 3),
    );
    final margin = result.topCandidates.length > 1
        ? result.score - result.topCandidates[1].score
        : 0.0;
    print(
      'pwm duty=$duty -> ${result.primaryType?.id ?? 'unknown'} '
      'score=${result.score.toStringAsFixed(1)} '
      'margin=${margin.toStringAsFixed(1)} '
      'conf=${result.confidence.name} alt=${result.mentionAlternatives}',
    );
  }
}
