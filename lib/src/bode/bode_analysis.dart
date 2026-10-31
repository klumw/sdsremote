/// Automatic analysis of Bode gain curves.
///
/// Provides peak, −3 dB, bandwidth, Q factor and gain-crossover extraction
/// from measured [BodePoint]s. Invalid or missing points are skipped, the
/// remaining points are sorted by frequency, and crossings are interpolated
/// linearly on the logarithmic frequency axis. Flutter-free and no I/O.
library;

import 'dart:math' as math;

import 'bode_models.dart';

/// Result of [analyzeBode].
class BodeAnalysisSummary {
  /// Highest measured gain and the frequency where it occurs.
  final double? peakGainDb;
  final double? peakFrequencyHz;

  /// Upper crossing of `reference − 3 dB` (the roll-off point).
  final double? minus3DbFrequencyHz;

  /// Lower crossing of `reference − 3 dB`, when the curve rises into the
  /// peak (resonant/band-pass response).
  final double? lowerMinus3DbFrequencyHz;

  /// `upper − lower` when both −3 dB crossings exist.
  final double? bandwidthHz;

  /// Peak frequency divided by [bandwidthHz], when the bandwidth is known.
  final double? qFactor;

  /// Frequency where the gain crosses 0 dB.
  final double? unityCrossoverHz;

  /// Explanations for values that could not be determined.
  final List<String> notes;

  const BodeAnalysisSummary({
    this.peakGainDb,
    this.peakFrequencyHz,
    this.minus3DbFrequencyHz,
    this.lowerMinus3DbFrequencyHz,
    this.bandwidthHz,
    this.qFactor,
    this.unityCrossoverHz,
    this.notes = const [],
  });

  bool get hasData => peakGainDb != null;
}

/// Returns the maximum gain and its frequency, or `null` without valid data.
({double gainDb, double frequencyHz})? findPeak(List<BodePoint> points) {
  final valid = _validGainPoints(points);
  if (valid.isEmpty) return null;

  var best = valid.first;
  for (final point in valid.skip(1)) {
    if (point.$2 > best.$2) best = point;
  }
  return (gainDb: best.$2, frequencyHz: best.$1);
}

/// Returns the upper −3 dB crossing relative to [referenceGainDb].
///
/// [referenceGainDb] defaults to the peak gain, so the result is the
/// half-power roll-off frequency. Returns `null` when the curve never falls
/// through that level.
double? findMinus3Db(List<BodePoint> points, {double? referenceGainDb}) {
  final valid = _validGainPoints(points);
  if (valid.isEmpty) return null;

  final reference = referenceGainDb ?? findPeak(points)?.gainDb;
  if (reference == null || !reference.isFinite) return null;
  final target = reference - 3;

  for (var i = 0; i + 1 < valid.length; i++) {
    final (f0, g0) = valid[i];
    final (f1, g1) = valid[i + 1];
    if (g0 == target) return f0;
    if (g0 > target && g1 <= target) {
      return _interpolateLog(f0, g0, f1, g1, target);
    }
  }
  return null;
}

/// Returns the first frequency where the gain crosses [targetDb].
///
/// The first crossing in ascending frequency order is returned, regardless of
/// its direction. Returns `null` when no crossing exists.
double? findGainCrossover(List<BodePoint> points, {double targetDb = 0}) {
  final valid = _validGainPoints(points);
  if (valid.isEmpty) return null;

  for (var i = 0; i + 1 < valid.length; i++) {
    final (f0, g0) = valid[i];
    final (f1, g1) = valid[i + 1];
    if (g0 == targetDb) return f0;
    if ((g0 < targetDb && g1 > targetDb) || (g0 > targetDb && g1 < targetDb)) {
      return _interpolateLog(f0, g0, f1, g1, targetDb);
    }
  }
  return null;
}

/// Frequency of the maximum gain.
double? resonanceFrequency(List<BodePoint> points) =>
    findPeak(points)?.frequencyHz;

/// −3 dB bandwidth (`upper − lower`) when both crossings exist.
double? bandwidth(List<BodePoint> points) => analyzeBode(points).bandwidthHz;

/// Q factor `peak frequency / bandwidth` when both crossings exist.
double? qFactor(List<BodePoint> points) => analyzeBode(points).qFactor;

/// Runs the full analysis used by the panel and the PDF report.
BodeAnalysisSummary analyzeBode(
  List<BodePoint> points, {
  double? referenceGainDb,
}) {
  final valid = _validGainPoints(points);
  if (valid.isEmpty) {
    return const BodeAnalysisSummary(notes: ['no valid gain points']);
  }

  final peak = findPeak(points);
  if (peak == null) {
    return const BodeAnalysisSummary(notes: ['no valid gain points']);
  }
  final reference = referenceGainDb ?? peak.gainDb;
  final target = reference - 3;
  final notes = <String>[];

  final upper = findMinus3Db(points, referenceGainDb: reference);
  if (upper == null) {
    notes.add('no -3 dB crossing found');
  }

  // The lower crossing is the last upward crossing at or below the peak.
  double? lower;
  for (var i = 0; i + 1 < valid.length; i++) {
    final (f0, g0) = valid[i];
    final (f1, g1) = valid[i + 1];
    if (f1 > peak.frequencyHz) break;
    if (g0 <= target && g1 > target) {
      lower = _interpolateLog(f0, g0, f1, g1, target);
    }
  }
  if (lower == null && peak.frequencyHz > valid.first.$1 * 1.001) {
    notes.add('lower -3 dB crossing not found; bandwidth/Q unavailable');
  }

  final bandwidth = lower != null && upper != null ? upper - lower : null;
  final q = bandwidth != null && bandwidth > 0
      ? peak.frequencyHz / bandwidth
      : null;

  final unity = findGainCrossover(points);
  if (unity == null) {
    notes.add('gain never crosses 0 dB');
  }

  return BodeAnalysisSummary(
    peakGainDb: peak.gainDb,
    peakFrequencyHz: peak.frequencyHz,
    minus3DbFrequencyHz: upper,
    lowerMinus3DbFrequencyHz: lower,
    bandwidthHz: bandwidth,
    qFactor: q,
    unityCrossoverHz: unity,
    notes: notes,
  );
}

/// Valid gain points as `(frequency, gain)`, sorted by frequency.
List<(double, double)> _validGainPoints(List<BodePoint> points) {
  final valid = <(double, double)>[];
  for (final point in points) {
    final gain = point.gainDb;
    if (!point.valid ||
        gain == null ||
        !gain.isFinite ||
        !point.frequencyHz.isFinite ||
        point.frequencyHz <= 0) {
      continue;
    }
    valid.add((point.frequencyHz, gain));
  }
  valid.sort((a, b) => a.$1.compareTo(b.$1));
  return valid;
}

/// Linear interpolation of the crossing frequency on a log10 axis.
double _interpolateLog(
  double f0,
  double g0,
  double f1,
  double g1,
  double target,
) {
  final span = g1 - g0;
  if (span == 0) return f0;
  final fraction = ((target - g0) / span).clamp(0.0, 1.0);
  final logF0 = math.log(f0) / math.ln10;
  final logF1 = math.log(f1) / math.ln10;
  final logFrequency = logF0 + (logF1 - logF0) * fraction;
  return math.pow(10, logFrequency).toDouble();
}
