part of 'calc_engine.dart';

// =============================================================================
// Special forms: if, loops, symbolic sums, numerical calculus and solving
// =============================================================================

extension on CalcEngine {
  bool _isSpecialCall(String name, List<CalcNode> arguments) {
    switch (name) {
      case 'if':
      case 'for':
      case 'while':
      case 'integrate':
      case 'derivative':
      case 'solve':
        return true;
      case 'sum':
      case 'product':
        // `sum(expr, n, from, to)` is the symbolic form; `sum(list)` is the
        // ordinary aggregate and goes through the built-in dispatch.
        return arguments.length == 4 && arguments[1] is CalcNameNode;
      default:
        return false;
    }
  }

  CalcValue _callSpecial(CalcCallNode node, _Scope? scope) {
    final name = node.name;
    final arguments = node.arguments;
    switch (name) {
      case 'if':
        if (arguments.length != 3) {
          throw argumentError(
            'if expects 3 arguments, got ${arguments.length}',
          );
        }
        final condition = _truthy(_eval(arguments[0], scope));
        return _eval(condition ? arguments[1] : arguments[2], scope);

      case 'for':
        if (arguments.length != 4) {
          throw argumentError('for expects (variable, from, to, expression)');
        }
        return _runFor(node, scope);

      case 'while':
        if (arguments.length != 2) {
          throw argumentError('while expects (condition, expression)');
        }
        return _runWhile(node, scope);

      case 'sum':
      case 'product':
        if (arguments.length != 4) {
          throw argumentError('$name expects (expression, variable, from, to)');
        }
        return _runSymbolicAggregate(name, node, scope);

      case 'integrate':
        if (arguments.length != 4) {
          throw argumentError(
            'integrate expects (expression, variable, from, to)',
          );
        }
        return _runIntegrate(node, scope);

      case 'derivative':
        if (arguments.length != 3) {
          throw argumentError('derivative expects (expression, variable, at)');
        }
        return _runDerivative(node, scope);

      case 'solve':
        if (arguments.length != 3 && arguments.length != 4) {
          throw argumentError(
            'solve expects (expression, variable, guess) or '
            '(expression, variable, low, high)',
          );
        }
        return _runSolve(node, scope);

      default:
        throw unsupportedError('unknown special form "$name"');
    }
  }

  String _variableName(CalcNode node, String form) {
    if (node is! CalcNameNode) {
      throw argumentError('$form expects a variable name');
    }
    if (!isAllowedLocalName(node.name)) {
      throw nameError(
        '"${node.name}" cannot be used as a loop or solver variable',
        node.position,
      );
    }
    return node.name;
  }

  int _loopBound(CalcNode node, _Scope? scope, String label) {
    final value = _eval(node, scope);
    if (value is! CalcQuantity) {
      throw argumentError('$label must be a dimensionless integer');
    }
    return CalcEngine._integerArgument(value, label);
  }

  CalcValue _runFor(CalcCallNode node, _Scope? scope) {
    final variable = _variableName(node.arguments[0], 'for');
    final from = _loopBound(node.arguments[1], scope, 'from');
    final to = _loopBound(node.arguments[2], scope, 'to');
    final body = node.arguments[3];
    final previous = _captureLocal(scope, variable);
    CalcValue result = CalcQuantity.number(0);
    try {
      for (var index = from; index <= to; index++) {
        _consumeLoopBudget();
        _setLocal(scope, variable, CalcQuantity.number(index));
        result = _eval(body, scope);
      }
    } finally {
      _restoreLocal(scope, variable, previous);
    }
    return result;
  }

  CalcValue _runWhile(CalcCallNode node, _Scope? scope) {
    CalcValue result = CalcQuantity.number(0);
    while (true) {
      final condition = _truthy(_eval(node.arguments[0], scope));
      if (!condition) break;
      _consumeLoopBudget();
      result = _eval(node.arguments[1], scope);
    }
    return result;
  }

