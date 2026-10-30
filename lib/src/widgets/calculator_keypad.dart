/// Scientific keypad of the engineering calculator.
///
/// The keypad only produces text and callbacks; parsing, units and errors are
/// handled by the calculator engine.
library;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../calculator/calculator_controller.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_value.dart';

enum _KeyKind { digit, operator, function, action, accent, danger, mode }

class _KeyData {
  const _KeyData({
    required this.label,
    this.shiftLabel,
    this.inverseLabel,
    this.primary,
    this.shiftText,
    this.inverseText,
    this.action,
    this.kind = _KeyKind.function,
    this.description,
  });

  final String label;
  final String? shiftLabel;
  final String? inverseLabel;
  final String? primary;
  final String? shiftText;
  final String? inverseText;
  final VoidCallback? action;
  final _KeyKind kind;
  final String? description;

  bool get hasAlternate =>
      shiftLabel != null ||
      inverseLabel != null ||
      shiftText != null ||
      inverseText != null;

  String? effectiveText(bool shift, bool inverse) {
    if (inverse) return inverseText ?? shiftText ?? primary;
    if (shift) return shiftText ?? primary;
    return primary;
  }

  VoidCallback? effectiveAction(bool shift, bool inverse) => action;

  String effectiveLabel(bool shift, bool inverse) {
    if (inverse) return inverseLabel ?? shiftLabel ?? label;
    if (shift) return shiftLabel ?? label;
    return label;
  }
}

/// Seven-column scientific keypad.
class CalculatorKeypad extends StatelessWidget {
  const CalculatorKeypad({
    super.key,
    required this.controller,
    required this.onInsert,
    required this.onEvaluate,
    required this.onClear,
    required this.onBackspace,
    required this.onSign,
    required this.onStore,
    required this.onRecall,
    required this.onUnit,
    required this.onConvert,
    required this.onHistory,
    required this.onVariables,
    required this.onFormulas,
    required this.onFavorites,
    required this.onProgram,
  });

  final CalculatorController controller;
  final ValueChanged<String> onInsert;
  final VoidCallback onEvaluate;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  final VoidCallback onSign;
  final VoidCallback onStore;
  final VoidCallback onRecall;
  final VoidCallback onUnit;
  final VoidCallback onConvert;
  final VoidCallback onHistory;
  final VoidCallback onVariables;
  final VoidCallback onFormulas;
  final VoidCallback onFavorites;
  final VoidCallback onProgram;

