/// Modal dialogs of the engineering calculator window.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../calculator/calc_error.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_formulas.dart';
import '../calculator/calc_units.dart';
import '../calculator/calc_value.dart';
import '../calculator/calc_workspace_store.dart';
import '../calculator/calculator_controller.dart';
import 'sensor_calibration_dialog.dart';

// =============================================================================
// Sensor calibration
// =============================================================================

/// Shows the linear sensor calibration dialog.
Future<void> showSensorCalibrationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const SensorCalibrationDialog(),
  );
}

// =============================================================================
// Settings
// =============================================================================

Future<void> showCalculatorSettingsDialog(
  BuildContext context,
  CalculatorController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _CalculatorSettingsDialog(controller: controller),
  );
}

class _CalculatorSettingsDialog extends StatefulWidget {
  const _CalculatorSettingsDialog({required this.controller});

  final CalculatorController controller;

  @override
  State<_CalculatorSettingsDialog> createState() =>
      _CalculatorSettingsDialogState();
}

class _CalculatorSettingsDialogState extends State<_CalculatorSettingsDialog> {
  late CalcNumberFormat _format;
  late int _fractionDigits;
  late CalcAngleMode _angleMode;
  late CalcIntegerBase _numberBase;

  @override
  void initState() {
    super.initState();
    final settings = widget.controller.session.settings;
    _format = settings.format;
    _fractionDigits = settings.fractionDigits;
    _angleMode = settings.angleMode;
    _numberBase = settings.numberBase;
  }

