/// Persistent calculator workspace: variables, functions, history, favorites,
/// saved programs and display settings.
///
/// The session is UI-independent. The calculator window and the AI tool use
/// the same class, so both see identical evaluation rules and state.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/app_paths.dart';
import 'calc_error.dart';
import 'calc_format.dart';
import 'calc_formulas.dart';
import 'calc_engine.dart';
import 'calc_units.dart';
import 'calc_value.dart';

/// One completed calculation in the history.
class CalcHistoryEntry {
  const CalcHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.expression,
    required this.normalized,
    required this.result,
    required this.valueSource,
    this.unit,
    this.dimension,
    this.usedVariables = const [],
    this.assignedVariables = const [],
    this.formulaId,
    this.formulaName,
    this.formulaExpression,
    this.formulaInputs = const {},
    this.assumptions = const [],
  });

  final String id;
  final DateTime timestamp;
  final String expression;
  final String normalized;
  final String result;

  /// Parseable source of the value, used to restore workspace state.
  final String valueSource;

  final String? unit;
  final String? dimension;
  final List<String> usedVariables;
  final List<String> assignedVariables;

  final String? formulaId;
  final String? formulaName;
  final String? formulaExpression;
  final Map<String, String> formulaInputs;
  final List<String> assumptions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'expression': expression,
    'normalized': normalized,
    'result': result,
    'valueSource': valueSource,
    if (unit != null) 'unit': unit,
    if (dimension != null) 'dimension': dimension,
    'usedVariables': usedVariables,
    'assignedVariables': assignedVariables,
    if (formulaId != null) 'formulaId': formulaId,
    if (formulaName != null) 'formulaName': formulaName,
    if (formulaExpression != null) 'formulaExpression': formulaExpression,
    if (formulaInputs.isNotEmpty) 'formulaInputs': formulaInputs,
    if (assumptions.isNotEmpty) 'assumptions': assumptions,
  };

  static CalcHistoryEntry fromJson(Map<String, dynamic> json) {
    return CalcHistoryEntry(
      id: json['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expression: json['expression'] as String? ?? '',
      normalized: json['normalized'] as String? ?? '',
      result: json['result'] as String? ?? '',
      valueSource: json['valueSource'] as String? ?? '',
      unit: json['unit'] as String?,
      dimension: json['dimension'] as String?,
      usedVariables: CalcSession._stringList(json['usedVariables']),
      assignedVariables: CalcSession._stringList(json['assignedVariables']),
      formulaId: json['formulaId'] as String?,
      formulaName: json['formulaName'] as String?,
      formulaExpression: json['formulaExpression'] as String?,
      formulaInputs: CalcSession._stringMap(json['formulaInputs']),
      assumptions: CalcSession._stringList(json['assumptions']),
    );
  }
}

