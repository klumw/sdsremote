/// Deterministic time-domain measurements for oscilloscope waveforms.
///
/// This library is intentionally free of Flutter dependencies so the same
/// code runs in unit tests and in background processing. It performs no I/O.
///
/// Measurements are computed from the acquisition data *before* the display
/// decimation performed by `convertChannel`, so rise/fall times and overshoot
/// retain the full sample resolution. Very large acquisitions are analysed
/// with a bounded stride; the limitation is reported in
/// [WaveformMeasurements.notes] instead of failing silently.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../instrument/measurement.dart' show formatMeasurementValue;
import 'waveform_converter.dart';

/// Default upper bound for the number of samples used for a measurement.
///
/// Typical acquisitions contain 1201 points; deep-memory acquisitions can
/// exceed 10 million samples. Analysing every sample of such a record would
/// add noticeable latency, so the measurement streams over a strided subset
/// and records the reduction in the result notes.
const int defaultMaxAnalysisPoints = 2000000;

/// Time-domain measurement result for one channel.
///
/// A value that cannot be determined from the data is `null` and explained in
/// [notes] — it is never silently reported as zero.
class WaveformMeasurements {
  /// Channel identifier, `'ch1'` … `'ch4'`.
  final String channel;

  /// Highest and lowest sampled voltage.
  final double? vMax;
  final double? vMin;

  /// Peak-to-peak voltage, `vMax - vMin`.
  final double? vPp;

  /// Arithmetic mean and RMS of all analysed samples.
  final double? vMean;
  final double? vRms;

  /// High and low levels derived from the 95 % and 5 % percentiles.
  final double? vTop;
  final double? vBase;

  /// Frequency and period derived from the rising mid-level crossings.
  final double? frequencyHz;
  final double? periodSeconds;

  /// Sample standard deviation of the measured periods (period jitter).
  final double? periodStdDevSeconds;

  /// Number of complete periods detected in the acquisition.
  final int periodCount;

  /// Duty cycle as a percentage and the high pulse width statistics.
  final double? dutyPercent;
  final double? pulseWidthSeconds;
  final double? pulseWidthMinSeconds;
  final double? pulseWidthMaxSeconds;
  final double? pulseWidthStdDevSeconds;

  /// Mean 10–90 % rise and fall times of [vTop] − [vBase].
  final double? riseTimeSeconds;
  final double? fallTimeSeconds;

  /// Overshoot above [vTop] and undershoot below [vBase], relative to
  /// [vTop] − [vBase] and expressed as a percentage.
  final double? overshootPercent;
  final double? undershootPercent;

  /// Number of mid-level edges detected after hysteresis filtering.
  final int risingEdgeCount;
  final int fallingEdgeCount;

  /// Number of analysed samples.
  final int sampleCount;

  /// Effective interval between analysed samples in seconds.
  final double? sampleIntervalSeconds;

  /// Human-readable explanations for values that are unavailable or for
  /// analysis limitations.
  final List<String> notes;

  const WaveformMeasurements({
    required this.channel,
    this.vMax,
    this.vMin,
    this.vPp,
    this.vMean,
    this.vRms,
    this.vTop,
    this.vBase,
    this.frequencyHz,
    this.periodSeconds,
    this.periodStdDevSeconds,
    this.periodCount = 0,
    this.dutyPercent,
    this.pulseWidthSeconds,
    this.pulseWidthMinSeconds,
    this.pulseWidthMaxSeconds,
    this.pulseWidthStdDevSeconds,
    this.riseTimeSeconds,
    this.fallTimeSeconds,
    this.overshootPercent,
    this.undershootPercent,
    this.risingEdgeCount = 0,
    this.fallingEdgeCount = 0,
    required this.sampleCount,
    this.sampleIntervalSeconds,
    this.notes = const [],
  });

  /// Whether any sample was available for analysis.
  bool get hasData => sampleCount > 0;