  CalcValue _runSymbolicAggregate(
    String name,
    CalcCallNode node,
    _Scope? scope,
  ) {
    final variable = _variableName(node.arguments[1], name);
    final from = _loopBound(node.arguments[2], scope, 'from');
    final to = _loopBound(node.arguments[3], scope, 'to');
    if (from > to) {
      return CalcQuantity.number(name == 'sum' ? 0 : 1);
    }
    final sum = name == 'sum';
    CalcValue? accumulator;
    final aggregateScope = _Scope(scope);
    for (var index = from; index <= to; index++) {
      _consumeLoopBudget();
      aggregateScope.locals[variable] = CalcQuantity.number(index);
      final term = _eval(node.arguments[0], aggregateScope);
      if (accumulator == null) {
        accumulator = term;
      } else {
        accumulator = sum
            ? _addValues(accumulator, term)
            : _multiplyValues(accumulator, term);
      }
    }
    return accumulator ?? CalcQuantity.number(sum ? 0 : 1);
  }

  CalcValue _runIntegrate(CalcCallNode node, _Scope? scope) {
    final variable = _variableName(node.arguments[1], 'integrate');
    final from = _eval(node.arguments[2], scope);
    final to = _eval(node.arguments[3], scope);
    if (from is! CalcQuantity || to is! CalcQuantity) {
      throw argumentError('integration bounds must be numbers');
    }
    if (!from.dimension.isCompatibleWith(to.dimension)) {
      throw dimensionError('integration bounds must have the same dimension');
    }
    if (!from.si.isReal || !to.si.isReal) {
      throw unsupportedError('integration bounds must be real');
    }
    if (from.isLogDisplay || to.isLogDisplay) {
      throw unitError(
        'convert level bounds to linear units before integrating',
      );
    }
    final variableDimension = from.dimension;
    final integrationScope = _Scope(scope);

    CalcDimension? functionDimension;
    CalcComplex sample(double value) {
      integrationScope.locals[variable] = CalcQuantity(
        si: CalcComplex.real(value),
        dimension: variableDimension,
      );
      final result = _eval(node.arguments[0], integrationScope);
      if (result is! CalcQuantity) {
        throw argumentError('integrate requires a numeric expression');
      }
      if (result.isLogDisplay) {
        throw unitError(
          'convert a level expression to a linear unit before integrating',
        );
      }
      if (functionDimension == null) {
        functionDimension = result.dimension;
      } else if (!functionDimension!.isCompatibleWith(result.dimension)) {
        throw dimensionError(
          'integrate expression changes dimension from '
          '${functionDimension!.describe()} to ${result.dimension.describe()}',
        );
      }
      return result.si;
    }

    final a = from.si.re;
    final b = to.si.re;
    if (a == b) {
      sample(a);
      return CalcQuantity(
        si: CalcComplex.zero,
        dimension: functionDimension! * variableDimension,
        displayUnit: null,
      );
    }
    final sign = a < b ? 1.0 : -1.0;
    final low = math.min(a, b);
    final high = math.max(a, b);
    final integral = _adaptiveSimpson(sample, low, high);
    return CalcQuantity(
      si: integral * CalcComplex.real(sign),
      dimension: functionDimension! * variableDimension,
    );
  }

  CalcComplex _adaptiveSimpson(
    CalcComplex Function(double) function,
    double low,
    double high,
  ) {
    final middle = (low + high) / 2;
    final fa = function(low);
    final fm = function(middle);
    final fb = function(high);
    final whole = _simpson(fa, fm, fb, high - low);
    return _simpsonRecursive(function, low, high, fa, fm, fb, whole, 1e-10, 0);
  }

