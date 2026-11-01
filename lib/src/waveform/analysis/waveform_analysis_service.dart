/// Public service facade of the waveform analysis engine.
///
/// The service exposes the five operations required by the UI and the
/// Waveform AI Agent: classify, compare against references, compare two
/// captures, extract features and generate a reference waveform. Expensive
/// calls have asynchronous variants that run in a background isolate so the
/// Flutter UI thread stays responsive.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'reference_waveform_generator.dart';
import 'waveform_analysis_models.dart';
import 'waveform_classifier.dart';
import 'waveform_feature_extractor.dart';
import 'waveform_preprocessor.dart';
import 'waveform_similarity.dart';

/// Service facade around the classification and comparison engine.
class WaveformAnalysisService {
  WaveformAnalysisService({
    WaveformClassifier classifier = const WaveformClassifier(),
    ReferenceWaveformGenerator generator = const ReferenceWaveformGenerator(),
  }) : _classifier = classifier,
       _generator = generator;

  final WaveformClassifier _classifier;
  final ReferenceWaveformGenerator _generator;
  final Map<String, ReferenceWaveform> _referenceCache = {};

  /// Classifies [trace] synchronously.
  WaveformClassification classify(
    WaveformTrace trace, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channel,
  }) {
    return _classifier.classify(trace, options: options, channel: channel);
  }

  /// Classifies [trace] in a background isolate.
  Future<WaveformClassification> classifyAsync(
    WaveformTrace trace, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channel,
  }) async {
    final request = _requestFor(trace, options: options, channel: channel);
    final map = await Isolate.run(() => _classifyInIsolate(request));
    return WaveformClassification.fromMap(map);
  }

  /// Compares [trace] against all or selected reference types.
  WaveformClassification compareToReferences(
    WaveformTrace trace, {
    List<WaveformSignalType>? referenceTypes,
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channel,
  }) {
    return classify(
      trace,
      options: options.copyWith(referenceTypes: referenceTypes),
      channel: channel,
    );
  }

  /// Asynchronous variant of [compareToReferences].
  Future<WaveformClassification> compareToReferencesAsync(
    WaveformTrace trace, {
    List<WaveformSignalType>? referenceTypes,
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channel,
  }) async {
    final request = _requestFor(
      trace,
      options: options.copyWith(referenceTypes: referenceTypes),
      channel: channel,
    );
    final map = await Isolate.run(() => _classifyInIsolate(request));
    return WaveformClassification.fromMap(map);
  }

  /// Extracts the full feature set of [trace] synchronously.
  WaveformFeatures features(
    WaveformTrace trace, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
  }) {
    final preprocessed = preprocessWaveform(
      trace,
      maxAnalysisPoints: options.maxAnalysisPoints,
      smoothing: options.smoothing,
    );
    return extractWaveformFeatures(
      preprocessed,
      harmonicCount: options.harmonicCount,
    );
  }

  /// Extracts the feature set in a background isolate.
  Future<WaveformFeatures> featuresAsync(
    WaveformTrace trace, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
  }) async {
    final request = _requestFor(trace, options: options);
    final map = await Isolate.run(() => _featuresInIsolate(request));
    return WaveformFeatures.fromMap(map);
  }

  /// Compares two captures with each other.
  WaveformComparisonResult compareWaveforms(
    WaveformTrace traceA,
    WaveformTrace traceB, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channelA,
    String? channelB,
  }) {
    final nameA = channelA ?? traceA.channel ?? 'A';
    final nameB = channelB ?? traceB.channel ?? 'B';
    final preA = preprocessWaveform(
      traceA,
      maxAnalysisPoints: options.maxAnalysisPoints,
      smoothing: options.smoothing,
    );
    final preB = preprocessWaveform(
      traceB,
      maxAnalysisPoints: options.maxAnalysisPoints,
      smoothing: options.smoothing,
    );
    if (!preA.sufficient || !preB.sufficient) {
      return WaveformComparisonResult(
        channelA: nameA,
        channelB: nameB,
        shapeSimilarity: 0,
        correlation: 0,
        lagSeconds: null,
        dtwDistance: 1,
        dtwSimilarity: 0,
        frequencySimilarity: 0,
        featureSimilarity: 0,
        overallSimilarity: 0,
        amplitudeDifferences: const {},
        timingDifferences: const {},
        summary:
            'At least one of the waveforms has insufficient data for a '
            'comparison.',
      );
    }
    final featuresA = extractWaveformFeatures(
      preA,
      harmonicCount: options.harmonicCount,
    );
    final featuresB = extractWaveformFeatures(
      preB,
      harmonicCount: options.harmonicCount,
    );
    final duration = math.min(
      preA.analysis.durationSeconds,
      preB.analysis.durationSeconds,
    );
    final shape = compareShapes(
      preA.normalized,
      preB.normalized,
      durationSeconds: duration,
    );
    final frequency = frequencyDomainSimilarity(featuresA, featuresB);
    final feature = generalFeatureSimilarity(featuresA, featuresB);
    final overall =
        (0.35 * shape.percent +
                0.20 * shape.dtwPercent +
                0.20 * frequency +
                0.25 * feature)
            .clamp(0.0, 100.0);

    final amplitudeDifferences = <String, dynamic>{
      'vppAVolts': _finite(featuresA.vPp),
      'vppBVolts': _finite(featuresB.vPp),
      'vppRatio': _ratio(featuresA.vPp, featuresB.vPp),
      'rmsAVolts': _finite(featuresA.vRms),
      'rmsBVolts': _finite(featuresB.vRms),
      'rmsRatio': _ratio(featuresA.vRms, featuresB.vRms),
      'meanDifferenceVolts': _difference(featuresA.vMean, featuresB.vMean),
      'topDifferenceVolts': _difference(featuresA.vTop, featuresB.vTop),
      'baseDifferenceVolts': _difference(featuresA.vBase, featuresB.vBase),
    };
    final timingDifferences = <String, dynamic>{
      'durationASeconds': _finite(featuresA.durationSeconds),
      'durationBSeconds': _finite(featuresB.durationSeconds),
      'frequencyAHz': _finite(featuresA.frequencyHz),
      'frequencyBHz': _finite(featuresB.frequencyHz),
      'frequencyRatio': _ratio(featuresA.frequencyHz, featuresB.frequencyHz),
      'periodDifferenceSeconds': _difference(
        featuresA.periodSeconds,
        featuresB.periodSeconds,
      ),
      'riseTimeDifferenceSeconds': _difference(
        featuresA.riseTimeSeconds,
        featuresB.riseTimeSeconds,
      ),
      'fallTimeDifferenceSeconds': _difference(
        featuresA.fallTimeSeconds,
        featuresB.fallTimeSeconds,
      ),
      'dutyDifferencePercent': _difference(
        featuresA.dutyPercent,
        featuresB.dutyPercent,
      ),
      'lagSeconds': shape.lagSeconds,
    };

    final summary = _comparisonSummary(
      nameA,
      nameB,
      overall: overall,
      shape: shape,
      frequency: frequency,
      feature: feature,
      featuresA: featuresA,
      featuresB: featuresB,
    );

    return WaveformComparisonResult(
      channelA: nameA,
      channelB: nameB,
      shapeSimilarity: shape.percent,
      correlation: shape.coefficient,
      lagSeconds: shape.lagSeconds,
      dtwDistance: shape.dtwDistance,
      dtwSimilarity: shape.dtwPercent,
      frequencySimilarity: frequency,
      featureSimilarity: feature,
      overallSimilarity: overall,
      amplitudeDifferences: amplitudeDifferences,
      timingDifferences: timingDifferences,
      summary: summary,
    );
  }

  /// Asynchronous variant of [compareWaveforms].
  Future<WaveformComparisonResult> compareWaveformsAsync(
    WaveformTrace traceA,
    WaveformTrace traceB, {
    WaveformAnalysisOptions options = const WaveformAnalysisOptions(),
    String? channelA,
    String? channelB,
  }) async {
    final request = <String, dynamic>{
      'a': _requestFor(traceA, options: options, channel: channelA),
      'b': _requestFor(traceB, options: options, channel: channelB),
      'options': options.toMap(),
    };
    return Isolate.run(() => _compareInIsolate(request));
  }

  /// Generates a reference waveform with the given parameters.
  ///
  /// Generated references are cached by type and rounded parameters, because
  /// the UI redraws the overlay without changing the parameters.
  ReferenceWaveform generateReference(
    WaveformSignalType type,
    ReferenceParameters parameters,
  ) {
    final key = _referenceKey(type, parameters);
    final cached = _referenceCache[key];
    if (cached != null) return cached;
    final generated = _generator.generate(type, parameters);
    if (_referenceCache.length >= 32) {
      _referenceCache.remove(_referenceCache.keys.first);
    }
    _referenceCache[key] = generated;
    return generated;
  }

  /// JSON-safe preview of a generated reference for the AI tools.
  Map<String, dynamic> referencePreview(
    ReferenceWaveform reference, {
    int maxPreviewPoints = 64,
  }) {
    final trace = reference.trace;
    final stride = math.max(1, (trace.length / maxPreviewPoints).ceil());
    var vMin = double.infinity;
    var vMax = -double.infinity;
    for (final value in trace.volts) {
      if (value < vMin) vMin = value;
      if (value > vMax) vMax = value;
    }
    return {
      'referenceType': reference.type.id,
      'referenceLabel': reference.type.label,
      'parameters': reference.parameters.toMap(),
      'sampleCount': trace.length,
      'durationSeconds': _finite(trace.durationSeconds),
      'sampleIntervalSeconds': _finite(trace.sampleIntervalSeconds),
      'vppVolts': trace.isEmpty ? null : _finite(vMax - vMin),
      'preview': [
        for (var i = 0; i < trace.length; i += stride)
          {
            'timeSeconds': _finite(trace.times[i]),
            'volts': _finite(trace.volts[i]),
          },
      ],
      'note':
          'The preview is downsampled. The complete reference waveform is '
          'available in the application and is not returned in the tool '
          'result.',
    };
  }
}