  @override
  Widget build(BuildContext context) {
    final workspace =
        widget.controller.session.storageFile?.path ?? 'in-memory workspace';
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.settings, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Calculator settings'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NUMBER FORMAT', style: _sectionStyle),
              const SizedBox(height: 6),
              DropdownButtonFormField<CalcNumberFormat>(
                initialValue: _format,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: CalcNumberFormat.auto,
                    child: Text('Auto (SI prefix, scientific when needed)'),
                  ),
                  DropdownMenuItem(
                    value: CalcNumberFormat.engineering,
                    child: Text('Engineering (exponent multiple of 3)'),
                  ),
                  DropdownMenuItem(
                    value: CalcNumberFormat.scientific,
                    child: Text('Scientific (d.ddd e±n)'),
                  ),
                  DropdownMenuItem(
                    value: CalcNumberFormat.fixed,
                    child: Text('Fixed-point'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _format = value ?? _format),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _fractionDigits,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Fraction digits (fixed-point)',
                ),
                items: [
                  for (var digits = 0; digits <= 10; digits++)
                    DropdownMenuItem(value: digits, child: Text('$digits')),
                ],
                onChanged: (value) =>
                    setState(() => _fractionDigits = value ?? _fractionDigits),
              ),
              const SizedBox(height: 16),
              const Text('ANGLES', style: _sectionStyle),
              const SizedBox(height: 6),
              SegmentedButton<CalcAngleMode>(
                segments: const [
                  ButtonSegment(
                    value: CalcAngleMode.degrees,
                    label: Text('Degrees'),
                  ),
                  ButtonSegment(
                    value: CalcAngleMode.radians,
                    label: Text('Radians'),
                  ),
                  ButtonSegment(
                    value: CalcAngleMode.gradians,
                    label: Text('Gradians'),
                  ),
                ],
                selected: {_angleMode},
                onSelectionChanged: (value) =>
                    setState(() => _angleMode = value.first),
              ),
              const SizedBox(height: 16),
              const Text('INTEGER DISPLAY', style: _sectionStyle),
              const SizedBox(height: 6),
              DropdownButtonFormField<CalcIntegerBase>(
                initialValue: _numberBase,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: CalcIntegerBase.decimal,
                    child: Text('Decimal'),
                  ),
                  DropdownMenuItem(
                    value: CalcIntegerBase.hexadecimal,
                    child: Text('Hexadecimal'),
                  ),
                  DropdownMenuItem(
                    value: CalcIntegerBase.octal,
                    child: Text('Octal'),
                  ),
                  DropdownMenuItem(
                    value: CalcIntegerBase.binary,
                    child: Text('Binary'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _numberBase = value ?? _numberBase),
              ),
              const SizedBox(height: 18),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),
              const Text(
                'The window opens with Ctrl+R. The shortcut is configurable '
                'in the main application under Settings → Calculator.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Text(
                'Workspace: $workspace',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.controller.updateSettings(
              widget.controller.session.settings.copyWith(
                format: _format,
                fractionDigits: _fractionDigits,
                angleMode: _angleMode,
                numberBase: _numberBase,
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

const _sectionStyle = TextStyle(
  color: Colors.white54,
  fontSize: 11,
  letterSpacing: 1.1,
  fontWeight: FontWeight.bold,
);

// =============================================================================
// Unit picker / converter
// =============================================================================

const List<String> _greekUnitSymbols = ['µ', 'μ', 'Ω', '°', 'Å'];

const Map<String, String> _greekUnitSymbolTooltips = {
  'µ': 'Micro prefix',
  'μ': 'Greek mu (normalized to micro)',
  'Ω': 'Ohm',
  '°': 'Degree',
  'Å': 'Angstrom',
};

Future<String?> showUnitPickerDialog(
  BuildContext context,
  CalculatorController controller,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => _UnitPickerDialog(controller: controller),
  );
}

class _UnitPickerDialog extends StatefulWidget {
  const _UnitPickerDialog({required this.controller});

  final CalculatorController controller;

  @override
  State<_UnitPickerDialog> createState() => _UnitPickerDialogState();
}

class _UnitPickerDialogState extends State<_UnitPickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final symbols = CalcUnits.commonSymbols
        .where(
          (symbol) => query.isEmpty || symbol.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.straighten, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Insert unit or symbol'),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search unit',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'GREEK UNIT SYMBOLS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final symbol in _greekUnitSymbols)
                  Tooltip(
                    message: _greekUnitSymbolTooltips[symbol]!,
                    child: ActionChip(
                      key: ValueKey('unit-symbol-$symbol'),
                      label: Text(
                        symbol,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontFamily: 'monospace',
                          fontSize: 15,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(symbol),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: symbols.length,
                itemBuilder: (context, index) {
                  final symbol = symbols[index];
                  final unit = CalcUnits.resolve(symbol);
                  return ListTile(
                    dense: true,
                    onTap: () => Navigator.of(context).pop(symbol),
                    title: Text(
                      symbol,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontFamily: 'monospace',
                      ),
                    ),
                    subtitle: Text(
                      unit?.quantityName ?? '',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

Future<String?> showConvertDialog(
  BuildContext context,
  CalculatorController controller, {
  String initialExpression = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ConvertDialog(
      controller: controller,
      initialExpression: initialExpression,
    ),
  );
}

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({
    required this.controller,
    required this.initialExpression,
  });

  final CalculatorController controller;
  final String initialExpression;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  late final TextEditingController _value;
  late final TextEditingController _target;
  String? _result;
  String? _source;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(
      text: widget.initialExpression.isNotEmpty
          ? widget.initialExpression
          : widget.controller.lastSuccess?.entry?.valueSource ?? '',
    );
    _target = TextEditingController(text: 'mV');
  }

  @override
  void dispose() {
    _value.dispose();
    _target.dispose();
    super.dispose();
  }

  void _convert() {
    setState(() {
      _result = null;
      _source = null;
      _error = null;
    });
    final unit = CalcUnits.resolve(_target.text.trim());
    if (unit == null) {
      setState(() => _error = 'Unknown unit "${_target.text.trim()}"');
      return;
    }
    try {
      final evaluation = widget.controller.session.engine.evaluate(_value.text);
      final converted = widget.controller.session.engine.convertValue(
        evaluation.value,
        unit,
      );
      final display = widget.controller.session.formatter.format(converted);
      setState(() {
        _result = display;
        _source = converted.toSource();
      });
    } on CalcException catch (error) {
      setState(() => _error = error.formattedMessage);
    } on Object catch (error) {
      setState(() => _error = 'Conversion failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.swap_horiz, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Unit conversion'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _value,
              decoration: const InputDecoration(
                labelText: 'Value with unit',
                hintText: 'e.g. 230 mV / 10 kΩ',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _convert(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    decoration: const InputDecoration(
                      labelText: 'Target unit',
                      hintText: 'Ω, µA, dBm, °C …',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _convert(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final unit = await showUnitPickerDialog(
                      context,
                      widget.controller,
                    );
                    if (unit != null) {
                      _target.text = unit;
                      _convert();
                    }
                  },
                  icon: const Icon(Icons.straighten, size: 16),
                  label: const Text('Pick'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            if (_result != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2E),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _result!,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 20,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(onPressed: _convert, child: const Text('Convert')),
        if (_source != null)
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(_source),
            child: const Text('Insert result'),
          ),
      ],
    );
  }
}

// =============================================================================
// Variable / favorite dialogs
// =============================================================================

Future<void> showStoreDialog(
  BuildContext context,
  CalculatorController controller, {
  String initialExpression = '',
}) async {
  final name = TextEditingController(text: 'R1');
  final expression = TextEditingController(
    text: initialExpression.isNotEmpty
        ? initialExpression
        : controller.lastSuccess?.entry?.valueSource ?? '',
  );
  final error = ValueNotifier<String?>(null);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.save, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Store variable'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Variable name',
                  hintText: 'R1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: expression,
                decoration: const InputDecoration(
                  labelText: 'Value or expression',
                  hintText: '10 kΩ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: error,
                builder: (context, value, _) => value == null
                    ? const SizedBox.shrink()
                    : Text(
                        value,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final outcome = controller.defineVariable(
                name.text.trim(),
                expression.text.trim(),
              );
              if (outcome.ok) {
                Navigator.of(context).pop();
              } else {
                error.value = outcome.error?.formattedMessage;
              }
            },
            child: const Text('Store'),
          ),
        ],
      ),
    );
  } finally {
    name.dispose();
    expression.dispose();
    error.dispose();
  }
}

Future<void> showFavoriteDialog(
  BuildContext context,
  CalculatorController controller, {
  String initialName = '',
  String initialExpression = '',
}) async {
  final name = TextEditingController(text: initialName);
  final expression = TextEditingController(text: initialExpression);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.star, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('Add favorite'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'RC cutoff',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: expression,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Expression',
                  hintText: '1 / (2*pi*R1*C1)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (expression.text.trim().isEmpty) return;
              controller.addFavorite(name.text, expression.text);
              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  } finally {
    name.dispose();
    expression.dispose();
  }
}

Future<void> showAddVariableDialog(
  BuildContext context,
  CalculatorController controller, {
  String initialExpression = '',
}) {
  return showStoreDialog(
    context,
    controller,
    initialExpression: initialExpression,
  );
}

// =============================================================================
// Formula runner
// =============================================================================

Future<String?> showFormulaDialog(
  BuildContext context,
  CalculatorController controller,
  CalcFormula formula,
) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _FormulaDialog(controller: controller, formula: formula),
  );
}

class _FormulaDialog extends StatefulWidget {
  const _FormulaDialog({required this.controller, required this.formula});

  final CalculatorController controller;
  final CalcFormula formula;

  @override
  State<_FormulaDialog> createState() => _FormulaDialogState();
}

class _FormulaDialogState extends State<_FormulaDialog> {
  late final Map<String, TextEditingController> _fields;
  late final Map<String, FocusNode> _focusNodes;
  String? _activeInput;
  String? _result;
  String? _source;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final input in widget.formula.inputs)
        input.name: TextEditingController(text: input.defaultExpression),
    };
    _focusNodes = {
      for (final input in widget.formula.inputs) input.name: FocusNode(),
    };
    _activeInput = widget.formula.inputs.isEmpty
        ? null
        : widget.formula.inputs.first.name;
    for (final entry in _focusNodes.entries) {
      entry.value.addListener(() {
        if (entry.value.hasFocus) _activeInput = entry.key;
      });
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _insertUnit() async {
    final symbol = await showUnitPickerDialog(context, widget.controller);
    if (!mounted || symbol == null) return;
    final name = _activeInput;
    if (name == null || !_fields.containsKey(name)) return;
    final field = _fields[name]!;
    final selection = field.selection;
    final start = selection.isValid ? selection.start : field.text.length;
    final end = selection.isValid ? selection.end : field.text.length;
    field.value = TextEditingValue(
      text: field.text.replaceRange(start, end, symbol),
      selection: TextSelection.collapsed(offset: start + symbol.length),
    );
    _focusNodes[name]?.requestFocus();
  }

  void _run() {
    setState(() {
      _result = null;
      _source = null;
      _error = null;
    });
    final outcome = widget.controller.runFormula(widget.formula, {
      for (final entry in _fields.entries) entry.key: entry.value.text,
    });
    if (outcome.ok) {
      setState(() {
        _result = outcome.entry?.result;
        _source = outcome.entry?.valueSource;
      });
    } else {
      setState(() => _error = outcome.error?.formattedMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formula = widget.formula;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.functions, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(formula.name)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formula.description,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (formula.imageAsset != null) ...[
                Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(maxHeight: 240),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Image.asset(
                    formula.imageAsset!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) => Text(
                      'Could not load ${formula.imageAsset}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2E),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  formula.shownExpression,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (formula.inputs.isNotEmpty)
                Row(
                  children: [
                    const Text('INPUTS', style: _sectionStyle),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _insertUnit,
                      icon: const Text(
                        'Ω',
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 18,
                        ),
                      ),
                      label: const Text('Unit'),
                    ),
                  ],
                ),
              for (final input in formula.inputs) ...[
                TextField(
                  controller: _fields[input.name],
                  focusNode: _focusNodes[input.name],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: input.label,
                    hintText: input.hint.isEmpty ? null : input.hint,
                    helperText: input.hint.isEmpty ? null : input.hint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _run(),
                ),
                const SizedBox(height: 8),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              if (_result != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1B2E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.cyanAccent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _result!,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 20,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (formula.resultLabel != null)
                        Text(
                          formula.resultLabel!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              if (formula.assumptions.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('ASSUMPTIONS', style: _sectionStyle),
                const SizedBox(height: 4),
                for (final assumption in formula.assumptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $assumption',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_source != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_source),
            child: const Text('Insert result'),
          ),
        FilledButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Run'),
        ),
      ],
    );
  }
}

// =============================================================================
// Program / workspace dialogs
// =============================================================================

Future<void> showSaveProgramDialog(
  BuildContext context,
  CalculatorController controller,
  String source,
) async {
  final name = TextEditingController(text: 'Calculation');
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save program'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Program name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              controller.saveProgram(name.text, source);
              Navigator.of(context).pop();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.saveProgram(name.text, source);
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  } finally {
    name.dispose();
  }
}

/// Shows the named-workspace export dialog and returns the saved path.
Future<String?> showExportWorkspaceDialog(
  BuildContext context,
  CalculatorController controller, {
  CalcWorkspaceStore? store,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ExportWorkspaceDialog(
      controller: controller,
      store: store ?? CalcWorkspaceStore(),
    ),
  );
}

class _ExportWorkspaceDialog extends StatefulWidget {
  const _ExportWorkspaceDialog({required this.controller, required this.store});

  final CalculatorController controller;
  final CalcWorkspaceStore store;

  @override
  State<_ExportWorkspaceDialog> createState() => _ExportWorkspaceDialogState();
}

class _ExportWorkspaceDialogState extends State<_ExportWorkspaceDialog> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _error = null);

    final String name;
    try {
      name = CalcWorkspaceStore.normalizeName(_name.text);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    final bool exists;
    try {
      exists = await widget.store.exists(name);
    } on Object catch (error) {
      setState(() => _error = 'Export failed: $error');
      return;
    }
    if (!mounted) return;
    if (exists) {
      final overwrite = await showConfirmDialog(
        context,
        title: 'Overwrite workspace?',
        message: 'A workspace named "$name" already exists. Overwrite it?',
        confirmLabel: 'Overwrite',
      );
      if (!overwrite || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final file = await widget.store.write(
        name,
        widget.controller.session.exportWorkspace(),
      );
      if (mounted) Navigator.of(context).pop(file.path);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Export failed: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.save_alt, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Export workspace'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save the current workspace as a named snapshot. The default '
              'workspace is saved automatically and cannot be used as a name.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Workspace name',
                hintText: 'e.g. power-supply-design',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _export(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved as <name>.json in the calculator folder.',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _export,
          child: const Text('Export'),
        ),
      ],
    );
  }
}

/// Shows the workspace import dialog.
Future<void> showImportWorkspaceDialog(
  BuildContext context,
  CalculatorController controller, {
  CalcWorkspaceStore? store,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ImportWorkspaceDialog(
      controller: controller,
      store: store ?? CalcWorkspaceStore(),
    ),
  );
}

class _ImportWorkspaceDialog extends StatefulWidget {
  const _ImportWorkspaceDialog({required this.controller, required this.store});

  final CalculatorController controller;
  final CalcWorkspaceStore store;

  @override
  State<_ImportWorkspaceDialog> createState() => _ImportWorkspaceDialogState();
}

class _ImportWorkspaceDialogState extends State<_ImportWorkspaceDialog> {
  /// Selection key for the automatically saved default workspace.
  static const String _defaultSelection = 'default://workspace';

  final List<CalcWorkspaceFile> _files = [];
  String _selected = _defaultSelection;
  String _defaultSubtitle = 'Automatically saved workspace (workspace.json)';
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final files = await widget.store.list();
      final modified = await widget.store.defaultModified();
      if (!mounted) return;
      setState(() {
        _files
          ..clear()
          ..addAll(files);
        _defaultSubtitle = modified != null
            ? 'Automatically saved workspace (workspace.json) · '
                  '${_formatModified(modified)}'
            : 'Automatically saved workspace (not created yet)';
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Loading workspaces failed: $error';
        });
      }
    }
  }

  static String _formatModified(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  CalcWorkspaceFile? get _selectedFile {
    if (_selected == _defaultSelection) return null;
    for (final file in _files) {
      if (file.file.path == _selected) return file;
    }
    return null;
  }

  Future<void> _delete(CalcWorkspaceFile workspace) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete workspace?',
      message: 'Delete "${workspace.name}"? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.store.delete(workspace);
      if (!mounted) return;
      setState(() {
        _files.removeWhere((file) => file.file.path == workspace.file.path);
        if (_selected == workspace.file.path) _selected = _defaultSelection;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Delete failed: $error');
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = _selectedFile;
      final String? text;
      if (selected == null) {
        text = await widget.store.readDefault();
      } else {
        text = await widget.store.read(selected.file);
      }
      if (text == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'The default workspace has not been created yet.';
          });
        }
        return;
      }
      widget.controller.session.importWorkspace(text);
      widget.controller.refresh();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Import failed: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.upload, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Import workspace'),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Load a workspace snapshot. This replaces variables, functions, '
              'history, favorites, programs and settings.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RadioGroup<String>(
                      groupValue: _selected,
                      onChanged: (value) {
                        if (value != null) setState(() => _selected = value);
                      },
                      child: ListView(
                        children: [
                          RadioListTile<String>(
                            value: _defaultSelection,
                            dense: true,
                            activeColor: Colors.cyanAccent,
                            title: const Text('Default workspace'),
                            subtitle: Text(
                              _defaultSubtitle,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const Divider(height: 1, color: AppColors.border),
                          if (_files.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No named workspaces yet.',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            for (final workspace in _files)
                              RadioListTile<String>(
                                value: workspace.file.path,
                                dense: true,
                                activeColor: Colors.cyanAccent,
                                title: Text(workspace.name),
                                subtitle: Text(
                                  'Last modified '
                                  '${_formatModified(workspace.modified)}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                secondary: IconButton(
                                  tooltip: 'Delete workspace',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () => _delete(workspace),
                                ),
                              ),
                        ],
                      ),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || _busy ? null : _import,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continue',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Lets the user pick a stored variable and returns its name.
Future<String?> showRecallDialog(
  BuildContext context,
  CalculatorController controller,
) {
  final variables = controller.session.listVariables();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.memory, color: Colors.cyanAccent),
          SizedBox(width: 8),
          Text('Recall variable'),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 400,
        child: variables.isEmpty
            ? const Center(
                child: Text(
                  'No variables stored yet.',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            : ListView(
                children: [
                  for (final entry in variables.entries)
                    ListTile(
                      dense: true,
                      onTap: () => Navigator.of(context).pop(entry.key),
                      title: Text(
                        entry.key,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontFamily: 'monospace',
                        ),
                      ),
                      subtitle: Text(
                        entry.value,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Lists saved favorites and returns the chosen expression.
Future<String?> showFavoritesDialog(
  BuildContext context,
  CalculatorController controller,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final favorites = controller.session.favorites;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.star, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text('Favorites'),
            ],
          ),
          content: SizedBox(
            width: 460,
            height: 420,
            child: favorites.isEmpty
                ? const Center(
                    child: Text(
                      'No favorites yet. Add one from a history entry.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final favorite = favorites[index];
                      return ListTile(
                        dense: true,
                        onTap: () =>
                            Navigator.of(context).pop(favorite.expression),
                        title: Text(
                          favorite.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          favorite.expression,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                        trailing: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete favorite',
                          icon: const Icon(Icons.close, size: 17),
                          onPressed: () {
                            controller.removeFavorite(favorite.id);
                            setState(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

/// The reference charts for component value codes.
const List<({String label, String asset})> _valueCodeCharts = [
  (label: 'Resistor', asset: 'assets/ref/Resistor.png'),
  (label: 'Capacitor', asset: 'assets/ref/Capacitor.png'),
  (label: 'Inductor', asset: 'assets/ref/Inductor.png'),
  (label: 'Inductor color codes', asset: 'assets/ref/InductorColorDot.png'),
];

/// Shows the component value-code reference charts.
Future<void> showValueCodeReferenceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _ValueCodeReferenceDialog(),
  );
}

class _ValueCodeReferenceDialog extends StatelessWidget {
  const _ValueCodeReferenceDialog();

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = (screen.width - 120).clamp(420.0, 1080.0).toDouble();
    final maxHeight = (screen.height - 200).clamp(320.0, 780.0).toDouble();
    // Tab bar, gap and zoom hint below the chart.
    const chromeHeight = 88.0;
    var chartHeight = maxHeight - chromeHeight;
    if (chartHeight < 220) chartHeight = 220;
    var chartWidth = chartHeight * 3 / 2;
    if (chartWidth > maxWidth) {
      chartWidth = maxWidth;
      chartHeight = chartWidth * 2 / 3;
    }
    final contentWidth = chartWidth;
    final contentHeight = chartHeight + chromeHeight;
    return DefaultTabController(
      length: _valueCodeCharts.length,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        title: const Row(
          children: [
            Icon(Icons.menu_book_outlined, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Component value codes'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        content: SizedBox(
          width: contentWidth,
          height: contentHeight,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                tabs: [
                  for (final chart in _valueCodeCharts) Tab(text: chart.label),
                ],
                indicatorColor: Colors.cyanAccent,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white70,
                dividerColor: Colors.transparent,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  // The reference charts are 3:2. Matching that aspect in the
                  // display area makes BoxFit.contain fill the width and avoids
                  // the black side bars.
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: TabBarView(
                      children: [
                        for (final chart in _valueCodeCharts)
                          _ValueCodeChartPage(chart: chart),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Scroll to zoom, drag to pan.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ValueCodeChartPage extends StatelessWidget {
  const _ValueCodeChartPage({required this.chart});

  final ({String label, String asset}) chart;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: InteractiveViewer(
        // Never shrink below the fitted size, and keep the chart inside the
        // viewport: at scale 1 no offset is possible, so zooming out snaps
        // back to the initial size and position.
        minScale: 1,
        maxScale: 8,
        boundaryMargin: EdgeInsets.zero,
        child: SizedBox.expand(
          child: Image.asset(
            chart.asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                'Could not load ${chart.asset}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copies text to the system clipboard and returns a short status message.
Future<String> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  return 'Copied: $text';
}
