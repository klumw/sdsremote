import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_math.dart';
import 'package:sdsremote/src/bode/bode_models.dart';
import 'package:sdsremote/src/signal_generator/models.dart';

void main() {
  group('frequency points', () {
    test('logarithmic endpoints and midpoint', () {
      const config = BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 10000,
        pointCount: 3,
      );
      final points = buildFrequencyPoints(config);
      expect(points.length, 3);
      expect(points.first, closeTo(100, 1e-9));
      expect(points[1], closeTo(1000, 1e-6));
      expect(points.last, closeTo(10000, 1e-6));
    });

    test('linear endpoints and midpoint', () {
      const config = BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 10000,
        pointCount: 3,
        spacing: BodeSpacing.linear,
      );
      final points = buildFrequencyPoints(config);
      expect(points, [100, 5050, 10000]);
    });

    test('rejects invalid ranges', () {
      expect(
        () => buildFrequencyPoints(
          const BodeConfig(startFrequencyHz: 0, stopFrequencyHz: 100),
        ),
        throwsArgumentError,
      );
      expect(
        () => buildFrequencyPoints(
          const BodeConfig(
            startFrequencyHz: 100,
            stopFrequencyHz: 100,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('phase', () {
    test('wraps into (-180, 180]', () {
      expect(wrapPhaseDeg(0), 0);
      expect(wrapPhaseDeg(180), 180);
      expect(wrapPhaseDeg(-180), 180);
      expect(wrapPhaseDeg(190), closeTo(-170, 1e-9));
      expect(wrapPhaseDeg(-190), closeTo(170, 1e-9));
      expect(wrapPhaseDeg(540), closeTo(180, 1e-9));
    });

    test('phase from delay follows -360 f dt', () {
      expect(phaseFromDelay(1000, 0), 0);
      expect(phaseFromDelay(1000, 0.000125), closeTo(-45, 1e-9));
      expect(phaseFromDelay(1000, -0.000125), closeTo(45, 1e-9));
    });
  });

  group('gain', () {
    test('computes the plain dB ratio', () {
      expect(bodeGainDb(1, 0.5), closeTo(-6.0206, 1e-3));
      expect(bodeGainDb(1, 2), closeTo(6.0206, 1e-3));
    });

    test('rejects missing or too-small input', () {
      expect(bodeGainDb(null, 1), isNull);
      expect(bodeGainDb(0, 1), isNull);
      expect(bodeGainDb(bodeMinVinRms / 2, 1), isNull);
    });

    test('allows a very small output (deep stopband)', () {
      expect(bodeGainDb(1, 1e-5), closeTo(-100, 1e-6));
    });
  });

  group('validation', () {
    const lite = Jds6600DeviceInfo(modelMHz: 15, serialNumber: 1);

    test('default config is valid for a Lite', () {
      expect(validateBodeConfig(const BodeConfig(), lite), isNull);
    });

    test('rejects invalid ranges, counts and channels', () {
      expect(
        validateBodeConfig(
          const BodeConfig(startFrequencyHz: 0),
          lite,
        ),
        contains('Start frequency'),
      );
      expect(
        validateBodeConfig(
          const BodeConfig(
            startFrequencyHz: 1000,
            stopFrequencyHz: 100,
          ),
          lite,
        ),
        contains('Stop frequency'),
      );
      expect(
        validateBodeConfig(const BodeConfig(pointCount: 1), lite),
        contains('Point count'),
      );
      expect(
        validateBodeConfig(
          const BodeConfig(vinChannel: 1, voutChannel: 1),
          lite,
        ),
        contains('different'),
      );
      expect(
        validateBodeConfig(
          const BodeConfig(vinChannel: 3, voutChannel: 2),
          lite,
        ),
        contains('Input channel'),
      );
    });

    test('rejects frequencies and amplitudes outside the generator limits', () {
      expect(
        validateBodeConfig(
          const BodeConfig(stopFrequencyHz: 20e6),
          lite,
        ),
        contains('exceeds'),
      );
      expect(
        validateBodeConfig(
          const BodeConfig(amplitudeVpp: 25),
          lite,
        ),
        contains('Amplitude'),
      );
    });
  });

  test('effective settling uses at least three periods and 200 ms', () {
    const config = BodeConfig(settling: Duration.zero);
    expect(
      effectiveSettling(config, 10).inMilliseconds,
      greaterThanOrEqualTo(300),
    );
    expect(
      effectiveSettling(config, 1000).inMilliseconds,
      200,
    );
    expect(
      effectiveSettling(
        const BodeConfig(settling: Duration(seconds: 1)),
        1000,
      ).inMilliseconds,
      1000,
    );
    expect(
      effectiveSettling(config, 0.1).inMilliseconds,
      5000,
    );
  });

  test('parses the last number from scope responses', () {
    expect(parseLastNumber('C1:PAVA RMS,1.234E-01V'), closeTo(0.1234, 1e-9));
    expect(parseLastNumber('C1-C2:MEAD PHA,-45.0'), -45);
    expect(parseLastNumber('***'), isNull);
  });

  test('formats frequency labels', () {
    expect(formatFrequencyHz(100), '100 Hz');
    expect(formatFrequencyHz(1000), '1 kHz');
    expect(formatFrequencyHz(1.5e6), '1.5 MHz');
  });
}
