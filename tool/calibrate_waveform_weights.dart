// Offline calibration of the waveform classifier weights and thresholds.
//
// Reads the JSONL produced by
// test/waveform_classification_calibration_live_test.dart, re-scores every
// recorded candidate with the stored shape/feature/frequency/DTW/rule
// components, and searches for the weights and thresholds that maximise the
// macro-averaged recall on a held-out frequency split.
//
//   dart run tool/calibrate_waveform_weights.dart \
//     /tmp/waveform_calibration/run1/cases.jsonl
//
// Optional:
//   --out=/path/report.json   report path (default: report.json next to input)
//   --step=10                 weight grid resolution (10 = 0.1 increments)
//   --top=200                 number of candidates re-checked with 5-fold CV
//   --min-weight=0.05         minimum weight for every score component
//   --min-high-score=0.90     minimum share of correct cases scoring over 90

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

class CandidateScore {
  final String type;
  final double shape;
  final double feature;
  final double frequency;
  final double dtw;
  final double rule;

  const CandidateScore({
    required this.type,
    required this.shape,
    required this.feature,
    required this.frequency,
    required this.dtw,
    required this.rule,
  });
}

class CaseData {
  final String caseId;
  final String expected;
  final double frequencyHz;
  final bool noiseLike;
  final String? baselinePrimary;
  final List<CandidateScore> candidates;
  int fold = 0;

  CaseData({
    required this.caseId,
    required this.expected,
    required this.frequencyHz,
    required this.noiseLike,
    required this.baselinePrimary,
    required this.candidates,
  });
}

class Weights {
  final double shape;
  final double feature;
  final double frequency;
  final double dtw;
  final double rule;

  const Weights(this.shape, this.feature, this.frequency, this.dtw, this.rule);

  static const defaults = Weights(0.24, 0.24, 0.16, 0.16, 0.20);

  String get label =>
      'shape=${shape.toStringAsFixed(2)} '
      'feature=${feature.toStringAsFixed(2)} '
      'frequency=${frequency.toStringAsFixed(2)} '
      'dtw=${dtw.toStringAsFixed(2)} '
      'rule=${rule.toStringAsFixed(2)}';

  Map<String, double> toMap() => {
    'shape': shape,
    'feature': feature,
    'frequency': frequency,
    'dtw': dtw,
    'rule': rule,
  };
}

class Evaluation {
  final int total;
  final int correct;
  final int unknown;
  final Map<String, int> totals;
  final Map<String, int> hits;
  final Map<String, Map<String, int>> confusion;

  const Evaluation({
    required this.total,
    required this.correct,
    required this.unknown,
    required this.totals,
    required this.hits,
    required this.confusion,
  });

  double get accuracy => total == 0 ? 0 : correct / total;

  double get macroRecall {
    final recalls = <double>[];
    for (final entry in totals.entries) {
      if (entry.value == 0) continue;
      recalls.add((hits[entry.key] ?? 0) / entry.value);
    }
    if (recalls.isEmpty) return 0;
    return recalls.reduce((a, b) => a + b) / recalls.length;
  }

  String get summary =>
      'acc=${(100 * accuracy).toStringAsFixed(1)}% '
      'macro=${(100 * macroRecall).toStringAsFixed(1)}% '
      'unknown=$unknown/$total';

  Map<String, dynamic> toMap() => {
    'total': total,
    'correct': correct,
    'unknown': unknown,
    'accuracy': accuracy,
    'macroRecall': macroRecall,
    'perTypeRecall': {
      for (final entry in totals.entries)
        entry.key: entry.value == 0
            ? 0.0
            : (hits[entry.key] ?? 0) / entry.value,
    },
    'confusion': {
      for (final entry in confusion.entries)
        entry.key: Map<String, int>.from(entry.value),
    },
  };
}

double scoreCandidate(CandidateScore candidate, Weights weights, double gate) {
  var score =
      weights.shape * candidate.shape +
      weights.feature * candidate.feature +
      weights.frequency * candidate.frequency +
      weights.dtw * candidate.dtw +
      weights.rule * candidate.rule;
  if (candidate.type == 'exponential_decay') {
    score *= (candidate.rule / 100 / gate).clamp(0.0, 1.0);
  }
  return score.clamp(0.0, 100.0);
}

