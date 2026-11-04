/// Analysis helpers for Bode/frequency-sweep audio tools.
///
/// The host application runs the sweep; these functions only interpret the
/// returned points. They reuse the existing Bode gain analysis and add phase
/// unwrapping and group-delay extraction.
library;

import 'dart:math' as math;

import '../../../bode/bode_analysis.dart';
import '../../../bode/bode_models.dart';
import 'audio_analysis_context.dart';

/// One phase-response point.
class AudioPhasePoint {
  const AudioPhasePoint({
    required this.frequencyHz,
    required this.phaseDeg,
    required this.unwrappedPhaseDeg,
    this.gainDb,
  });

  final double frequencyHz;
  final double phaseDeg;
  final double unwrappedPhaseDeg;
  final double? gainDb;
}

/// Phase response summary.
class AudioPhaseResponse {
  const AudioPhaseResponse({
    required this.points,
    this.startPhaseDeg,
    this.stopPhaseDeg,
    this.phaseRangeDeg,
    required this.notes,
  });

  final List<AudioPhasePoint> points;
  final double? startPhaseDeg;
  final double? stopPhaseDeg;
  final double? phaseRangeDeg;
  final List<String> notes;
}

/// One group-delay point.
class AudioGroupDelayPoint {
  const AudioGroupDelayPoint({
    required this.frequencyHz,
    required this.delaySeconds,
    required this.phaseDeg,
    this.gainDb,
  });

  final double frequencyHz;
  final double delaySeconds;
  final double phaseDeg;
  final double? gainDb;
}

/// Group-delay summary.
class AudioGroupDelay {
  const AudioGroupDelay({
    required this.points,
    this.meanDelaySeconds,
    this.minDelaySeconds,
    this.maxDelaySeconds,
    required this.notes,
  });

  final List<AudioGroupDelayPoint> points;
  final double? meanDelaySeconds;
  final double? minDelaySeconds;
  final double? maxDelaySeconds;
  final List<String> notes;
}

/// Complete sweep analysis.
class AudioSweepAnalysis {
  const AudioSweepAnalysis({
    required this.gain,
    required this.phase,
    required this.groupDelay,
    required this.validPointCount,
    required this.notes,
  });

  final BodeAnalysisSummary gain;
  final AudioPhaseResponse phase;
  final AudioGroupDelay groupDelay;
  final int validPointCount;
  final List<String> notes;
}

/// Converts the audio sweep points to the existing [BodePoint] model.
List<BodePoint> audioSweepToBodePoints(AudioSweepData data) => [
  for (final point in data.points)
    BodePoint(
      frequencyHz: point.frequencyHz,
      gainDb: point.gainDb,
      phaseDeg: point.phaseDeg,
      vinRms: point.vinRms,
      voutRms: point.voutRms,
      valid: point.valid,
      note: point.note,
    ),
];

/// Runs the existing gain analysis on [data].
BodeAnalysisSummary analyzeAudioSweepGain(AudioSweepData data) =>
    analyzeBode(audioSweepToBodePoints(data));

/// −3 dB bandwidth that also handles a low-pass response.
///
/// [analyzeBode] requires both a lower and an upper crossing, so a low-pass
/// whose peak is at the lowest measured frequency gets no bandwidth there.
/// In that case the bandwidth runs from the first valid frequency to the
/// upper −3 dB crossing.
double? audioSweepBandwidth(AudioSweepData data) {
  final points = audioSweepToBodePoints(data);
  final summary = analyzeBode(points);
  if (summary.bandwidthHz != null) return summary.bandwidthHz;
  final peak = findPeak(points);
  final upper = findMinus3Db(points);
  if (peak == null || upper == null) return null;
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
  if (valid.length < 2) return null;
  final firstFrequency = valid.first.$1;
  if (peak.frequencyHz <= firstFrequency * 1.01) {
    return upper - firstFrequency;
  }
  return null;
}

