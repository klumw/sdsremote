import 'package:sdsremote/src/calculator/calculator_shortcut.dart';
import 'package:sdsremote/src/signal_generator/signal_generator_shortcut.dart';
import 'package:test/test.dart';

void main() {
  test('Ctrl+J is the default shortcut', () {
    expect(SignalGeneratorShortcut.defaultShortcut.id, 'ctrl_j');
    expect(SignalGeneratorShortcut.defaultShortcut.label, 'Ctrl+J');
    expect(SignalGeneratorShortcut.fromPreference(null).id, 'ctrl_j');
    expect(SignalGeneratorShortcut.fromPreference('').id, 'ctrl_j');
    expect(SignalGeneratorShortcut.fromPreference('unknown').id, 'ctrl_j');
  });

  test('presets are unique and resolvable by id and label', () {
    final ids = SignalGeneratorShortcut.presets
        .map((preset) => preset.id)
        .toSet();
    final labels = SignalGeneratorShortcut.presets
        .map((preset) => preset.label)
        .toSet();
    expect(ids, hasLength(SignalGeneratorShortcut.presets.length));
    expect(labels, hasLength(SignalGeneratorShortcut.presets.length));
    for (final preset in SignalGeneratorShortcut.presets) {
      expect(SignalGeneratorShortcut.fromPreference(preset.id).id, preset.id);
      expect(
        SignalGeneratorShortcut.fromPreference(preset.label).id,
        preset.id,
      );
      expect(SignalGeneratorShortcut.byId(preset.id).id, preset.id);
    }
    expect(
      SignalGeneratorShortcut.presets.map((preset) => preset.label),
      containsAll(['Ctrl+J', 'Ctrl+Shift+J', 'Ctrl+Alt+G', 'F10']),
    );
  });

  test('presets do not collide with the calculator shortcuts', () {
    final calculatorLabels = CalculatorShortcut.presets
        .map((preset) => preset.label)
        .toSet();
    for (final preset in SignalGeneratorShortcut.presets) {
      expect(calculatorLabels, isNot(contains(preset.label)));
    }
  });
}
