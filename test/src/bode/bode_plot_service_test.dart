import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_models.dart';
import 'package:sdsremote/src/bode/bode_plot_service.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';

import '../signal_generator/fake_jds6600_transport.dart';
import 'fake_bode_scope.dart';

void main() {
  late FakeJds6600Transport transport;
  late SignalGeneratorService generator;
  late FakeBodeScope scope;
  late BodePlotService service;

  setUp(() async {
    transport = FakeJds6600Transport();
    generator = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    scope = FakeBodeScope();
    service = BodePlotService(
      signalGenerator: generator,
      scope: scope,
      skipSettling: true,
    );
    await generator.connect('/dev/ttyUSB0');
  });

  tearDown(() async {
    service.dispose();
    await generator.shutdown();
  });

  test('runs the full sweep and leaves the generator safe', () async {
    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 1000,
        pointCount: 3,
        measurePhase: true,
      ),
    );

    expect(service.status, BodeStatus.completed);
    expect(service.points.length, 3);
    expect(service.points.first.frequencyHz, closeTo(100, 1e-6));
    expect(service.points.last.frequencyHz, closeTo(1000, 1e-6));
    expect(service.points.first.gainDb, closeTo(-6.0206, 1e-3));
    expect(service.points.first.phaseDeg, -45);
    expect(service.points.first.phaseSource, BodePhaseSource.mead);
    expect(scope.prepareCalls, 1);
    expect(scope.readCalls, 3);
    expect(scope.restoreCalls, 1);
    expect(transport.sentCommands, contains(':w20=1,0.'));
    expect(transport.sentCommands, contains(':w20=0,0.'));
    expect(transport.sentCommands, contains(':w32=0,0,0,0.'));
    expect(generator.outputs.ch1, isFalse);
    expect(generator.outputs.ch2, isFalse);
  });

  test('rejects an invalid configuration before touching the devices',
      () async {
    await service.start(
      const BodeConfig(
        startFrequencyHz: 1000,
        stopFrequencyHz: 100,
      ),
    );

    expect(service.status, BodeStatus.error);
    expect(service.errorMessage, contains('Stop frequency'));
    expect(scope.prepareCalls, 0);
    expect(scope.readCalls, 0);
  });

  test('retries an out-of-range point once after auto-set', () async {
    scope.outOfRangeOnce = true;

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );

    expect(scope.autoSetCalls, 1);
    expect(service.status, BodeStatus.completed);
    expect(service.points.length, 2);
    expect(service.points.every((point) => point.valid), isTrue);
  });

  test('retries a collapsed Vin reading', () async {
    scope.vinSequence.addAll([0.01, 1.0, 1.0, 1.0]);

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 3,
      ),
    );

    expect(scope.readCalls, 4);
    expect(service.points.every((point) => point.valid), isTrue);
    expect(service.points.first.gainDb, closeTo(-6.0206, 1e-3));
  });

  test('marks a persistently collapsed Vin point invalid', () async {
    scope.voutRms = 0.005;
    scope.vinSequence.addAll(List<double>.filled(6, 0.01));

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );

    expect(scope.readCalls, 6);
    expect(service.points.every((point) => !point.valid), isTrue);
    expect(service.points.first.note, contains('Unstable measurement'));
  });

  test('does not plot points below 5 mV on Vout', () async {
    scope.voutRms = 0.004;

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );

    expect(service.status, BodeStatus.completed);
    expect(service.points.length, 2);
    expect(service.points.every((point) => !point.valid), isTrue);
    expect(service.points.every((point) => point.gainDb == null), isTrue);
    expect(service.points.first.note, contains('Vout below 5 mV'));
  });

  test('does not plot points below 5 mV on Vin', () async {
    scope.vinRms = 0.004;

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );

    expect(service.points.every((point) => !point.valid), isTrue);
    expect(service.points.every((point) => point.gainDb == null), isTrue);
    expect(service.points.first.note, contains('Vin below 5 mV'));
  });

  test('keeps points at exactly 5 mV', () async {
    scope.voutRms = 0.005;

    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );

    expect(service.points.every((point) => point.valid), isTrue);
  });

  test('cancels a running sweep and turns the outputs off', () async {
    scope.readDelay = const Duration(milliseconds: 20);

    final future = service.start(
      const BodeConfig(
        startFrequencyHz: 10,
        stopFrequencyHz: 1000,
        pointCount: 50,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.stop();
    await future;

    expect(service.status, BodeStatus.cancelled);
    expect(generator.outputs.ch1, isFalse);
    expect(generator.outputs.ch2, isFalse);
    expect(transport.sentCommands, contains(':w20=0,0.'));
  });

  test('clears completed results', () async {
    await service.start(
      const BodeConfig(
        startFrequencyHz: 100,
        stopFrequencyHz: 200,
        pointCount: 2,
      ),
    );
    expect(service.points, isNotEmpty);

    service.clear();

    expect(service.points, isEmpty);
    expect(service.status, BodeStatus.idle);
    expect(service.completedPoints, 0);
  });
}
