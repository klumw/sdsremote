/// JSON-facing facade over the calculator engine and workspace.
///
/// The calculator window uses [CalcSession] directly; this facade is the
/// stable API for an AI agent (and for tests). Every method returns ordinary
/// JSON-compatible maps instead of Dart objects, so a tool implementation only
/// has to serialize the result.
library;

import 'calc_engine.dart';
import 'calc_error.dart';
import 'calc_format.dart';
import 'calc_formulas.dart';
import 'calc_session.dart';
import 'calc_units.dart';
import 'calc_value.dart';

/// Machine-readable calculator API.
class CalculatorService {
  CalculatorService({CalcSession? session})
    : session = session ?? CalcSession.memory();

  final CalcSession session;

  /// Evaluates one expression or a multi-statement program.
  Map<String, dynamic> evaluate(String expression) {
    return _outcomeToJson(session.evaluate(expression));
  }

  /// Defines a named variable, e.g. `R1` from `10 kΩ`.
  Map<String, dynamic> defineVariable(String name, String expression) {
    return _outcomeToJson(session.defineVariable(name, expression));
  }

  /// Removes a variable from the workspace.
  Map<String, dynamic> deleteVariable(String name) {
    session.deleteVariable(name);
    return {'ok': true, 'deleted': name};
  }

  /// Runs a formula from the library.
  Map<String, dynamic> runFormula(
    String formulaId, [
    Map<String, String> inputs = const {},
  ]) {
    final formula = session.formulaById(formulaId);
    if (formula == null) {
      return {
        'ok': false,
        'error': 'unknown formula "$formulaId"',
        'error_type': 'name',
        'formula_id': formulaId,
      };
    }
    return _outcomeToJson(session.runFormula(formula, inputs));
  }

  /// Converts an expression to [unitSymbol], e.g. `20 dBm` to `W`.
  Map<String, dynamic> convert(String expression, String unitSymbol) {
    final unit = CalcUnits.resolve(unitSymbol);
    if (unit == null) {
      return {
        'ok': false,
        'error': 'unknown unit "$unitSymbol"',
        'error_type': 'unit',
      };
    }
    try {
      final source = session.engine.evaluate(expression);
      final converted = session.engine.convertValue(source.value, unit);
      final formatter = CalcFormatter(session.settings);
      final result = formatter.format(converted);
      final unitText = formatter.unitSymbol(converted);
      return {
        'ok': true,
        'expression': expression,
        'normalized': source.normalized,
        'unit_requested': unitSymbol,
        'result': result,
        'value': converted.toSource(),
        'unit': unitText,
        'si_value': converted is CalcQuantity && converted.si.isReal
            ? converted.si.re
            : null,
      };
    } on CalcException catch (error) {
      return _errorToJson(error);
    } on Object catch (error) {
      return {
        'ok': false,
        'error': 'internal calculator error: $error',
        'error_type': 'unsupported',
      };
    }
  }

  /// Lists every global variable with its formatted value and source.
  List<Map<String, dynamic>> listVariables() {
    final names = session.engine.variables.keys.toList()..sort();
    return [
      for (final name in names)
        {
          'name': name,
          'value': _formatSafely(session.engine.variables[name]!),
          'source':
              session.variableSources[name] ??
              session.engine.variables[name]!.toSource(),
        },
    ];
  }

  /// Lists user-defined functions.
  List<Map<String, dynamic>> listFunctions() {
    final names = session.engine.functions.keys.toList()..sort();
    return [
      for (final name in names)
        {
          'name': name,
          'source': session.engine.functions[name]!.source,
          'parameters': session.engine.functions[name]!.parameters,
        },
    ];
  }

  /// Recent history, newest first.
  List<Map<String, dynamic>> history({int limit = 20}) {
    return session
        .recentHistory(limit)
        .map((entry) {
          return {
            ...entry.toJson(),
            if (entry.formulaId != null) 'formula_id': entry.formulaId,
          };
        })
        .toList(growable: false);
  }

