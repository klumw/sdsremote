import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_controller.dart';
import 'package:sdsremote/src/widgets/signal_generator_panel.dart';

import 'fake_siggen_window_client.dart';

Future<SignalGeneratorPanelController> _pumpPanel(
  WidgetTester tester, {
  FakeSigGenWindowClient? client,
}) async {
  final fake = client ?? FakeSigGenWindowClient();
  final controller = SignalGeneratorPanelController(client: fake);
  await controller.init();
  await tester.pumpWidget(
    MaterialApp(home: SignalGeneratorPanel(controller: controller)),
  );
  await tester.pumpAndSettle();
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  testWidgets('fits the minimum window size without overflow', (tester) async {
    tester.view.physicalSize = const Size(760, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPanel(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('pending hint and success message share the bottom bar', (
    tester,
  ) async {
    final controller = await _pumpPanel(tester);

    expect(find.text('Press apply changes when finished'), findsNothing);

    controller.updateFrequencyText('2');
    await tester.pumpAndSettle();

    final hint = find.text('Press apply changes when finished');
    expect(hint, findsOneWidget);
    final pendingBottom = tester.getBottomLeft(hint).dy;
    expect(pendingBottom, greaterThan(560));

    await tester.ensureVisible(find.text('APPLY CHANGES'));
    await tester.tap(find.text('APPLY CHANGES'));
    await tester.pumpAndSettle();

    expect(find.text('Press apply changes when finished'), findsNothing);
    final success = find.text('Settings applied');
    expect(success, findsOneWidget);
    expect(tester.getBottomLeft(success).dy, equals(pendingBottom));
  });

  testWidgets('shows the two channel entries and CH1 fields', (tester) async {
    await _pumpPanel(tester);

    expect(find.text('CH1'), findsNWidgets(2));
    expect(find.text('CH2'), findsOneWidget);
    expect(find.text('Frequency Counter'), findsNothing);
    expect(find.text('Waveform'), findsOneWidget);
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Amplitude'), findsOneWidget);
    expect(find.text('DC Offset'), findsOneWidget);
    expect(find.text('Duty Cycle'), findsOneWidget);
    expect(find.text('Phase (CH2 vs CH1)'), findsOneWidget);
    expect(find.text('APPLY CHANGES'), findsOneWidget);
    expect(find.text('USE DEVICE VALUES'), findsNothing);
  });

  testWidgets('CH2 also exposes duty and phase', (tester) async {
    final controller = await _pumpPanel(tester);

    controller.selectDevice(SigGenDeviceSelection.ch2);
    await tester.pumpAndSettle();

    expect(find.text('Duty Cycle'), findsOneWidget);
    expect(find.text('Phase (CH2 vs CH1)'), findsOneWidget);
  });

  testWidgets('duty and phase are always visible on one row', (tester) async {
    final controller = await _pumpPanel(tester);

    expect(find.text('Duty Cycle'), findsOneWidget);
    expect(find.text('Phase (CH2 vs CH1)'), findsOneWidget);
    final dutyY = tester.getTopLeft(find.text('Duty Cycle')).dy;
    final phaseY = tester.getTopLeft(find.text('Phase (CH2 vs CH1)')).dy;
    expect((dutyY - phaseY).abs(), lessThan(1));

    controller.updateWaveform(Jds6600Waveform.square);
    await tester.pumpAndSettle();
    expect(find.text('Duty Cycle'), findsOneWidget);
    expect(find.text('Phase (CH2 vs CH1)'), findsOneWidget);
  });

  testWidgets('invalid input shows an error and disables apply', (
    tester,
  ) async {
    final controller = await _pumpPanel(tester);

    controller.updateFrequencyUnit('MHz');
    controller.updateFrequencyText('20');
    await tester.pumpAndSettle();

    expect(find.textContaining('outside'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'APPLY CHANGES'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('apply sends changed values to the client', (tester) async {
    final client = FakeSigGenWindowClient();
    final controller = await _pumpPanel(tester, client: client);
    client.calls.clear();

    controller.updateFrequencyText('2');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('APPLY CHANGES'));
    await tester.tap(find.text('APPLY CHANGES'));
    await tester.pumpAndSettle();

    expect(client.calls, contains('setFrequency:1:2000.0'));
    expect(find.text('Settings applied'), findsOneWidget);
  });

  testWidgets('output switch is separate from apply', (tester) async {
    final client = FakeSigGenWindowClient();
    final controller = await _pumpPanel(tester, client: client);
    client.calls.clear();

    final outputSwitch = find.byType(Switch);
    expect(outputSwitch, findsOneWidget);
    final offLabel = find.byKey(const Key('output-off-label'));
    final onLabel = find.byKey(const Key('output-on-label'));
    expect(offLabel, findsOneWidget);
    expect(onLabel, findsOneWidget);
    expect(
      tester.getCenter(offLabel).dx,
      lessThan(tester.getCenter(outputSwitch).dx),
    );
    expect(
      tester.getCenter(outputSwitch).dx,
      lessThan(tester.getCenter(onLabel).dx),
    );

    await tester.tap(outputSwitch);
    await tester.pumpAndSettle();

    expect(client.calls, equals(['setOutput:1:true']));
    expect(controller.generator.ch1Output, isTrue);
  });

  testWidgets('spinners adjust frequency, amplitude, offset, duty and phase', (
    tester,
  ) async {
    final controller = await _pumpPanel(tester);

    expect(controller.draft.frequencyText, '1');
    await tester.tap(find.byTooltip('Increase Frequency'));
    await tester.pumpAndSettle();
    expect(controller.draft.frequencyText, '2');

    await tester.ensureVisible(find.byTooltip('Decrease Amplitude'));
    await tester.tap(find.byTooltip('Decrease Amplitude'));
    await tester.pumpAndSettle();
    expect(controller.draft.amplitudeVpp, closeTo(0.9, 1e-9));

    await tester.ensureVisible(find.byTooltip('Increase DC Offset'));
    await tester.tap(find.byTooltip('Increase DC Offset'));
    await tester.pumpAndSettle();
    expect(controller.draft.offsetV, closeTo(0.1, 1e-9));

    await tester.ensureVisible(find.byTooltip('Increase Duty Cycle'));
    await tester.tap(find.byTooltip('Increase Duty Cycle'));
    await tester.pumpAndSettle();
    expect(controller.draft.dutyText, '51');

    await tester.ensureVisible(find.byTooltip('Increase Phase'));
    await tester.tap(find.byTooltip('Increase Phase'));
    await tester.pumpAndSettle();
    expect(controller.draft.phaseText, '1');
  });

  testWidgets('offline generator disables the editor', (tester) async {
    final client = FakeSigGenWindowClient(fakeWindowState(connected: false));
    await _pumpPanel(tester, client: client);

    expect(find.text('OFFLINE'), findsOneWidget);
    expect(
      find.text('Signal generator offline — controls are disabled.'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'APPLY CHANGES'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Bode sweep banner is shown and block mutations', (tester) async {
    final client = FakeSigGenWindowClient(fakeWindowState(mutable: false));
    final controller = await _pumpPanel(tester, client: client);

    expect(
      find.text('Bode sweep running — settings cannot be changed.'),
      findsOneWidget,
    );

    controller.updateFrequencyText('2');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('APPLY CHANGES'));
    await tester.tap(find.text('APPLY CHANGES'));
    await tester.pumpAndSettle();

    expect(
      client.calls.where((call) => call.startsWith('setFrequency')),
      isEmpty,
    );
  });
}