  CalcComplex _simpsonRecursive(
    CalcComplex Function(double) function,
    double low,
    double high,
    CalcComplex fa,
    CalcComplex fm,
    CalcComplex fb,
    CalcComplex whole,
    double tolerance,
    int depth,
  ) {
    final middle = (low + high) / 2;
    final leftMiddle = (low + middle) / 2;
    final rightMiddle = (middle + high) / 2;
    final flm = function(leftMiddle);
    final frm = function(rightMiddle);
    final left = _simpson(fa, flm, fm, middle - low);
    final right = _simpson(fm, frm, fb, high - middle);
    final delta = left + right - whole;
    final scale = 1.0 + (left + right).magnitude;
    if (depth >= 30 || delta.magnitude <= tolerance * scale) {
      return left + right + delta / CalcComplex.real(15);
    }
    return _simpsonRecursive(
          function,
          low,
          middle,
          fa,
          flm,
          fm,
          left,
          tolerance,
          depth + 1,
        ) +
        _simpsonRecursive(
          function,
          middle,
          high,
          fm,
          frm,
          fb,
          right,
          tolerance,
          depth + 1,
        );
  }

  static CalcComplex _simpson(
    CalcComplex fa,
    CalcComplex fm,
    CalcComplex fb,
    double width,
  ) {
    return (fa + fm * CalcComplex.real(4) + fb) * CalcComplex.real(width / 6);
  }

  CalcValue _runDerivative(CalcCallNode node, _Scope? scope) {
    final variable = _variableName(node.arguments[1], 'derivative');
    final point = _eval(node.arguments[2], scope);
    if (point is! CalcQuantity) {
      throw argumentError('derivative point must be a number');
    }
    if (!point.si.isReal) {
      throw unsupportedError('derivative point must be real');
    }
    if (point.isLogDisplay) {
      throw unitError(
        'convert a level to a linear unit before differentiating',
      );
    }
    final x = point.si.re;
    final step = math.max(x.abs() * 1e-6, 1e-9);
    final derivativeScope = _Scope(scope);

    CalcDimension? functionDimension;
    CalcComplex sample(double value) {
      derivativeScope.locals[variable] = CalcQuantity(
        si: CalcComplex.real(value),
        dimension: point.dimension,
      );
      final result = _eval(node.arguments[0], derivativeScope);
      if (result is! CalcQuantity) {
        throw argumentError('derivative requires a numeric expression');
      }
      if (result.isLogDisplay) {
        throw unitError(
          'convert a level expression to a linear unit before differentiating',
        );
      }
      if (functionDimension == null) {
        functionDimension = result.dimension;
      } else if (!functionDimension!.isCompatibleWith(result.dimension)) {
        throw dimensionError(
          'derivative expression changes dimension from '
          '${functionDimension!.describe()} to ${result.dimension.describe()}',
        );
      }
      return result.si;
    }

    final forward = sample(x + step);
    final backward = sample(x - step);
    final slope = (forward - backward) / CalcComplex.real(2 * step);
    return CalcQuantity(
      si: slope,
      dimension: functionDimension! / point.dimension,
    );
  }