  /// Formula catalogue, optionally filtered by category or search text.
  List<Map<String, dynamic>> listFormulas({String? category, String? query}) {
    Iterable<CalcFormula> formulas = CalcFormulaLibrary.formulas;
    if (category != null && category.trim().isNotEmpty) {
      formulas = formulas.where((formula) => formula.category == category);
    }
    if (query != null && query.trim().isNotEmpty) {
      final lower = query.trim().toLowerCase();
      formulas = formulas.where(
        (formula) =>
            formula.name.toLowerCase().contains(lower) ||
            formula.id.toLowerCase().contains(lower) ||
            formula.description.toLowerCase().contains(lower),
      );
    }
    return formulas.map(_formulaToJson).toList(growable: false);
  }

  List<String> listCategories() => CalcFormulaCategories.all;

  List<String> listUnits() => CalcUnits.commonSymbols;

  List<String> listConstants() => CalcEngineConstants.names;

  Map<String, dynamic> setAngleMode(String mode) {
    final parsed = mode.toLowerCase();
    final CalcAngleMode value;
    if (parsed == 'deg' || parsed == 'degrees') {
      value = CalcAngleMode.degrees;
    } else if (parsed == 'rad' || parsed == 'radians') {
      value = CalcAngleMode.radians;
    } else if (parsed == 'grad' || parsed == 'gradians' || parsed == 'gon') {
      value = CalcAngleMode.gradians;
    } else {
      return {
        'ok': false,
        'error': 'angle mode must be "deg", "rad" or "grad"',
        'error_type': 'argument',
      };
    }
    session.setAngleMode(value);
    return {'ok': true, 'angle_mode': value.name};
  }

  Map<String, dynamic> clearHistory() {
    session.clearHistory();
    return {'ok': true};
  }

  Future<void> save() => session.save();

  Map<String, dynamic> _outcomeToJson(CalcOutcome outcome) {
    final error = outcome.error;
    if (error != null) return _errorToJson(error);
    final entry = outcome.entry;
    final evaluation = outcome.evaluation;
    final value = evaluation?.value;
    final quantity = value is CalcQuantity ? value : null;
    return {
      'ok': true,
      'expression': entry?.expression ?? '',
      'normalized': evaluation?.normalized ?? '',
      'result': entry?.result ?? '',
      'value': entry?.valueSource ?? '',
      'unit': entry?.unit,
      'dimension': entry?.dimension,
      'si_value': quantity != null && quantity.si.isReal
          ? quantity.si.re
          : null,
      'si_real': quantity?.si.re,
      'si_imag': quantity?.si.im,
      'variables_used': evaluation?.usedVariables.toList() ?? const [],
      'assigned_variables': evaluation?.assignedVariables.toList() ?? const [],
      'formula_id': entry?.formulaId,
      'formula_name': entry?.formulaName,
      'formula_inputs': entry?.formulaInputs,
      'assumptions': entry?.assumptions ?? const [],
      'history_id': entry?.id,
    };
  }

  Map<String, dynamic> _errorToJson(CalcException error) => {
    'ok': false,
    'error': error.message,
    'error_type': error.typeName,
    'position': error.position,
  };

  String _formatSafely(CalcValue value) {
    try {
      return session.formatter.format(value);
    } on Object {
      return value.toSource();
    }
  }

  static Map<String, dynamic> _formulaToJson(CalcFormula formula) => {
    'id': formula.id,
    'name': formula.name,
    'category': formula.category,
    'description': formula.description,
    'expression': formula.expression,
    'display_expression': formula.shownExpression,
    'inputs': [
      for (final input in formula.inputs)
        {
          'name': input.name,
          'label': input.label,
          'default': input.defaultExpression,
          if (input.hint.isNotEmpty) 'hint': input.hint,
        },
    ],
    'assumptions': formula.assumptions,
    'image_asset': formula.imageAsset,
    'result_label': formula.resultLabel,
  };
}

/// Names of the built-in constants, exposed without importing the engine.
class CalcEngineConstants {
  CalcEngineConstants._();

  static List<String> get names => CalcEngine.constantNames;
}