  /// Whether periodic properties (frequency, duty) are available.
  bool get hasPeriodicMeasurements => periodCount > 0 && frequencyHz != null;
}

/// Statistical summary of one metric over several acquisitions.
class MeasurementStatistics {
  /// Number of finite metric values that contributed to the statistics.
  final int count;

  final double? min;
  final double? max;
  final double? mean;

  /// Sample standard deviation (`n − 1` denominator); `null` for `count < 2`.
  final double? standardDeviation;

  const MeasurementStatistics({
    required this.count,
    this.min,
    this.max,
    this.mean,
    this.standardDeviation,
  });

  const MeasurementStatistics.empty()
    : count = 0,
      min = null,
      max = null,
      mean = null,
      standardDeviation = null;
}

/// Statistics of the last acquisitions of one channel, keyed by metric name.
///
/// Metric names match the fields of [WaveformMeasurements], e.g. `vPp`,
/// `vRms`, `frequencyHz` or `dutyPercent`.
class WaveformChannelStatistics {
  final String channel;
  final int measurementCount;
  final Map<String, MeasurementStatistics> metrics;

  const WaveformChannelStatistics({
    required this.channel,
    required this.measurementCount,
    required this.metrics,
  });
}

/// Measures [points] (time in seconds, voltage in volts) of [channel].
///
/// The list may contain non-uniform or missing samples; the actual timestamps
/// are used for all frequency and edge calculations. Non-finite samples are
/// ignored and reported in [WaveformMeasurements.notes].
WaveformMeasurements measureWaveform({
  required String channel,
  required List<(double, double)> points,
  double hysteresisRatio = 0.05,
  double maxPeriodRelativeStdDev = 0.2,
  int maxAnalysisPoints = defaultMaxAnalysisPoints,
}) {
  if (points.isEmpty) {
    return WaveformMeasurements(
      channel: channel,
      sampleCount: 0,
      notes: const ['no samples'],
    );
  }
  final series = _PointSeries(
    points,
    _strideFor(points.length, maxAnalysisPoints),
  );
  return _measureSeries(
    channel: channel,
    series: series,
    hysteresisRatio: hysteresisRatio,
    maxPeriodRelativeStdDev: maxPeriodRelativeStdDev,
  );
}

/// Measures a raw acquisition channel directly from its 8-bit sample codes.
///
/// The voltage conversion uses the Siglent scale
/// ([WaveformConverter.toVoltage]) and the sample times follow
/// `1 / sampleRate`, unless [sampleIntervalSeconds] is given. The explicit
/// interval is required when the instrument delivers fewer points than the
/// requested display window: `SARA?` then reports the maximum sample rate,
/// not the effective rate of the transferred record. Callers can derive it
/// from the acquisition parameters with the same rule as
/// `WaveformConverter.computeTimeAxis`.
///
/// Streaming over [rawData] avoids building a full `(time, voltage)` list for
/// deep-memory acquisitions.
///
/// The leading samples that `convertChannel` discards for the display are
/// skipped here as well, because the acquisition artifact they contain would
/// otherwise corrupt min/max and overshoot measurements.
WaveformMeasurements measureRawChannel({
  required String channel,
  required Uint8List rawData,
  required double vdiv,
  required double voffset,
  required double sampleRate,
  double? sampleIntervalSeconds,
  int leadingSamplesToSkip = 8,
  double hysteresisRatio = 0.05,
  double maxPeriodRelativeStdDev = 0.2,
  int maxAnalysisPoints = defaultMaxAnalysisPoints,
}) {
  if (rawData.isEmpty) {
    return WaveformMeasurements(
      channel: channel,
      sampleCount: 0,
      notes: const ['no samples'],
    );
  }
  final series = _RawSeries(
    rawData,
    vdiv: vdiv,
    voffset: voffset,
    sampleRate: sampleRate,
    sampleIntervalSeconds: sampleIntervalSeconds,
    leadingSamplesToSkip: leadingSamplesToSkip,
    stride: _strideFor(rawData.length, maxAnalysisPoints),
  );
  return _measureSeries(
    channel: channel,
    series: series,
    hysteresisRatio: hysteresisRatio,
    maxPeriodRelativeStdDev: maxPeriodRelativeStdDev,
  );
}

