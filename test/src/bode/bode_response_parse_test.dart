import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_math.dart';

void main() {
  group('parsePavaRms', () {
    test('parses the RMS value of the requested channel', () {
      expect(
        parsePavaRms('C1:PAVA RMS,3.424000E-01V', 1),
        closeTo(0.3424, 1e-12),
      );
      expect(
        parsePavaRms('C2:PAVA RMS,6.210000E-03V', 2),
        closeTo(0.00621, 1e-12),
      );
    });

    test('accepts a response without a comma', () {
      expect(
        parsePavaRms('C1:PAVA RMS 3.424E-01V', 1),
        closeTo(0.3424, 1e-12),
      );
    });

    test('rejects a response for the other channel', () {
      expect(parsePavaRms('C2:PAVA RMS,3.424000E-01V', 1), isNull);
    });

    test('rejects out-of-range and foreign responses', () {
      expect(parsePavaRms('C1:PAVA RMS,****', 1), isNull);
      expect(
        parsePavaRms('Siglent Technologies,SDS1202X-E,SDS1EDEX5R7059,1.3.27', 1),
        isNull,
      );
    });
  });

  group('parseMeadPhase', () {
    test('parses degrees and negative values', () {
      expect(
        parseMeadPhase('C1-C2:MEAD PHA,5.760000E-03degree'),
        closeTo(0.00576, 1e-12),
      );
      expect(
        parseMeadPhase('C1-C2:MEAD PHA,-1.110000E+00degree'),
        closeTo(-1.11, 1e-12),
      );
      expect(
        parseMeadPhase('C2-C1:MEAD PHA,1.800600E+02degree'),
        closeTo(180.06, 1e-12),
      );
    });

    test('rejects out-of-range and foreign responses', () {
      expect(parseMeadPhase('C1-C2:MEAD PHA,****'), isNull);
      expect(
        parseMeadPhase('Siglent Technologies,SDS1202X-E,SDS1EDEX5R7059,1.3.27'),
        isNull,
      );
      expect(
        parseMeadPhase('-113,Undefined header,MEASURE_DELAY'),
        isNull,
      );
    });
  });
}
