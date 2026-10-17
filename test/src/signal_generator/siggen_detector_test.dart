import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/serial_port_info.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_detector.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';

import 'fake_jds6600_transport.dart';

void main() {
  late FakeJds6600Transport transport;
  late SignalGeneratorService service;
  late SignalGeneratorDetector detector;

  setUp(() {
    transport = FakeJds6600Transport();
    service = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    detector = SignalGeneratorDetector(
      service: service,
      listPorts: () async => const [SerialPortInfo(name: '/dev/ttyUSB0')],
      interval: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    detector.dispose();
    await service.shutdown();
  });

  test('detects the JDS6600 via the SCPI identity', () async {
    await detector.checkNow();
    detector.stop();

    expect(detector.isDetected, isTrue);
    expect(detector.port, '/dev/ttyUSB0');
    expect(detector.identity, contains('JDS6600'));
  });

  test('paused detector does not touch the port', () async {
    detector.setPaused(true);
    await detector.checkNow();

    expect(detector.isDetected, isFalse);
    expect(transport.sentCommands, isEmpty);

    detector.setPaused(false);
    await detector.checkNow();
    detector.stop();
    expect(detector.isDetected, isTrue);
  });

  test('reports not detected when the port cannot be opened', () async {
    transport.errorOnOpen = StateError('unplugged');

    await detector.checkNow();
    detector.stop();

    expect(detector.isDetected, isFalse);
  });
}
