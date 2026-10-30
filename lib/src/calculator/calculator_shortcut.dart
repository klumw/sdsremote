/// Configurable global shortcut that opens the calculator window.
library;

import 'package:flutter/services.dart';

/// One selectable calculator shortcut.
class CalculatorShortcut {
  const CalculatorShortcut({
    required this.id,
    required this.label,
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final String id;
  final String label;
  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;

  /// The default Ctrl+R combination requested by the calculator feature.
  static const CalculatorShortcut defaultShortcut = CalculatorShortcut(
    id: 'ctrl_r',
    label: 'Ctrl+R',
    key: LogicalKeyboardKey.keyR,
    control: true,
  );

  /// Selectable alternatives. Ctrl+R stays first because it is the default.
  static const List<CalculatorShortcut> presets = [
    defaultShortcut,
    CalculatorShortcut(
      id: 'ctrl_shift_r',
      label: 'Ctrl+Shift+R',
      key: LogicalKeyboardKey.keyR,
      control: true,
      shift: true,
    ),
    CalculatorShortcut(
      id: 'ctrl_alt_c',
      label: 'Ctrl+Alt+C',
      key: LogicalKeyboardKey.keyC,
      control: true,
      alt: true,
    ),
    CalculatorShortcut(id: 'f9', label: 'F9', key: LogicalKeyboardKey.f9),
  ];

  static CalculatorShortcut fromPreference(String? value) {
    if (value == null || value.trim().isEmpty) return defaultShortcut;
    final normalized = value.trim().toLowerCase();
    for (final preset in presets) {
      if (preset.id == normalized || preset.label.toLowerCase() == normalized) {
        return preset;
      }
    }
    return defaultShortcut;
  }

  static CalculatorShortcut byId(String id) => fromPreference(id);

  /// True when [event] is the key-down event of this shortcut with exactly
  /// the configured modifiers.
  bool matches(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != key) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed != control) return false;
    if (keyboard.isShiftPressed != shift) return false;
    if (keyboard.isAltPressed != alt) return false;
    if (keyboard.isMetaPressed) return false;
    return true;
  }
}