/// Computes min/max/mean/standard deviation for the metrics of [measurements].
///
/// All entries are expected to belong to the same channel (the channel of the
/// first entry is reported). `null` and non-finite metric values are skipped;
/// metrics without a single finite value are omitted from the result.
WaveformChannelStatistics measureChannelStatistics(
  List<WaveformMeasurements> measurements,
) {
  final channel = measurements.isEmpty ? '' : measurements.first.channel;
  final metrics = <String, MeasurementStatistics>{};

  void add(String key, double? Function(WaveformMeasurements) selector) {
    final values = <double>[];
    for (final measurement in measurements) {
      final value = selector(measurement);
      if (value != null && value.isFinite) values.add(value);
    }
    if (values.isNotEmpty) {
      metrics[key] = _statistics(values);
    }
  }

  add('vMax', (m) => m.vMax);
  add('vMin', (m) => m.vMin);
  add('vPp', (m) => m.vPp);
  add('vMean', (m) => m.vMean);
  add('vRms', (m) => m.vRms);
  add('vTop', (m) => m.vTop);
  add('vBase', (m) => m.vBase);
  add('frequencyHz', (m) => m.frequencyHz);
  add('periodSeconds', (m) => m.periodSeconds);
  add('dutyPercent', (m) => m.dutyPercent);
  add('pulseWidthSeconds', (m) => m.pulseWidthSeconds);
  add('riseTimeSeconds', (m) => m.riseTimeSeconds);
  add('fallTimeSeconds', (m) => m.fallTimeSeconds);
  add('overshootPercent', (m) => m.overshootPercent);
  add('undershootPercent', (m) => m.undershootPercent);

  return WaveformChannelStatistics(
    channel: channel,
    measurementCount: measurements.length,
    metrics: metrics,
  );
}

/// Formats a duration in seconds with an SI prefix (`s`, `ms`, `µs`, `ns`).
///
/// The painter keeps its own private formatter; this top-level helper is the
/// reusable variant for measurement panels and reports.
String formatTime(double seconds) => formatMeasurementValue(seconds, 's');

/// Returns the stride that limits an analysis to [maxAnalysisPoints] samples.
int _strideFor(int sampleCount, int maxAnalysisPoints) {
  if (maxAnalysisPoints <= 0 || sampleCount <= maxAnalysisPoints) return 1;
  return (sampleCount / maxAnalysisPoints).ceil();
}

