import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/jds6600_protocol.dart';
import 'package:sdsremote/src/signal_generator/models.dart';

void main() {
  group('framing', () {
    test('pads register numbers below 10', () {
      expect(Jds6600Protocol.registerText(0), '00');
      expect(Jds6600Protocol.registerText(9), '09');
      expect(Jds6600Protocol.registerText(20), '20');
    });

    test('builds read and write commands', () {
      expect(Jds6600Protocol.readCommand(20), ':r20=0.\n');
      expect(Jds6600Protocol.readCommand(20, count: 13), ':r20=12.\n');
      expect(Jds6600Protocol.writeCommand(20, '1,0'), ':w20=1,0.\n');
    });

    test('parses padded and unpadded echoes', () {
      expect(Jds6600Protocol.parseRegisterResponse(20, ':r20=1,0.'), [1, 0]);
      expect(Jds6600Protocol.parseRegisterResponse(0, ':r00=15.'), [15]);
      expect(Jds6600Protocol.parseRegisterResponse(0, ':r0=15.'), [15]);
    });

    test('parses a register sequence', () {
      final parsed = Jds6600Protocol.parseRegisterSequence(20, [
        ':r20=1,0.',
        ':r21=0.',
        ':r22=1.',
      ]);
      expect(parsed, [
        [1, 0],
        [0],
        [1],
      ]);
    });

    test('rejects mismatched echoes', () {
      expect(
        () => Jds6600Protocol.parseRegisterResponse(21, ':r22=0.'),
        throwsA(isA<Jds6600ProtocolException>()),
      );
    });

    test('accepts :ok case-insensitively', () {
      expect(Jds6600Protocol.isAck(':ok'), isTrue);
      expect(Jds6600Protocol.isAck(':OK'), isTrue);
      expect(Jds6600Protocol.isAck(':r20=0.'), isFalse);
    });
  });

  group('conversions', () {
    test('frequency', () {
      expect(Jds6600Protocol.encodeFrequency(1000), '100000,0');
      expect(Jds6600Protocol.decodeFrequency([100000, 0]), 1000);
      expect(Jds6600Protocol.decodeFrequency([100000, 3]), 1);
      expect(Jds6600Protocol.decodeFrequency([100000, 4]), 0.001);
    });

    test('amplitude, offset, duty and phase', () {
      expect(Jds6600Protocol.encodeAmplitude(1), '1000');
      expect(Jds6600Protocol.decodeAmplitude([1000]), 1);
      expect(Jds6600Protocol.encodeOffset(-0.5), '950');
      expect(Jds6600Protocol.decodeOffset([950]), -0.5);
      expect(Jds6600Protocol.encodeDuty(25), '250');
      expect(Jds6600Protocol.decodeDuty([250]), 25);
      expect(Jds6600Protocol.encodePhase(90), '900');
      expect(Jds6600Protocol.decodePhase([900]), 90);
    });

    test('waveforms and arbitrary slots', () {
      expect(Jds6600Protocol.decodeWaveform([0]), Jds6600Waveform.sine);
      expect(Jds6600Protocol.decodeWaveform([1]), Jds6600Waveform.square);
      expect(Jds6600Protocol.decodeWaveform([101]), Jds6600Waveform.arbitrary);
      expect(Jds6600Protocol.decodeWaveform([160]), Jds6600Waveform.arbitrary);
      expect(Jds6600Waveform.fromScpi('SINE'), Jds6600Waveform.sine);
      expect(Jds6600Waveform.fromScpi('square'), Jds6600Waveform.square);
    });
  });

  group('model limits and validation', () {
    const lite = Jds6600DeviceInfo(modelMHz: 15, serialNumber: 1);
    const standard = Jds6600DeviceInfo(modelMHz: 60, serialNumber: 2);

    test('Lite limits', () {
      expect(lite.isLite, isTrue);
      expect(lite.maxFrequencyHz(Jds6600Waveform.sine), 15e6);
      expect(lite.maxFrequencyHz(Jds6600Waveform.square), 15e6);
      expect(lite.maxFrequencyHz(Jds6600Waveform.pulse), 6e6);
    });

    test('standard limits', () {
      expect(standard.isLite, isFalse);
      expect(standard.maxFrequencyHz(Jds6600Waveform.sine), 60e6);
      expect(standard.maxFrequencyHz(Jds6600Waveform.square), 15e6);
      expect(standard.maxFrequencyHz(Jds6600Waveform.noise), 6e6);
    });

    test('amplitude limit depends on frequency', () {
      expect(lite.maxAmplitudeVpp(1e6), 20);
      expect(lite.maxAmplitudeVpp(10e6), 10);
    });

    test('validation throws for out-of-range values', () {
      expect(
        () =>
            Jds6600Protocol.validateFrequency(lite, Jds6600Waveform.sine, 20e6),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () =>
            Jds6600Protocol.validateFrequency(lite, Jds6600Waveform.sine, 1e3),
        returnsNormally,
      );
      expect(
        () => Jds6600Protocol.validateAmplitude(lite, 1e3, 21),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Jds6600Protocol.validateOffset(-10),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Jds6600Protocol.validateDuty(101),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Jds6600Protocol.validatePhase(361),
        throwsA(isA<Jds6600RangeException>()),
      );
    });
  });

  test('synthesises an identity without firmware', () {
    const info = Jds6600DeviceInfo(modelMHz: 15, serialNumber: 12345);
    expect(Jds6600Protocol.identify(info), 'JOY-IT,JDS6600-LITE,12345,N/A');
  });
}
