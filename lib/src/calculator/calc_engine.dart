/// Evaluator of the engineering calculator language.
///
/// The engine is deliberately independent of Flutter: the window, the
/// persistence layer and an AI tool all use this class. It never evaluates
/// user text as Dart code — parsing produces [CalcNode] trees and the
/// evaluator walks them with explicit type and dimension checks.
library;

import 'dart:math' as math;

import 'calc_ast.dart';
import 'calc_complex.dart';
import 'calc_dimension.dart';
import 'calc_error.dart';
import 'calc_format.dart';
import 'calc_parser.dart';
import 'calc_units.dart';
import 'calc_value.dart';

part 'calc_engine_builtins.dart';
part 'calc_engine_lists.dart';
part 'calc_engine_special.dart';

/// A user-defined function such as `f(x) = x^2 + 1`.
class CalcUserFunction {
  const CalcUserFunction({
    required this.name,
    required this.parameters,
    required this.body,
    required this.source,
  });

  final String name;
  final List<String> parameters;
  final CalcNode body;

  /// Normalized definition, used for persistence and the variables panel.
  final String source;
}

/// Result of evaluating a program.
class CalcEvaluation {
  const CalcEvaluation({
    required this.value,
    required this.normalized,
    required this.usedVariables,
    required this.assignedVariables,
  });

  final CalcValue value;
  final String normalized;
  final Set<String> usedVariables;
  final Set<String> assignedVariables;
}

/// Evaluates calculator expressions and programs.
class CalcEngine {
  CalcEngine({
    Map<String, CalcValue>? variables,
    Map<String, CalcUserFunction>? functions,
    this.settings = const CalcFormatSettings(),
  }) : variables = variables ?? <String, CalcValue>{},
       functions = functions ?? <String, CalcUserFunction>{};

  /// Global variables, shared with the session and the UI.
  final Map<String, CalcValue> variables;

  /// User-defined functions.
  final Map<String, CalcUserFunction> functions;

  CalcFormatSettings settings;

  /// Result of the most recent successful evaluation (`ans`).
  CalcValue? lastAnswer;

  int _loopBudget = 0;
  int _callDepth = 0;
  final Set<String> _usedVariables = <String>{};
  final Set<String> _assignedVariables = <String>{};

  static const int maxLoopIterations = 100000;
  static const int maxCallDepth = 64;

  /// Evaluates [source] as one program and returns the final value.
  CalcEvaluation evaluate(String source) {
    final statements = CalcParser.parse(source).parseProgram();
    if (statements.isEmpty) {
      throw argumentError('expression is empty');
    }
    final normalized = statements.map((node) => node.toSource()).join('; ');
    _usedVariables.clear();
    _assignedVariables.clear();
    _loopBudget = maxLoopIterations;
    _callDepth = 0;

    CalcValue? value;
    try {
      for (final statement in statements) {
        value = _eval(statement, null);
      }
    } on CalcException {
      rethrow;
    } on ComplexDivisionByZero {
      throw divisionByZero();
    } on ComplexDomainError catch (error) {
      throw domainError(error.message);
    } on UnitConversionError catch (error) {
      throw unitError(error.message);
    } on DimensionRootError catch (error) {
      throw dimensionError(error.toString());
    } on DimensionPowerError catch (error) {
      throw dimensionError(error.toString());
    } on ArgumentError catch (error) {
      throw argumentError(error.message?.toString() ?? 'invalid argument');
    }

    final result = value;
    if (result == null) throw argumentError('expression is empty');
    _checkFinite(result);
    lastAnswer = result;

    return CalcEvaluation(
      value: result,
      normalized: normalized,
      usedVariables: Set.unmodifiable(_usedVariables),
      assignedVariables: Set.unmodifiable(_assignedVariables),
    );
  }

  /// Convenience for callers that only need the value.
  CalcValue evaluateValue(String source) => evaluate(source).value;

