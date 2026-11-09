import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_models.dart';
import 'package:sdsremote/src/signal_generator/fy6900_driver.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';
import 'package:sdsremote/src/widgets/bode_plot_panel.dart';

import '../signal_generator/fake_fy6900_transport.dart';
import '../signal_generator/fake_jds6600_transport.dart';

void main() {
  testWidgets('shows the identified FY6900 model limits', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeFy6900Transport(model: 'FY6900-60M');
    final generator = SignalGeneratorService(
      driverFactory: (_) => Fy6900Driver(transport),
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bode-model-limits')), findsOneWidget);
    expect(find.textContaining('FY6900-60M'), findsOneWidget);
    expect(find.textContaining('Sine up to 60 MHz'), findsOneWidget);
    expect(find.textContaining('±12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bode panel renders the configuration form', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeJds6600Transport();
    final generator = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bode Plot Configuration'), findsOneWidget);
    expect(find.text('Report Name (optional)'), findsOneWidget);
    expect(find.text('Generator output'), findsOneWidget);
    expect(find.byKey(const Key('bode-sweep-purpose')), findsOneWidget);
    expect(find.text('START SWEEP'), findsOneWidget);
    expect(find.text('CH1'), findsWidgets);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generator output selection updates the waveform set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeFy6900Transport(model: 'FY6900-60M');
    final generator = SignalGeneratorService(
      driverFactory: (_) => Fy6900Driver(transport),
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Adj-Pulse on CH1; the FY6900 protocol has no pulse shape for
    // the auxiliary output, so switching to CH2 must fall back to Sine.
    await tester.tap(find.byKey(const ValueKey('bode-waveform-1-sine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adj-Pulse').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bode-waveform-1-pulse')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bode-generator-channel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CH2').last);
    await tester.pumpAndSettle();

    final channelField = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const ValueKey('bode-generator-channel')),
    );
    expect(channelField.initialValue, 2);
    expect(find.byKey(const ValueKey('bode-waveform-2-sine')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bode panel returns to the configuration form on error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeJds6600Transport();
    final generator = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);
    final plotKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
            plotKey: plotKey,
            savedConfig: const BodeConfig(),
            savedStatus: BodeStatus.error,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(plotKey), findsNothing);
    expect(find.text('Bode Plot Configuration'), findsOneWidget);
    expect(find.text('START SWEEP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches between frequency and amplitude sweep', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeJds6600Transport();
    final generator = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bode-mode')), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Amplitude (Vpp)'), findsOneWidget);
    expect(find.byKey(const Key('bode-sweep-purpose')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bode-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amplitude Sweep').last);
    await tester.pumpAndSettle();

    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Amplitude Start (Vpp)'), findsOneWidget);
    expect(find.text('Amplitude Stop (Vpp)'), findsOneWidget);
    expect(find.text('Scope input'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bode-spacing-amplitude')),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNothing);
    expect(
      find.byKey(const Key('bode-amplitude-sweep-purpose')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bode-sweep-purpose')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the completed amplitude-sweep charts', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final generator = SignalGeneratorService(
      transportFactory: (_) => FakeJds6600Transport(),
      pollInterval: Duration.zero,
    );
    addTearDown(generator.shutdown);
    final plotKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
            plotKey: plotKey,
            savedConfig: const BodeConfig(
              mode: BodeMode.amplitudeSweep,
              sweepFrequencyHz: 1000,
              startAmplitudeVpp: 0.5,
              stopAmplitudeVpp: 2.5,
              pointCount: 3,
              amplitudeSpacing: BodeSpacing.linear,
            ),
            savedPoints: const [
              BodePoint(
                frequencyHz: 1000,
                amplitudeVpp: 0.5,
                vinRms: 0.18,
                voutRms: 0.15,
                vinVpp: 0.5,
                voutVpp: 0.45,
                gainDb: -1.4,
              ),
              BodePoint(
                frequencyHz: 1000,
                amplitudeVpp: 1.5,
                vinRms: 0.54,
                voutRms: 0.46,
                vinVpp: 1.5,
                voutVpp: 1.34,
                gainDb: -1.4,
              ),
              BodePoint(
                frequencyHz: 1000,
                amplitudeVpp: 2.5,
                vinRms: 0.9,
                voutRms: 0.76,
                vinVpp: 2.5,
                voutVpp: 2.18,
                gainDb: -1.4,
              ),
            ],
            savedStatus: BodeStatus.completed,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(plotKey), findsOneWidget);
    expect(find.text('Bode Plot — Amplitude Sweep — Complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bode panel dismisses the error message', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = FakeJds6600Transport();
    final generator = SignalGeneratorService(
      transportFactory: (_) => transport,
      pollInterval: Duration.zero,
    );
    await generator.connect('/dev/ttyUSB0');
    addTearDown(generator.shutdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BodePlotPanel(
            getInstrument: () async => null,
            signalGenerator: generator,
            isOnline: true,
            generatorDetected: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Fails in the scope handshake, which the panel shows as an error.
    await tester.tap(find.text('START SWEEP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Oscilloscope is not available'),
      findsOneWidget,
    );
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.textContaining('Oscilloscope is not available'), findsNothing);
    expect(find.byTooltip('Dismiss'), findsNothing);
    expect(find.text('Bode Plot Configuration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
