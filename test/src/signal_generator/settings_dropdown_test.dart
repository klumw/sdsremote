import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/widgets/osci_settings_panel.dart';

void main() {
  testWidgets('signal generator dropdown offers all entries', (tester) async {
    String selected = 'none';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SettingsPanel(
                offset: const Offset(20, 20),
                ipAddress: '192.168.1.100',
                isUsb: false,
                signalGenerator: 'none',
                onSignalGeneratorChanged: (value) => selected = value,
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

    expect(find.text('Signal Generator'), findsOneWidget);
    expect(find.text('No Signal Generator'), findsOneWidget);

    await tester.tap(find.text('No Signal Generator'));
    await tester.pumpAndSettle();
    expect(find.text('JDS6600'), findsOneWidget);
    expect(find.text('FY6900'), findsOneWidget);

    await tester.tap(find.text('FY6900'));
    await tester.pumpAndSettle();

    expect(selected, 'fy6900');
    expect(tester.takeException(), isNull);
  });
}
