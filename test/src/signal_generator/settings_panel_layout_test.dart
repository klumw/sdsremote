import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/widgets/osci_settings_panel.dart';

void main() {
  Future<void> pumpPanel(WidgetTester tester, {required bool isUsb}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SettingsPanel(
                offset: const Offset(20, 20),
                ipAddress: '192.168.1.100',
                isUsb: isUsb,
                signalGenerator: 'none',
                onSignalGeneratorChanged: (_) {},
                providerNames: const ['Test Provider'],
                selectedProvider: 'Test Provider',
                aiApiToken: '',
                llmModel: '',
                saveWithParams: false,
                askForFilenamePrefix: false,
                callbacks: SettingsPanelCallbacks(
                  onSave: (_, _, _, _, _) {},
                  onClose: () {},
                  onDrag: (_) {},
                ),
                onSaveWithParamsChanged: (_) {},
                onAskForFilenamePrefixChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pairs the requested settings fields in the same row', (
    tester,
  ) async {
    await pumpPanel(tester, isUsb: false);

    double dyOf(String text) => tester.getCenter(find.text(text)).dy;

    expect(
      dyOf('Oscilloscope IP Address'),
      closeTo(dyOf('Oscilloscope Connection Mode'), 1),
    );
    expect(
      dyOf('Signal Generator Window'),
      closeTo(dyOf('Signal Generator'), 1),
    );
    expect(dyOf('AI API Token'), closeTo(dyOf('AI Provider'), 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel keeps its size when USB mode hides the IP field', (
    tester,
  ) async {
    await pumpPanel(tester, isUsb: false);
    final panel = find.byKey(const ValueKey('settings-panel'));
    final visibility = find.byKey(const ValueKey('ip-address-visibility'));
    final sizeBefore = tester.getSize(panel);
    expect(tester.widget<Visibility>(visibility).visible, isTrue);

    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USB').last);
    await tester.pumpAndSettle();

    expect(tester.getSize(panel), sizeBefore);
    expect(tester.widget<Visibility>(visibility).visible, isFalse);
    expect(find.text('Oscilloscope IP Address'), findsOneWidget);
    final ipField = tester.widget<TextField>(
      find.ancestor(
        of: find.text('Oscilloscope IP Address'),
        matching: find.byType(TextField),
      ),
    );
    expect(ipField.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the signal generator window only for a selected device', (
    tester,
  ) async {
    await pumpPanel(tester, isUsb: false);
    final panel = find.byKey(const ValueKey('settings-panel'));
    final visibility = find.byKey(
      const ValueKey('signal-generator-window-visibility'),
    );
    final sizeBefore = tester.getSize(panel);
    expect(tester.widget<Visibility>(visibility).visible, isFalse);

    await tester.tap(find.text('No Signal Generator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FY6900').last);
    await tester.pumpAndSettle();

    expect(tester.widget<Visibility>(visibility).visible, isTrue);
    expect(tester.getSize(panel), sizeBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('places both save switches on the same row', (tester) async {
    await pumpPanel(tester, isUsb: false);

    final saveTop = tester.getTopLeft(find.text('Save csv data')).dy;
    final askTop = tester.getTopLeft(find.text('Ask for filename on save')).dy;
    expect(askTop, closeTo(saveTop, 1));

    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    expect(
      tester.getCenter(switches.at(0)).dy,
      closeTo(tester.getCenter(switches.at(1)).dy, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
