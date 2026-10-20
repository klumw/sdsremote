import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/fy6900_protocol.dart';
import 'package:sdsremote/src/signal_generator/models.dart';

void main() {
  group('framing', () {
    test('builds main and auxiliary channel commands', () {
      expect(Fy6900Protocol.readCommand(1, Fy6900Parameter.waveform), 'RMW\n');
      expect(Fy6900Protocol.readCommand(2, Fy6900Parameter.frequency), 'RFF\n');
      expect(
        Fy6900Protocol.writeCommand(
          1,
          Fy6900Parameter.frequency,
          '00001000.000000',
        ),
        'WMF00001000.000000\n',
      );
      expect(
        Fy6900Protocol.writeCommand(2, Fy6900Parameter.output, '1'),
        'WFN1\n',
      );
      expect(Fy6900Protocol.readModelCommand, 'UMO\n');
      expect(Fy6900Protocol.readIdCommand, 'UID\n');
    });

    test('accepts the bare-LF acknowledgement', () {
      expect(Fy6900Protocol.isAck(''), isTrue);
      expect(Fy6900Protocol.isAck('ok'), isTrue);
      expect(Fy6900Protocol.isAck('OK'), isTrue);
      expect(Fy6900Protocol.isAck('00'), isFalse);
    });

    test('rejects invalid channels', () {
      expect(
        () => Fy6900Protocol.readCommand(3, Fy6900Parameter.waveform),
        throwsA(isA<Jds6600RangeException>()),
      );
    });
  });

  group('conversions', () {
    test('frequency uses decimal Hz padded to 15 characters', () {
      expect(Fy6900Protocol.encodeFrequency(1000), '00001000.000000');
      expect(Fy6900Protocol.encodeFrequency(10000), '00010000.000000');
      expect(Fy6900Protocol.encodeFrequency(0.01), '00000000.010000');
      expect(Fy6900Protocol.encodeFrequencyMicroHz(1000), '00001000000000');
      expect(Fy6900Protocol.decodeFrequency('00010000.000000'), 10000);
      expect(Fy6900Protocol.decodeFrequency('12345.678900'), 12345.6789);
    });

    test('frequency tolerance covers the firmware rounding', () {
      expect(Fy6900Protocol.frequencyToleranceHz(174.668135), 0.1);
      expect(Fy6900Protocol.frequencyToleranceHz(20e3), 0.2);
      expect(Fy6900Protocol.frequencyToleranceHz(60e6), 600);
    });

    test('amplitude is volts on write and 0.1 mV on read', () {
      expect(Fy6900Protocol.encodeAmplitude(12.34), '12.340');
      expect(Fy6900Protocol.decodeAmplitude('123400'), 12.34);
      expect(Fy6900Protocol.decodeAmplitude('5000'), 0.5);
    });

    test('offset uses signed 32-bit millivolts on read', () {
      expect(Fy6900Protocol.encodeOffset(-2.5), '-2.500');
      expect(Fy6900Protocol.decodeOffset('12340'), 12.34);
      expect(Fy6900Protocol.decodeOffset('4294962296'), -5);
    });

    test('duty and phase use 0.001 units on read', () {
      expect(Fy6900Protocol.encodeDuty(50), '50.0');
      expect(Fy6900Protocol.decodeDuty('50000'), 50);
      expect(Fy6900Protocol.decodeDuty('68900'), 68.9);
      expect(Fy6900Protocol.encodePhase(380.3), '20.30');
      expect(Fy6900Protocol.decodePhase('189300'), 189.3);
    });

    test('output readback is 0 or 255', () {
      expect(Fy6900Protocol.encodeOutput(true), '1');
      expect(Fy6900Protocol.encodeOutput(false), '0');
      expect(Fy6900Protocol.decodeOutput('255'), isTrue);
      expect(Fy6900Protocol.decodeOutput('0'), isFalse);
    });
  });

  group('device identity', () {
    test('parses the model suffix and ID', () {
      final info = Fy6900Protocol.parseDeviceInfo(
        model: 'FY6900-60M',
        id: '1234567890123',
      );
      expect(info.family, SiggenFamily.fy6900);
      expect(info.modelMHz, 60);
      expect(info.serialNumber, 1234567890123);
      expect(info.modelName, 'FY6900-60M');
      expect(info.scpiIdentity, 'FeelElec,FY6900-60M,1234567890123,N/A');
    });

    test('accepts the shortened model without an M suffix', () {
      final info = Fy6900Protocol.parseDeviceInfo(
        model: 'FY6900-30M',
        id: '42',
      );
      expect(info.modelMHz, 30);
      expect(info.modelName, 'FY6900-30M');

      final shortened = Fy6900Protocol.parseDeviceInfo(
        model: 'FY6900-60',
        id: '42',
      );
      expect(shortened.modelMHz, 60);
      expect(shortened.modelName, 'FY6900-60');
    });

    test('falls back to the conservative 20 MHz class', () {
      final info = Fy6900Protocol.parseDeviceInfo(model: 'FY6900', id: '42');
      expect(info.modelMHz, 20);
      expect(info.modelName, 'FY6900');
    });
  });

  group('waveform mapping', () {
    test('main and auxiliary channels use different indices', () {
      expect(Fy6900Protocol.waveformIndex(1, Jds6600Waveform.sine), 0);
      // Rectangle (2) is the duty-adjustable square on the FY6900.
      expect(Fy6900Protocol.waveformIndex(1, Jds6600Waveform.square), 2);
      expect(Fy6900Protocol.waveformIndex(2, Jds6600Waveform.square), 2);
      expect(Fy6900Protocol.waveformIndex(1, Jds6600Waveform.pulse), 5);
      expect(Fy6900Protocol.waveformIndex(1, Jds6600Waveform.dc), 6);
      expect(Fy6900Protocol.waveformIndex(1, Jds6600Waveform.triangle), 7);
      expect(Fy6900Protocol.waveformIndex(2, Jds6600Waveform.dc), 5);
      expect(Fy6900Protocol.waveformIndex(2, Jds6600Waveform.triangle), 6);
      // CH2 has no adjustable pulse; a duty-adjustable rectangle is closest.
      expect(Fy6900Protocol.waveformIndex(2, Jds6600Waveform.pulse), 2);
    });

    test('decodes device indices back to shared waveforms', () {
      expect(Fy6900Protocol.decodeWaveform(1, 1), Jds6600Waveform.square);
      expect(Fy6900Protocol.decodeWaveform(1, 2), Jds6600Waveform.square);
      expect(Fy6900Protocol.decodeWaveform(2, 2), Jds6600Waveform.square);
      expect(Fy6900Protocol.decodeWaveform(1, 6), Jds6600Waveform.dc);
      expect(Fy6900Protocol.decodeWaveform(2, 6), Jds6600Waveform.triangle);
      expect(Fy6900Protocol.decodeWaveform(1, 37), Jds6600Waveform.arbitrary);
      expect(Fy6900Protocol.decodeWaveform(2, 36), Jds6600Waveform.arbitrary);
    });

    test('arbitrary waveform selection is rejected', () {
      expect(
        () => Fy6900Protocol.waveformIndex(1, Jds6600Waveform.arbitrary),
        throwsA(isA<Jds6600RangeException>()),
      );
    });
  });

  group('validation', () {
    const info = Jds6600DeviceInfo(
      modelMHz: 60,
      serialNumber: 1,
      family: SiggenFamily.fy6900,
      modelNameOverride: 'FY6900-60M',
    );

    test('frequency limits depend on the waveform', () {
      expect(
        () =>
            Fy6900Protocol.validateFrequency(info, Jds6600Waveform.sine, 60e6),
        returnsNormally,
      );
      expect(
        () => Fy6900Protocol.validateFrequency(
          info,
          Jds6600Waveform.sine,
          60.1e6,
        ),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Fy6900Protocol.validateFrequency(
          info,
          Jds6600Waveform.square,
          25e6,
        ),
        returnsNormally,
      );
      expect(
        () => Fy6900Protocol.validateFrequency(
          info,
          Jds6600Waveform.square,
          25.1e6,
        ),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Fy6900Protocol.validateFrequency(
          info,
          Jds6600Waveform.triangle,
          10.1e6,
        ),
        throwsA(isA<Jds6600RangeException>()),
      );
    });

    test('amplitude limits follow the frequency bands', () {
      expect(
        () => Fy6900Protocol.validateAmplitude(info, 1e6, 24),
        returnsNormally,
      );
      expect(
        () => Fy6900Protocol.validateAmplitude(info, 1e6, 24.1),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Fy6900Protocol.validateAmplitude(info, 15e6, 10),
        returnsNormally,
      );
      expect(
        () => Fy6900Protocol.validateAmplitude(info, 15e6, 10.1),
        throwsA(isA<Jds6600RangeException>()),
      );
    });

    test('offset, duty and phase ranges', () {
      expect(() => Fy6900Protocol.validateOffset(-12), returnsNormally);
      expect(() => Fy6900Protocol.validateOffset(12), returnsNormally);
      expect(
        () => Fy6900Protocol.validateOffset(12.1),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(() => Fy6900Protocol.validateDuty(0.1), returnsNormally);
      expect(() => Fy6900Protocol.validateDuty(99.9), returnsNormally);
      expect(
        () => Fy6900Protocol.validateDuty(0),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(
        () => Fy6900Protocol.validateDuty(100),
        throwsA(isA<Jds6600RangeException>()),
      );
      expect(() => Fy6900Protocol.validatePhase(360), returnsNormally);
      expect(
        () => Fy6900Protocol.validatePhase(360.1),
        throwsA(isA<Jds6600RangeException>()),
      );
    });
  });
}