  /// Converts [value] to [unit] with the same rules as the `to` operator.
  CalcValue convertValue(CalcValue value, CalcUnit unit) =>
      _convertTo(value, CalcQuantity.unitMarker(unit));

  /// Evaluates [source] with temporary global inputs, e.g. formula
  /// parameters. Previous values are restored afterwards, while variables
  /// assigned by the expression itself persist.
  CalcEvaluation evaluateWithInputs(
    String source,
    Map<String, CalcValue> inputs,
  ) {
    final previous = <String, CalcValue?>{};
    for (final entry in inputs.entries) {
      previous[entry.key] = variables[entry.key];
      variables[entry.key] = entry.value;
    }
    try {
      return evaluate(source);
    } finally {
      for (final entry in previous.entries) {
        if (entry.value == null) {
          variables.remove(entry.key);
        } else {
          variables[entry.key] = entry.value!;
        }
      }
    }
  }

  /// True when [name] cannot be used as a variable, function or parameter
  /// name because it is a unit, constant or built-in.
  /// True when [name] may be used for a loop variable or function parameter.
  ///
  /// Constants may be shadowed locally (a loop over `i` is more common than
  /// the imaginary unit inside a loop), but units and functions may not.
  bool isAllowedLocalName(String name) {
    if (name == 'true' ||
        name == 'false' ||
        name == 'ans' ||
        name == 'ANS' ||
        name == 'not' ||
        name == 'and' ||
        name == 'or' ||
        name == 'mod' ||
        name == 'in' ||
        name == 'to') {
      return false;
    }
    if (CalcUnits.resolve(name) != null) return false;
    if (_builtinNames.contains(name)) return false;
    if (_specialFormNames.contains(name)) return false;
    return true;
  }

  bool isReservedName(String name) {
    if (name == 'true' ||
        name == 'false' ||
        name == 'ans' ||
        name == 'ANS' ||
        name == 'not' ||
        name == 'and' ||
        name == 'or' ||
        name == 'mod' ||
        name == 'in' ||
        name == 'to') {
      return true;
    }
    if (_constants.containsKey(name)) return true;
    if (CalcUnits.resolve(name) != null) return true;
    if (_builtinNames.contains(name)) return true;
    if (_specialFormNames.contains(name)) return true;
    return false;
  }

  // -------------------------------------------------------------------------
  // Tree walking
  // -------------------------------------------------------------------------

  CalcValue _eval(CalcNode node, _Scope? scope) {
    switch (node) {
      case CalcNumberNode():
        return CalcQuantity.number(node.value);
      case CalcNameNode():
        return _resolveName(node.name, scope, node.position);
      case CalcUnaryNode():
        return _evalUnary(node, scope);
      case CalcBinaryNode():
        return _evalBinary(node, scope);
      case CalcPostfixNode():
        return _evalPostfix(node, scope);
      case CalcCallNode():
        return _evalCall(node, scope);
      case CalcListNode():
        return CalcList(
          node.items.map((item) => _eval(item, scope)).toList(growable: false),
        );
      case CalcIndexNode():
        return _evalIndex(node, scope);
      case CalcAssignmentNode():
        return _evalAssignment(node, scope);
      case CalcFunctionDefinitionNode():
        return _evalFunctionDefinition(node, scope);
    }
  }

  CalcValue _resolveName(String name, _Scope? scope, int position) {
    if (name == 'true') return const CalcBool(true);
    if (name == 'false') return const CalcBool(false);
    if (name == 'ans' || name == 'ANS') {
      final answer = lastAnswer;
      if (answer == null) {
        throw nameError('there is no previous result yet', position);
      }
      return answer;
    }

    final local = scope?.lookup(name);
    if (local != null) return local;

    // Globals come before constants so loop variables such as `i` or `n` can
    // temporarily shadow the imaginary unit or an SI-prefix constant.
    final variable = variables[name];
    if (variable != null) {
      _usedVariables.add(name);
      return variable;
    }

    final constant = _constants[name];
    if (constant != null) return constant;

    final unit = CalcUnits.resolve(name);
    if (unit != null) return CalcQuantity.unitMarker(unit);

    throw nameError('unknown name "$name"', position);
  }

