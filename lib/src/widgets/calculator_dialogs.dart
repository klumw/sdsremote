/// Modal dialogs of the engineering calculator window.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../calculator/calc_error.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_formulas.dart';
import '../calculator/calc_units.dart';
import '../calculator/calc_value.dart';
import '../calculator/calculator_controller.dart';

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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2E),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  formula.expression,
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
                  child: Text(
                    _result!,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 20,
                      fontFamily: 'monospace',
                    ),
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

Future<void> showImportWorkspaceDialog(
  BuildContext context,
  CalculatorController controller,
) async {
  final content = TextEditingController();
  final error = ValueNotifier<String?>(null);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import workspace'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste a workspace JSON document. This replaces variables, '
                'functions, history, favorites and programs.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: content,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{ "version": 1, ... }',
                ),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: error,
                builder: (context, value, _) => value == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          value,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
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
              try {
                controller.session.importWorkspace(content.text);
                controller.refresh();
                Navigator.of(context).pop();
              } on Object catch (exception) {
                error.value = 'Import failed: $exception';
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  } finally {
    content.dispose();
    error.dispose();
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

/// Copies text to the system clipboard and returns a short status message.
Future<String> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  return 'Copied: $text';
}
