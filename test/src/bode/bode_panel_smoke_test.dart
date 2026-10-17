import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_service.dart';
import 'package:sdsremote/src/widgets/bode_plot_panel.dart';

import '../signal_generator/fake_jds6600_transport.dart';

void main() {
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
    expect(tester.takeException(), isNull);
  });
}
