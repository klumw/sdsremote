/// Preprocessing of captured waveforms before classification.
///
/// The original time and voltage values are preserved in
/// [PreprocessedWaveform.original]. A cleaned, optionally decimated copy is
/// used for analysis, and a standardised copy is used for shape comparison.
/// No filtering is applied unless the caller explicitly requests it, so short
/// pulses and sharp edges survive.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';
import 'waveform_math.dart';

/// Result of the preprocessing pipeline.
class PreprocessedWaveform {
  /// Original waveform exactly as captured.
  final WaveformTrace original;

  /// Cleaned waveform with a valid, uniformly spaced time axis.
  final WaveformTrace cleaned;

  /// Decimated analysis copy (at most the configured point limit).
  final WaveformTrace analysis;

  /// Standardised analysis samples (zero mean, unit standard deviation).
  final Float64List normalized;

  /// Effective interval between analysed samples in seconds.
  final double? sampleIntervalSeconds;

  /// Fundamental frequency estimated from the autocorrelation, or `null`
  /// when the signal is not periodic.
  final double? estimatedFundamentalHz;

  /// Number of samples removed because they were invalid or duplicated.
  final int removedSamples;

  /// Number of cleaned samples before analysis decimation.
  final int cleanedSampleCount;

  /// Human-readable warnings about the capture or the analysis limits.
  final List<String> warnings;

  /// Whether enough valid, dynamic data is available for classification.
  final bool sufficient;

  const PreprocessedWaveform({
    required this.original,
    required this.cleaned,
    required this.analysis,
    required this.normalized,
    required this.sampleIntervalSeconds,
    required this.estimatedFundamentalHz,
    required this.removedSamples,
    required this.cleanedSampleCount,
    required this.warnings,
    required this.sufficient,
  });

  bool get isEmpty => analysis.isEmpty;
}

/// Runs validation, cleaning, normalisation and fundamental estimation.
PreprocessedWaveform preprocessWaveform(
  WaveformTrace trace, {
  int maxAnalysisPoints = 4096,
  bool smoothing = false,
}) {
  final warnings = <String>[];
  final original = trace;

  final cleaned = _sanitize(trace, warnings);
  if (cleaned.length < 2) {
    warnings.add('waveform contains fewer than two valid samples');
    return PreprocessedWaveform(
      original: original,
      cleaned: cleaned,
      analysis: cleaned,
      normalized: Float64List(0),
      sampleIntervalSeconds: null,
      estimatedFundamentalHz: null,
      removedSamples: trace.length - cleaned.length,
      cleanedSampleCount: cleaned.length,
      warnings: warnings,
      sufficient: false,
    );
  }

  var sampleInterval = cleaned.sampleIntervalSeconds;
  var usable = cleaned;
  if (sampleInterval == null || sampleInterval <= 0) {
    warnings.add(
      'sample interval unavailable; an index-based time axis was used',
    );
    sampleInterval = 1;
    usable = WaveformTrace.synthetic(
      [for (var i = 0; i < cleaned.length; i++) cleaned.volts[i]],
      sampleIntervalSeconds: sampleInterval,
      channel: cleaned.channel,
    );
  } else if (!_isUniform(cleaned, sampleInterval)) {
    warnings.add(
      'non-uniform sample spacing; the analysis used a uniformly resampled '
      'copy',
    );
    usable = resampleTrace(cleaned, cleaned.length);
    sampleInterval = usable.sampleIntervalSeconds ?? sampleInterval;
  }

  if (smoothing && usable.length >= 5) {
    usable = WaveformTrace(
      times: usable.times,
      volts: medianFilter3(usable.volts),
      channel: usable.channel,
    );
    warnings.add('a three-sample median filter was applied for the analysis');
  }

  final limit = math.max(8, maxAnalysisPoints);
  final stride = math.max(1, (usable.length / limit).ceil());
  final analysis = stride == 1
      ? usable
      : WaveformTrace(
          times: Float64List.fromList([
            for (var i = 0; i < usable.length; i += stride) usable.times[i],
          ]),
          volts: Float64List.fromList([
            for (var i = 0; i < usable.length; i += stride) usable.volts[i],
          ]),
          channel: usable.channel,
        );
  if (stride > 1) {
    warnings.add(
      'analysis limited to ${analysis.length} of ${usable.length} samples',
    );
  }

  final normalized = zScore(analysis.volts);
  final vPp = _peakToPeak(analysis.volts);
  final duration = analysis.durationSeconds;
  final sampleIntervalOut = analysis.sampleIntervalSeconds ?? sampleInterval;

  double? fundamental;
  if (sampleIntervalOut > 0 && normalized.isNotEmpty) {
    fundamental = estimateFundamentalHz(normalized, sampleIntervalOut);
  }

  var sufficient = analysis.length >= 16 && duration > 0 && vPp > 0;
  if (analysis.length < 32) {
    warnings.add(
      'short record (${analysis.length} samples); classification confidence '
      'may be limited',
    );
  }
  if (vPp <= 0) {
    warnings.add('flat-line signal; no shape information is available');
  }
  if (fundamental == null) {
    warnings.add(
      'no periodic fundamental detected; non-periodic references were used',
    );
  }
  if (analysis.length < 16 || duration <= 0) {
    sufficient = false;
    warnings.add('insufficient data for reliable classification');
  }

  return PreprocessedWaveform(
    original: original,
    cleaned: usable,
    analysis: analysis,
    normalized: normalized,
    sampleIntervalSeconds: sampleIntervalOut,
    estimatedFundamentalHz: fundamental,
    removedSamples: original.length - usable.length,
    cleanedSampleCount: usable.length,
    warnings: warnings,
    sufficient: sufficient,
  );
}

/// Removes invalid samples, sorts by time and collapses duplicate timestamps.
WaveformTrace _sanitize(WaveformTrace trace, List<String> warnings) {
  if (trace.isEmpty) return trace;
  final points = <(double, double)>[];
  var skipped = 0;
  for (var i = 0; i < trace.length; i++) {
    final time = trace.times[i];
    final voltage = trace.volts[i];
    if (!time.isFinite || !voltage.isFinite) {
      skipped++;
      continue;
    }
    points.add((time, voltage));
  }
  if (skipped > 0) warnings.add('$skipped invalid samples were removed');
  points.sort((a, b) => a.$1.compareTo(b.$1));

  final times = <double>[];
  final volts = <double>[];
  for (final (time, voltage) in points) {
    if (times.isNotEmpty && time <= times.last) {
      skipped++;
      continue;
    }
    times.add(time);
    volts.add(voltage);
  }
  if (skipped > 0) {
    return WaveformTrace(
      times: Float64List.fromList(times),
      volts: Float64List.fromList(volts),
      channel: trace.channel,
    );
  }
  return trace;
}

/// Whether the time axis is uniform within ten percent of the median step.
bool _isUniform(WaveformTrace trace, double medianInterval) {
  final tolerance = medianInterval.abs() * 0.1;
  final limit = math.min(trace.length - 1, 1000);
  for (var i = 0; i < limit; i++) {
    final dt = trace.times[i + 1] - trace.times[i];
    if ((dt - medianInterval).abs() > tolerance) return false;
  }
  return true;
}

double _peakToPeak(Float64List values) {
  if (values.isEmpty) return 0;
  var min = values.first;
  var max = values.first;
  for (final value in values) {
    if (value < min) min = value;
    if (value > max) max = value;
  }
  return max - min;
}