/// Runs the shared measurement algorithm over [series].
WaveformMeasurements _measureSeries({
  required String channel,
  required _SampleSeries series,
  required double hysteresisRatio,
  required double maxPeriodRelativeStdDev,
}) {
  final notes = <String>[];
  final n = series.length;
  final hasTimeAxis = series.sampleIntervalSeconds != null;

  if (!hasTimeAxis) {
    notes.add('sample interval unavailable; periodic measurements unavailable');
  }

  if (series.stride > 1) {
    notes.add(
      'analysis limited to ${series.length} of '
      '${series.sourceSampleCount} samples',
    );
  }

  // Pass 1: level statistics.
  var vMin = double.infinity;
  var vMax = -double.infinity;
  var sum = 0.0;
  var sumSquares = 0.0;
  var finiteCount = 0;
  var skippedNonFinite = 0;
  for (var i = 0; i < n; i++) {
    final v = series.voltageAt(i);
    if (!v.isFinite) {
      skippedNonFinite++;
      continue;
    }
    finiteCount++;
    sum += v;
    sumSquares += v * v;
    if (v < vMin) vMin = v;
    if (v > vMax) vMax = v;
  }
  if (skippedNonFinite > 0) {
    notes.add('$skippedNonFinite non-finite samples ignored');
  }
  if (finiteCount == 0) {
    notes.add('no finite samples');
    return WaveformMeasurements(
      channel: channel,
      sampleCount: 0,
      sampleIntervalSeconds: series.sampleIntervalSeconds,
      notes: notes,
    );
  }

  final sampleCount = finiteCount;
  final vMean = sum / sampleCount;
  final vRms = math.sqrt(sumSquares / sampleCount);
  final vPp = vMax - vMin;

  if (vPp == 0) {
    notes.add('flatline signal; dynamic measurements unavailable');
    return WaveformMeasurements(
      channel: channel,
      vMax: vMax,
      vMin: vMin,
      vPp: 0,
      vMean: vMean,
      vRms: vRms,
      vTop: vMax,
      vBase: vMin,
      sampleCount: sampleCount,
      sampleIntervalSeconds: series.sampleIntervalSeconds,
      notes: notes,
    );
  }

  final (vBase, vTop) = _percentileLevels(series, vMin, vMax);
  final amplitude = vTop - vBase;

  if (amplitude <= 0) {
    notes.add('no distinguishable high and low levels');
    return WaveformMeasurements(
      channel: channel,
      vMax: vMax,
      vMin: vMin,
      vPp: vPp,
      vMean: vMean,
      vRms: vRms,
      vTop: vTop,
      vBase: vBase,
      sampleCount: sampleCount,
      sampleIntervalSeconds: series.sampleIntervalSeconds,
      notes: notes,
    );
  }

  final mid = (vTop + vBase) / 2;
  final lowRef = vBase + 0.1 * amplitude;
  final highRef = vBase + 0.9 * amplitude;
  final hysteresis = amplitude * hysteresisRatio;
  final midLow = mid - hysteresis;
  final midHigh = mid + hysteresis;

  final risingTimes = <double>[];
  final fallingTimes = <double>[];
  final riseDurations = <double>[];
  final fallDurations = <double>[];
  final periods = <double>[];
  final dutyRatios = <double>[];
  final pulseWidths = <double>[];

  double? prevT;
  double? prevV;
  var lowArmed = false;
  var highArmed = false;
  double? lastLowRefUpT;
  double? lastHighRefDownT;
  _Edge? pendingRise;
  _Edge? pendingFall;
  double? cycleStartT;
  double? lastHighDuration;

  for (var i = 0; i < n; i++) {
    final v = series.voltageAt(i);
    if (!v.isFinite) continue;
    final t = series.timeAt(i);

    if (prevV != null) {
      final pv = prevV;
      final pt = prevT!;

      // Threshold crossings used for the 10–90 % transition times.
      if (pv < lowRef && v >= lowRef) {
        lastLowRefUpT = _interpolateTime(pt, pv, t, v, lowRef);
      }
      if (pv > highRef && v <= highRef) {
        lastHighRefDownT = _interpolateTime(pt, pv, t, v, highRef);
      }

      // Complete transitions that were confirmed at the mid level earlier.
      final rise = pendingRise;
      if (rise != null && pv < highRef && v >= highRef) {
        rise.highTime = _interpolateTime(pt, pv, t, v, highRef);
        if (rise.lowTime case final double lowTime) {
          final duration = rise.highTime! - lowTime;
          if (duration > 0) riseDurations.add(duration);
        }
        pendingRise = null;
      }
      final fall = pendingFall;
      if (fall != null && pv > lowRef && v <= lowRef) {
        fall.lowTime = _interpolateTime(pt, pv, t, v, lowRef);
        if (fall.highTime case final double highTime) {
          final duration = fall.lowTime! - highTime;
          if (duration > 0) fallDurations.add(duration);
        }
        pendingFall = null;
      }

      // Mid-level crossings with hysteresis. The arming state comes from the
      // previous sample, so a single steep step is not missed.
      if (pv < mid && v >= mid && lowArmed) {
        final tCross = _interpolateTime(pt, pv, t, v, mid);
        risingTimes.add(tCross);
        if (cycleStartT case final double cycleStart) {
          if (lastHighDuration case final double highDuration) {
            final period = tCross - cycleStart;
            if (period > 0) {
              periods.add(period);
              dutyRatios.add(highDuration / period);
              pulseWidths.add(highDuration);
            }
          }
        }
        cycleStartT = tCross;
        lastHighDuration = null;
        final edge = _Edge(lowTime: lastLowRefUpT);
        if (pv < highRef && v >= highRef) {
          // The complete 10–90 % transition happened within one interval.
          edge.highTime = _interpolateTime(pt, pv, t, v, highRef);
          if (edge.lowTime case final double lowTime) {
            final duration = edge.highTime! - lowTime;
            if (duration > 0) riseDurations.add(duration);
          }
        } else {
          pendingRise = edge;
        }
        pendingFall = null;
        lastLowRefUpT = null;
        lastHighRefDownT = null;
      } else if (pv >= mid && v < mid && highArmed) {
        final tCross = _interpolateTime(pt, pv, t, v, mid);
        fallingTimes.add(tCross);
        if (cycleStartT != null) {
          lastHighDuration = tCross - cycleStartT;
        }
        final edge = _Edge(highTime: lastHighRefDownT);
        if (pv > lowRef && v <= lowRef) {
          // The complete 90–10 % transition happened within one interval.
          edge.lowTime = _interpolateTime(pt, pv, t, v, lowRef);
          if (edge.highTime case final double highTime) {
            final duration = edge.lowTime! - highTime;
            if (duration > 0) fallDurations.add(duration);
          }
        } else {
          pendingFall = edge;
        }
        pendingRise = null;
        lastHighRefDownT = null;
        lastLowRefUpT = null;
      }
    }

    if (v < midLow) {
      lowArmed = true;
      highArmed = false;
    } else if (v > midHigh) {
      highArmed = true;
      lowArmed = false;
    }
    prevT = t;
    prevV = v;
  }

  // Periodic metrics, gated on a stable period so noise does not produce
  // invented frequency or PWM values.
  final periodCount = periods.length;
  double? periodMean;
  double? periodStdDev;
  double? frequency;
  double? duty;
  double? pulseWidth;
  double? pulseWidthMin;
  double? pulseWidthMax;
  double? pulseWidthStdDev;

  if (!hasTimeAxis) {
    // Edge counts remain valid, but frequency and duty depend on the time
    // axis, so they stay unavailable.
  } else if (periods.isNotEmpty) {
    final meanPeriod = _mean(periods)!;
    final deviation = _standardDeviation(periods) ?? 0.0;
    periodMean = meanPeriod;
    periodStdDev = deviation;
    final relativeDeviation = meanPeriod > 0
        ? deviation / meanPeriod
        : double.infinity;
    if (relativeDeviation <= maxPeriodRelativeStdDev && meanPeriod > 0) {
      frequency = 1 / meanPeriod;
      duty = _mean(dutyRatios)! * 100;
      pulseWidth = _mean(pulseWidths);
      pulseWidthMin = pulseWidths.reduce(math.min);
      pulseWidthMax = pulseWidths.reduce(math.max);
      pulseWidthStdDev = _standardDeviation(pulseWidths);
    } else {
      notes.add(
        'period unstable (relative standard deviation '
        '${(relativeDeviation * 100).toStringAsFixed(1)} %); '
        'periodic measurements unavailable',
      );
    }
  } else if (risingTimes.length < 2) {
    notes.add('fewer than two rising edges; periodic measurements unavailable');
  } else {
    notes.add('no complete period; periodic measurements unavailable');
  }

  final riseTime = _meanPositive(riseDurations);
  final fallTime = _meanPositive(fallDurations);
  if (riseTime == null && risingTimes.isNotEmpty) {
    notes.add('no measurable 10–90 % rising transition');
  }
  if (fallTime == null && fallingTimes.isNotEmpty) {
    notes.add('no measurable 10–90 % falling transition');
  }

  return WaveformMeasurements(
    channel: channel,
    vMax: vMax,
    vMin: vMin,
    vPp: vPp,
    vMean: vMean,
    vRms: vRms,
    vTop: vTop,
    vBase: vBase,
    frequencyHz: frequency,
    periodSeconds: periodMean,
    periodStdDevSeconds: periodStdDev,
    periodCount: periodCount,
    dutyPercent: duty,
    pulseWidthSeconds: pulseWidth,
    pulseWidthMinSeconds: pulseWidthMin,
    pulseWidthMaxSeconds: pulseWidthMax,
    pulseWidthStdDevSeconds: pulseWidthStdDev,
    riseTimeSeconds: riseTime,
    fallTimeSeconds: fallTime,
    overshootPercent: (vMax - vTop) / amplitude * 100,
    undershootPercent: (vBase - vMin) / amplitude * 100,
    risingEdgeCount: risingTimes.length,
    fallingEdgeCount: fallingTimes.length,
    sampleCount: sampleCount,
    sampleIntervalSeconds: series.sampleIntervalSeconds,
    notes: notes,
  );
}

