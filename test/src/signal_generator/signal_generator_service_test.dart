import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';

import 'fake_jds6600_transport.dart';

void main() {
  late FakeJds6600Transport transport;
  late SignalGeneratorService service;

  setUp(() {
    transport = FakeJds6600Transport();
    service = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
  });

  tearDown(() async {
    await service.shutdown();
  });

  test('connect reads identity and state', () async {
    await service.connect('/dev/ttyUSB0');
    expect(service.isConnected, isTrue);
    expect(service.deviceInfo!.modelMHz, 15);
    expect(service.deviceInfo!.serialNumber, 12345);
    expect(service.ch1.frequencyHz, 1000);
    expect(service.ch2.amplitudeVpp, 1);
    expect(service.outputs.ch1, isFalse);
    expect(service.outputs.ch2, isFalse);
  });

  test('setFrequency writes the channel register and updates the cache',
      () async {
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();
    await service.setFrequency(1, 2000);
    expect(transport.sentCommands, contains(':w23=200000,0.'));
    expect(service.ch1.frequencyHz, 2000);
  });

  test('output writes preserve the other channel', () async {
    transport.registers[20] = [0, 1];
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();
    await service.setOutput(1, true);
    expect(transport.sentCommands, contains(':w20=1,1.'));
    expect(service.outputs.ch1, isTrue);
    expect(service.outputs.ch2, isTrue);
  });

  test('SCPI set and query', () async {
    await service.connect('/dev/ttyUSB0');
    await service.executeScpi('SOUR1:FREQ 1KHZ');
    expect(service.ch1.frequencyHz, 1000);

    transport.registers[23] = [250000, 0];
    expect(await service.executeScpi('SOUR1:FREQ?'), '2500.00');
  });

  test('unknown SCPI command queues an error', () async {
    await service.connect('/dev/ttyUSB0');
    expect(await service.executeScpi('BOGUS:CMD'), isNull);
    expect(await service.executeScpi('SYST:ERR?'), contains('-113'));
  });

  test('deferred sweep command is rejected explicitly', () async {
    await service.connect('/dev/ttyUSB0');
    expect(await service.executeScpi('SOUR1:SWE:STAT ON'), isNull);
    expect(await service.executeScpi('SYST:ERR?'), contains('-113'));
  });

  test('resetSafeState writes a safe state on both channels', () async {
    await service.connect('/dev/ttyUSB0');
    transport.sentCommands.clear();
    await service.resetSafeState();
    expect(transport.sentCommands, contains(':w20=0,0.'));
    expect(transport.sentCommands, contains(':w23=100000,0.'));
    expect(transport.sentCommands, contains(':w25=1000.'));
    expect(transport.sentCommands, contains(':w27=1000.'));
    expect(transport.sentCommands, contains(':w29=500.'));
    expect(service.outputs.ch1, isFalse);
    expect(service.outputs.ch2, isFalse);
  });

  test('range validation rejects 20 MHz on a Lite', () async {
    await service.connect('/dev/ttyUSB0');
    await expectLater(
      service.setFrequency(1, 20e6),
      throwsA(isA<Jds6600RangeException>()),
    );
  });

  test('testConnection reports the device identity', () async {
    final result = await service.testConnection('/dev/ttyUSB0');
    expect(result, startsWith('SUCCESS'));
    expect(result, contains('JDS6600-LITE'));
  });
}