  CalcValue _evalUnary(CalcUnaryNode node, _Scope? scope) {
    final operand = _eval(node.operand, scope);
    switch (node.operator) {
      case '+':
        _requireNumeric(operand, 'unary +');
        return operand;
      case '-':
        return _negateValue(operand);
      case 'sqrt':
        return _sqrtValue(operand);
      case 'cbrt':
        return _cbrtValue(operand);
      case 'not':
        return CalcBool(!_truthy(operand));
      default:
        throw unsupportedError('unknown unary operator "${node.operator}"');
    }
  }

  CalcValue _evalBinary(CalcBinaryNode node, _Scope? scope) {
    switch (node.operator) {
      case '&&':
        final left = _eval(node.left, scope);
        if (!_truthy(left)) return const CalcBool(false);
        return CalcBool(_truthy(_eval(node.right, scope)));
      case '||':
        final left = _eval(node.left, scope);
        if (_truthy(left)) return const CalcBool(true);
        return CalcBool(_truthy(_eval(node.right, scope)));
      case 'to':
        final left = _eval(node.left, scope);
        final right = _eval(node.right, scope);
        return _convertTo(left, right);
      case '∠':
        final left = _eval(node.left, scope);
        final right = _eval(node.right, scope);
        return _polarValue(left, right);
      case 'mod':
        final left = _eval(node.left, scope);
        final right = _eval(node.right, scope);
        return _modValues(left, right);
    }

    final left = _eval(node.left, scope);
    final right = _eval(node.right, scope);
    final CalcValue result;
    switch (node.operator) {
      case '+':
        result = _addValues(left, right);
      case '-':
        result = _subtractValues(left, right);
      case '*':
        result = _multiplyValues(left, right);
      case '/':
        result = _divideValues(left, right);
      case '^':
        result = _powerValues(left, right);
      case '<':
        result = _compareValue(left, right, (a, b) => a < b);
      case '>':
        result = _compareValue(left, right, (a, b) => a > b);
      case '<=':
        result = _compareValue(left, right, (a, b) => a <= b);
      case '>=':
        result = _compareValue(left, right, (a, b) => a >= b);
      case '==':
        result = CalcBool(_equalsValue(left, right));
      case '!=':
        result = CalcBool(!_equalsValue(left, right));
      default:
        throw unsupportedError('unknown operator "${node.operator}"');
    }
    _checkFinite(result);
    return result;
  }

  CalcValue _evalPostfix(CalcPostfixNode node, _Scope? scope) {
    if (node.operator != '!') {
      throw unsupportedError('unknown postfix operator "${node.operator}"');
    }
    final operand = _eval(node.operand, scope);
    return _factorialValue(operand);
  }

  CalcValue _evalCall(CalcCallNode node, _Scope? scope) {
    if (_isSpecialCall(node.name, node.arguments)) {
      return _callSpecial(node, scope);
    }

    final userFunction = functions[node.name];
    if (userFunction != null) {
      return _callUserFunction(userFunction, node, scope);
    }

    if (!_builtinNames.contains(node.name)) {
      throw nameError('unknown function "${node.name}"', node.position);
    }

    final arguments = node.arguments
        .map((argument) => _eval(argument, scope))
        .toList(growable: false);
    final result = _callBuiltin(node.name, arguments);
    _checkFinite(result);
    return result;
  }

