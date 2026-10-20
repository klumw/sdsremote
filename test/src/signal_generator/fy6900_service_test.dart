import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/fy6900_driver.dart';
import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/serial_port_info.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_detector.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';

import 'fake_fy6900_transport.dart';

void main() {
  late FakeFy6900Transport transport;
  late SignalGeneratorService service;

  setUp(() {
    transport = FakeFy6900Transport();
    service = SignalGeneratorService(
      driverFactory: (_) => Fy6900Driver(transport),
      pollInterval: Duration.zero,
    );
  });

  tearDown(() async {
    await service.shutdown();
  });

  test('connect reads identity and state', () async {
    await service.connect('/dev/ttyUSB0');

    expect(service.isConnected, isTrue);
    expect(service.deviceInfo!.family, SiggenFamily.fy6900);
    expect(service.deviceInfo!.modelName, 'FY6900-60M');
    expect(service.deviceInfo!.modelMHz, 60);
    expect(service.ch1.frequencyHz, 1000);
    expect(service.ch2.amplitudeVpp, 1);
    expect(service.outputs.ch1, isFalse);
    expect(service.outputs.ch2, isFalse);
  });

  test('offers the same SCPI command syntax as the JDS6600', () async {
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();

    await service.executeScpi('SOUR1:FREQ 1KHZ');
    expect(transport.sentCommands, contains('WMF00001000.000000'));

    transport.channel(1).frequencyHz = 2500;
    expect(await service.executeScpi('SOUR1:FREQ?'), '2500.00');

    await service.executeScpi('SOUR1:FUNC SQUARE');
    // Rectangle (2) is the duty-adjustable square on the FY6900.
    expect(transport.channel(1).waveform, 2);
    expect(await service.executeScpi('SOUR1:FUNC?'), 'SQU');

    await service.executeScpi('SOUR1:VOLT 2');
    expect(transport.channel(1).amplitudeVpp, 2);
    expect(await service.executeScpi('SOUR1:VOLT?'), '2.000');

    await service.executeScpi('SOUR1:VOLT:OFFS -1');
    expect(transport.channel(1).offsetV, -1);
    expect(await service.executeScpi('SOUR1:VOLT:OFFS?'), '-1.00');

    await service.executeScpi('SOUR1:PULS:DCYC 25');
    expect(transport.channel(1).dutyPercent, 25);
    expect(transport.sentCommands, contains('WMD25.0'));
    expect(await service.executeScpi('SOUR1:FUNC:SQU:DCYC?'), '25.0');

    await service.executeScpi('SOUR2:PULS:DCYC 12.5');
    expect(transport.channel(2).dutyPercent, 12.5);
    expect(transport.sentCommands, contains('WFD12.5'));

    await service.executeScpi('SOUR2:PHAS 90');
    expect(transport.channel(2).phaseDeg, 90);
    expect(await service.executeScpi('SOUR2:PHAS?'), '90.0');
    // CH1 must not be touched by a CH2 phase command.
    expect(await service.executeScpi('SOUR1:PHAS?'), '0.0');

    await service.executeScpi('SOUR1:PHAS 45');
    expect(transport.channel(1).phaseDeg, 45);
    expect(await service.executeScpi('SOUR1:PHAS?'), '45.0');
    expect(await service.executeScpi('SOUR2:PHAS?'), '90.0');
    expect(transport.sentCommands, contains('WMP45.00'));
    expect(transport.sentCommands, contains('WFP90.00'));

    await service.executeScpi('OUTP1:STAT ON');
    expect(transport.channel(1).output, isTrue);
    expect(await service.executeScpi('OUTP1:STAT?'), '1');

    expect(
      await service.executeScpi('*IDN?'),
      'FeelElec,FY6900-60M,1234567890123,N/A',
    );
    expect(await service.executeScpi('SYST:ERR?'), '0,"No error"');

    // Unsupported subsystems produce exactly the same SCPI error as on the
    // JDS6600 backend.
    expect(await service.executeScpi('SOUR1:SWE:STAT ON'), isNull);
    expect(await service.executeScpi('SYST:ERR?'), contains('-113'));
  });

  test('writes and verifies the frequency readback', () async {
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();

    await service.setFrequency(1, 5000);

    expect(transport.channel(1).frequencyHz, 5000);
    expect(service.ch1.frequencyHz, 5000);
    expect(transport.sentCommands, contains('WMF00005000.000000'));
  });

  test('accepts the FY6900 frequency readback rounding', () async {
    // Hardware observation: 174.668135 Hz requested, 174.602599 Hz read back.
    transport.frequencyReadbackErrorHz = -0.065536;
    await service.connect('/dev/ttyUSB0');

    await service.setFrequency(1, 174.668135);

    expect(transport.channel(1).frequencyHz, closeTo(174.668135, 1e-9));
    expect(service.ch1.frequencyHz, 174.668135);
  });

  test('rejects a zero frequency readback', () async {
    transport.forceZeroFrequencyReadback = true;
    await service.connect('/dev/ttyUSB0');

    await expectLater(
      service.setFrequency(1, 1000),
      throwsA(isA<Jds6600ProtocolException>()),
    );
  });

  test('falls back to the legacy microhertz format', () async {
    transport.acceptDecimalFrequency = false;
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();

    await service.setFrequency(1, 2000);

    expect(transport.sentCommands, contains('WMF00002000.000000'));
    expect(transport.sentCommands, contains('WMF00002000000000'));
    expect(transport.channel(1).frequencyHz, 2000);
    expect(service.ch1.frequencyHz, 2000);
  });

  test('range validation uses the FY6900 limits', () async {
    await service.connect('/dev/ttyUSB0');

    await expectLater(
      service.setFrequency(1, 70e6),
      throwsA(isA<Jds6600RangeException>()),
    );
    await expectLater(
      service.setAmplitude(1, 25),
      throwsA(isA<Jds6600RangeException>()),
    );

    await service.setAmplitude(1, 24);
    expect(transport.channel(1).amplitudeVpp, 24);
  });

  test('outputs are switched per channel', () async {
    await service.connect('/dev/ttyUSB0');

    await service.setOutput(1, true);

    expect(transport.channel(1).output, isTrue);
    expect(transport.channel(2).output, isFalse);
    expect(service.outputs.ch1, isTrue);
    expect(service.outputs.ch2, isFalse);
    expect(await service.readOutput(2), isFalse);
  });

  test('resetSafeState writes a safe state on both channels', () async {
    await service.connect('/dev/ttyUSB0');
    for (final channel in const [1, 2]) {
      transport.channel(channel).output = true;
      transport.channel(channel).waveform = 27;
      transport.channel(channel).frequencyHz = 12e6;
      transport.channel(channel).amplitudeVpp = 10;
      transport.channel(channel).offsetV = 5;
      transport.channel(channel).dutyPercent = 75;
      transport.channel(channel).phaseDeg = 45;
    }

    await service.resetSafeState();

    for (final channel in const [1, 2]) {
      final state = transport.channel(channel);
      expect(state.output, isFalse);
      expect(state.waveform, 0);
      expect(state.frequencyHz, 1000);
      expect(state.amplitudeVpp, 1);
      expect(state.offsetV, 0);
      expect(state.dutyPercent, 50);
      expect(state.phaseDeg, 0);
    }
    expect(service.outputs.ch1, isFalse);
    expect(service.outputs.ch2, isFalse);
    expect(service.ch1.frequencyHz, 1000);
  });

  test('detects an FY6900 via the identity token', () async {
    final detector = SignalGeneratorDetector(
      service: service,
      listPorts: () async => const [SerialPortInfo(name: '/dev/ttyUSB0')],
      interval: const Duration(hours: 1),
      identityToken: 'FY6900',
    );

    await detector.checkNow();
    detector.stop();

    expect(detector.isDetected, isTrue);
    expect(detector.port, '/dev/ttyUSB0');
    expect(detector.identity, contains('FY6900'));
    detector.dispose();
  });

  test('duty switches a fixed square to the adjustable rectangle', () async {
    await service.connect('/dev/ttyUSB0');
    for (final channel in const [1, 2]) {
      transport.channel(channel).waveform = 1; // fixed 50 % square
    }
    transport.sentCommands.clear();

    await service.setDuty(1, 25);
    await service.setDuty(2, 35);

    expect(transport.sentCommands, contains('WMW2'));
    expect(transport.sentCommands, contains('WMD25.0'));
    expect(transport.sentCommands, contains('WFW2'));
    expect(transport.sentCommands, contains('WFD35.0'));
    expect(transport.channel(1).waveform, 2);
    expect(transport.channel(2).waveform, 2);
    expect(transport.channel(1).dutyPercent, 25);
    expect(transport.channel(2).dutyPercent, 35);
  });

  test('all settings use the requested FY6900 channel prefix', () async {
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();

    await service.setWaveform(1, Jds6600Waveform.sine);
    await service.setFrequency(1, 1000);
    await service.setAmplitude(1, 1);
    await service.setOffset(1, 0);
    await service.setDuty(1, 50);
    await service.setPhase(1, 10);
    await service.setOutput(1, true);

    expect(transport.sentCommands, contains('WMW0'));
    expect(transport.sentCommands, contains('WMF00001000.000000'));
    expect(transport.sentCommands, contains('WMA1.000'));
    expect(transport.sentCommands, contains('WMO0.000'));
    expect(transport.sentCommands, contains('WMD50.0'));
    expect(transport.sentCommands, contains('WMP10.00'));
    expect(transport.sentCommands, contains('WMN1'));

    transport.sentCommands.clear();
    await service.setWaveform(2, Jds6600Waveform.sine);
    await service.setFrequency(2, 2000);
    await service.setAmplitude(2, 2);
    await service.setOffset(2, -1);
    await service.setDuty(2, 25);
    await service.setPhase(2, 20);
    await service.setOutput(2, true);

    expect(transport.sentCommands, contains('WFW0'));
    expect(transport.sentCommands, contains('WFF00002000.000000'));
    expect(transport.sentCommands, contains('WFA2.000'));
    expect(transport.sentCommands, contains('WFO-1.000'));
    expect(transport.sentCommands, contains('WFD25.0'));
    expect(transport.sentCommands, contains('WFP20.00'));
    expect(transport.sentCommands, contains('WFN1'));
  });
}