Map<String, dynamic> _requestFor(
  WaveformTrace trace, {
  required WaveformAnalysisOptions options,
  String? channel,
}) => {
  'times': trace.times.toList(),
  'volts': trace.volts.toList(),
  'channel': channel ?? trace.channel,
  'options': options.toMap(),
};

WaveformTrace _traceFromRequest(Map<String, dynamic> request) {
  final times = request['times'];
  final volts = request['volts'];
  Float64List read(Object? value) {
    if (value is Float64List) return Float64List.fromList(value);
    if (value is List) {
      return Float64List.fromList([
        for (final entry in value)
          if (entry is num) entry.toDouble(),
      ]);
    }
    return Float64List(0);
  }

  return WaveformTrace(
    times: read(times),
    volts: read(volts),
    channel: request['channel']?.toString(),
  );
}

WaveformAnalysisOptions _optionsFromRequest(Map<String, dynamic> request) {
  final options = request['options'];
  return options is Map
      ? WaveformAnalysisOptions.fromMap(Map<String, dynamic>.from(options))
      : const WaveformAnalysisOptions();
}

Map<String, dynamic> _classifyInIsolate(Map<String, dynamic> request) {
  final service = WaveformAnalysisService();
  return service
      .classify(
        _traceFromRequest(request),
        options: _optionsFromRequest(request),
        channel: request['channel']?.toString(),
      )
      .toMap();
}

