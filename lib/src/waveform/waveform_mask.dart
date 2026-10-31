/// Software mask test: tolerance band around a reference waveform.
///
/// The reference defines a voltage band (optionally expanded by a time
/// tolerance); a live acquisition passes when every covered point stays inside
/// it. The module is Flutter-free and performs no I/O.
library;

import 'dart:collection';

/// Voltage band around a reference trace.
///
/// [times], [low] and [high] are parallel lists sorted by time. The band
/// between two samples is interpolated linearly.
class MaskBand {
  final List<double> times;
  final List<double> low;
  final List<double> high;

  const MaskBand({required this.times, required this.low, required this.high});

  const MaskBand.empty() : times = const [], low = const [], high = const [];

  bool get isEmpty => times.isEmpty;
  bool get isNotEmpty => times.isNotEmpty;
}

/// Result of evaluating a live trace against a [MaskBand].
class MaskResult {
  /// Whether at least one point was checked and all checked points passed.
  final bool passed;

  /// Number of violating points.
  final int violations;

  /// Number of live points covered by the band.
  final int checkedPoints;

  final double? firstViolationTime;
  final double? lastViolationTime;

  /// Largest distance outside the band, in volts.
  final double maxViolationVolts;

  /// Violating live points, used to mark them in the plot.
  final List<(double, double)> violationPoints;

  const MaskResult({
    required this.passed,
    required this.violations,
    required this.checkedPoints,
    this.firstViolationTime,
    this.lastViolationTime,
    this.maxViolationVolts = 0,
    this.violationPoints = const [],
  });

  const MaskResult.empty()
    : passed = false,
      violations = 0,
      checkedPoints = 0,
      firstViolationTime = null,
      lastViolationTime = null,
      maxViolationVolts = 0,
      violationPoints = const [];

  /// Whether any live point overlapped the band.
  bool get hasData => checkedPoints > 0;
}

/// Builds the tolerance band around [reference].
///
/// [toleranceVolts] is the vertical half-width of the band. A positive
/// [toleranceTime] additionally widens the allowed voltage at each reference
/// sample to the minimum/maximum of all reference samples within that time
/// window, so a horizontal timing tolerance is accepted as well.
MaskBand buildMaskBand(
  List<(double, double)> reference, {
  required double toleranceVolts,
  double? toleranceTime,
}) {
  if (reference.isEmpty) return const MaskBand.empty();
  final sorted = _sortedByTime(reference);
  final count = sorted.length;
  final tolerance = toleranceVolts.abs();
  final times = [for (final point in sorted) point.$1];
  final values = [for (final point in sorted) point.$2];
  final window = toleranceTime ?? 0;

  if (window <= 0) {
    return MaskBand(
      times: times,
      low: [for (final value in values) value - tolerance],
      high: [for (final value in values) value + tolerance],
    );
  }

  // Sliding-window minimum and maximum with monotonic queues: each reference
  // sample contributes to the band of every sample within ±window.
  final low = List<double>.filled(count, 0);
  final high = List<double>.filled(count, 0);
  final minQueue = ListQueue<int>();
  final maxQueue = ListQueue<int>();
  var left = 0;
  var right = 0; // exclusive end of the current window

  for (var i = 0; i < count; i++) {
    final windowStart = times[i] - window;
    final windowEnd = times[i] + window;

    while (right < count && times[right] <= windowEnd) {
      while (minQueue.isNotEmpty && values[minQueue.last] >= values[right]) {
        minQueue.removeLast();
      }
      minQueue.addLast(right);
      while (maxQueue.isNotEmpty && values[maxQueue.last] <= values[right]) {
        maxQueue.removeLast();
      }
      maxQueue.addLast(right);
      right++;
    }
    while (left < right && times[left] < windowStart) {
      if (minQueue.isNotEmpty && minQueue.first == left) {
        minQueue.removeFirst();
      }
      if (maxQueue.isNotEmpty && maxQueue.first == left) {
        maxQueue.removeFirst();
      }
      left++;
    }

    low[i] = values[minQueue.first] - tolerance;
    high[i] = values[maxQueue.first] + tolerance;
  }

  return MaskBand(times: times, low: low, high: high);
}

/// Checks every covered point of [live] against [band].
///
/// Live points outside the band's time range are skipped, so missing
/// reference data never produces a false violation.
MaskResult evaluateMask(List<(double, double)> live, MaskBand band) {
  if (live.isEmpty || band.isEmpty) return const MaskResult.empty();

  final sortedLive = _sortedByTime(live);
  final bandTimes = band.times;
  final firstTime = bandTimes.first;
  final lastTime = bandTimes.last;

  var checked = 0;
  var violations = 0;
  var maxViolation = 0.0;
  double? firstViolationTime;
  double? lastViolationTime;
  final violationPoints = <(double, double)>[];

  for (final (time, voltage) in sortedLive) {
    if (!time.isFinite || time < firstTime || time > lastTime) continue;
    final index = _segmentIndex(bandTimes, time);
    final double low;
    final double high;
    if (index == bandTimes.length - 1 || bandTimes[index] == time) {
      low = band.low[index];
      high = band.high[index];
    } else {
      final span = bandTimes[index + 1] - bandTimes[index];
      final fraction = span > 0 ? (time - bandTimes[index]) / span : 0.0;
      low =
          band.low[index] + (band.low[index + 1] - band.low[index]) * fraction;
      high =
          band.high[index] +
          (band.high[index + 1] - band.high[index]) * fraction;
    }

    checked++;
    final double violation;
    if (voltage < low) {
      violation = low - voltage;
    } else if (voltage > high) {
      violation = voltage - high;
    } else {
      violation = 0;
    }
    if (violation > 0) {
      violations++;
      if (violation > maxViolation) maxViolation = violation;
      firstViolationTime ??= time;
      lastViolationTime = time;
      violationPoints.add((time, voltage));
    }
  }

  return MaskResult(
    passed: checked > 0 && violations == 0,
    violations: violations,
    checkedPoints: checked,
    firstViolationTime: firstViolationTime,
    lastViolationTime: lastViolationTime,
    maxViolationVolts: maxViolation,
    violationPoints: violationPoints,
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

/// Index of the last point at or before [time] in the sorted [times].
int _segmentIndex(List<double> times, double time) {
  var low = 0;
  var high = times.length - 1;
  while (low < high) {
    final middle = (low + high + 1) >> 1;
    if (times[middle] <= time) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low;
}