/// Returns the 5 % and 95 % voltage percentiles as `(base, top)`.
///
/// A histogram keeps the percentile calculation O(n) with bounded memory.
/// Its resolution is `range / 2047`, far below the 8-bit acquisition
/// resolution of the instrument.
(double base, double top) _percentileLevels(
  _SampleSeries series,
  double vMin,
  double vMax,
) {
  const bins = 2048;
  final histogram = Int32List(bins);
  final range = vMax - vMin;
  var count = 0;
  for (var i = 0; i < series.length; i++) {
    final v = series.voltageAt(i);
    if (!v.isFinite) continue;
    var bin = (((v - vMin) / range) * (bins - 1)).round();
    if (bin < 0) bin = 0;
    if (bin >= bins) bin = bins - 1;
    histogram[bin]++;
    count++;
  }

  double valueAt(double fraction) {
    final rank = (fraction * (count - 1)).round();
    var cumulative = 0;
    for (var bin = 0; bin < bins; bin++) {
      cumulative += histogram[bin];
      if (cumulative > rank) {
        return vMin + bin / (bins - 1) * range;
      }
    }
    return vMax;
  }

  return (valueAt(0.05), valueAt(0.95));
}

/// Linearly interpolates the time at which the signal crosses [target].
double _interpolateTime(
  double t0,
  double v0,
  double t1,
  double v1,
  double target,
) {
  final denominator = v1 - v0;
  if (denominator == 0 || !denominator.isFinite) return t0;
  final fraction = ((target - v0) / denominator).clamp(0.0, 1.0).toDouble();
  return t0 + (t1 - t0) * fraction;
}