  CalcValue _callUserFunction(
    CalcUserFunction function,
    CalcCallNode node,
    _Scope? scope,
  ) {
    if (node.arguments.length != function.parameters.length) {
      throw argumentError(
        '${function.name} expects ${function.parameters.length} argument(s), '
        'got ${node.arguments.length}',
      );
    }
    if (_callDepth >= maxCallDepth) {
      throw limitError('maximum function call depth exceeded');
    }
    final arguments = node.arguments
        .map((argument) => _eval(argument, scope))
        .toList(growable: false);
    final callScope = _Scope(null);
    for (var index = 0; index < function.parameters.length; index++) {
      callScope.locals[function.parameters[index]] = arguments[index];
    }
    _callDepth++;
    try {
      return _eval(function.body, callScope);
    } finally {
      _callDepth--;
    }
  }

  CalcValue _evalIndex(CalcIndexNode node, _Scope? scope) {
    final target = _eval(node.target, scope);
    final index = _eval(node.index, scope);
    return _indexValue(target, index);
  }

  CalcValue _evalAssignment(CalcAssignmentNode node, _Scope? scope) {
    if (isReservedName(node.name)) {
      throw nameError(
        '"${node.name}" is a reserved unit, constant or function name',
        node.position,
      );
    }
    final value = _eval(node.value, scope);
    if (scope != null) {
      scope.locals[node.name] = value;
    } else {
      variables[node.name] = value;
    }
    _assignedVariables.add(node.name);
    return value;
  }

  CalcValue _evalFunctionDefinition(
    CalcFunctionDefinitionNode node,
    _Scope? scope,
  ) {
    if (scope != null) {
      throw unsupportedError(
        'functions can only be defined at the top level of a program',
      );
    }
    if (isReservedName(node.name)) {
      throw nameError(
        '"${node.name}" is a reserved unit, constant or function name',
        node.position,
      );
    }
    final seen = <String>{};
    for (final parameter in node.parameters) {
      if (!isAllowedLocalName(parameter)) {
        throw nameError(
          '"$parameter" cannot be used as a parameter name',
          node.position,
        );
      }
      if (!seen.add(parameter)) {
        throw argumentError('duplicate parameter "$parameter" in ${node.name}');
      }
    }
    final source = node.toSource();
    functions[node.name] = CalcUserFunction(
      name: node.name,
      parameters: List.unmodifiable(node.parameters),
      body: node.body,
      source: source,
    );
    return CalcText('defined $source');
  }

  void _checkFinite(CalcValue value) {
    switch (value) {
      case CalcQuantity():
        if (!value.si.re.isFinite || !value.si.im.isFinite) {
          throw overflowError('result is not a finite number');
        }
      case CalcList():
        for (final item in value.items) {
          _checkFinite(item);
        }
      case CalcBool():
      case CalcText():
        break;
    }
  }

  static CalcValue _requireNumeric(CalcValue value, String operation) {
    if (value is CalcQuantity || value is CalcList) return value;
    throw argumentError('$operation requires a number');
  }

  static void _requireArity(
    String name,
    List<CalcValue> arguments,
    int minimum, [
    int? maximum,
  ]) {
    final upper = maximum ?? minimum;
    if (arguments.length < minimum || arguments.length > upper) {
      if (minimum == upper) {
        throw argumentError(
          '$name expects $minimum argument(s), got ${arguments.length}',
        );
      }
      throw argumentError(
        '$name expects $minimum to $upper arguments, got ${arguments.length}',
      );
    }
  }

  static CalcQuantity _quantityArgument(
    String name,
    List<CalcValue> arguments,
    int index,
  ) {
    final value = arguments[index];
    if (value is CalcQuantity) return value;
    throw argumentError('$name argument ${index + 1} must be a number');
  }

  static double _realArgument(CalcQuantity value, String label) {
    if (!value.si.isReal) {
      throw argumentError('$label must be real, not complex');
    }
    return value.si.re;
  }

