import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_host.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_protocol.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';
import 'package:test/test.dart';

import 'fake_jds6600_transport.dart';

class _RecordingSink implements SigGenWindowEventSink {
  final List<SigGenWindowState> states = <SigGenWindowState>[];

  @override
  Future<void> pushState(SigGenWindowState state) async {
    states.add(state);
  }
}

void main() {
  late FakeJds6600Transport transport;
  late SignalGeneratorService service;
  late _RecordingSink sink;
  late SigGenWindowHost host;
  var mutable = true;

  setUp(() async {
    mutable = true;
    transport = FakeJds6600Transport(deviceType: 15, serialNumber: 4242);
    service = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    await service.connect('/dev/fake');
    await service.refreshDeviceInfo();
    await service.refreshAll();
    sink = _RecordingSink();
    host = SigGenWindowHost(
      service: service,
      sink: sink,
      canMutate: () => mutable,
    );
    host.activate();
  });

  tearDown(() async {
    host.dispose();
    await service.shutdown();
  });

  test('builds a complete snapshot', () {
    final state = host.buildSnapshot();

    expect(state.generator.configured, isTrue);
    expect(state.generator.connected, isTrue);
    expect(state.generator.mutable, isTrue);
    expect(state.generator.modelName, equals('JDS6600-LITE'));
    expect(state.generator.modelMHz, equals(15));
    expect(state.generator.port, equals('/dev/fake'));
    expect(state.generator.ch1.waveform, equals(Jds6600Waveform.sine));
    expect(state.generator.ch1.frequencyHz, equals(1000));
  });

  test('snapshot JSON round-trips', () {
    final state = host.buildSnapshot();
    final decoded = SigGenWindowState.fromJson(state.toJson());

    expect(decoded.generator.connected, isTrue);
    expect(decoded.generator.ch1.frequencyHz, equals(1000));
    expect(decoded.generator.ch2.waveform, equals(Jds6600Waveform.sine));
    expect(decoded.generator.lastRefresh, isNotNull);
  });

  test('dispatches setFrequency to CH1 only', () async {
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 1,
      'value': 5000.0,
    });

    expect(result.ok, isTrue);
    expect(result.state.generator.ch1.frequencyHz, equals(5000));
    expect(result.state.generator.ch2.frequencyHz, equals(1000));
    expect(transport.registers[23], equals([500000, 0]));
    expect(transport.registers[24], equals([100000, 0]));
  });

  test('dispatches setFrequency to CH2 only', () async {
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 2,
      'value': 250.0,
    });

    expect(result.ok, isTrue);
    expect(transport.registers[24], equals([25000, 0]));
    expect(transport.registers[23], equals([100000, 0]));
  });

  test('dispatches waveform, amplitude, offset and duty', () async {
    expect(
      (await host.handleCommand(SigGenWindowMethods.setWaveform, {
        'channel': 1,
        'waveform': 'square',
      })).ok,
      isTrue,
    );
    expect(transport.registers[21], equals([1]));

    expect(
      (await host.handleCommand(SigGenWindowMethods.setAmplitude, {
        'channel': 1,
        'value': 3.3,
      })).ok,
      isTrue,
    );
    expect(transport.registers[25], equals([3300]));

    expect(
      (await host.handleCommand(SigGenWindowMethods.setOffset, {
        'channel': 1,
        'value': -1.5,
      })).ok,
      isTrue,
    );
    expect(transport.registers[27], equals([850]));

    expect(
      (await host.handleCommand(SigGenWindowMethods.setDuty, {
        'channel': 1,
        'value': 25.0,
      })).ok,
      isTrue,
    );
    expect(transport.registers[29], equals([250]));
  });

  test('dispatches global phase', () async {
    final result = await host.handleCommand(SigGenWindowMethods.setPhase, {
      'value': 90.0,
    });

    expect(result.ok, isTrue);
    expect(transport.registers[31], equals([900]));
    expect(result.state.generator.phaseDeg, equals(90));
  });

  test('setOutput preserves the other channel', () async {
    await service.setOutput(2, true);

    final result = await host.handleCommand(SigGenWindowMethods.setOutput, {
      'channel': 1,
      'enabled': true,
    });

    expect(result.ok, isTrue);
    expect(transport.registers[20], equals([1, 1]));
    expect(result.state.generator.ch1Output, isTrue);
    expect(result.state.generator.ch2Output, isTrue);
  });

  test('returns range errors without writing beyond validation', () async {
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 1,
      'value': 1e9,
    });

    expect(result.ok, isFalse);
    expect(result.errorType, equals('range'));
    expect(result.error, contains('Frequency'));
    expect(
      transport.sentCommands.where((command) => command.startsWith(':w23')),
      isEmpty,
    );
  });

  test('rejects mutations while a Bode sweep is running', () async {
    mutable = false;
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 1,
      'value': 5000.0,
    });

    expect(result.ok, isFalse);
    expect(result.errorType, equals('busy'));
    expect(result.state.generator.mutable, isFalse);
    expect(
      transport.sentCommands.where((command) => command.startsWith(':w23')),
      isEmpty,
    );
  });

  test('rejects mutations when disconnected', () async {
    await service.disconnect();
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 1,
      'value': 5000.0,
    });

    expect(result.ok, isFalse);
    expect(result.errorType, equals('disconnected'));
  });

  test('rejects an invalid channel', () async {
    final result = await host.handleCommand(SigGenWindowMethods.setFrequency, {
      'channel': 7,
      'value': 5000.0,
    });

    expect(result.ok, isFalse);
    expect(result.errorType, equals('error'));
  });

  test('pushes snapshots when active', () async {
    await service.setFrequency(1, 2500);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(sink.states, isNotEmpty);
    expect(sink.states.last.generator.ch1.frequencyHz, equals(2500));
  });

  test('does not push after deactivate', () async {
    host.deactivate();
    await service.setFrequency(1, 2500);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(sink.states, isEmpty);
  });

  test('unknown command yields a protocol error', () async {
    final result = await host.handleCommand('doesNotExist', const {});

    expect(result.ok, isFalse);
    expect(result.errorType, equals('protocol'));
  });
}