String predictedType(
  CaseData data,
  Weights weights,
  double minScore, {
  double gate = 0.15,
}) {
  CandidateScore? best;
  var bestScore = -1.0;
  for (final candidate in data.candidates) {
    final score = scoreCandidate(candidate, weights, gate);
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  if (best == null || data.noiseLike || bestScore < minScore) return 'unknown';
  return best.type;
}

Evaluation evaluate(
  List<CaseData> cases,
  Weights weights,
  double minScore, {
  double gate = 0.15,
}) {
  final totals = <String, int>{};
  final hits = <String, int>{};
  final confusion = <String, Map<String, int>>{};
  var correct = 0;
  var unknown = 0;

  for (final data in cases) {
    totals[data.expected] = (totals[data.expected] ?? 0) + 1;
    final predicted = predictedType(data, weights, minScore, gate: gate);
    if (predicted == 'unknown') unknown++;
    if (predicted == data.expected) {
      correct++;
      hits[data.expected] = (hits[data.expected] ?? 0) + 1;
    }
    confusion.putIfAbsent(data.expected, () => {});
    confusion[data.expected]![predicted] =
        (confusion[data.expected]![predicted] ?? 0) + 1;
  }

  return Evaluation(
    total: cases.length,
    correct: correct,
    unknown: unknown,
    totals: totals,
    hits: hits,
    confusion: confusion,
  );
}

/// Share of correctly classified cases whose best score is above 90.
///
/// The agent only states a classification above 90 %, so a weight vector that
/// keeps the scores below that threshold would silence the assistant even
/// when the classifier itself is correct.
double highScoreFraction(
  List<CaseData> cases,
  Weights weights,
  double minScore,
  double gate,
) {
  var correct = 0;
  var high = 0;
  for (final data in cases) {
    final predicted = predictedType(data, weights, minScore, gate: gate);
    if (predicted != data.expected) continue;
    correct++;
    var bestScore = 0.0;
    for (final candidate in data.candidates) {
      final score = scoreCandidate(candidate, weights, gate);
      if (score > bestScore) bestScore = score;
    }
    if (bestScore > 90) high++;
  }
  return correct == 0 ? 0 : high / correct;
}

Iterable<Weights> weightGrid(int step) sync* {
  for (var a = 0; a <= step; a++) {
    for (var b = 0; b <= step - a; b++) {
      for (var c = 0; c <= step - a - b; c++) {
        for (var d = 0; d <= step - a - b - c; d++) {
          final e = step - a - b - c - d;
          yield Weights(a / step, b / step, c / step, d / step, e / step);
        }
      }
    }
  }
}

List<CaseData> loadCases(File input) {
  final cases = <CaseData>[];
  for (final line in input.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final map = jsonDecode(line) as Map<String, dynamic>;
    final candidates = <CandidateScore>[
      for (final raw in (map['candidates'] as List? ?? const []))
        if (raw is Map)
          CandidateScore(
            type: raw['type']?.toString() ?? 'unknown',
            shape: (raw['shape'] as num?)?.toDouble() ?? 0,
            feature: (raw['feature'] as num?)?.toDouble() ?? 0,
            frequency: (raw['frequency'] as num?)?.toDouble() ?? 0,
            dtw: (raw['dtw'] as num?)?.toDouble() ?? 0,
            rule: (raw['rule'] as num?)?.toDouble() ?? 0,
          ),
    ];
    final baseline = map['baseline'];
    cases.add(
      CaseData(
        caseId: map['caseId']?.toString() ?? 'unknown',
        expected: map['type']?.toString() ?? 'unknown',
        frequencyHz: (map['frequencyHz'] as num?)?.toDouble() ?? 0,
        noiseLike: map['noiseLike'] == true,
        baselinePrimary: baseline is Map
            ? baseline['primaryType']?.toString()
            : null,
        candidates: candidates,
      ),
    );
  }
  return cases;
}

void assignFolds(List<CaseData> cases) {
  final byType = <String, List<CaseData>>{};
  for (final data in cases) {
    byType.putIfAbsent(data.expected, () => []).add(data);
  }
  for (final group in byType.values) {
    group.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    for (var i = 0; i < group.length; i++) {
      group[i].fold = (i ~/ 5) % 5;
    }
  }
}

double crossValidatedMacro(
  List<CaseData> cases,
  Weights weights,
  double minScore,
  double gate,
) {
  var sum = 0.0;
  var folds = 0;
  for (var fold = 0; fold < 5; fold++) {
    final validation = cases.where((data) => data.fold == fold).toList();
    if (validation.isEmpty) continue;
    sum += evaluate(validation, weights, minScore, gate: gate).macroRecall;
    folds++;
  }
  return folds == 0 ? 0 : sum / folds;
}

int baselineMismatches(List<CaseData> cases) {
  var mismatches = 0;
  for (final data in cases) {
    final predicted = predictedType(data, Weights.defaults, 40);
    if (predicted != (data.baselinePrimary ?? 'unknown')) mismatches++;
  }
  return mismatches;
}

void printConfusion(Evaluation evaluation, List<String> types) {
  print('\nconfusion (expected -> predicted):');
  for (final expected in types) {
    final row = evaluation.confusion[expected] ?? {};
    final entries = row.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) continue;
    print(
      '  ${expected.padRight(20)} '
      '${entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}',
    );
  }
}