double? _mean(List<double> values) {
  if (values.isEmpty) return null;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double? _meanPositive(List<double> values) {
  final positive = values.where((value) => value > 0 && value.isFinite);
  if (positive.isEmpty) return null;
  var sum = 0.0;
  var count = 0;
  for (final value in positive) {
    sum += value;
    count++;
  }
  return count == 0 ? null : sum / count;
}

/// Sample standard deviation (`n − 1`); `null` for fewer than two values.
double? _standardDeviation(List<double> values) {
  if (values.length < 2) return null;
  final mean = _mean(values)!;
  var sumSquares = 0.0;
  for (final value in values) {
    final deviation = value - mean;
    sumSquares += deviation * deviation;
  }
  return math.sqrt(sumSquares / (values.length - 1));
}

MeasurementStatistics _statistics(List<double> values) {
  if (values.isEmpty) return const MeasurementStatistics.empty();
  var min = values.first;
  var max = values.first;
  var sum = 0.0;
  for (final value in values) {
    if (value < min) min = value;
    if (value > max) max = value;
    sum += value;
  }
  return MeasurementStatistics(
    count: values.length,
    min: min,
    max: max,
    mean: sum / values.length,
    standardDeviation: _standardDeviation(values),
  );
}

/// A read-only view over the samples selected for analysis.
abstract class _SampleSeries {
  /// Number of analysed samples.
  int get length;

  /// Number of samples in the source before analysis decimation.
  int get sourceSampleCount;

  /// Stride between analysed samples in the source.
  int get stride;

  /// Effective interval between analysed samples, or `null` if unknown.
  double? get sampleIntervalSeconds;

  /// Time of analysed sample [index] in seconds, relative to the first sample.
  double timeAt(int index);

  /// Voltage of analysed sample [index] in volts.
  double voltageAt(int index);
}

/// [_SampleSeries] over an already converted `(time, voltage)` list.
class _PointSeries implements _SampleSeries {
  final List<(double, double)> _points;

  @override
  final int stride;

  @override
  final int length;

  _PointSeries(List<(double, double)> points, this.stride)
    : _points = points,
      length = ((points.length - 1) ~/ stride) + 1;

  @override
  int get sourceSampleCount => _points.length;

  @override
  double? get sampleIntervalSeconds {
    if (_points.length < 2) return null;
    final diffs = <double>[];
    final limit = math.min(_points.length - 1, 1000);
    for (var i = 0; i < limit; i++) {
      final dt = _points[i + 1].$1 - _points[i].$1;
      if (dt.isFinite && dt > 0) diffs.add(dt);
    }
    if (diffs.isEmpty) return null;
    diffs.sort();
    final middle = diffs.length ~/ 2;
    final median = diffs.length.isOdd
        ? diffs[middle]
        : (diffs[middle - 1] + diffs[middle]) / 2;
    return median * stride;
  }

  @override
  double timeAt(int index) => _points[index * stride].$1 - _points.first.$1;

  @override
  double voltageAt(int index) => _points[index * stride].$2;
}

/// [_SampleSeries] over raw 8-bit acquisition bytes.
class _RawSeries implements _SampleSeries {
  final Uint8List _raw;
  final double _vdiv;
  final double _voffset;
  final double _sampleRate;
  final double? _sampleIntervalSeconds;
  final int _start;

  @override
  final int stride;

  @override
  late final int length;

  _RawSeries(
    Uint8List raw, {
    required double vdiv,
    required double voffset,
    required double sampleRate,
    required double? sampleIntervalSeconds,
    required int leadingSamplesToSkip,
    required this.stride,
  }) : _raw = raw,
       _vdiv = vdiv,
       _voffset = voffset,
       _sampleRate = sampleRate,
       _sampleIntervalSeconds = sampleIntervalSeconds,
       _start = raw.length > leadingSamplesToSkip * 4
           ? leadingSamplesToSkip
           : 0 {
    final usable = _raw.length - _start;
    length = ((usable - 1) ~/ stride) + 1;
  }

  @override
  int get sourceSampleCount => _raw.length;

  /// Interval between raw samples in seconds, or `null` if unknown.
  double? get _rawInterval =>
      _sampleIntervalSeconds ?? (_sampleRate > 0 ? 1 / _sampleRate : null);

  @override
  double? get sampleIntervalSeconds {
    final interval = _rawInterval;
    return interval == null ? null : interval * stride;
  }

  @override
  double timeAt(int index) {
    final interval = _rawInterval;
    return interval == null ? index.toDouble() : index * stride * interval;
  }

  @override
  double voltageAt(int index) => WaveformConverter.toVoltage(
    _raw[_start + index * stride],
    _vdiv,
    _voffset,
  );
}

/// One detected edge while its 10–90 % thresholds are still being located.
class _Edge {
  double? lowTime;
  double? highTime;

  _Edge({this.lowTime, this.highTime});
}
