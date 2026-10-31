/// Configurable global shortcut that opens the signal generator window.
library;

import 'package:flutter/services.dart';

/// One selectable signal generator shortcut.
class SignalGeneratorShortcut {
  const SignalGeneratorShortcut({
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

  /// The default Ctrl+J combination used by the signal generator window.
  static const SignalGeneratorShortcut defaultShortcut =
      SignalGeneratorShortcut(
        id: 'ctrl_j',
        label: 'Ctrl+J',
        key: LogicalKeyboardKey.keyJ,
        control: true,
      );

  /// Selectable alternatives. Ctrl+J stays first because it is the default.
  static const List<SignalGeneratorShortcut> presets = [
    defaultShortcut,
    SignalGeneratorShortcut(
      id: 'ctrl_shift_j',
      label: 'Ctrl+Shift+J',
      key: LogicalKeyboardKey.keyJ,
      control: true,
      shift: true,
    ),
    SignalGeneratorShortcut(
      id: 'ctrl_alt_g',
      label: 'Ctrl+Alt+G',
      key: LogicalKeyboardKey.keyG,
      control: true,
      alt: true,
    ),
    SignalGeneratorShortcut(
      id: 'f10',
      label: 'F10',
      key: LogicalKeyboardKey.f10,
    ),
  ];

  static SignalGeneratorShortcut fromPreference(String? value) {
    if (value == null || value.trim().isEmpty) return defaultShortcut;
    final normalized = value.trim().toLowerCase();
    for (final preset in presets) {
      if (preset.id == normalized || preset.label.toLowerCase() == normalized) {
        return preset;
      }
    }
    return defaultShortcut;
  }

  static SignalGeneratorShortcut byId(String id) => fromPreference(id);

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