  static int _integerArgument(CalcQuantity value, String label) {
    final real = _realArgument(value, label);
    if (!value.isDimensionless) {
      throw dimensionError('$label must be dimensionless');
    }
    if (real != real.roundToDouble()) {
      throw argumentError('$label must be an integer');
    }
    if (real.abs() > 9.007199254740992e15) {
      throw argumentError('$label is too large for an exact integer');
    }
    return real.toInt();
  }

  /// Names of built-in functions.
  static const Set<String> _builtinNames = {
    'abs',
    'sqrt',
    'cbrt',
    'exp',
    'ln',
    'log',
    'log10',
    'log2',
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'atan2',
    'sinh',
    'cosh',
    'tanh',
    'asinh',
    'acosh',
    'atanh',
    'floor',
    'ceil',
    'round',
    'trunc',
    'frac',
    'sign',
    'min',
    'max',
    'sum',
    'prod',
    'product',
    'mean',
    'avg',
    'median',
    'stdev',
    'variance',
    'rms',
    'peak',
    'p2p',
    'crest',
    'meanabs',
    'count',
    'mod',
    'intdiv',
    'factorial',
    'gamma',
    'comb',
    'perm',
    'gcd',
    'lcm',
    'isprime',
    'hypot',
    'clamp',
    'solve_quadratic',
    're',
    'im',
    'conj',
    'arg',
    'phase',
    'polar',
    'rect',
    'complex',
    'mag',
    'dot',
    'cross',
    'matmul',
    'transpose',
    'det',
    'inv',
    'norm',
    'trace',
    'shape',
    'identity',
    'linsolve',
    'zeros',
    'ones',
    'seq',
    'to',
    'convert',
    'in',
    'value',
    'ratio',
    'lin',
    'db_value',
    'level',
    'db',
    'db10',
    'db20',
    'dbm',
    'dbw',
    'dbv',
    'dbu',
    'dbfs',
    'dbuv',
    'db_to_ratio',
    'ratio_to_db',
    'db_to_amp',
    'amp_to_db',
    'w_to_dbm',
    'dbm_to_w',
    'vrms_to_dbm',
    'dbm_to_vrms',
    'dbv_to_vrms',
    'vrms_to_dbv',
    'dbu_to_vrms',
    'vrms_to_dbu',
    'dbfs_to_vrms',
    'vrms_to_dbfs',
    'dbuv_to_vrms',
    'vrms_to_dbuv',
    'parallel',
    'series',
    'rc_cutoff',
    'rl_cutoff',
    'lc_resonance',
    'rlc_q',
    'impedance_c',
    'impedance_l',
    'impedance_r',
    'wavelength',
    'fspl',
    'path_loss',
    'link_budget',
    'eirp',
    'vswr',
    'reflection',
    'return_loss',
    'mismatch_loss',
    'cable_loss',
    'thermal_noise',
    'noise_floor_dbm',
    'nf_cascade',
    'nf_cascade_db',
    'sensitivity_dbm',
    'dbm_per_hz',
    'thd',
    'thd_db',
    'snr_db',
    'sinad_db',
    'adc_lsb',
    'adc_snr',
    'quantization_error',
    'counts',
    'percent_error',
    'tolerance',
    'pwm_frequency',
    'pwm_duty',
    'timer_ticks',
    'uart_baud',
    'baud_error',
    'can_bitrate',
    'nyquist',
    'fft_resolution',
    'rise_time',
    'band',
    'bor',
    'bxor',
    'bnot',
    'shl',
    'shr',
    'sar',
    'popcount',
    'parity',
    'bit',
    'mask',
    'to_signed',
    'to_unsigned',
    'hex',
    'bin',
    'oct',
    'dec',
    'crc8',
    'crc16_ccitt',
    'q_format',
    'q_to_float',
    'version',
    'functions',
    'constants',
    'units',
  };

  static const Set<String> _specialFormNames = {
    'if',
    'for',
    'while',
    'integrate',
    'derivative',
    'solve',
    'sum',
    'product',
  };

  static final Map<String, CalcValue> _constants = _buildConstants();