  @override
  Widget build(BuildContext context) {
    final shift = controller.shift;
    final inverse = controller.inverse;
    final settings = controller.session.settings;
    final base = settings.numberBase;

    final rows = <List<_KeyData>>[
      _modeRow(settings),
      [
        _KeyData(
          label: 'sin',
          shiftLabel: 'asin',
          inverseLabel: 'sinh',
          primary: 'sin(',
          shiftText: 'asin(',
          inverseText: 'sinh(',
          description:
              'Sine. SHIFT inserts the inverse sine; INV inserts the '
              'hyperbolic sine.',
        ),
        _KeyData(
          label: 'cos',
          shiftLabel: 'acos',
          inverseLabel: 'cosh',
          primary: 'cos(',
          shiftText: 'acos(',
          inverseText: 'cosh(',
          description:
              'Cosine. SHIFT inserts the inverse cosine; INV inserts the '
              'hyperbolic cosine.',
        ),
        _KeyData(
          label: 'tan',
          shiftLabel: 'atan',
          inverseLabel: 'tanh',
          primary: 'tan(',
          shiftText: 'atan(',
          inverseText: 'tanh(',
          description:
              'Tangent. SHIFT inserts the inverse tangent; INV inserts the '
              'hyperbolic tangent.',
        ),
        _KeyData(
          label: 'ln',
          shiftLabel: 'eˣ',
          inverseLabel: 'log₂',
          primary: 'ln(',
          shiftText: 'exp(',
          inverseText: 'log2(',
          description:
              'Natural logarithm. SHIFT inserts exp(); INV inserts log2().',
        ),
        _KeyData(
          label: 'log',
          shiftLabel: '10ˣ',
          inverseLabel: 'logₓ',
          primary: 'log10(',
          shiftText: '10^(',
          inverseText: 'log(',
          description:
              'Base-10 logarithm. SHIFT inserts 10^x; INV inserts a logarithm '
              'with an explicit base.',
        ),
        _KeyData(
          label: 'exp',
          shiftLabel: 'eˣ',
          inverseLabel: 'π',
          primary: 'exp(',
          shiftText: 'e^(',
          inverseText: 'pi',
          description:
              'Exponential function. SHIFT inserts e^x; INV inserts pi.',
        ),
        _KeyData(
          label: 'xʸ',
          shiftLabel: 'ʸ√x',
          inverseLabel: 'x²',
          primary: '^',
          shiftText: '^(1/',
          inverseText: '^2',
          kind: _KeyKind.operator,
          description: 'Power. SHIFT inserts a root; INV inserts the square.',
        ),
      ],
      [
        _KeyData(
          label: '√',
          shiftLabel: '∛',
          inverseLabel: '√',
          primary: 'sqrt(',
          shiftText: 'cbrt(',
          inverseText: '√(',
          description:
              'Square root. SHIFT inserts the cube root; INV inserts a root '
              'with an explicit index.',
        ),
        _KeyData(
          label: 'x²',
          shiftLabel: 'x³',
          inverseLabel: 'x^½',
          primary: '^2',
          shiftText: '^3',
          inverseText: '^(1/2)',
          description:
              'Square. SHIFT inserts the cube; INV inserts the square root '
              'using an exponent of 1/2.',
        ),
        _KeyData(
          label: '1/x',
          shiftLabel: '%',
          inverseLabel: '‰',
          primary: '1/(',
          shiftText: '%',
          inverseText: 'ppm',
          description:
              'Reciprocal. SHIFT inserts percent; INV inserts parts per '
              'million.',
        ),
        _KeyData(
          label: 'n!',
          shiftLabel: 'Γ',
          inverseLabel: 'nCr',
          primary: '!',
          shiftText: 'gamma(',
          inverseText: 'comb(',
          description:
              'Factorial. SHIFT inserts the gamma function; INV inserts the '
              'combination function.',
        ),
        _KeyData(
          label: 'ABS',
          shiftLabel: 'mag',
          inverseLabel: 'arg',
          primary: 'abs(',
          shiftText: 'mag(',
          inverseText: 'arg(',
          description:
              'Absolute value. SHIFT inserts the magnitude; INV inserts the '
              'argument or phase.',
        ),
        const _KeyData(
          label: 'π',
          primary: 'pi',
          description: 'Insert the constant pi.',
        ),
        const _KeyData(
          label: 'e',
          primary: 'e',
          description: "Insert Euler's number e.",
        ),
      ],
      const [
        _KeyData(
          label: '(',
          primary: '(',
          kind: _KeyKind.function,
          description: 'Open parenthesis.',
        ),
        _KeyData(
          label: ')',
          primary: ')',
          kind: _KeyKind.function,
          description: 'Close parenthesis.',
        ),
        _KeyData(
          label: 'mod',
          primary: ' mod ',
          kind: _KeyKind.operator,
          description: 'Modulo: insert the remainder operator.',
        ),
        _KeyData(
          label: '∠',
          primary: '∠',
          kind: _KeyKind.operator,
          description: 'Polar angle operator: magnitude∠angle.',
        ),
        _KeyData(
          label: 'j',
          primary: 'j',
          kind: _KeyKind.function,
          description: 'Insert the imaginary unit j.',
        ),
        _KeyData(
          label: '°',
          primary: '°',
          kind: _KeyKind.function,
          description: 'Insert the degree unit.',
        ),
        _KeyData(
          label: '%',
          primary: '%',
          kind: _KeyKind.function,
          description: 'Insert percent; plain numbers are divided by 100.',
        ),
      ],
      [
        const _KeyData(label: '7', primary: '7', kind: _KeyKind.digit),
        const _KeyData(label: '8', primary: '8', kind: _KeyKind.digit),
        const _KeyData(label: '9', primary: '9', kind: _KeyKind.digit),
        const _KeyData(
          label: '÷',
          primary: '/',
          kind: _KeyKind.operator,
          description: 'Divide.',
        ),
        _KeyData(
          label: 'STO',
          action: onStore,
          kind: _KeyKind.action,
          description: 'Store the current result in a named variable.',
        ),
        _KeyData(
          label: 'RCL',
          action: onRecall,
          kind: _KeyKind.action,
          description: 'Recall a stored variable into the expression.',
        ),
        _KeyData(
          label: 'HIST',
          action: onHistory,
          kind: _KeyKind.action,
          description: 'Open the calculation history.',
        ),
      ],
      [
        const _KeyData(label: '4', primary: '4', kind: _KeyKind.digit),
        const _KeyData(label: '5', primary: '5', kind: _KeyKind.digit),
        const _KeyData(label: '6', primary: '6', kind: _KeyKind.digit),
        const _KeyData(
          label: '×',
          primary: '*',
          kind: _KeyKind.operator,
          description: 'Multiply.',
        ),
        _KeyData(
          label: 'VAR',
          action: onVariables,
          kind: _KeyKind.action,
          description: 'Show variables and user-defined functions.',
        ),
        _KeyData(
          label: 'UNIT',
          action: onUnit,
          kind: _KeyKind.action,
          description: 'Insert a unit or Greek unit symbol from a list.',
        ),
        _KeyData(
          label: 'CONV',
          action: onConvert,
          kind: _KeyKind.action,
          description: 'Convert the expression to another unit.',
        ),
      ],
      [
        const _KeyData(label: '1', primary: '1', kind: _KeyKind.digit),
        const _KeyData(label: '2', primary: '2', kind: _KeyKind.digit),
        const _KeyData(label: '3', primary: '3', kind: _KeyKind.digit),
        const _KeyData(
          label: '−',
          primary: '-',
          kind: _KeyKind.operator,
          description: 'Subtract.',
        ),
        _KeyData(
          label: 'FAV',
          action: onFavorites,
          kind: _KeyKind.action,
          description: 'Open favorite calculations.',
        ),
        _KeyData(
          label: 'FORM',
          action: onFormulas,
          kind: _KeyKind.action,
          description: 'Open the formula library.',
        ),
        _KeyData(
          label: 'PROG',
          action: onProgram,
          kind: _KeyKind.action,
          description: 'Open the program editor.',
        ),
      ],
      [
        const _KeyData(label: '0', primary: '0', kind: _KeyKind.digit),
        const _KeyData(label: '.', primary: '.', kind: _KeyKind.digit),
        _KeyData(
          label: '±',
          action: onSign,
          kind: _KeyKind.function,
          description:
              'Change the sign of the selection or insert a minus sign.',
        ),
        const _KeyData(
          label: '+',
          primary: '+',
          kind: _KeyKind.operator,
          description: 'Add.',
        ),
        _KeyData(
          label: 'ANS',
          primary: 'ans',
          kind: _KeyKind.function,
          description: 'Insert the previous result (ans).',
        ),
        _KeyData(
          label: '=',
          action: onEvaluate,
          kind: _KeyKind.accent,
          description: 'Evaluate the expression.',
        ),
        _KeyData(
          label: '⌫',
          action: onBackspace,
          kind: _KeyKind.danger,
          description:
              'Delete the selection or the character before the cursor.',
        ),
      ],
    ];

    final columns = <Widget>[];
    for (final row in rows) {
      columns.add(
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (var index = 0; index < row.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _CalcKeyButton(
                      keyData: row[index],
                      shift: shift,
                      inverse: inverse,
                      onPress: () => _press(row[index], shift, inverse),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (base != CalcIntegerBase.decimal) {
      columns.insert(
        4,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: _CalcKeyButton(
                    keyData: _KeyData(
                      label: '0x',
                      shiftLabel: '0b',
                      inverseLabel: '0o',
                      primary: '0x',
                      shiftText: '0b',
                      inverseText: '0o',
                      kind: _KeyKind.action,
                    ),
                    shift: shift,
                    inverse: inverse,
                    onPress: () => _press(
                      _KeyData(
                        label: '0x',
                        shiftLabel: '0b',
                        inverseLabel: '0o',
                        primary: '0x',
                        shiftText: '0b',
                        inverseText: '0o',
                        kind: _KeyKind.action,
                      ),
                      shift,
                      inverse,
                    ),
                  ),
                ),
                for (final hex in const ['A', 'B', 'C', 'D', 'E', 'F']) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: _CalcKeyButton(
                      keyData: _KeyData(
                        label: hex,
                        primary: hex,
                        kind: _KeyKind.digit,
                      ),
                      shift: shift,
                      inverse: inverse,
                      onPress: () => onInsert(hex),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1626),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(children: columns),
    );
  }

  List<_KeyData> _modeRow(CalcFormatSettings settings) {
    final angleLabel = switch (settings.angleMode) {
      CalcAngleMode.degrees => 'DEG',
      CalcAngleMode.radians => 'RAD',
      CalcAngleMode.gradians => 'GRAD',
    };
    final formatLabel = switch (settings.format) {
      CalcNumberFormat.auto => 'AUTO',
      CalcNumberFormat.fixed => 'FIXED',
      CalcNumberFormat.scientific => 'SCI',
      CalcNumberFormat.engineering => 'ENG',
    };
    final baseLabel = switch (settings.numberBase) {
      CalcIntegerBase.decimal => 'DEC',
      CalcIntegerBase.hexadecimal => 'HEX',
      CalcIntegerBase.octal => 'OCT',
      CalcIntegerBase.binary => 'BIN',
    };
    return [
      _KeyData(
        label: 'SHIFT',
        action: controller.toggleShift,
        kind: _KeyKind.mode,
        description: 'Apply the amber secondary function printed above a key.',
      ),
      _KeyData(
        label: 'INV',
        action: controller.toggleInverse,
        kind: _KeyKind.mode,
        description:
            'Apply the inverse or hyperbolic function printed above a key.',
      ),
      _KeyData(
        label: angleLabel,
        action: controller.cycleAngleMode,
        kind: _KeyKind.mode,
        description:
            'Cycle the angle unit for plain numbers: degrees, radians, '
            'gradians (gon).',
      ),
      _KeyData(
        label: formatLabel,
        action: () {
          const order = [
            CalcNumberFormat.auto,
            CalcNumberFormat.engineering,
            CalcNumberFormat.fixed,
            CalcNumberFormat.scientific,
          ];
          final index = order.indexOf(settings.format);
          controller.setNumberFormat(order[(index + 1) % order.length]);
        },
        kind: _KeyKind.mode,
        description:
            'Cycle the number format: Auto, Engineering, Fixed, Scientific.',
      ),
      _KeyData(
        label: baseLabel,
        action: controller.cycleNumberBase,
        kind: _KeyKind.mode,
        description:
            'Cycle the integer display base: decimal, hexadecimal, octal, '
            'binary.',
      ),
      _KeyData(
        label: 'CLR',
        action: onClear,
        kind: _KeyKind.danger,
        description: 'Clear the expression and the displayed result.',
      ),
    ];
  }

  void _press(_KeyData key, bool shift, bool inverse) {
    final action = key.effectiveAction(shift, inverse);
    if (action != null) {
      action();
      return;
    }
    final text = key.effectiveText(shift, inverse);
    if (text != null) onInsert(text);
  }
}

class _CalcKeyButton extends StatefulWidget {
  const _CalcKeyButton({
    required this.keyData,
    required this.shift,
    required this.inverse,
    required this.onPress,
  });

  final _KeyData keyData;
  final bool shift;
  final bool inverse;
  final VoidCallback onPress;

  @override
  State<_CalcKeyButton> createState() => _CalcKeyButtonState();
}

class _CalcKeyButtonState extends State<_CalcKeyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final key = widget.keyData;
    final active = widget.shift || widget.inverse;
    final baseColor = switch (key.kind) {
      _KeyKind.digit => const Color(0xFF16243A),
      _KeyKind.operator => const Color(0xFF173754),
      _KeyKind.function => const Color(0xFF101F33),
      _KeyKind.action => const Color(0xFF152640),
      _KeyKind.accent => const Color(0xFF0E7490),
      _KeyKind.danger => const Color(0xFF6B1D1D),
      _KeyKind.mode => const Color(0xFF1B2B45),
    };
    final isMode = key.kind == _KeyKind.mode;
    final modifierActive =
        (key.label == 'SHIFT' && widget.shift) ||
        (key.label == 'INV' && widget.inverse);
    final highlight = modifierActive || (active && key.hasAlternate && !isMode);

    final foreground = key.label == 'SHIFT'
        ? Colors.amberAccent
        : key.kind == _KeyKind.accent
        ? Colors.white
        : (key.kind == _KeyKind.operator ? Colors.cyanAccent : Colors.white);

    final effectiveLabel = key.effectiveLabel(widget.shift, widget.inverse);
    final description = key.description;
    return Tooltip(
      message: description == null
          ? effectiveLabel
          : '$effectiveLabel\n$description',
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Keep the expression field focused: a keypad tap must not move the
          // caret or replace the current selection before the text is
          // inserted.
          canRequestFocus: false,
          onTap: widget.onPress,
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            decoration: BoxDecoration(
              color: highlight
                  ? const Color(0xFF4A3A12)
                  : (_hovered
                        ? Color.lerp(baseColor, Colors.white, 0.10)
                        : baseColor),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: highlight
                    ? Colors.amberAccent
                    : (isMode ? const Color(0xFF3B82F6) : AppColors.border),
                width: highlight ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (key.hasAlternate && !isMode)
                  Text(
                    _secondaryLabel(key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 8,
                      height: 1,
                    ),
                  ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    key.label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: isMode ? 10 : 14,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _secondaryLabel(_KeyData key) {
    if (widget.inverse) return key.inverseLabel ?? key.shiftLabel ?? '';
    if (widget.shift) return key.shiftLabel ?? '';
    return key.shiftLabel ?? key.inverseLabel ?? '';
  }
}
