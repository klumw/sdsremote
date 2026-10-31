import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_analysis.dart';
import 'package:sdsremote/src/bode/bode_models.dart';

BodePoint _point(double frequencyHz, double gainDb, {bool valid = true}) =>
    BodePoint(frequencyHz: frequencyHz, gainDb: gainDb, valid: valid);

/// First-order RC low-pass with a corner at [fc].
List<BodePoint> _rcLowPass({double fc = 1000, int count = 200}) {
  final points = <BodePoint>[];
  for (var i = 0; i < count; i++) {
    final f = 10 * math.pow(10, i / (count - 1) * 4).toDouble();
    final gain = -10 * (math.log(1 + (f / fc) * (f / fc)) / math.ln10);
    points.add(_point(f, gain));
  }
  return points;
}

/// Series RLC resonance with a quality factor [q] at [f0].
List<BodePoint> _rlc({double f0 = 1000, double q = 5, int count = 2000}) {
  final points = <BodePoint>[];
  for (var i = 0; i < count; i++) {
    final f = 100 * math.pow(10, i / (count - 1) * 2).toDouble();
    final u = f / f0;
    final magnitude =
        1 / math.sqrt((1 - u * u) * (1 - u * u) + (u / q) * (u / q));
    points.add(_point(f, 20 * (math.log(magnitude) / math.ln10)));
  }
  return points;
}

void main() {
  test('finds the peak and the -3 dB corner of an RC low-pass', () {
    final points = _rcLowPass();

    final peak = findPeak(points)!;
    expect(peak.frequencyHz, closeTo(10, 0.1));
    expect(peak.gainDb, closeTo(0, 0.01));

    final minus3 = findMinus3Db(points)!;
    expect(minus3, closeTo(1000, 10));
    expect(findMinus3Db(points, referenceGainDb: 0), closeTo(1000, 10));

    final analysis = analyzeBode(points);
    expect(analysis.minus3DbFrequencyHz, closeTo(1000, 10));
    expect(analysis.lowerMinus3DbFrequencyHz, isNull);
    expect(analysis.bandwidthHz, isNull);
    expect(analysis.qFactor, isNull);
    expect(analysis.unityCrossoverHz, isNull);
    expect(analysis.notes.join(' '), contains('0 dB'));
  });

  test('computes bandwidth and Q for an RLC resonance', () {
    final points = _rlc();

    final analysis = analyzeBode(points);
    expect(analysis.peakFrequencyHz, closeTo(990, 20));
    expect(analysis.peakGainDb, closeTo(13.98, 0.2));
    expect(analysis.minus3DbFrequencyHz, closeTo(1100, 60));
    expect(analysis.lowerMinus3DbFrequencyHz, closeTo(900, 60));
    expect(analysis.bandwidthHz, closeTo(200, 30));
    expect(analysis.qFactor, closeTo(5, 0.6));
    expect(analysis.unityCrossoverHz, closeTo(1414, 80));

    expect(bandwidth(points), closeTo(analysis.bandwidthHz!, 1e-9));
    expect(qFactor(points), closeTo(analysis.qFactor!, 1e-9));
    expect(
      resonanceFrequency(points),
      closeTo(analysis.peakFrequencyHz!, 1e-9),
    );
  });

  test('interpolates crossings on a logarithmic frequency axis', () {
    final points = [_point(1, 10), _point(10, -10)];

    expect(findGainCrossover(points), closeTo(math.sqrt(10), 1e-9));
    expect(
      findMinus3Db(points, referenceGainDb: 10),
      closeTo(math.pow(10, 3 / 20).toDouble(), 1e-9),
    );
  });

  test('skips invalid and missing points', () {
    final points = [
      _point(1, -20),
      _point(10, 100, valid: false),
      _point(100, 6),
      const BodePoint(frequencyHz: 1000, valid: true),
      _point(10000, -6),
    ];

    final peak = findPeak(points)!;
    expect(peak.frequencyHz, 100);
    expect(peak.gainDb, 6);
    // Peak is +6 dB at 100 Hz; the −3 dB level (+3 dB) is crossed on the
    // log axis one quarter of the way from 100 Hz to 10 kHz → 316.2 Hz.
    expect(findMinus3Db(points), closeTo(316.23, 0.1));
  });

  test('sorts non-monotonic input', () {
    final points = [_point(1000, -10), _point(10, 0), _point(100, 5)];

    final peak = findPeak(points)!;
    expect(peak.frequencyHz, 100);
    expect(peak.gainDb, 5);
  });

  test('returns empty results without valid data', () {
    final empty = analyzeBode(const []);
    expect(empty.hasData, isFalse);
    expect(empty.notes, contains('no valid gain points'));

    final one = analyzeBode([_point(10, 0)]);
    expect(one.hasData, isTrue);
    expect(one.minus3DbFrequencyHz, isNull);
    expect(findPeak(const []), isNull);
    expect(findMinus3Db(const []), isNull);
    expect(findGainCrossover(const []), isNull);
    expect(bandwidth(const []), isNull);
    expect(qFactor(const []), isNull);
    expect(resonanceFrequency(const []), isNull);
  });
}
