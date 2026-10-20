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
    expect(find.text('START SWEEP'), findsOneWidget);
    expect(find.text('CH1'), findsWidgets);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bode panel returns to the configuration form on error', (
    tester,
  ) async {
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
