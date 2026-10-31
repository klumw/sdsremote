/// Golden-sample / before-after comparison of two waveform traces.
///
/// The module is Flutter-free and performs no I/O: it resamples a reference
/// trace onto the live time axis, applies the manual reference offset and
/// derives the difference trace plus deviation metrics.
library;

import 'dart:math' as math;

import 'waveform_models.dart';

/// Deviation metrics of a live waveform against a reference.
///
/// A live point only counts when the (shifted) reference covers its timestamp;
/// [coveragePercent] tells how much of the live trace was compared. The error
/// fields stay `null` when nothing overlaps.
class ComparisonMetrics {
  /// Number of points in the live trace.
  final int livePoints;

  /// Number of live points covered by the reference.
  final int comparedPoints;

  /// Share of the live trace covered by the reference, in percent.
  final double coveragePercent;

  /// Root-mean-square of `live − reference` in volts.
  final double? rmsErrorVolts;

  /// Largest absolute deviation in volts.
  final double? maxAbsDeviationVolts;

  /// Mean of `live − reference` in volts.
  final double? meanErrorVolts;

  const ComparisonMetrics({
    required this.livePoints,
    required this.comparedPoints,
    required this.coveragePercent,
    this.rmsErrorVolts,
    this.maxAbsDeviationVolts,
    this.meanErrorVolts,
  });

  const ComparisonMetrics.empty()
    : livePoints = 0,
      comparedPoints = 0,
      coveragePercent = 0,
      rmsErrorVolts = null,
      maxAbsDeviationVolts = null,
      meanErrorVolts = null;

  bool get hasData => comparedPoints > 0;
}

/// Shifts [reference] by the manual alignment [offset].
///
/// The horizontal shift is `offset.dxDiv · timebase` seconds and the vertical
/// shift is `offset.dyDiv · referenceVdiv` volts — the same mapping the
/// painter uses. The returned list is sorted by time.
List<(double, double)> shiftReference(
  List<(double, double)> reference, {
  ReferenceOffset offset = const ReferenceOffset(),
  double timebase = 0,
  double referenceVdiv = 0,
}) {
  if (reference.isEmpty) return const [];
  final dt = offset.timeShiftSeconds(timebase);
  final dv = offset.voltageShiftVolts(referenceVdiv);
  var shifted = reference;
  if (dt != 0 || dv != 0) {
    shifted = [for (final point in reference) (point.$1 + dt, point.$2 + dv)];
  }
  return _sortedByTime(shifted);
}

/// Linearly interpolates [source] at each requested timestamp.
///
/// Returns `(time, voltage)` for timestamps inside the source range and `null`
/// outside it — values are never extrapolated. [source] is sorted internally
/// when needed, so unsorted CSV data is handled as well.
List<(double, double)?> resampleAtTimes(
  List<(double, double)> source,
  List<double> times,
) {
  if (source.isEmpty) return List<(double, double)?>.filled(times.length, null);
  final sorted = _sortedByTime(source);
  final firstTime = sorted.first.$1;
  final lastTime = sorted.last.$1;
  final result = List<(double, double)?>.filled(times.length, null);

  for (var i = 0; i < times.length; i++) {
    final t = times[i];
    if (!t.isFinite || t < firstTime || t > lastTime) continue;
    final index = _segmentIndex(sorted, t);
    final (t0, v0) = sorted[index];
    if (t == t0 || index == sorted.length - 1) {
      result[i] = (t, v0);
      continue;
    }
    final (t1, v1) = sorted[index + 1];
    final span = t1 - t0;
    final value = span > 0 ? v0 + (v1 - v0) * (t - t0) / span : v0;
    result[i] = (t, value);
  }
  return result;
}

/// Builds the difference `live − reference` on the live time axis.
///
/// The reference is shifted by [offset] before it is resampled, so the
/// difference follows the manual alignment shown in the plot. Points outside
/// the reference range are omitted instead of being invented.
List<(double, double)> differenceTrace({
  required List<(double, double)> live,
  required List<(double, double)> reference,
  ReferenceOffset offset = const ReferenceOffset(),
  double timebase = 0,
  double referenceVdiv = 0,
}) {
  if (live.isEmpty || reference.isEmpty) return const [];
  final shifted = shiftReference(
    reference,
    offset: offset,
    timebase: timebase,
    referenceVdiv: referenceVdiv,
  );
  final times = [for (final point in live) point.$1];
  final resampled = resampleAtTimes(shifted, times);

  final difference = <(double, double)>[];
  for (var i = 0; i < live.length; i++) {
    final referencePoint = resampled[i];
    if (referencePoint == null) continue;
    final (t, v) = live[i];
    difference.add((t, v - referencePoint.$2));
  }
  return difference;
}

/// Computes RMS, maximum and mean deviation of [live] against [reference].
ComparisonMetrics comparisonMetrics({
  required List<(double, double)> live,
  required List<(double, double)> reference,
  ReferenceOffset offset = const ReferenceOffset(),
  double timebase = 0,
  double referenceVdiv = 0,
}) {
  if (live.isEmpty) return const ComparisonMetrics.empty();
  if (reference.isEmpty) {
    return ComparisonMetrics(
      livePoints: live.length,
      comparedPoints: 0,
      coveragePercent: 0,
    );
  }

  final shifted = shiftReference(
    reference,
    offset: offset,
    timebase: timebase,
    referenceVdiv: referenceVdiv,
  );
  final times = [for (final point in live) point.$1];
  final resampled = resampleAtTimes(shifted, times);

  var compared = 0;
  var sum = 0.0;
  var sumSquares = 0.0;
  var maxAbs = 0.0;
  for (var i = 0; i < live.length; i++) {
    final referencePoint = resampled[i];
    if (referencePoint == null) continue;
    final error = live[i].$2 - referencePoint.$2;
    if (!error.isFinite) continue;
    compared++;
    sum += error;
    sumSquares += error * error;
    if (error.abs() > maxAbs) maxAbs = error.abs();
  }

  if (compared == 0) {
    return ComparisonMetrics(
      livePoints: live.length,
      comparedPoints: 0,
      coveragePercent: 0,
    );
  }

  return ComparisonMetrics(
    livePoints: live.length,
    comparedPoints: compared,
    coveragePercent: compared / live.length * 100,
    rmsErrorVolts: math.sqrt(sumSquares / compared),
    maxAbsDeviationVolts: maxAbs,
    meanErrorVolts: sum / compared,
  );
}

/// Returns a time-sorted copy of [points] (the input is returned when it is
/// already sorted).
List<(double, double)> _sortedByTime(List<(double, double)> points) {
  for (var i = 1; i < points.length; i++) {
    if (points[i].$1 < points[i - 1].$1) {
      return [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    }
  }
  return points;
}

/// Index of the last point at or before [time] in the sorted [points].
int _segmentIndex(List<(double, double)> points, double time) {
  var low = 0;
  var high = points.length - 1;
  while (low < high) {
    final middle = (low + high + 1) >> 1;
    if (points[middle].$1 <= time) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low;
}