Map<String, dynamic> _featuresInIsolate(Map<String, dynamic> request) {
  final service = WaveformAnalysisService();
  return service
      .features(
        _traceFromRequest(request),
        options: _optionsFromRequest(request),
      )
      .toMap();
}

WaveformComparisonResult _compareInIsolate(Map<String, dynamic> request) {
  final requestA = request['a'];
  final requestB = request['b'];
  if (requestA is! Map || requestB is! Map) {
    return const WaveformComparisonResult(
      channelA: 'A',
      channelB: 'B',
      shapeSimilarity: 0,
      correlation: 0,
      lagSeconds: null,
      dtwDistance: 1,
      dtwSimilarity: 0,
      frequencySimilarity: 0,
      featureSimilarity: 0,
      overallSimilarity: 0,
      amplitudeDifferences: {},
      timingDifferences: {},
      summary: 'Invalid comparison request.',
    );
  }
  final options = _optionsFromRequest(request);
  final service = WaveformAnalysisService();
  return service.compareWaveforms(
    _traceFromRequest(Map<String, dynamic>.from(requestA)),
    _traceFromRequest(Map<String, dynamic>.from(requestB)),
    options: options,
    channelA: requestA['channel']?.toString(),
    channelB: requestB['channel']?.toString(),
  );
}

