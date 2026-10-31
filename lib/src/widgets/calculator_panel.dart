/// Main UI of the engineering calculator window.
///
/// The widget is presentation only: expression parsing, units, history and
/// persistence live in the calculator engine and session.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/agents/calculator_agent.dart';
import '../ai/ai_settings.dart';
import '../ai/calculator_chat_controller.dart';
import '../app/app_paths.dart';
import '../app/app_preferences.dart';
import '../app/app_theme.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_formulas.dart';
import '../calculator/calc_session.dart';
import '../calculator/calc_value.dart';
import '../calculator/calculator_controller.dart';
import 'animated_sync_icon.dart';
import 'calculator_chat_panel.dart';
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
  late final CalculatorChatController _chatController;
  late final TabController _tabs;
  final TextEditingController _expression = TextEditingController();
  final ProgramEditorController _program = ProgramEditorController();
  final UndoHistoryController _undo = UndoHistoryController();
  final FocusNode _focus = FocusNode();
  final FocusNode _programFocus = FocusNode();
  String _lastProgramText = '';
  CalcOutcome? _programOutcome;
  String? _programErrorMessage;
  int _historyCursor = -1;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_onControllerChanged);
    _chatController = CalculatorChatController();
    _chatController.addListener(_onControllerChanged);
    _lastProgramText = _program.text;
    _program.addListener(_onProgramChanged);
    _tabs = TabController(length: 4, vsync: this);
    unawaited(_controller.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        unawaited(_loadAiSettings());
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _chatController.removeListener(_onControllerChanged);
    _chatController.dispose();
    _tabs.dispose();
    _expression.dispose();
    _program.removeListener(_onProgramChanged);
    _program.dispose();
    _undo.dispose();
    _focus.dispose();
    _programFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onProgramChanged() {
    if (_program.text == _lastProgramText) return;
    _lastProgramText = _program.text;
    _program.clearError();
  }

  CalculatorAgentContext get _aiContext => CalculatorAgentContext(
    session: _controller.session,
    readExpression: () => _expression.text,
    readProgram: () => _program.text,
    readVariables: _controller.session.listVariables,
    readFunctions: _controller.session.listFunctions,
    readSettings: () => _controller.session.settings,
  );

  Future<void> _loadAiSettings() async {
    AppPreferences.invalidateCache();
    final provider = await AppPreferences.getString('ai_provider') ?? '';
    final token = await AppPreferences.getString('ai_api_token') ?? '';
    final model = await AppPreferences.getString('llm_model') ?? '';
    final settings =
        provider.trim().isNotEmpty &&
            token.trim().length >= 8 &&
            model.trim().isNotEmpty
        ? AiSettings.fromProviderConfig(
            providerName: provider,
            apiToken: token,
            modelName: model,
          )
        : null;
    if (!mounted) return;
    _chatController.configure(settings, context: _aiContext);
  }

  void _toggleCalculatorChat() {
    if (_chatController.isOpen) {
      _closeCalculatorChat();
      return;
    }
    unawaited(_loadAiSettings());
    _chatController.toggleOpen();
  }

  void _closeCalculatorChat() {
    _chatController.close();
    _focus.requestFocus();
  }

  Future<void> _applyChatProgram(String code) async {
    if (_program.text.trim().isNotEmpty) {
      final replace = await showConfirmDialog(
        context,
        title: 'Replace program?',
        message:
            'The Programs editor already contains code. Replace it with the '
            "assistant's code block? The previous program will be lost.",
        confirmLabel: 'Replace',
      );
      if (!replace || !mounted) return;
    }
    _program.text = code;
    _program.selection = TextSelection.collapsed(offset: code.length);
    _tabs.animateTo(3);
    _snack('Program inserted. Review it and press Run.');
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
            const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
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
            child: Text(
              'ENGINEERING CALCULATOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (!_controller.initialized)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: AnimatedSyncIcon(size: 16, color: Colors.cyanAccent),
            ),
          _buildAiButton(),
          IconButton(
            tooltip: 'Component value codes',
            icon: const Icon(Icons.menu_book_outlined, size: 21),
            color: Colors.white70,
            onPressed: () => showValueCodeReferenceDialog(context),
          ),
          IconButton(
            tooltip: 'Sensor calibration',
            icon: const Icon(Icons.linear_scale, size: 21),
            color: Colors.white70,
            onPressed: () => showSensorCalibrationDialog(context),
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

  Widget _buildAiButton() {
    final active = _chatController.isOpen;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: active
            ? Colors.cyanAccent.withValues(alpha: 0.14)
            : Colors.transparent,
        border: Border.all(
          color: active ? Colors.cyanAccent : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: IconButton(
        tooltip: 'Calculator AI assistant',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.auto_awesome, size: 20),
        color: active ? Colors.cyanAccent : Colors.white70,
        onPressed: _toggleCalculatorChat,
      ),
    );
  }

  Widget _buildDisplay() {
    final outcome = _controller.lastOutcome;
    final error = outcome?.error;
    final errorMessage = identical(outcome, _programOutcome)
        ? (_programErrorMessage ?? error?.formattedMessage)
        : error?.formattedMessage;
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
                _angleChip(settings.angleMode),
                onTap: _controller.cycleAngleMode,
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
                    errorMessage ?? error.formattedMessage,
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
        final wide = constraints.maxWidth >= 900;
        final content = wide
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(flex: 5, child: keypad),
                    const SizedBox(width: 10),
                    Expanded(flex: 4, child: side),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Expanded(flex: 3, child: keypad),
                    const SizedBox(height: 8),
                    Expanded(flex: 2, child: side),
                  ],
                ),
              );
        final chatWidth = wide
            ? (constraints.maxWidth * 0.55).clamp(480.0, 640.0).toDouble()
            : constraints.maxWidth;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOutCubic,
                left: _chatController.isOpen ? 0 : -chatWidth - 16,
                top: 0,
                bottom: 0,
                width: chatWidth,
                child: IgnorePointer(
                  ignoring: !_chatController.isOpen,
                  child: CalculatorChatPanel(
                    controller: _chatController,
                    calculatorController: _controller,
                    onClose: _closeCalculatorChat,
                    onReloadSettings: () => unawaited(_loadAiSettings()),
                    onInsertExpression: _useExpression,
                    onStoreResult: (source) => unawaited(
                      showStoreDialog(
                        context,
                        _controller,
                        initialExpression: source,
                      ),
                    ),
                    onApplyProgram: _applyChatProgram,
                  ),
                ),
              ),
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
                  onClearVariables: _confirmClearVariables,
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
                  focusNode: _programFocus,
                  onRun: _runProgram,
                  onSave: _saveProgram,
                  onInsertUnit: _insertProgramUnit,
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

  void _handleEscape() {
    if (_chatController.isOpen) {
      _closeCalculatorChat();
      return;
    }
    _clearAll();
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

  void _useExpression(String expression, {bool resetHistoryCursor = true}) {
    _expression.value = TextEditingValue(
      text: expression,
      selection: TextSelection.collapsed(offset: expression.length),
    );
    if (resetHistoryCursor) _historyCursor = -1;
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
    _useExpression(
      history[_historyCursor].expression,
      resetHistoryCursor: false,
    );
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

  void _confirmClearVariables() async {
    final variables = _controller.session.listVariables();
    if (variables.isEmpty) {
      _snack('There are no variables to clear.');
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear variables?',
      message:
          'All ${variables.length} stored variables will be removed. '
          'User-defined functions and history are kept.',
      confirmLabel: 'Clear variables',
    );
    if (!confirmed || !mounted) return;
    _controller.clearAllVariables();
    _snack('All variables cleared.');
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

  Future<void> _insertProgramUnit() async {
    final symbol = await showUnitPickerDialog(context, _controller);
    if (!mounted) return;
    if (symbol != null) {
      final value = _program.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      _program.value = TextEditingValue(
        text: value.text.replaceRange(start, end, symbol),
        selection: TextSelection.collapsed(offset: start + symbol.length),
      );
    }
    _programFocus.requestFocus();
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
    final original = _program.text;
    final source = original.trim();
    if (source.isEmpty) {
      _snack('The program editor is empty.');
      return;
    }
    final outcome = _controller.evaluate(source);
    final error = outcome.error;
    final location = _programErrorLocation(original, error?.position);
    _programOutcome = outcome;
    _programErrorMessage = error != null && location != null
        ? 'Line ${location.line}, column ${location.column}: ${error.message}'
        : null;
    _program.setErrorRange(location?.start, location?.end);
  }

  /// Maps an error offset in the trimmed program back to its source location
  /// and expands it to the token that should be underlined.
  ({int line, int column, int start, int end})? _programErrorLocation(
    String original,
    int? position,
  ) {
    if (position == null || original.isEmpty) return null;
    final leading = original.length - original.trimLeft().length;
    final offset = (leading + position).clamp(0, original.length).toInt();

    var start = offset < original.length
        ? offset
        : _previousContentChar(original, original.length - 1);
    if (start >= 0 && _isProgramWhitespace(original.codeUnitAt(start))) {
      final previous = _previousContentChar(original, start);
      final next = _nextContentChar(original, start);
      start = previous >= 0 ? previous : next;
    }
    if (start < 0) return null;

    var end = start + 1;
    if (_isProgramWordChar(original.codeUnitAt(start))) {
      while (end < original.length &&
          _isProgramWordChar(original.codeUnitAt(end))) {
        end++;
      }
    }

    var line = 1;
    for (var i = 0; i < start; i++) {
      if (original.codeUnitAt(i) == 0x0A) line++;
    }
    final previousNewline = start == 0
        ? -1
        : original.lastIndexOf('\n', start - 1);
    final column = start - previousNewline;
    return (line: line, column: column, start: start, end: end);
  }

  int _previousContentChar(String text, int from) {
    for (var i = from; i >= 0; i--) {
      if (!_isProgramWhitespace(text.codeUnitAt(i))) return i;
    }
    return -1;
  }

  int _nextContentChar(String text, int from) {
    for (var i = from; i < text.length; i++) {
      if (!_isProgramWhitespace(text.codeUnitAt(i))) return i;
    }
    return -1;
  }

  bool _isProgramWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

  bool _isProgramWordChar(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F ||
      code > 0x7F;

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
  2 + 3 * 4              multiplication before addition
  2^3^2                  power is right-associative (= 512)
  2(3 + 4)               implicit multiplication
  x = 4; 1/2x            implicit multiplication binds tighter = 1/(2x)
  3!                     factorial
  200*50%                percent (= 100)
  [1, 2, 3]              vector; [[1,2],[3,4]] matrix
  v[1]                   first element (indexes start at 1)
  Use "." for decimals; "1,5" is invalid. Commas separate arguments.

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
  UNIT opens the unit list and a palette of Greek unit symbols:
  µ (micro), μ (Greek mu), Ω (ohm), ° (degree), Å (angstrom).
  The same picker is available in the Programs tab via the Ω button.

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
  The Variables tab can add a variable or clear all stored variables;
  functions and history are kept.
  Use the Programs tab for multi-line programs. The editor has a line-
  number gutter. If Run fails, the error names the line and column, the
  failing line number turns red and the faulty token gets a wavy red
  underline; editing clears the underline.

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
  DEG/RAD/GRAD cycles degrees, radians and gradians (gon) for plain
  numbers; unit-carrying angles are always converted exactly. The format key cycles AUTO -> ENG -> FIXED
  -> SCI: AUTO chooses the most readable form, ENG always uses engineering
  notation with SI prefixes, FIXED uses the configured decimal places and
  SCI uses scientific notation. DEC/HEX/OCT/BIN controls integer display.
  hex(), bin(), oct() force a base for one result.

KEYBOARD AND SHORTCUTS (main application)
  Enter        evaluate
  Esc          close the AI panel first; otherwise clear expression/result
  Ctrl+Z/Y     undo/redo in the expression field
  Ctrl+R       open or focus this calculator window (configurable in
               Settings → Calculator)

AI ASSISTANT (optional)
  The sparkle button next to this help button opens the Calculator AI
  panel. Configure provider, token and model in SDS-Remote Settings.
  The assistant uses the deterministic engine and asks for missing
  values. It can read the current expression, program and variables
  read-only. Results appear as numbered footnotes [1], [2], ... in the
  answer. Right-click a footnote for Copy, Insert result, Use in
  program or Use as variable; hovering it shows the result and the
  calculation.

All results are recorded in the History tab with the normalized expression,
unit, variables used and the formula (when a library formula was run).
''';
}

String _angleChip(CalcAngleMode mode) {
  switch (mode) {
    case CalcAngleMode.degrees:
      return 'DEG';
    case CalcAngleMode.radians:
      return 'RAD';
    case CalcAngleMode.gradians:
      return 'GRAD';
  }
}

String _formatChip(CalcNumberFormat format) {
  switch (format) {
    case CalcNumberFormat.auto:
      return 'AUTO';
    case CalcNumberFormat.fixed:
      return 'FIXED';
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
