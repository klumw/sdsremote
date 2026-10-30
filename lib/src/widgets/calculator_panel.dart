/// Main UI of the engineering calculator window.
///
/// The widget is presentation only: expression parsing, units, history and
/// persistence live in the calculator engine and session.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_paths.dart';
import '../app/app_theme.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_formulas.dart';
import '../calculator/calc_session.dart';
import '../calculator/calc_value.dart';
import '../calculator/calculator_controller.dart';
import 'calculator_dialogs.dart';
import 'calculator_keypad.dart';
import 'calculator_side_panels.dart';

class CalculatorPanel extends StatefulWidget {
  const CalculatorPanel({super.key, required this.controller});

  final CalculatorController controller;

  @override
  State<CalculatorPanel> createState() => _CalculatorPanelState();
}

class _CalculatorPanelState extends State<CalculatorPanel>
    with SingleTickerProviderStateMixin {
  late final CalculatorController _controller;
  late final TabController _tabs;
  final TextEditingController _expression = TextEditingController();
  final TextEditingController _program = TextEditingController();
  final UndoHistoryController _undo = UndoHistoryController();
  final FocusNode _focus = FocusNode();
  int _historyCursor = -1;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
    _tabs = TabController(length: 4, vsync: this);
    unawaited(_controller.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _tabs.dispose();
    _expression.dispose();
    _program.dispose();
    _undo.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // =========================================================================
  // Build
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _clearAll,
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.panelBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildDisplay(),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF10233D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.calculate, color: Colors.cyanAccent, size: 24),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENGINEERING CALCULATOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Scientific · Units · Complex · Programs',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          if (!_controller.initialized)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.cyanAccent,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Syntax help',
            icon: const Icon(Icons.help_outline, size: 21),
            color: Colors.white70,
            onPressed: _showHelp,
          ),
          IconButton(
            tooltip: 'Calculator settings',
            icon: const Icon(Icons.settings, size: 21),
            color: Colors.white70,
            onPressed: () => showCalculatorSettingsDialog(context, _controller),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplay() {
    final outcome = _controller.lastOutcome;
    final error = outcome?.error;
    final result = _controller.lastSuccess?.display ?? '';
    final settings = _controller.session.settings;

    return Container(
      width: double.infinity,
      color: const Color(0xFF06101F),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _chip(
                settings.angleMode == CalcAngleMode.degrees ? 'DEG' : 'RAD',
                onTap: _controller.toggleAngleMode,
              ),
              const SizedBox(width: 6),
              _chip(
                _formatChip(settings.format),
                onTap: () => showCalculatorSettingsDialog(context, _controller),
              ),
              const SizedBox(width: 6),
              _chip(
                _baseChip(settings.numberBase),
                onTap: _controller.cycleNumberBase,
              ),
              if (_controller.shift) ...[
                const SizedBox(width: 6),
                _chip('SHIFT', active: true, color: Colors.amberAccent),
              ],
              if (_controller.inverse) ...[
                const SizedBox(width: 6),
                _chip('INV', active: true, color: Colors.amberAccent),
              ],
              const Spacer(),
              _iconAction(Icons.undo, 'Undo (Ctrl+Z)', () => _undo.undo()),
              _iconAction(Icons.redo, 'Redo (Ctrl+Y)', () => _undo.redo()),
              _iconAction(Icons.history, 'Previous calculation', () {
                _recallHistory(1);
              }),
              _iconAction(Icons.keyboard_arrow_down, 'Next calculation', () {
                _recallHistory(-1);
              }),
              _iconAction(Icons.content_paste, 'Paste expression', _paste),
              _iconAction(Icons.copy, 'Copy result', _copyResult),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('calculator-expression'),
            controller: _expression,
            focusNode: _focus,
            undoController: _undo,
            textAlign: TextAlign.right,
            maxLines: 1,
            // Keypad taps and mode buttons must not take the focus away from
            // the expression field: on desktop a single-line field selects
            // all of its text when it regains focus, which would make the
            // next key replace the whole expression.
            selectAllOnFocus: false,
            onTapOutside: (_) {},
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontFamily: 'monospace',
              letterSpacing: 0.3,
            ),
            cursorColor: Colors.cyanAccent,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Enter an expression…',
              hintStyle: TextStyle(
                color: Colors.white24,
                fontSize: 18,
                fontFamily: 'monospace',
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
            onSubmitted: (_) => _evaluate(),
            onChanged: (_) {
              if (_historyCursor != -1) setState(() => _historyCursor = -1);
            },
          ),
          if (error != null)
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    error.formattedMessage,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 17,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                _errorChip(error.typeName),
              ],
            )
          else
            SelectableText(
              result.isEmpty ? '0' : result,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: result.isEmpty ? Colors.white30 : Colors.cyanAccent,
                fontSize: 30,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  _secondaryText(outcome),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (outcome?.entry?.formulaName != null)
                Row(
                  children: [
                    const Icon(
                      Icons.functions,
                      size: 12,
                      color: Colors.amberAccent,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      outcome!.entry!.formulaName!,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _secondaryText(CalcOutcome? outcome) {
    if (outcome == null) {
      return 'Enter = evaluate · Esc = clear · Ctrl+Z/Y = undo/redo';
    }
    if (!outcome.ok) {
      return 'Error type: ${outcome.error!.typeName}';
    }
    final entry = outcome.entry;
    if (entry == null) return '';
    final parts = <String>[];
    if (entry.normalized != entry.expression) {
      parts.add('normalized: ${entry.normalized}');
    }
    if (entry.usedVariables.isNotEmpty) {
      parts.add('vars: ${entry.usedVariables.join(', ')}');
    }
    if (entry.assignedVariables.isNotEmpty) {
      parts.add('stored: ${entry.assignedVariables.join(', ')}');
    }
    if (entry.dimension != null && entry.dimension != 'dimensionless') {
      parts.add(entry.dimension!);
    }
    return parts.join(' · ');
  }

  Widget _chip(
    String label, {
    VoidCallback? onTap,
    bool active = false,
    Color? color,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? (color ?? Colors.cyanAccent).withValues(alpha: 0.18)
            : const Color(0xFF0C1A2C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active
              ? (color ?? Colors.cyanAccent)
              : const Color(0xFF2A4160),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? (color ?? Colors.cyanAccent) : Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: content,
    );
  }

  Widget _errorChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback action) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18),
      color: Colors.white54,
      onPressed: action,
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keypad = CalculatorKeypad(
          controller: _controller,
          onInsert: _insert,
          onEvaluate: _evaluate,
          onClear: _clearAll,
          onBackspace: _backspace,
          onSign: _toggleSign,
          onStore: _store,
          onRecall: _recall,
          onUnit: _insertUnit,
          onConvert: _showConvert,
          onHistory: () => _tabs.animateTo(0),
          onVariables: () => _tabs.animateTo(1),
          onFormulas: () => _tabs.animateTo(2),
          onFavorites: _showFavorites,
          onProgram: () => _tabs.animateTo(3),
        );
        final side = _buildSidePanel();
        if (constraints.maxWidth >= 900) {
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(flex: 5, child: keypad),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: side),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(flex: 3, child: keypad),
              const SizedBox(height: 8),
              Expanded(flex: 2, child: side),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1525),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF10233D),
            child: TabBar(
              controller: _tabs,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.cyanAccent,
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.history, size: 18), text: 'History'),
                Tab(icon: Icon(Icons.memory, size: 18), text: 'Variables'),
                Tab(icon: Icon(Icons.functions, size: 18), text: 'Formulas'),
                Tab(icon: Icon(Icons.code, size: 18), text: 'Programs'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                CalculatorHistoryView(
                  controller: _controller,
                  onUseExpression: _useExpression,
                  onCopy: _copyText,
                  onFavorite: _favorite,
                  onExport: _exportHistory,
                  onClear: _confirmClearHistory,
                ),
                CalculatorVariablesView(
                  controller: _controller,
                  onInsert: _insert,
                  onAddVariable: _addVariable,
                  onOpenSettings: () =>
                      showCalculatorSettingsDialog(context, _controller),
                ),
                CalculatorFormulasView(
                  controller: _controller,
                  onOpenFormula: _showFormula,
                ),
                CalculatorProgramView(
                  controller: _controller,
                  editor: _program,
                  onRun: _runProgram,
                  onSave: _saveProgram,
                  onLoad: _loadProgram,
                  onDelete: (id) => _controller.deleteProgram(id),
                  onExportWorkspace: _exportWorkspace,
                  onImportWorkspace: _importWorkspace,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Expression editing
  // =========================================================================

  void _insert(String text) {
    final value = _expression.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    _expression.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _historyCursor = -1;
    _controller.clearModifiers();
    _focus.requestFocus();
  }

  void _backspace() {
    final value = _expression.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    if (selection.start != selection.end) {
      final next = value.text.replaceRange(selection.start, selection.end, '');
      _expression.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    } else if (selection.start > 0) {
      final next = value.text.replaceRange(
        selection.start - 1,
        selection.start,
        '',
      );
      _expression.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: selection.start - 1),
      );
    }
    _focus.requestFocus();
  }

  void _toggleSign() {
    final value = _expression.value;
    final selection = value.selection;
    if (selection.isValid && selection.start != selection.end) {
      final selected = value.text.substring(selection.start, selection.end);
      _insert('-($selected)');
      return;
    }
    if (value.text.isEmpty) {
      _insert('-');
      return;
    }
    if (value.text.startsWith('-')) {
      final next = value.text.substring(1);
      _expression.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: 0),
      );
      _focus.requestFocus();
      return;
    }
    _insert('-');
  }

  void _clearAll() {
    _expression.clear();
    _historyCursor = -1;
    _controller.clearResult();
    _focus.requestFocus();
  }

  void _evaluate() {
    final source = _expression.text.trim();
    if (source.isEmpty) return;
    final outcome = _controller.evaluate(source);
    if (outcome.ok) {
      _expression.clear();
      _historyCursor = -1;
      _controller.clearModifiers();
    }
    _focus.requestFocus();
  }

  void _useExpression(String expression) {
    _expression.value = TextEditingValue(
      text: expression,
      selection: TextSelection.collapsed(offset: expression.length),
    );
    _historyCursor = -1;
    _focus.requestFocus();
  }

  void _recallHistory(int direction) {
    final history = _controller.session.history;
    if (history.isEmpty) return;
    if (direction > 0) {
      if (_historyCursor >= history.length - 1) return;
      _historyCursor++;
    } else {
      if (_historyCursor < 0) return;
      _historyCursor--;
    }
    if (_historyCursor < 0) {
      _useExpression('');
      return;
    }
    _useExpression(history[_historyCursor].expression);
  }

  // =========================================================================
  // Actions
  // =========================================================================

  void _store() {
    final initial = _expression.text.trim().isNotEmpty
        ? _expression.text.trim()
        : (_controller.lastSuccess?.entry?.valueSource ?? '');
    unawaited(
      showStoreDialog(context, _controller, initialExpression: initial),
    );
  }

  void _addVariable() {
    final initial = _expression.text.trim().isNotEmpty
        ? _expression.text.trim()
        : (_controller.lastSuccess?.entry?.valueSource ?? '');
    unawaited(
      showAddVariableDialog(context, _controller, initialExpression: initial),
    );
  }

  void _recall() async {
    final name = await showRecallDialog(context, _controller);
    if (name != null) _insert(name);
  }

  void _insertUnit() async {
    final unit = await showUnitPickerDialog(context, _controller);
    if (unit == null) return;
    final text = _expression.text;
    final needsSpace =
        text.isNotEmpty && !text.endsWith(' ') && !text.endsWith('(');
    _insert(needsSpace ? ' $unit' : unit);
  }

  void _showConvert() async {
    final initial = _expression.text.trim().isNotEmpty
        ? _expression.text.trim()
        : (_controller.lastSuccess?.entry?.valueSource ?? '');
    final result = await showConvertDialog(
      context,
      _controller,
      initialExpression: initial,
    );
    if (result != null) {
      _useExpression(result);
    }
  }

  void _showFormula(CalcFormula formula) async {
    final result = await showFormulaDialog(context, _controller, formula);
    if (result != null) {
      _useExpression(result);
    }
  }

  void _showFavorites() async {
    final expression = await showFavoritesDialog(context, _controller);
    if (expression != null) {
      _useExpression(expression);
    }
  }

  void _favorite(CalcHistoryEntry entry) {
    unawaited(
      showFavoriteDialog(
        context,
        _controller,
        initialName: entry.formulaName ?? entry.expression,
        initialExpression: entry.expression,
      ),
    );
  }

  void _copyResult() {
    final value =
        _controller.lastSuccess?.display ??
        _controller.lastSuccess?.entry?.valueSource;
    if (value == null || value.isEmpty) {
      _snack('There is no result to copy.');
      return;
    }
    _copyText(value);
  }

  void _copyText(String text) async {
    final message = await copyToClipboard(text);
    if (mounted) _snack(message);
  }

  void _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _snack('Clipboard is empty.');
      return;
    }
    _insert(text);
  }

  void _runProgram() {
    final source = _program.text.trim();
    if (source.isEmpty) {
      _snack('The program editor is empty.');
      return;
    }
    _controller.evaluate(source);
  }

  void _saveProgram() {
    final source = _program.text;
    if (source.trim().isEmpty) {
      _snack('The program editor is empty.');
      return;
    }
    unawaited(showSaveProgramDialog(context, _controller, source));
  }

  void _loadProgram(CalcProgram program) {
    _program.text = program.source;
    _program.selection = TextSelection.collapsed(offset: _program.text.length);
  }

  void _exportHistory(String format) {
    final (content, extension) = switch (format) {
      'csv' => (_controller.session.exportHistoryCsv(), 'csv'),
      'json' => (_controller.session.exportHistoryJson(), 'json'),
      _ => (_controller.session.exportHistoryReport(), 'md'),
    };
    unawaited(_writeExport(content, 'calculator_history', extension));
  }

  void _exportWorkspace() {
    unawaited(
      _writeExport(
        _controller.session.exportWorkspace(),
        'calculator_workspace',
        'json',
      ),
    );
  }

  void _importWorkspace() {
    unawaited(showImportWorkspaceDialog(context, _controller));
  }

  Future<void> _writeExport(
    String content,
    String baseName,
    String extension,
  ) async {
    try {
      final directory = await AppPaths.getOrCreateCalculatorDir();
      final file = await AppPaths.getUniqueFilePath(
        directory,
        baseName,
        extension,
      );
      await file.writeAsString(content);
      if (mounted) _snack('Saved ${file.path}');
    } on Object catch (error) {
      if (mounted) _snack('Export failed: $error');
    }
  }

  void _confirmClearHistory() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear history?',
      message: 'All recorded calculations will be removed.',
      confirmLabel: 'Clear',
    );
    if (confirmed) _controller.clearHistory();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // =========================================================================
  // Help
  // =========================================================================

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Calculator syntax'),
          ],
        ),
        content: SizedBox(
          width: 640,
          height: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              _helpText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
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

  static const String _helpText = '''
EXPRESSIONS
  2 + 3 * 4              point before dash
  2^3^2                  power is right-associative (= 512)
  2(3 + 4)               implicit multiplication
  1/2x                   implicit multiplication binds tighter = 1/(2x)
  3!                     factorial
  50%                    percent (0.5)
  [1, 2, 3]              vector; [[1,2],[3,4]] matrix
  v[1]                   first element (indexes start at 1)

UNITS AND PREFIXES
  230 mV / 10 kΩ         → 23 µA
  4.7 kΩ * 2.2 µF        → 10.34 ms
  1 / (2*pi*10 kHz*100 nF)
  3.3 V / 220 Ω
  25 °C to °F            affine temperature conversion
  to(20 dBm, W)          explicit conversion
  value(20 dBm, dBm)     numeric level
  Prefixes: p n µ m k M G T (also f a z y and others).
  A prefixed unit is written without a space: mV, kHz, µF.

COMPLEX NUMBERS
  50 + j25
  (50 + j25) Ω
  75∠30° Ω
  polar(50 + j25)        show polar form
  rect(50 + j25)         show rectangular form
  abs(z), arg(z), conj(z), re(z), im(z)

LEVELS AND dB
  20 dBm + 3 dB          → 23 dBm (level plus gain)
  20 dBm - 5 dBm         → 15 dB (ratio)
  20 dBm + 20 dBm        rejected: two absolute levels
  dBm/dBW are power levels; dBV/dBu/dBµV are voltage levels.
  dBFS is an amplitude ratio relative to full scale; converting it to
  volts needs a full-scale reference: dbfs_to_vrms(level, full_scale).
  dBi/dBd are antenna gains; 0 dBd = 2.15 dBi.

VARIABLES AND FUNCTIONS
  R1 = 10 kΩ
  C1 = 100 nF
  FC = 1 / (2*pi*R1*C1)
  f(x) = x^2 + 1
  f(3)
  Several statements are separated by ";" or a new line.
  Use the Programs tab for multi-line programs.

CONTROL AND NUMERICAL FORMS
  if(condition, then, else)
  for(i, from, to, expression)
  while(condition, expression)
  sum(expression, variable, from, to)      e.g. sum(n^2, n, 1, 10)
  product(expression, variable, from, to)
  integrate(expression, variable, from, to)
  derivative(expression, variable, at)
  solve(expression, variable, guess)       e.g. solve(x^2-4, x, 1)
  solve(expression, variable, low, high)

ENGINEERING FUNCTIONS (selection)
  rc_cutoff(r, c), rl_cutoff(r, l), lc_resonance(l, c), rlc_q(r, l, c)
  impedance_c(c, f), impedance_l(l, f), parallel(a, b), series(a, b)
  fspl(distance, frequency), link_budget(ptx, gtx, grx, lpath, ...)
  vswr(gamma), reflection(z_load, z0), return_loss(gamma)
  dbm_to_vrms(level, z0), vrms_to_dbm(voltage, z0)
  thermal_noise(bw, temperature), noise_floor_dbm(bw, noise_figure)
  thd(fundamental, harmonics), snr_db(signal, noise)
  adc_lsb(bits, vref), adc_snr(bits), quantization_error(lsb)
  pwm_frequency(clock, prescaler, top), uart_baud(clock, oversampling, divisor)
  band, bor, bxor, bnot, shl, shr, popcount, mask, to_signed, hex, bin, oct
  crc8(bytes), crc16_ccitt(bytes), q_format(value, fractional_bits)

DISPLAY
  DEG/RAD selects the angle unit for plain numbers (unit-carrying angles
  are always converted exactly). ENG selects engineering notation with SI
  prefixes; SCI selects scientific notation. DEC/HEX/OCT/BIN controls
  integer display. hex(), bin(), oct() force a base for one result.

KEYBOARD AND SHORTCUTS (main application)
  Enter        evaluate
  Esc          clear the expression and result
  Ctrl+Z/Y     undo/redo in the expression field
  Ctrl+R       open or focus this calculator window (configurable in
               Settings → Calculator)

All results are recorded in the History tab with the normalized expression,
unit, variables used and the formula (when a library formula was run).
''';
}

String _formatChip(CalcNumberFormat format) {
  switch (format) {
    case CalcNumberFormat.auto:
      return 'AUTO';
    case CalcNumberFormat.fixed:
      return 'FIX';
    case CalcNumberFormat.scientific:
      return 'SCI';
    case CalcNumberFormat.engineering:
      return 'ENG';
  }
}

String _baseChip(CalcIntegerBase base) {
  switch (base) {
    case CalcIntegerBase.decimal:
      return 'DEC';
    case CalcIntegerBase.hexadecimal:
      return 'HEX';
    case CalcIntegerBase.octal:
      return 'OCT';
    case CalcIntegerBase.binary:
      return 'BIN';
  }
}