  CalcValue _runSolve(CalcCallNode node, _Scope? scope) {
    final variable = _variableName(node.arguments[1], 'solve');
    final third = _eval(node.arguments[2], scope);
    if (third is! CalcQuantity) {
      throw argumentError('solve requires a numeric guess or lower bound');
    }
    if (!third.si.isReal) {
      throw unsupportedError('solve guess must be real');
    }
    if (third.isLogDisplay) {
      throw unitError('convert a level to a linear unit before solving');
    }
    final solveScope = _Scope(scope);

    double evaluateAt(double value) {
      solveScope.locals[variable] = CalcQuantity(
        si: CalcComplex.real(value),
        dimension: third.dimension,
        displayUnit: third.displayUnit,
      );
      final result = _eval(node.arguments[0], solveScope);
      if (result is! CalcQuantity) {
        throw argumentError('solve requires a numeric expression');
      }
      if (!result.si.isReal) {
        throw unsupportedError('solve requires a real expression');
      }
      return result.si.re;
    }

    if (node.arguments.length == 4) {
      final upper = _eval(node.arguments[3], scope);
      if (upper is! CalcQuantity) {
        throw argumentError('solve upper bound must be a number');
      }
      if (!upper.dimension.isCompatibleWith(third.dimension) ||
          !upper.si.isReal) {
        throw dimensionError('solve bounds must have the same dimension');
      }
      final low = third.si.re;
      final high = upper.si.re;
      if (low == high) {
        throw argumentError('solve bounds must differ');
      }
      final lowValue = evaluateAt(low);
      final highValue = evaluateAt(high);
      final tolerance = 1e-12 * (1 + math.max(low.abs(), high.abs()));
      if (lowValue.abs() <= tolerance) {
        return _solvedQuantity(low, third);
      }
      if (highValue.abs() <= tolerance) {
        return _solvedQuantity(high, third);
      }
      if (lowValue.sign == highValue.sign) {
        throw convergenceError('no sign change between the solve bounds');
      }
      var a = low;
      var b = high;
      var fa = lowValue;
      for (var iteration = 0; iteration < 200; iteration++) {
        final middle = (a + b) / 2;
        final fm = evaluateAt(middle);
        if (fm.abs() <= tolerance || (b - a).abs() <= tolerance) {
          return _solvedQuantity(middle, third);
        }
        if (fa.sign == fm.sign) {
          a = middle;
          fa = fm;
        } else {
          b = middle;
        }
      }
      throw convergenceError('bisection did not converge after 200 steps');
    }

    var x = third.si.re;
    final tolerance = 1e-10 * (1 + x.abs());
    for (var iteration = 0; iteration < 100; iteration++) {
      final fx = evaluateAt(x);
      if (fx.abs() <= tolerance) {
        return _solvedQuantity(x, third);
      }
      final step = math.max(x.abs() * 1e-6, 1e-9);
      final derivative =
          (evaluateAt(x + step) - evaluateAt(x - step)) / (2 * step);
      if (!derivative.isFinite || derivative.abs() < 1e-14) {
        throw convergenceError(
          'solver derivative is zero or not finite near the guess',
        );
      }
      final next = x - fx / derivative;
      if (!next.isFinite) {
        throw convergenceError('solver diverged');
      }
      if ((next - x).abs() <= tolerance) {
        return _solvedQuantity(next, third);
      }
      x = next;
    }
    throw convergenceError('solver did not converge after 100 iterations');
  }

  CalcQuantity _solvedQuantity(double value, CalcQuantity reference) {
    return CalcQuantity(
      si: CalcComplex.real(value),
      dimension: reference.dimension,
      displayUnit: reference.displayUnit,
    );
  }

  void _consumeLoopBudget() {
    if (_loopBudget <= 0) {
      throw limitError(
        'loop limit of ${CalcEngine.maxLoopIterations} iterations exceeded',
      );
    }
    _loopBudget--;
  }

  _SavedLocal _captureLocal(_Scope? scope, String name) {
    if (scope == null) {
      return _SavedLocal(variables.containsKey(name), variables[name]);
    }
    return _SavedLocal(scope.locals.containsKey(name), scope.locals[name]);
  }

  void _setLocal(_Scope? scope, String name, CalcValue value) {
    if (scope == null) {
      variables[name] = value;
    } else {
      scope.locals[name] = value;
    }
  }

  void _restoreLocal(_Scope? scope, String name, _SavedLocal saved) {
    if (scope == null) {
      if (saved.existed) {
        variables[name] = saved.value!;
      } else {
        variables.remove(name);
      }
    } else {
      if (saved.existed) {
        scope.locals[name] = saved.value!;
      } else {
        scope.locals.remove(name);
      }
    }
  }
}

class _SavedLocal {
  const _SavedLocal(this.existed, this.value);

  final bool existed;
  final CalcValue? value;
}
