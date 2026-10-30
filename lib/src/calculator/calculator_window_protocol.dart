/// Window argument marker for the engineering-calculator child engine.
///
/// The calculator window is self-contained: it loads its own workspace and
/// needs no command bridge to the main window. Only the window identity is
/// shared, so the launcher can find and focus an existing window.
library;

import 'dart:convert';

const String calculatorWindowType = 'calculator';

class CalculatorWindowArguments {
  const CalculatorWindowArguments._();

  static String toArguments() => jsonEncode({'type': calculatorWindowType});

  static bool isCalculatorWindow(String raw) {
    if (raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['type'] == calculatorWindowType;
    } on FormatException {
      return false;
    }
  }
}
