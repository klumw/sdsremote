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
    required this.onOpenSettings,
  });

  final CalculatorController controller;
  final ValueChanged<String> onInsert;
  final VoidCallback onAddVariable;
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
                              formula.expression,
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

class CalculatorProgramView extends StatelessWidget {
  const CalculatorProgramView({
    super.key,
    required this.controller,
    required this.editor,
    required this.onRun,
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
    required this.onExportWorkspace,
    required this.onImportWorkspace,
  });

  final CalculatorController controller;
  final TextEditingController editor;
  final VoidCallback onRun;
  final VoidCallback onSave;
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
                  child: TextField(
                    controller: editor,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'R1 = 10 kΩ\n'
                          'C1 = 100 nF\n'
                          'FC = 1 / (2*pi*R1*C1)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
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
