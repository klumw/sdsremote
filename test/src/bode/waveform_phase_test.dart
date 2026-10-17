import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/waveform_phase.dart';

void main() {
  const frequency = 1000.0;

  List<double> sine(List<double> times, double phaseRadians) => times
      .map((time) => math.sin(2 * math.pi * frequency * time + phaseRadians))
      .toList(growable: false);

  List<double> makeTimes({int count = 4000}) =>
      List<double>.generate(count, (index) => index / 1e6);

  test('detects a lagging output', () {
    final times = makeTimes();
    final vin = sine(times, 0);
    final vout = sine(times, -math.pi / 4);

    final phase = estimatePhaseFromSamples(
      frequencyHz: frequency,
      times: times,
      vin: vin,
      vout: vout,
    );

    expect(phase, isNotNull);
    expect(phase!, closeTo(-45, 1.5));
  });

  test('detects a leading output', () {
    final times = makeTimes();
    final vin = sine(times, 0);
    final vout = sine(times, math.pi / 4);

    final phase = estimatePhaseFromSamples(
      frequencyHz: frequency,
      times: times,
      vin: vin,
      vout: vout,
    );

    expect(phase, isNotNull);
    expect(phase!, closeTo(45, 1.5));
  });

  test('returns null without crossings', () {
    final times = makeTimes();
    final flat = List<double>.filled(times.length, 1.0);

    expect(
      estimatePhaseFromSamples(
        frequencyHz: frequency,
        times: times,
        vin: flat,
        vout: flat,
      ),
      isNull,
    );
  });

  test('returns null when the record is shorter than one period', () {
    final times = makeTimes(count: 20);
    final vin = sine(times, 0);
    final vout = sine(times, -math.pi / 4);

    expect(
      estimatePhaseFromSamples(
        frequencyHz: frequency,
        times: times,
        vin: vin,
        vout: vout,
      ),
      isNull,
    );
  });
}