/// A saved expression that can be recalled quickly.
class CalcFavorite {
  const CalcFavorite({
    required this.id,
    required this.name,
    required this.expression,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String expression;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'expression': expression,
    'createdAt': createdAt.toIso8601String(),
  };

  static CalcFavorite fromJson(Map<String, dynamic> json) => CalcFavorite(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    expression: json['expression'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// A reusable multi-statement calculator program.
class CalcProgram {
  const CalcProgram({
    required this.id,
    required this.name,
    required this.source,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String source;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static CalcProgram fromJson(Map<String, dynamic> json) => CalcProgram(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    source: json['source'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Result of one evaluation.
class CalcOutcome {
  const CalcOutcome.success(this.evaluation, this.entry) : error = null;

  const CalcOutcome.failure(this.error) : evaluation = null, entry = null;

  final CalcEvaluation? evaluation;
  final CalcHistoryEntry? entry;
  final CalcException? error;

  bool get ok => error == null;

  String get display => entry?.result ?? (error?.formattedMessage ?? '');
}

/// The calculator workspace shared by the UI and the AI tool.
class CalcSession {
  CalcSession({this.storageFile, this.autoSave = false});

  /// A session without persistence, used by tests and by callers that only
  /// need a scratch calculator.
  CalcSession.memory() : this(storageFile: null);

  /// A session backed by the standard application workspace file.
  factory CalcSession.withDefaultStorage({bool autoSave = true}) {
    return CalcSession(
      storageFile: AppPaths.calculatorWorkspaceFile,
      autoSave: autoSave,
    );
  }

  static const int historyLimit = 300;

  final CalcEngine engine = CalcEngine();
  final List<CalcHistoryEntry> history = [];
  final List<CalcFavorite> favorites = [];
  final List<CalcProgram> programs = [];
  final Map<String, String> variableSources = {};

  File? storageFile;
  final bool autoSave;

  String? lastLoadError;
  String? lastSaveError;

  int _idCounter = 0;
  Future<void>? _saveInFlight;

  CalcFormatSettings get settings => engine.settings;

  set settings(CalcFormatSettings value) {
    engine.settings = value;
    _scheduleSave();
  }

  CalcFormatter get formatter => CalcFormatter(engine.settings);

  /// Evaluates [source] and records the result in the history.
  CalcOutcome evaluate(String source) {
    try {
      final evaluation = engine.evaluate(source);
      _syncAssignedVariables(evaluation.assignedVariables);
      final entry = _record(evaluation, original: source.trim());
      _scheduleSave();
      return CalcOutcome.success(evaluation, entry);
    } on CalcException catch (error) {
      return CalcOutcome.failure(error);
    } on Object catch (error) {
      return CalcOutcome.failure(
        unsupportedError('internal calculator error: $error'),
      );
    }
  }

  /// Runs a library formula with optional input expressions.
  CalcOutcome runFormula(
    CalcFormula formula, [
    Map<String, String> inputExpressions = const {},
  ]) {
    try {
      final values = <String, CalcValue>{};
      final usedExpressions = <String, String>{};
      for (final input in formula.inputs) {
        final expression =
            inputExpressions[input.name]?.trim().isNotEmpty == true
            ? inputExpressions[input.name]!.trim()
            : input.defaultExpression;
        usedExpressions[input.name] = expression;
        final inputResult = engine.evaluate(expression);
        _syncAssignedVariables(inputResult.assignedVariables);
        values[input.name] = inputResult.value;
      }
      final evaluation = engine.evaluateWithInputs(formula.expression, values);
      _syncAssignedVariables(evaluation.assignedVariables);
      final entry = _record(
        evaluation,
        original: formula.expression,
        formulaId: formula.id,
        formulaName: formula.name,
        formulaExpression: formula.expression,
        formulaInputs: usedExpressions,
        assumptions: formula.assumptions,
      );
      _scheduleSave();
      return CalcOutcome.success(evaluation, entry);
    } on CalcException catch (error) {
      return CalcOutcome.failure(error);
    } on Object catch (error) {
      return CalcOutcome.failure(
        unsupportedError('internal calculator error: $error'),
      );
    }
  }

  /// Defines a variable from an expression, e.g. `R1` and `10 kΩ`.
  CalcOutcome defineVariable(String name, String expression) =>
      evaluate('$name = $expression');

  void deleteVariable(String name) {
    engine.variables.remove(name);
    variableSources.remove(name);
    _scheduleSave();
  }

  /// Removes every stored variable. Functions and history are kept.
  void clearVariables() {
    engine.variables.clear();
    variableSources.clear();
    _scheduleSave();
  }

  void deleteFunction(String name) {
    engine.functions.remove(name);
    _scheduleSave();
  }

  /// A copy of all global variables formatted for display.
  Map<String, String> listVariables() {
    final names = engine.variables.keys.toList()..sort();
    final result = <String, String>{};
    for (final name in names) {
      try {
        result[name] = formatter.format(engine.variables[name]!);
      } on Object {
        result[name] = engine.variables[name]!.toSource();
      }
    }
    return result;
  }

  /// A copy of all user functions with their normalized source.
  Map<String, String> listFunctions() {
    final names = engine.functions.keys.toList()..sort();
    return {for (final name in names) name: engine.functions[name]!.source};
  }

  String? variableSource(String name) => variableSources[name];

  void clearHistory() {
    history.clear();
    _scheduleSave();
  }

  void addFavorite(String name, String expression) {
    final trimmedName = name.trim().isEmpty ? expression.trim() : name.trim();
    favorites.insert(
      0,
      CalcFavorite(
        id: _nextId(),
        name: trimmedName,
        expression: expression.trim(),
        createdAt: DateTime.now(),
      ),
    );
    _scheduleSave();
  }

  void removeFavorite(String id) {
    favorites.removeWhere((favorite) => favorite.id == id);
    _scheduleSave();
  }

  CalcProgram saveProgram(String name, String source) {
    final existingIndex = programs.indexWhere(
      (program) => program.name == name,
    );
    final program = CalcProgram(
      id: existingIndex >= 0 ? programs[existingIndex].id : _nextId(),
      name: name.trim().isEmpty ? 'Untitled program' : name.trim(),
      source: source,
      updatedAt: DateTime.now(),
    );
    if (existingIndex >= 0) {
      programs[existingIndex] = program;
    } else {
      programs.insert(0, program);
    }
    _scheduleSave();
    return program;
  }

  void deleteProgram(String id) {
    programs.removeWhere((program) => program.id == id);
    _scheduleSave();
  }

  void setAngleMode(CalcAngleMode mode) {
    settings = settings.copyWith(angleMode: mode);
  }

  void setNumberFormat(CalcNumberFormat format) {
    settings = settings.copyWith(format: format);
  }

  void setNumberBase(CalcIntegerBase base) {
    settings = settings.copyWith(numberBase: base);
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  String exportHistoryCsv() {
    final buffer = StringBuffer()
      ..writeln(
        'timestamp,expression,normalized,result,unit,formula,assumptions',
      );
    for (final entry in history) {
      buffer.writeln(
        [
          entry.timestamp.toIso8601String(),
          entry.expression,
          entry.normalized,
          entry.result,
          entry.unit ?? '',
          entry.formulaName ?? '',
          entry.assumptions.join('; '),
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  String exportHistoryJson() {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(history.map((entry) => entry.toJson()).toList());
  }

  String exportHistoryReport() {
    final buffer = StringBuffer()
      ..writeln('# Engineering Calculator Report')
      ..writeln()
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln();
    for (final entry in history.reversed) {
      buffer
        ..writeln('## ${entry.expression}')
        ..writeln()
        ..writeln('- Result: `${entry.result}`')
        ..writeln('- Normalized: `${entry.normalized}`');
      if (entry.unit != null) {
        buffer.writeln('- Unit: ${entry.unit}');
      }
      if (entry.usedVariables.isNotEmpty) {
        buffer.writeln('- Variables: ${entry.usedVariables.join(', ')}');
      }
      if (entry.formulaName != null) {
        buffer.writeln('- Formula: ${entry.formulaName}');
      }
      for (final assumption in entry.assumptions) {
        buffer.writeln('- Assumption: $assumption');
      }
      buffer
        ..writeln()
        ..writeln('Timestamp: ${entry.timestamp.toIso8601String()}')
        ..writeln();
    }
    return buffer.toString();
  }

  String exportWorkspace() =>
      const JsonEncoder.withIndent('  ').convert(_workspaceJson());

  /// Replaces the workspace with [jsonText]. Throws [FormatException] or
  /// [CalcException] when the document is invalid.
  void importWorkspace(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('workspace must be a JSON object');
    }
    _clearWorkspace();
    _applyWorkspace(decoded);
    _scheduleSave();
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> load() async {
    final file = storageFile;
    if (file == null) return;
    lastLoadError = null;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('workspace must be a JSON object');
      }
      _clearWorkspace();
      _applyWorkspace(decoded);
    } on Object catch (error) {
      lastLoadError = error.toString();
    }
  }

  Future<void> save() async {
    final file = storageFile;
    if (file == null) return;
    final inFlight = _saveInFlight;
    if (inFlight != null) {
      await inFlight;
      return save();
    }
    final future = _writeWorkspace(file);
    _saveInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_saveInFlight, future)) _saveInFlight = null;
    }
  }

  Future<void> _writeWorkspace(File file) async {
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_workspaceJson()),
        flush: true,
      );
      await temporary.rename(file.path);
      lastSaveError = null;
    } on Object catch (error) {
      lastSaveError = error.toString();
    }
  }

  Map<String, dynamic> _workspaceJson() {
    return {
      'version': 1,
      'settings': engine.settings.toJson(),
      'variables': [
        for (final entry in variableSources.entries)
          {'name': entry.key, 'source': entry.value},
      ],
      'functions': [
        for (final function in engine.functions.values) function.source,
      ],
      'history': history.map((entry) => entry.toJson()).toList(),
      'favorites': favorites.map((favorite) => favorite.toJson()).toList(),
      'programs': programs.map((program) => program.toJson()).toList(),
    };
  }

  void _clearWorkspace() {
    engine.variables.clear();
    engine.functions.clear();
    variableSources.clear();
    history.clear();
    favorites.clear();
    programs.clear();
    engine.lastAnswer = null;
  }

  void _applyWorkspace(Map<String, dynamic> json) {
    final settings = json['settings'];
    if (settings is Map) {
      engine.settings = CalcFormatSettings.fromJson(
        settings.cast<String, dynamic>(),
      );
    }

    final functions = json['functions'];
    if (functions is List) {
      for (final source in functions) {
        if (source is! String || source.trim().isEmpty) continue;
        try {
          engine.evaluate(source);
        } on CalcException catch (error) {
          lastLoadError = 'function skipped: ${error.message}';
        }
      }
    }

    final variables = json['variables'];
    if (variables is List) {
      final pending = <({String name, String source})>[];
      for (final item in variables) {
        if (item is! Map) continue;
        final entry = item.cast<String, dynamic>();
        final name = entry['name'];
        final source = entry['source'];
        if (name is! String || source is! String) continue;
        pending.add((name: name, source: source));
      }
      // Variables may reference each other; retry unresolved entries so a
      // workspace does not depend on the order in which it was written.
      for (var pass = 0; pass < 4 && pending.isNotEmpty; pass++) {
        final failed = <({String name, String source})>[];
        for (final entry in pending) {
          try {
            final value = engine.evaluate(entry.source).value;
            engine.variables[entry.name] = value;
            variableSources[entry.name] = entry.source;
          } on CalcException catch (error) {
            lastLoadError = 'variable ${entry.name} skipped: ${error.message}';
            failed.add(entry);
          }
        }
        if (failed.length == pending.length) break;
        pending
          ..clear()
          ..addAll(failed);
      }
    }

    final storedHistory = json['history'];
    if (storedHistory is List) {
      for (final item in storedHistory) {
        if (item is Map) {
          history.add(CalcHistoryEntry.fromJson(item.cast<String, dynamic>()));
        }
      }
      if (history.length > historyLimit) {
        history.removeRange(historyLimit, history.length);
      }
    }

    final storedFavorites = json['favorites'];
    if (storedFavorites is List) {
      for (final item in storedFavorites) {
        if (item is Map) {
          favorites.add(CalcFavorite.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final storedPrograms = json['programs'];
    if (storedPrograms is List) {
      for (final item in storedPrograms) {
        if (item is Map) {
          programs.add(CalcProgram.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
  }

  void _scheduleSave() {
    if (!autoSave || storageFile == null) return;
    unawaited(
      save().catchError((Object error) {
        lastSaveError = error.toString();
      }),
    );
  }

  void _syncAssignedVariables(Set<String> assigned) {
    for (final name in assigned) {
      final value = engine.variables[name];
      if (value == null) {
        variableSources.remove(name);
      } else {
        variableSources[name] = value.toSource();
      }
    }
  }

  CalcHistoryEntry _record(
    CalcEvaluation evaluation, {
    required String original,
    String? formulaId,
    String? formulaName,
    String? formulaExpression,
    Map<String, String> formulaInputs = const {},
    List<String> assumptions = const [],
  }) {
    final value = evaluation.value;
    String result;
    try {
      result = formatter.format(value);
    } on Object {
      result = value.toSource();
    }
    final unit = formatter.unitSymbol(value);
    final dimension = value is CalcQuantity ? value.dimension.describe() : null;

    final entry = CalcHistoryEntry(
      id: _nextId(),
      timestamp: DateTime.now(),
      expression: original,
      normalized: evaluation.normalized,
      result: result,
      valueSource: value.toSource(),
      unit: unit,
      dimension: dimension,
      usedVariables: evaluation.usedVariables.toList()..sort(),
      assignedVariables: evaluation.assignedVariables.toList()..sort(),
      formulaId: formulaId,
      formulaName: formulaName,
      formulaExpression: formulaExpression,
      formulaInputs: Map.unmodifiable(formulaInputs),
      assumptions: List.unmodifiable(assumptions),
    );
    history.insert(0, entry);
    if (history.length > historyLimit) {
      history.removeRange(historyLimit, history.length);
    }
    return entry;
  }

  String _nextId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  // -------------------------------------------------------------------------
  // Convenience queries for the UI and the AI tool
  // -------------------------------------------------------------------------

  List<CalcHistoryEntry> recentHistory([int limit = 20]) =>
      history.take(limit).toList(growable: false);

  List<String> commonUnits() => CalcUnits.commonSymbols;

  List<CalcFormula> formulas() => CalcFormulaLibrary.formulas;

  CalcFormula? formulaById(String id) => CalcFormulaLibrary.find(id);

  CalcValue? variableValue(String name) => engine.variables[name];

  static String _csvCell(String value) {
    if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', '$item'));
    }
    return const {};
  }
}