String _comparisonSummary(
  String nameA,
  String nameB, {
  required double overall,
  required ShapeSimilarity shape,
  required double frequency,
  required double feature,
  required WaveformFeatures featuresA,
  required WaveformFeatures featuresB,
}) {
  final parts = <String>[
    '$nameA and $nameB are ${overall.toStringAsFixed(1)} % similar',
    'shape correlation ${shape.percent.toStringAsFixed(1)} %',
    'DTW similarity ${shape.dtwPercent.toStringAsFixed(1)} %',
    'feature similarity ${feature.toStringAsFixed(1)} %',
    'frequency-domain similarity ${frequency.toStringAsFixed(1)} %',
  ];
  if (shape.lagSeconds != null) {
    parts.add('relative delay ${_formatSeconds(shape.lagSeconds!)}');
  }
  if (featuresA.frequencyHz != null && featuresB.frequencyHz != null) {
    parts.add(
      'fundamental ${_formatHz(featuresA.frequencyHz!)} vs '
      '${_formatHz(featuresB.frequencyHz!)}',
    );
  }
  if (featuresA.vPp != null && featuresB.vPp != null) {
    parts.add(
      'Vpp ${_formatVolts(featuresA.vPp!)} vs '
      '${_formatVolts(featuresB.vPp!)}',
    );
  }
  return '${parts.join('; ')}.';
}

double? _ratio(double? a, double? b) {
  if (a == null || b == null || b.abs() < 1e-12) return null;
  final result = a / b;
  return result.isFinite ? result : null;
}

double? _difference(double? a, double? b) {
  if (a == null || b == null) return null;
  final result = a - b;
  return result.isFinite ? result : null;
}

double? _finite(double? value) =>
    value != null && value.isFinite ? value : null;

String _referenceKey(WaveformSignalType type, ReferenceParameters p) => [
  type.id,
  p.frequencyHz.toStringAsFixed(6),
  p.amplitudeVolts.toStringAsFixed(6),
  p.offsetVolts.toStringAsFixed(6),
  p.phaseRadians.toStringAsFixed(4),
  p.sampleRateHz.toStringAsFixed(3),
  p.durationSeconds.toStringAsFixed(8),
  p.dutyCycle.toStringAsFixed(4),
  p.noiseLevelPercent.toStringAsFixed(3),
  p.dampingPerSecond.toStringAsFixed(4),
  p.timeConstantSeconds.toStringAsFixed(8),
  p.lowerClipLevel.toStringAsFixed(4),
  p.upperClipLevel.toStringAsFixed(4),
  p.rectangularEdgeFraction.toStringAsFixed(5),
  p.directionIsRising,
  p.seed,
].join('|');

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