/// Unwraps the phase response and returns its range.
AudioPhaseResponse measureAudioPhaseResponse(AudioSweepData data) {
  final valid = <BodePoint>[
    for (final point in audioSweepToBodePoints(data))
      if (point.valid &&
          point.phaseDeg != null &&
          point.phaseDeg!.isFinite &&
          point.frequencyHz.isFinite &&
          point.frequencyHz > 0)
        point,
  ]..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));

  final notes = <String>[];
  if (valid.length < 2) {
    notes.add('fewer than two valid phase points');
  }

  final points = <AudioPhasePoint>[];
  double? previousUnwrapped;
  for (final point in valid) {
    final raw = point.phaseDeg!;
    var unwrapped = raw;
    if (previousUnwrapped != null) {
      while (unwrapped - previousUnwrapped > 180) {
        unwrapped -= 360;
      }
      while (unwrapped - previousUnwrapped < -180) {
        unwrapped += 360;
      }
    }
    previousUnwrapped = unwrapped;
    points.add(
      AudioPhasePoint(
        frequencyHz: point.frequencyHz,
        phaseDeg: raw,
        unwrappedPhaseDeg: unwrapped,
        gainDb: point.gainDb,
      ),
    );
  }

  double? start;
  double? stop;
  double? range;
  if (points.isNotEmpty) {
    start = points.first.unwrappedPhaseDeg;
    stop = points.last.unwrappedPhaseDeg;
    var min = points.first.unwrappedPhaseDeg;
    var max = points.first.unwrappedPhaseDeg;
    for (final point in points.skip(1)) {
      if (point.unwrappedPhaseDeg < min) min = point.unwrappedPhaseDeg;
      if (point.unwrappedPhaseDeg > max) max = point.unwrappedPhaseDeg;
    }
    range = max - min;
  }

  return AudioPhaseResponse(
    points: points,
    startPhaseDeg: start,
    stopPhaseDeg: stop,
    phaseRangeDeg: range,
    notes: notes,
  );
}

/// Computes group delay `−dφ/dω` from the unwrapped phase response.
///
/// Adjacent valid points are used; the result is assigned to the midpoint
/// frequency. No smoothing is applied, so a noisy phase measurement produces
/// a noisy group delay, which the notes state explicitly.
AudioGroupDelay measureAudioGroupDelay(AudioSweepData data) {
  final phase = measureAudioPhaseResponse(data);
  final notes = <String>[...phase.notes];
  final points = <AudioGroupDelayPoint>[];

  for (var i = 0; i + 1 < phase.points.length; i++) {
    final first = phase.points[i];
    final second = phase.points[i + 1];
    final deltaFrequency = second.frequencyHz - first.frequencyHz;
    if (!(deltaFrequency > 0)) continue;
    final deltaPhase = second.unwrappedPhaseDeg - first.unwrappedPhaseDeg;
    final delay = -deltaPhase / (360 * deltaFrequency);
    if (!delay.isFinite) continue;
    points.add(
      AudioGroupDelayPoint(
        frequencyHz: (first.frequencyHz + second.frequencyHz) / 2,
        delaySeconds: delay,
        phaseDeg: (first.unwrappedPhaseDeg + second.unwrappedPhaseDeg) / 2,
        gainDb: _averageNullable(first.gainDb, second.gainDb),
      ),
    );
  }

  if (points.isEmpty) {
    notes.add('group delay needs at least two valid phase points');
  } else {
    notes.add(
      'group delay is derived from adjacent sweep points; no smoothing was '
      'applied',
    );
  }

  final delays = [for (final point in points) point.delaySeconds];
  return AudioGroupDelay(
    points: points,
    meanDelaySeconds: delays.isEmpty ? null : _mean(delays),
    minDelaySeconds: delays.isEmpty ? null : _min(delays),
    maxDelaySeconds: delays.isEmpty ? null : _max(delays),
    notes: notes,
  );
}

/// Runs gain, phase and group-delay analysis on one sweep.
AudioSweepAnalysis analyzeAudioSweep(AudioSweepData data) {
  final gain = analyzeAudioSweepGain(data);
  final phase = measureAudioPhaseResponse(data);
  final groupDelay = measureAudioGroupDelay(data);
  final notes = <String>[...gain.notes, ...phase.notes, ...groupDelay.notes];
  final validPoints = data.points.where((point) => point.valid).length;
  if (validPoints == 0) {
    notes.add('the sweep returned no valid points');
  }
  return AudioSweepAnalysis(
    gain: gain,
    phase: phase,
    groupDelay: groupDelay,
    validPointCount: validPoints,
    notes: notes.toSet().toList(),
  );
}

double? _averageNullable(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return (a + b) / 2;
}

double _mean(List<double> values) {
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double _min(List<double> values) => values.reduce(math.min);

double _max(List<double> values) => values.reduce(math.max);
