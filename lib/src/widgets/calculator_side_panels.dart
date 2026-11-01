/// History, variables, formula-library and program views of the calculator
/// window.
library;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../calculator/calc_format.dart';
import '../calculator/calc_formulas.dart';
import '../calculator/calc_session.dart';
import '../calculator/calculator_controller.dart';

// =============================================================================
// History
// =============================================================================

class CalculatorHistoryView extends StatefulWidget {
  const CalculatorHistoryView({
    super.key,
    required this.controller,
    required this.onUseExpression,
    required this.onCopy,
    required this.onFavorite,
    required this.onExport,
    required this.onClear,
  });

  final CalculatorController controller;
  final ValueChanged<String> onUseExpression;
  final ValueChanged<String> onCopy;
  final ValueChanged<CalcHistoryEntry> onFavorite;
  final ValueChanged<String> onExport;
  final VoidCallback onClear;

  @override
  State<CalculatorHistoryView> createState() => _CalculatorHistoryViewState();
}

class _CalculatorHistoryViewState extends State<CalculatorHistoryView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final entries = widget.controller.session.history
        .where(
          (entry) =>
              query.isEmpty ||
              entry.expression.toLowerCase().contains(query) ||
              entry.normalized.toLowerCase().contains(query) ||
              entry.result.toLowerCase().contains(query) ||
              (entry.formulaName?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Filter history',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Export history',
                icon: const Icon(Icons.download, size: 20),
                onSelected: widget.onExport,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                  PopupMenuItem(value: 'json', child: Text('Export JSON')),
                  PopupMenuItem(value: 'report', child: Text('Export report')),
                ],
              ),
              IconButton(
                tooltip: 'Clear history',
                icon: const Icon(Icons.delete_sweep, size: 20),
                onPressed: widget.onClear,
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const _EmptyHint(
                  icon: Icons.history,
                  text: 'No calculations yet.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _HistoryTile(
                      entry: entry,
                      onUse: () => widget.onUseExpression(entry.expression),
                      onCopy: () => widget.onCopy(entry.result),
                      onFavorite: () => widget.onFavorite(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onUse,
    required this.onCopy,
    required this.onFavorite,
  });

  final CalcHistoryEntry entry;
  final VoidCallback onUse;
  final VoidCallback onCopy;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0E1C30),
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onUse,
                    child: Text(
                      entry.expression,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy result',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: onCopy,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Add to favorites',
                  icon: const Icon(
                    Icons.star_border,
                    size: 16,
                    color: Colors.amberAccent,
                  ),
                  onPressed: onFavorite,
                ),
              ],
            ),
            InkWell(
              onTap: onCopy,
              child: Text(
                entry.result,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (entry.formulaName != null) ...[
                  const Icon(
                    Icons.functions,
                    size: 12,
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      entry.formulaName!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _formatTimestamp(entry.timestamp),
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
                if (entry.unit != null)
                  Text(
                    entry.unit!,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Variables
// =============================================================================

class CalculatorVariablesView extends StatelessWidget {
  const CalculatorVariablesView({
    super.key,
    required this.controller,
    required this.onInsert,
    required this.onAddVariable,
    required this.onClearVariables,
    required this.onOpenSettings,
  });

  final CalculatorController controller;
  final ValueChanged<String> onInsert;
  final VoidCallback onAddVariable;
  final VoidCallback onClearVariables;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final variables = controller.session.listVariables();
    final functions = controller.session.listFunctions();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'VARIABLES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAddVariable,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
            ),
            TextButton.icon(
              onPressed: variables.isEmpty ? null : onClearVariables,
              icon: const Icon(Icons.delete_sweep, size: 16),
              label: const Text('Clear'),
            ),
          ],
        ),
        if (variables.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Assign a value with STO or “name = expression”.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        for (final entry in variables.entries)
          Card(
            color: const Color(0xFF0E1C30),
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              dense: true,
              onTap: () => onInsert(entry.key),
              title: Text(
                entry.key,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                entry.value,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Insert variable',
                    icon: const Icon(Icons.input, size: 17),
                    onPressed: () => onInsert(entry.key),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete variable',
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: () => controller.deleteVariable(entry.key),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'FUNCTIONS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (functions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Define one with “f(x) = x^2 + 1”.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        for (final entry in functions.entries)
          Card(
            color: const Color(0xFF0E1C30),
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: ListTile(
              dense: true,
              onTap: () => onInsert(entry.key),
              title: Text(
                entry.key,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                entry.value,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete function',
                icon: const Icon(Icons.close, size: 17),
                onPressed: () => controller.deleteFunction(entry.key),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF0E1C30),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.settings, size: 18),
            title: const Text(
              'Display settings',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            subtitle: Text(
              '${_formatLabel(controller.session.settings)} · '
              '${controller.session.settings.angleMode.name}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            onTap: onOpenSettings,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Formulas
// =============================================================================

class CalculatorFormulasView extends StatefulWidget {
  const CalculatorFormulasView({
    super.key,
    required this.controller,
    required this.onOpenFormula,
  });

  final CalculatorController controller;
  final ValueChanged<CalcFormula> onOpenFormula;

  @override
  State<CalculatorFormulasView> createState() => _CalculatorFormulasViewState();
}

class _CalculatorFormulasViewState extends State<CalculatorFormulasView> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var formulas = CalcFormulaLibrary.search(_search.text);
    final category = _category;
    if (category != null) {
      formulas = formulas
          .where((formula) => formula.category == category)
          .toList(growable: false);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search formulas',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _category,
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final category in CalcFormulaCategories.all)
                    DropdownMenuItem<String?>(
                      value: category,
                      child: Text(category),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: formulas.isEmpty
              ? const _EmptyHint(
                  icon: Icons.functions,
                  text: 'No formula matches the filter.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: formulas.length,
                  itemBuilder: (context, index) {
                    final formula = formulas[index];
                    return Card(
                      color: const Color(0xFF0E1C30),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        onTap: () => widget.onOpenFormula(formula),
                        title: Text(
                          formula.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formula.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formula.shownExpression,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// Programs
// =============================================================================

/// Program editor controller that highlights the failed token with the same
/// wavy red underline used by the Macro Editor's lint controller.
class ProgramEditorController extends TextEditingController {
  int? _errorStart;
  int? _errorEnd;

  int? get errorStart => _errorStart;
  int? get errorEnd => _errorEnd;

  /// The 1-based line containing [errorStart], if a range is marked.
  int? get errorLine {
    final start = _errorStart;
    if (start == null) return null;
    var line = 1;
    for (var i = 0; i < start && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  void setErrorRange(int? start, int? end) {
    if (start == null || end == null || start < 0 || end <= start) {
      clearError();
      return;
    }
    if (_errorStart == start && _errorEnd == end) return;
    _errorStart = start;
    _errorEnd = end;
    notifyListeners();
  }

  /// Removes the marker without notifying again; callers use this while the
  /// text change that invalidates the marker is already being processed.
  void clearError() {
    _errorStart = null;
    _errorEnd = null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final start = _errorStart;
    final end = _errorEnd;
    final textLength = value.text.length;
    if (start == null ||
        end == null ||
        textLength == 0 ||
        start >= textLength) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final highlightEnd = end > textLength ? textLength : end;
    if (highlightEnd <= start) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final baseStyle = style ?? const TextStyle();
    final errorStyle = baseStyle.merge(
      const TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: Colors.red,
        decorationStyle: TextDecorationStyle.wavy,
      ),
    );
    final children = <TextSpan>[
      if (start > 0)
        TextSpan(text: value.text.substring(0, start), style: baseStyle),
      TextSpan(
        text: value.text.substring(start, highlightEnd),
        style: errorStyle,
      ),
      if (highlightEnd < textLength)
        TextSpan(text: value.text.substring(highlightEnd), style: baseStyle),
    ];
    return TextSpan(style: baseStyle, children: children);
  }
}

const TextStyle _programEditorTextStyle = TextStyle(
  color: Colors.white,
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.35,
);

const TextStyle _programGutterTextStyle = TextStyle(
  color: Colors.white38,
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.35,
);

const TextStyle _programGutterErrorStyle = TextStyle(
  color: Colors.red,
  fontFamily: 'monospace',
  fontSize: 12,
  height: 1.35,
);

const double _programEditorTopPadding = 10;
const double _programGutterWidth = 42;
const double _programGutterGap = 6;
const double _programGutterVerticalOffset = -5;

/// Program text field with a gutter of line numbers.
class _ProgramEditorField extends StatefulWidget {
  const _ProgramEditorField({
    required this.controller,
    required this.focusNode,
  });

  final ProgramEditorController controller;
  final FocusNode focusNode;

  @override
  State<_ProgramEditorField> createState() => _ProgramEditorFieldState();
}

class _ProgramEditorFieldState extends State<_ProgramEditorField> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textFieldWidth =
            (constraints.maxWidth - _programGutterWidth - _programGutterGap)
                .clamp(0.0, double.infinity);
        // TextField content padding (10 left/right) and its one-pixel border.
        final contentWidth = (textFieldWidth - 22).clamp(1.0, double.infinity);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: _programGutterWidth,
              decoration: const BoxDecoration(
                color: Color(0xFF081522),
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              child: ClipRect(
                child: CustomPaint(
                  key: const ValueKey('program-line-numbers'),
                  painter: _ProgramLineNumberPainter(
                    controller: widget.controller,
                    scrollController: _scrollController,
                    contentWidth: contentWidth,
                    topPadding: _programEditorTopPadding,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: _programGutterGap),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                scrollController: _scrollController,
                maxLines: null,
                expands: true,
                selectAllOnFocus: false,
                textAlignVertical: TextAlignVertical.top,
                style: _programEditorTextStyle,
                decoration: const InputDecoration(
                  hintText:
                      'R1 = 10 kΩ\n'
                      'C1 = 100 nF\n'
                      'FC = 1 / (2*pi*R1*C1)',
                  hintStyle: TextStyle(
                    color: Colors.white24,
                    fontStyle: FontStyle.italic,
                  ),
                  contentPadding: EdgeInsets.fromLTRB(
                    10,
                    _programEditorTopPadding,
                    10,
                    10,
                  ),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProgramLineNumberPainter extends CustomPainter {
  _ProgramLineNumberPainter({
    required this.controller,
    required this.scrollController,
    required this.contentWidth,
    required this.topPadding,
    required this.textScaler,
  }) : super(repaint: Listenable.merge([controller, scrollController]));

  final ProgramEditorController controller;
  final ScrollController scrollController;
  final double contentWidth;
  final double topPadding;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final source = controller.text.isEmpty ? ' ' : controller.text;
    final metricsPainter = TextPainter(
      text: TextSpan(text: source, style: _programEditorTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: contentWidth);
    final metrics = metricsPainter.computeLineMetrics();
    final scrollOffset = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    final errorLine = controller.errorLine;

    var logicalLine = 1;
    for (var i = 0; i < metrics.length; i++) {
      final startsLogicalLine = i == 0 || metrics[i - 1].hardBreak;
      if (!startsLogicalLine) continue;
      final metric = metrics[i];
      // Align the top of the number with the top of the visual line. Aligning
      // baselines would shift the digits down by the line's leading.
      final y =
          topPadding +
          metric.baseline -
          metric.ascent -
          scrollOffset +
          _programGutterVerticalOffset;
      if (y + metric.height >= 0 && y <= size.height) {
        final style = logicalLine == errorLine
            ? _programGutterErrorStyle
            : _programGutterTextStyle;
        final numberPainter = TextPainter(
          text: TextSpan(text: '$logicalLine', style: style),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
        numberPainter.paint(
          canvas,
          Offset(size.width - 8 - numberPainter.width, y),
        );
        numberPainter.dispose();
      }
      logicalLine++;
    }

    metricsPainter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ProgramLineNumberPainter oldDelegate) {
    return oldDelegate.controller != controller ||
        oldDelegate.scrollController != scrollController ||
        oldDelegate.contentWidth != contentWidth ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.textScaler != textScaler;
  }
}

class CalculatorProgramView extends StatelessWidget {
  const CalculatorProgramView({
    super.key,
    required this.controller,
    required this.editor,
    required this.focusNode,
    required this.onRun,
    required this.onSave,
    required this.onInsertUnit,
    required this.onLoad,
    required this.onDelete,
    required this.onExportWorkspace,
    required this.onImportWorkspace,
  });

  final CalculatorController controller;
  final ProgramEditorController editor;
  final FocusNode focusNode;
  final VoidCallback onRun;
  final VoidCallback onSave;
  final VoidCallback onInsertUnit;
  final ValueChanged<CalcProgram> onLoad;
  final ValueChanged<String> onDelete;
  final VoidCallback onExportWorkspace;
  final VoidCallback onImportWorkspace;

  @override
  Widget build(BuildContext context) {
    final programs = controller.session.programs;
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'PROGRAM',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onRun,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Run'),
                    ),
                    IconButton(
                      tooltip: 'Insert unit or Greek symbol',
                      icon: const Text(
                        'Ω',
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 18,
                        ),
                      ),
                      onPressed: onInsertUnit,
                    ),
                    IconButton(
                      tooltip: 'Save program',
                      icon: const Icon(Icons.save, size: 18),
                      onPressed: onSave,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _ProgramEditorField(
                    controller: editor,
                    focusNode: focusNode,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: onExportWorkspace,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Export workspace'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onImportWorkspace,
                      icon: const Icon(Icons.upload, size: 16),
                      label: const Text('Import'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          flex: 2,
          child: programs.isEmpty
              ? const _EmptyHint(
                  icon: Icons.code,
                  text: 'No saved programs yet.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: programs.length,
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    return Card(
                      color: const Color(0xFF0E1C30),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        dense: true,
                        onTap: () => onLoad(program),
                        title: Text(
                          program.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          _formatTimestamp(program.updatedAt),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Load program',
                              icon: const Icon(Icons.edit, size: 17),
                              onPressed: () => onLoad(program),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete program',
                              icon: const Icon(Icons.close, size: 17),
                              onPressed: () => onDelete(program.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared widgets
// =============================================================================

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.white24),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _formatLabel(CalcFormatSettings settings) {
  final format = switch (settings.format) {
    CalcNumberFormat.auto => 'Auto',
    CalcNumberFormat.fixed => 'Fixed ${settings.fractionDigits}',
    CalcNumberFormat.scientific => 'Scientific',
    CalcNumberFormat.engineering => 'Engineering',
  };
  return format;
}