  static Map<String, CalcValue> _buildConstants() {
    final values = <String, CalcValue>{
      'pi': CalcQuantity.number(math.pi),
      'π': CalcQuantity.number(math.pi),
      'e': CalcQuantity.number(math.e),
      'tau': CalcQuantity.number(2 * math.pi),
      'phi': CalcQuantity.number((1 + math.sqrt(5)) / 2),
      'j': const CalcQuantity(
        si: CalcComplex.imaginaryUnit,
        dimension: CalcDimension.none,
      ),
      'i': const CalcQuantity(
        si: CalcComplex.imaginaryUnit,
        dimension: CalcDimension.none,
      ),
      'k': CalcQuantity.number(1e3),
      'M': CalcQuantity.number(1e6),
      'G': CalcQuantity.number(1e9),
      'u': CalcQuantity.number(1e-6),
      'µ': CalcQuantity.number(1e-6),
      'n': CalcQuantity.number(1e-9),
      'p': CalcQuantity.number(1e-12),
    };

    CalcQuantity withUnit(double value, String symbol) {
      final unit = CalcUnits.resolve(symbol);
      if (unit == null) {
        throw StateError('calculator unit $symbol is missing');
      }
      return CalcQuantity.fromUnit(value, unit);
    }

    values['c_0'] = withUnit(299792458, 'm/s');
    values['g_0'] = withUnit(9.80665, 'm/s²');
    values['q_e'] = withUnit(1.602176634e-19, 'C');
    values['k_B'] = _derived(1.380649e-23, 'J', 'K', divide: true);
    values['h_planck'] = _derived(6.62607015e-34, 'J', 's', multiply: true);
    values['N_A'] = _derived(
      6.02214076e23,
      CalcQuantity.number(1),
      'mol',
      divide: true,
    );
    values['R_gas'] = _derived(
      8.31446261815324,
      _derived(1.0, 'J', 'mol', divide: true),
      'K',
      divide: true,
    );
    values['T_0'] = withUnit(290, 'K');
    values['Z_0'] = withUnit(376.730313668, 'Ω');
    values['eps_0'] = _derived(8.8541878128e-12, 'F', 'm', divide: true);
    values['mu_0'] = _derived(1.25663706212e-6, 'H', 'm', divide: true);
    return values;
  }

  static CalcQuantity _derived(
    double value,
    Object baseOrValue,
    String symbol, {
    bool multiply = false,
    bool divide = false,
  }) {
    CalcQuantity base;
    if (baseOrValue is CalcQuantity) {
      base = baseOrValue;
    } else {
      final unit = CalcUnits.resolve(baseOrValue as String);
      if (unit == null) {
        throw StateError('calculator unit $baseOrValue missing');
      }
      base = CalcQuantity.unitMarker(unit);
    }
    final otherUnit = CalcUnits.resolve(symbol);
    if (otherUnit == null) {
      if (symbol == '1') {
        return CalcQuantity(
          si: CalcComplex(value, 0),
          dimension: base.dimension,
        );
      }
      throw StateError('calculator unit $symbol is missing');
    }
    final other = CalcQuantity.unitMarker(otherUnit);
    final dimension = multiply
        ? base.dimension * other.dimension
        : (divide ? base.dimension / other.dimension : base.dimension);
    return CalcQuantity(si: CalcComplex(value, 0), dimension: dimension);
  }

  /// Known constant names, for the UI and the AI tool.
  static List<String> get constantNames => _constants.keys.toList()..sort();

  /// Known built-in function names, for the UI and the AI tool.
  static List<String> get builtinNames => _builtinNames.toList()..sort();
}

class _Scope {
  _Scope(this.parent);

  final _Scope? parent;
  final Map<String, CalcValue> locals = <String, CalcValue>{};

  CalcValue? lookup(String name) {
    final local = locals[name];
    if (local != null) return local;
    return parent?.lookup(name);
  }
}
