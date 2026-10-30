/// Window argument marker for the engineering-calculator child engine.
///
/// The calculator window is self-contained: it loads its own workspace and
/// needs no command bridge to the main window. Only the window identity is
/// shared, so the launcher can find and focus an existing window.
library;

import 'dart:convert';

const String calculatorWindowType = 'calculator';

/// Screen position of the calculator window, in logical pixels.
class CalculatorWindowPosition {
  const CalculatorWindowPosition({required this.left, required this.top});

  final double left;
  final double top;
}

class CalculatorWindowArguments {
  const CalculatorWindowArguments._();

  static const double windowWidth = 1240;
  static const double windowHeight = 820;

  static String toArguments({CalculatorWindowPosition? position}) {
    return jsonEncode({
      'type': calculatorWindowType,
      if (position != null) ...{'left': position.left, 'top': position.top},
    });
  }

  static bool isCalculatorWindow(String raw) {
    if (raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['type'] == calculatorWindowType;
    } on FormatException {
      return false;
    }
  }

  /// Parses the optional target position from the child-window arguments.
  static CalculatorWindowPosition? positionFrom(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['type'] != calculatorWindowType) {
        return null;
      }
      final left = decoded['left'];
      final top = decoded['top'];
      if (left is num && top is num) {
        return CalculatorWindowPosition(
          left: left.toDouble(),
          top: top.toDouble(),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Centers the calculator window inside the main-window frame.
  static CalculatorWindowPosition centeredIn({
    required double mainLeft,
    required double mainTop,
    required double mainWidth,
    required double mainHeight,
  }) {
    return CalculatorWindowPosition(
      left: mainLeft + (mainWidth - windowWidth) / 2,
      top: mainTop + (mainHeight - windowHeight) / 2,
    );
  }
}