double percentile(List<double> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

void main(List<String> args) {
  if (args.isEmpty) {
    print(
      'Usage: dart run tool/calibrate_waveform_weights.dart '
      '<cases.jsonl> [--out=report.json] [--step=10] [--top=200] '
      '[--min-weight=0.05] [--min-high-score=0.90] '
      '[--weights=0.55,0.10,0.05,0.15,0.15]',
    );
    exitCode = 2;
    return;
  }
  final input = File(args.first);
  if (!input.existsSync()) {
    print('Input not found: ${input.path}');
    exitCode = 2;
    return;
  }
  String? outputPath;
  var step = 10;
  var topCount = 200;
  var minWeight = 0.0;
  var minHighScore = 0.0;
  List<double>? manualWeights;
  for (final arg in args.skip(1)) {
    if (arg.startsWith('--out=')) outputPath = arg.substring(6);
    if (arg.startsWith('--step=')) {
      step = int.tryParse(arg.substring(7)) ?? step;
    }
    if (arg.startsWith('--top=')) {
      topCount = int.tryParse(arg.substring(6)) ?? topCount;
    }
    if (arg.startsWith('--min-weight=')) {
      minWeight = double.tryParse(arg.substring(13)) ?? minWeight;
    }
    if (arg.startsWith('--min-high-score=')) {
      minHighScore = double.tryParse(arg.substring(17)) ?? minHighScore;
    }
    if (arg.startsWith('--weights=')) {
      manualWeights = [
        for (final value in arg.substring(10).split(','))
          double.tryParse(value.trim()) ?? double.nan,
      ];
    }
  }

  final cases = loadCases(input);
  assignFolds(cases);
  final types = cases.map((caseData) => caseData.expected).toSet().toList()
    ..sort();
  print('Cases: ${cases.length}, types: ${types.length}');
  print(
    'Fold sizes: ${[for (var fold = 0; fold < 5; fold++) cases.where((data) => data.fold == fold).length]}',
  );

  final baseline = evaluate(cases, Weights.defaults, 40);
  print('\nBaseline: ${baseline.summary}');
  print(
    'Baseline CV macro: '
    '${(100 * crossValidatedMacro(cases, Weights.defaults, 40, 0.15)).toStringAsFixed(1)}%',
  );
  print(
    'Baseline mismatches vs recorded result: '
    '${baselineMismatches(cases)}',
  );
  printConfusion(baseline, types);

  if (manualWeights != null) {
    if (manualWeights.length != 5 ||
        manualWeights.any((value) => !value.isFinite)) {
      print('--weights requires five comma-separated numbers');
      exitCode = 2;
      return;
    }
    final weights = Weights(
      manualWeights[0],
      manualWeights[1],
      manualWeights[2],
      manualWeights[3],
      manualWeights[4],
    );
    final evaluation = evaluate(cases, weights, 40);
    print('\nManual weights: ${weights.label}');
    print('  ${evaluation.summary}');
    print(
      '  CV macro: '
      '${(100 * crossValidatedMacro(cases, weights, 40, 0.15)).toStringAsFixed(1)}%',
    );
    print(
      '  High-score fraction: '
      '${(100 * highScoreFraction(cases, weights, 40, 0.15)).toStringAsFixed(1)}%',
    );
    printConfusion(evaluation, types);
    return;
  }

  const minScores = <double>[0, 20, 30, 40, 50, 60, 70, 80];
  final scored = <(Weights, double, Evaluation)>[];
  for (final weights in weightGrid(step)) {
    if (weights.shape < minWeight ||
        weights.feature < minWeight ||
        weights.frequency < minWeight ||
        weights.dtw < minWeight ||
        weights.rule < minWeight) {
      continue;
    }
    for (final minScore in minScores) {
      final evaluation = evaluate(cases, weights, minScore);
      if (minHighScore > 0 &&
          highScoreFraction(cases, weights, minScore, 0.15) < minHighScore) {
        continue;
      }
      scored.add((weights, minScore, evaluation));
    }
  }
  if (scored.isEmpty) {
    print('No weight vector satisfies --min-weight=$minWeight');
    exitCode = 2;
    return;
  }
  scored.sort((a, b) {
    final macro = b.$3.macroRecall.compareTo(a.$3.macroRecall);
    if (macro != 0) return macro;
    return b.$3.accuracy.compareTo(a.$3.accuracy);
  });
  print('\nTop grid candidates:');
  for (final entry in scored.take(5)) {
    print(
      '  ${entry.$3.summary}  min=${entry.$2.toStringAsFixed(0)}  '
      '${entry.$1.label}',
    );
  }

  var bestWeights = scored.first.$1;
  var bestMinScore = scored.first.$2;
  var bestCv = -1.0;
  for (final entry in scored.take(topCount)) {
    final cv = crossValidatedMacro(cases, entry.$1, entry.$2, 0.15);
    final better =
        cv > bestCv + 1e-9 ||
        (cv > bestCv - 1e-9 &&
            (entry.$2 - 40).abs() < (bestMinScore - 40).abs());
    if (better) {
      bestCv = cv;
      bestWeights = entry.$1;
      bestMinScore = entry.$2;
    }
  }
  final best = evaluate(cases, bestWeights, bestMinScore);
  print('\nBest by 5-fold CV:');
  print('  ${best.summary}');
  print('  CV macro: ${(100 * bestCv).toStringAsFixed(1)}%');
  print('  minConfidentScore: ${bestMinScore.toStringAsFixed(0)}');
  print('  ${bestWeights.label}');
  printConfusion(best, types);

  // Exponential-decay gate. Keep the current 0.15 unless the data clearly
  // supports a different value.
  var bestGate = 0.15;
  var bestGateCv = crossValidatedMacro(
    cases,
    bestWeights,
    bestMinScore,
    bestGate,
  );
  for (final gate in const [0.05, 0.10, 0.20, 0.25, 0.30, 0.40]) {
    final cv = crossValidatedMacro(cases, bestWeights, bestMinScore, gate);
    if (cv > bestGateCv + 0.002) {
      bestGateCv = cv;
      bestGate = gate;
    }
  }
  final gateEvaluation = evaluate(
    cases,
    bestWeights,
    bestMinScore,
    gate: bestGate,
  );
  print(
    '\nExponential gate: ${bestGate.toStringAsFixed(2)} '
    '(${gateEvaluation.summary}, CV '
    '${(100 * bestGateCv).toStringAsFixed(1)}%)',
  );

  // Ambiguity margin analysis: flag close results, measure how many wrong
  // predictions are caught versus how many correct ones are falsely flagged.
  var bestMargin = 5.0;
  var bestJ = -2.0;
  double? jAtDefault;
  final margins = <String, dynamic>{};
  for (var margin = 1; margin <= 20; margin++) {
    var wrong = 0;
    var wrongFlagged = 0;
    var right = 0;
    var rightFlagged = 0;
    for (final data in cases) {
      final scores = <double>[
        for (final candidate in data.candidates)
          scoreCandidate(candidate, bestWeights, bestGate),
      ]..sort((a, b) => b.compareTo(a));
      if (scores.isEmpty) continue;
      final bestScore = scores.first;
      final secondScore = scores.length > 1 ? scores[1] : 0.0;
      final predicted = predictedType(
        data,
        bestWeights,
        bestMinScore,
        gate: bestGate,
      );
      final flagged = bestScore < 75 && (bestScore - secondScore) < margin;
      if (predicted == data.expected) {
        right++;
        if (flagged) rightFlagged++;
      } else {
        wrong++;
        if (flagged) wrongFlagged++;
      }
    }
    final tp = wrong == 0 ? 0.0 : wrongFlagged / wrong;
    final fp = right == 0 ? 0.0 : rightFlagged / right;
    final j = tp - fp;
    margins['$margin'] = {'wrongFlagged': tp, 'rightFlagged': fp, 'youdenJ': j};
    if (margin == 5) jAtDefault = j;
    if (j > bestJ) {
      bestJ = j;
      bestMargin = margin.toDouble();
    }
  }
  // Keep the current 5-point margin unless another value improves the
  // flagging trade-off clearly.
  final defaultJ = jAtDefault ?? bestJ;
  if (bestMargin != 5.0 && bestJ < defaultJ + 0.02) {
    bestMargin = 5.0;
    bestJ = defaultJ;
  }
  print(
    'Ambiguity margin: ${bestMargin.toStringAsFixed(0)} '
    '(Youden J ${bestJ.toStringAsFixed(3)})',
  );

  // Score distribution of the best prediction.
  final correctScores = <double>[];
  final incorrectScores = <double>[];
  for (final data in cases) {
    final scores = <double>[
      for (final candidate in data.candidates)
        scoreCandidate(candidate, bestWeights, bestGate),
    ]..sort((a, b) => b.compareTo(a));
    if (scores.isEmpty) continue;
    final predicted = predictedType(
      data,
      bestWeights,
      bestMinScore,
      gate: bestGate,
    );
    if (predicted == data.expected) {
      correctScores.add(scores.first);
    } else {
      incorrectScores.add(scores.first);
    }
  }

  final above90 = correctScores.where((score) => score > 90).length;
  print(
    'Correct scores: n=${correctScores.length} '
    'p50=${percentile(correctScores, 0.5).toStringAsFixed(1)} '
    'p90=${percentile(correctScores, 0.9).toStringAsFixed(1)} '
    '>90=$above90 '
    '(${correctScores.isEmpty ? 0 : (100 * above90 / correctScores.length).toStringAsFixed(1)}%)',
  );
  print(
    'Incorrect scores: n=${incorrectScores.length} '
    'p50=${percentile(incorrectScores, 0.5).toStringAsFixed(1)} '
    'p90=${percentile(incorrectScores, 0.9).toStringAsFixed(1)}',
  );

  final report = {
    'input': input.path,
    'cases': cases.length,
    'baseline': {
      'weights': Weights.defaults.toMap(),
      'minConfidentScore': 40,
      'evaluation': baseline.toMap(),
      'cvMacroRecall': crossValidatedMacro(cases, Weights.defaults, 40, 0.15),
      'mismatchesVsRecorded': baselineMismatches(cases),
    },
    'best': {
      'weights': bestWeights.toMap(),
      'minConfidentScore': bestMinScore,
      'exponentialGate': bestGate,
      'ambiguityMargin': bestMargin,
      'cvMacroRecall': bestCv,
      'evaluation': gateEvaluation.toMap(),
    },
    'scoreDistribution': {
      'correctAbove90': above90,
      'correctCount': correctScores.length,
      'incorrectCount': incorrectScores.length,
      'correctP50': percentile(correctScores, 0.5),
      'correctP90': percentile(correctScores, 0.9),
      'incorrectP50': percentile(incorrectScores, 0.5),
      'incorrectP90': percentile(incorrectScores, 0.9),
    },
    'ambiguityMargins': margins,
    'recommendation': {
      'weights': bestWeights.toMap(),
      'minConfidentScore': bestMinScore,
      'ambiguityMargin': bestMargin,
      'exponentialGate': bestGate,
    },
  };
  final output = File(
    outputPath ?? '${input.parent.path}/calibration_report.json',
  );
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  print('\nReport written to ${output.path}');
  print('\nRecommended code values:');
  print(
    '  SimilarityWeights('
    'shape: ${bestWeights.shape.toStringAsFixed(2)}, '
    'feature: ${bestWeights.feature.toStringAsFixed(2)}, '
    'frequency: ${bestWeights.frequency.toStringAsFixed(2)}, '
    'dtw: ${bestWeights.dtw.toStringAsFixed(2)}, '
    'rule: ${bestWeights.rule.toStringAsFixed(2)})',
  );
  print('  minConfidentScore: ${bestMinScore.toStringAsFixed(0)}');
  print('  ambiguityMargin: ${bestMargin.toStringAsFixed(0)}');
  print('  exponentialGate: ${bestGate.toStringAsFixed(2)}');
}
