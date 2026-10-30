part of 'calc_engine.dart';

// =============================================================================
// Scalar and list arithmetic
// =============================================================================

extension on CalcEngine {
  CalcValue _addValues(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left + right;
    }
    if (left is CalcList && right is CalcList) {
      _requireSameShape(left, right, 'add');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) => _addValues(left.items[index], right.items[index]),
          growable: false,
        ),
      );
    }
    if (left is CalcList && right is CalcQuantity) {
      return CalcList(
        left.items
            .map((item) => _addValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is CalcQuantity && right is CalcList) {
      return CalcList(
        right.items
            .map((item) => _addValues(left, item))
            .toList(growable: false),
      );
    }
    throw argumentError(
      'cannot add ${_typeName(left)} and ${_typeName(right)}',
    );
  }

  CalcValue _subtractValues(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left - right;
    }
    if (left is CalcList && right is CalcList) {
      _requireSameShape(left, right, 'subtract');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) => _subtractValues(left.items[index], right.items[index]),
          growable: false,
        ),
      );
    }
    if (left is CalcList && right is CalcQuantity) {
      return CalcList(
        left.items
            .map((item) => _subtractValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is CalcQuantity && right is CalcList) {
      return CalcList(
        right.items
            .map((item) => _subtractValues(left, item))
            .toList(growable: false),
      );
    }
    throw argumentError(
      'cannot subtract ${_typeName(right)} from ${_typeName(left)}',
    );
  }

  CalcValue _multiplyValues(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left * right;
    }
    if (left is CalcList && right is CalcQuantity) {
      return CalcList(
        left.items
            .map((item) => _multiplyValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is CalcQuantity && right is CalcList) {
      return CalcList(
        right.items
            .map((item) => _multiplyValues(left, item))
            .toList(growable: false),
      );
    }
    if (left is CalcList && right is CalcList) {
      if (left.isMatrix && right.isMatrix) {
        return _matrixMultiply(left, right);
      }
      if (left.isMatrix && !right.isMatrix) {
        return _matrixVectorMultiply(left, right);
      }
      if (!left.isMatrix && right.isMatrix) {
        return _vectorMatrixMultiply(left, right);
      }
      _requireSameShape(left, right, 'multiply');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) => _multiplyValues(left.items[index], right.items[index]),
          growable: false,
        ),
      );
    }
    throw argumentError(
      'cannot multiply ${_typeName(left)} and ${_typeName(right)}',
    );
  }

  CalcValue _divideValues(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left / right;
    }
    if (left is CalcList && right is CalcQuantity) {
      return CalcList(
        left.items
            .map((item) => _divideValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is CalcQuantity && right is CalcList) {
      return CalcList(
        right.items
            .map((item) => _divideValues(left, item))
            .toList(growable: false),
      );
    }
    if (left is CalcList && right is CalcList) {
      _requireSameShape(left, right, 'divide');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) => _divideValues(left.items[index], right.items[index]),
          growable: false,
        ),
      );
    }
    throw argumentError(
      'cannot divide ${_typeName(left)} by ${_typeName(right)}',
    );
  }

  CalcValue _powerValues(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left.pow(right);
    }
    if (left is CalcList && right is CalcQuantity) {
      return CalcList(
        left.items
            .map((item) => _powerValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is CalcQuantity && right is CalcList) {
      return CalcList(
        right.items
            .map((item) => _powerValues(left, item))
            .toList(growable: false),
      );
    }
    throw argumentError(
      'cannot raise ${_typeName(left)} to the power ${_typeName(right)}',
    );
  }

  CalcValue _modValues(CalcValue left, CalcValue right) {
    if (left is CalcList && right is CalcList) {
      _requireSameShape(left, right, 'mod');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) => _modValues(left.items[index], right.items[index]),
        ),
      );
    }
    if (left is CalcList) {
      return CalcList(
        left.items
            .map((item) => _modValues(item, right))
            .toList(growable: false),
      );
    }
    if (left is! CalcQuantity || right is! CalcQuantity) {
      throw argumentError('mod requires two numbers');
    }
    if (!left.dimension.isCompatibleWith(right.dimension)) {
      throw dimensionError('mod requires compatible dimensions');
    }
    final a = CalcEngine._realArgument(left, 'a');
    final b = CalcEngine._realArgument(right, 'b');
    if (b == 0) throw divisionByZero('modulo by zero');
    final quotient = (a / b).floorToDouble();
    return CalcQuantity(
      si: CalcComplex(a - b * quotient, 0),
      dimension: left.dimension,
    );
  }

  CalcValue _polarValue(CalcValue left, CalcValue right) {
    if (right is! CalcQuantity) {
      throw argumentError('the angle must be a number');
    }
    if (left is CalcList) {
      return CalcList(
        left.items
            .map((item) => _polarValue(item, right))
            .toList(growable: false),
      );
    }
    if (left is! CalcQuantity) {
      throw argumentError('the magnitude must be a number');
    }
    if (left.isLogDisplay) {
      throw unitError('convert a level to a linear unit before using ∠');
    }
    if (left.displayUnit?.isAffine == true) {
      throw unitError('affine temperature units cannot be used with ∠');
    }
    final radians = _angleToRadians(right);
    final magnitude = left.si.magnitude;
    return CalcQuantity(
      si: CalcComplex.fromPolar(magnitude, radians),
      dimension: left.dimension,
      displayUnit: left.displayUnit,
      complexForm: CalcComplexForm.polar,
    );
  }

  CalcValue _convertTo(CalcValue value, CalcValue target) {
    if (target is! CalcQuantity ||
        !target.unitMarker ||
        target.displayUnit == null) {
      throw unitError(
        'the target of a conversion must be a unit such as Ω or mV',
      );
    }
    final unit = target.displayUnit!;
    if (value is CalcList) {
      return CalcList(
        value.items
            .map((item) => _convertTo(item, target))
            .toList(growable: false),
      );
    }
    if (value is! CalcQuantity) {
      throw argumentError('only a number can be converted');
    }
    return value.convertTo(unit);
  }

  CalcValue _negateValue(CalcValue value) {
    if (value is CalcQuantity) {
      return value.copyWith(si: -value.si);
    }
    if (value is CalcList) {
      return CalcList(value.items.map(_negateValue).toList(growable: false));
    }
    throw argumentError('only a number can be negated');
  }

  CalcValue _sqrtValue(CalcValue value) {
    if (value is CalcQuantity) {
      if (value.isLogDisplay) {
        throw unitError('convert a level to a linear unit before sqrt');
      }
      return value.sqrtValue();
    }
    if (value is CalcList) {
      return CalcList(value.items.map(_sqrtValue).toList(growable: false));
    }
    throw argumentError('sqrt requires a number');
  }

  CalcValue _cbrtValue(CalcValue value) {
    if (value is CalcList) {
      return CalcList(value.items.map(_cbrtValue).toList(growable: false));
    }
    if (value is! CalcQuantity) {
      throw argumentError('cbrt requires a number');
    }
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear unit before cbrt');
    }
    final dimension = _rootDimension(value.dimension, 3);
    final real = value.si;
    final CalcComplex result;
    if (real.isReal && real.re < 0) {
      result = CalcComplex.real(-math.pow(-real.re, 1 / 3).toDouble());
    } else if (real.isReal) {
      result = CalcComplex.real(math.pow(real.re, 1 / 3).toDouble());
    } else {
      result = real.pow(const CalcComplex.real(1 / 3));
    }
    return CalcQuantity(si: result, dimension: dimension);
  }

  CalcDimension _rootDimension(CalcDimension dimension, int root) {
    var result = CalcDimension.none;
    for (final base in CalcBaseDimension.order) {
      final exponent = dimension.exponentOf(base);
      if (exponent == 0) continue;
      if (exponent % root != 0) {
        throw dimensionError(
          'cannot take root $root of ${dimension.describe()}',
        );
      }
      result = result * CalcDimension.base(base, exponent ~/ root);
    }
    return result;
  }

  CalcValue _factorialValue(CalcValue value) {
    if (value is CalcList) {
      return CalcList(value.items.map(_factorialValue).toList(growable: false));
    }
    if (value is! CalcQuantity) {
      throw argumentError('factorial requires a number');
    }
    if (!value.isDimensionless) {
      throw dimensionError('factorial requires a dimensionless number');
    }
    final real = CalcEngine._realArgument(value, 'factorial argument');
    if (real < 0) {
      throw domainError('factorial is not defined for negative numbers');
    }
    if (real == real.roundToDouble()) {
      if (real > 170) {
        throw overflowError('factorial overflows the double range');
      }
      var result = 1.0;
      for (var index = 2; index <= real.toInt(); index++) {
        result *= index;
      }
      return CalcQuantity.number(result);
    }
    final result = _gammaFunction(real + 1);
    if (!result.isFinite) {
      throw overflowError('factorial overflows the double range');
    }
    return CalcQuantity.number(result);
  }

  CalcValue _compareValue(
    CalcValue left,
    CalcValue right,
    bool Function(double a, double b) comparator,
  ) {
    if (left is CalcQuantity && right is CalcQuantity) {
      if (!left.dimension.isCompatibleWith(right.dimension)) {
        throw dimensionError(
          'cannot compare ${left.dimension.describe()} and '
          '${right.dimension.describe()}',
        );
      }
      if (!left.si.isReal || !right.si.isReal) {
        throw unsupportedError('complex values cannot be ordered');
      }
      return CalcBool(comparator(left.si.re, right.si.re));
    }
    if (left is CalcList && right is CalcList) {
      _requireSameShape(left, right, 'compare');
      return CalcList(
        List<CalcValue>.generate(
          left.items.length,
          (index) =>
              _compareValue(left.items[index], right.items[index], comparator),
        ),
      );
    }
    throw argumentError(
      'comparison requires two numbers of the same dimension',
    );
  }

  bool _equalsValue(CalcValue left, CalcValue right) {
    if (left is CalcQuantity && right is CalcQuantity) {
      return left.dimension.isCompatibleWith(right.dimension) &&
          left.si == right.si;
    }
    if (left is CalcList && right is CalcList) {
      if (left.items.length != right.items.length) return false;
      for (var index = 0; index < left.items.length; index++) {
        if (!_equalsValue(left.items[index], right.items[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is CalcBool && right is CalcBool) return left.value == right.value;
    if (left is CalcText && right is CalcText) return left.text == right.text;
    return false;
  }

  bool _truthy(CalcValue value) {
    if (value is CalcBool) return value.value;
    if (value is CalcQuantity) return value.truthy();
    throw argumentError('a condition must be a boolean or a number');
  }

  CalcValue _indexValue(CalcValue target, CalcValue index) {
    if (target is! CalcList) {
      throw argumentError('indexing is only defined for vectors and matrices');
    }
    if (index is CalcList) {
      if (index.items.length != 2) {
        throw argumentError('a matrix index needs [row, column]');
      }
      final row = CalcEngine._integerArgument(
        CalcEngine._quantityArgument('index', index.items, 0),
        'row',
      );
      final column = CalcEngine._integerArgument(
        CalcEngine._quantityArgument('index', index.items, 1),
        'column',
      );
      final rowList = target.items[_resolveIndex(row, target.items.length)];
      if (rowList is! CalcList) {
        throw argumentError('the target is not a matrix');
      }
      return rowList.items[_resolveIndex(column, rowList.items.length)];
    }
    if (index is! CalcQuantity) {
      throw argumentError('the index must be a number');
    }
    final position = CalcEngine._integerArgument(index, 'index');
    return target.items[_resolveIndex(position, target.items.length)];
  }

  int _resolveIndex(int position, int length) {
    if (position == 0) {
      throw argumentError('index 0 does not exist; indexes start at 1');
    }
    final resolved = position > 0 ? position - 1 : length + position;
    if (resolved < 0 || resolved >= length) {
      throw argumentError('index $position is out of range for length $length');
    }
    return resolved;
  }

  // -------------------------------------------------------------------------
  // Statistics and matrix helpers
  // -------------------------------------------------------------------------

  List<CalcValue> _collectValues(List<CalcValue> arguments, String name) {
    if (arguments.length == 1 && arguments.first is CalcList) {
      return (arguments.first as CalcList).items;
    }
    if (arguments.isEmpty) {
      throw argumentError('$name requires at least one value');
    }
    return arguments;
  }

  CalcValue _sumValues(List<CalcValue> values) {
    if (values.isEmpty) return CalcQuantity.number(0);
    var result = values.first;
    for (var index = 1; index < values.length; index++) {
      result = _addValues(result, values[index]);
    }
    return result;
  }

  CalcValue _productValues(List<CalcValue> values) {
    if (values.isEmpty) return CalcQuantity.number(1);
    var result = values.first;
    for (var index = 1; index < values.length; index++) {
      result = _multiplyValues(result, values[index]);
    }
    return result;
  }

  CalcValue _meanValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('mean requires at least one value');
    }
    return _divideValues(
      _sumValues(values),
      CalcQuantity.number(values.length),
    );
  }

  CalcValue _varianceValue(List<CalcValue> values) {
    if (values.length < 2) {
      throw argumentError('variance requires at least two values');
    }
    final mean = _meanValue(values);
    CalcValue? sum;
    for (final value in values) {
      final delta = _subtractValues(value, mean);
      final square = _multiplyValues(delta, delta);
      sum = sum == null ? square : _addValues(sum, square);
    }
    if (sum == null) {
      throw argumentError('variance requires at least two values');
    }
    return _divideValues(sum, CalcQuantity.number(values.length - 1));
  }

  CalcValue _stdevValue(List<CalcValue> values) =>
      _sqrtValue(_varianceValue(values));

  CalcValue _rmsValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('rms requires at least one value');
    }
    CalcValue? sum;
    for (final value in values) {
      final square = _multiplyValues(value, value);
      sum = sum == null ? square : _addValues(sum, square);
    }
    if (sum == null) {
      throw argumentError('rms requires at least one value');
    }
    final mean = _divideValues(sum, CalcQuantity.number(values.length));
    return _sqrtValue(mean);
  }

  CalcValue _medianValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('median requires at least one value');
    }
    final quantities = values.map(_requireQuantityValue).toList();
    for (final value in quantities) {
      if (!value.si.isReal) {
        throw unsupportedError('median is only defined for real values');
      }
    }
    quantities.sort((a, b) => a.si.re.compareTo(b.si.re));
    final middle = quantities.length ~/ 2;
    if (quantities.length.isOdd) return quantities[middle];
    return _divideValues(
      _addValues(quantities[middle - 1], quantities[middle]),
      CalcQuantity.number(2),
    );
  }

  CalcValue _peakValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('peak requires at least one value');
    }
    CalcQuantity? best;
    for (final item in values) {
      final value = _requireQuantityValue(item);
      if (value.isLogDisplay) {
        throw unitError('convert levels to linear units before peak');
      }
      final magnitude = value.si.magnitude;
      if (best == null || magnitude > best.si.re) {
        best = CalcQuantity(
          si: CalcComplex.real(magnitude),
          dimension: value.dimension,
        );
      }
    }
    return best!;
  }

  CalcValue _p2pValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('p2p requires at least one value');
    }
    var minimum = _requireQuantityValue(values.first);
    var maximum = minimum;
    for (final item in values.skip(1)) {
      final value = _requireQuantityValue(item);
      if (!value.si.isReal) {
        throw unsupportedError('p2p is only defined for real values');
      }
      if (value.si.re < minimum.si.re) minimum = value;
      if (value.si.re > maximum.si.re) maximum = value;
    }
    return _subtractValues(maximum, minimum);
  }

  CalcValue _crestValue(List<CalcValue> values) {
    final peak = _peakValue(values);
    final rms = _rmsValue(values);
    return _divideValues(peak, rms);
  }

  CalcValue _meanAbsValue(List<CalcValue> values) {
    if (values.isEmpty) {
      throw argumentError('meanabs requires at least one value');
    }
    CalcValue? sum;
    for (final item in values) {
      final value = _requireQuantityValue(item);
      final magnitude = CalcQuantity(
        si: CalcComplex.real(value.si.magnitude),
        dimension: value.dimension,
      );
      sum = sum == null ? magnitude : _addValues(sum, magnitude);
    }
    if (sum == null) {
      throw argumentError('meanabs requires at least one value');
    }
    return _divideValues(sum, CalcQuantity.number(values.length));
  }

  CalcValue _minValue(List<CalcValue> values) =>
      _extremeValue(values, minimum: true);

  CalcValue _maxValue(List<CalcValue> values) =>
      _extremeValue(values, minimum: false);

  CalcValue _extremeValue(List<CalcValue> values, {required bool minimum}) {
    if (values.isEmpty) {
      throw argumentError('${minimum ? 'min' : 'max'} requires values');
    }
    var best = values.first;
    var bestReal = CalcEngine._realArgument(
      _requireQuantityValue(best),
      'value',
    );
    for (final item in values.skip(1)) {
      final quantity = _requireQuantityValue(item);
      final real = CalcEngine._realArgument(quantity, 'value');
      if (!quantity.dimension.isCompatibleWith(
        _requireQuantityValue(best).dimension,
      )) {
        throw dimensionError('all values must have the same dimension');
      }
      if (minimum ? real < bestReal : real > bestReal) {
        best = item;
        bestReal = real;
      }
    }
    return best;
  }

  CalcQuantity _requireQuantityValue(CalcValue value) {
    if (value is CalcQuantity) return value;
    throw argumentError('expected a number, found ${_typeName(value)}');
  }

  void _requireSameShape(CalcList left, CalcList right, String operation) {
    if (left.items.length != right.items.length) {
      throw argumentError(
        'cannot $operation lists of different length '
        '(${left.items.length} and ${right.items.length})',
      );
    }
    for (var index = 0; index < left.items.length; index++) {
      final a = left.items[index];
      final b = right.items[index];
      if (a is CalcList && b is CalcList) {
        _requireSameShape(a, b, operation);
      } else if (a is CalcList || b is CalcList) {
        throw argumentError('cannot $operation nested and flat lists');
      }
    }
  }

  CalcValue _matrixMultiply(CalcList a, CalcList b) {
    final rowsA = a.items.length;
    final columnsA = a.row(0).items.length;
    final rowsB = b.items.length;
    final columnsB = b.row(0).items.length;
    if (columnsA != rowsB) {
      throw argumentError(
        'matrix dimensions do not match: ${rowsA}x$columnsA times '
        '${rowsB}x$columnsB',
      );
    }
    final result = <CalcValue>[];
    for (var row = 0; row < rowsA; row++) {
      final resultRow = <CalcValue>[];
      for (var column = 0; column < columnsB; column++) {
        CalcValue? sum;
        for (var index = 0; index < columnsA; index++) {
          final product = _multiplyValues(
            a.row(row).items[index],
            b.row(index).items[column],
          );
          sum = sum == null ? product : _addValues(sum, product);
        }
        resultRow.add(sum ?? CalcQuantity.number(0));
      }
      result.add(CalcList(resultRow));
    }
    return CalcList(result);
  }

  CalcValue _matrixVectorMultiply(CalcList matrix, CalcList vector) {
    final columns = matrix.row(0).items.length;
    if (vector.items.length != columns) {
      throw argumentError(
        'matrix columns ($columns) do not match vector length '
        '(${vector.items.length})',
      );
    }
    final result = <CalcValue>[];
    for (var row = 0; row < matrix.items.length; row++) {
      CalcValue? sum;
      for (var column = 0; column < columns; column++) {
        final product = _multiplyValues(
          matrix.row(row).items[column],
          vector.items[column],
        );
        sum = sum == null ? product : _addValues(sum, product);
      }
      result.add(sum ?? CalcQuantity.number(0));
    }
    return CalcList(result);
  }

  CalcValue _vectorMatrixMultiply(CalcList vector, CalcList matrix) {
    final rows = matrix.items.length;
    if (vector.items.length != rows) {
      throw argumentError(
        'vector length (${vector.items.length}) does not match matrix rows '
        '($rows)',
      );
    }
    final columns = matrix.row(0).items.length;
    final result = <CalcValue>[];
    for (var column = 0; column < columns; column++) {
      CalcValue? sum;
      for (var row = 0; row < rows; row++) {
        final product = _multiplyValues(
          vector.items[row],
          matrix.row(row).items[column],
        );
        sum = sum == null ? product : _addValues(sum, product);
      }
      result.add(sum ?? CalcQuantity.number(0));
    }
    return CalcList(result);
  }

  CalcValue _transposeValue(CalcList matrix) {
    if (!matrix.isMatrix) {
      throw argumentError('transpose requires a matrix');
    }
    final rows = matrix.items.length;
    final columns = matrix.row(0).items.length;
    final result = <CalcValue>[];
    for (var column = 0; column < columns; column++) {
      final resultRow = <CalcValue>[];
      for (var row = 0; row < rows; row++) {
        resultRow.add(matrix.row(row).items[column]);
      }
      result.add(CalcList(resultRow));
    }
    return CalcList(result);
  }

  CalcValue _determinantValue(CalcList matrix) {
    final size = _requireSquare(matrix);
    final rows = List<List<CalcValue>>.generate(
      size,
      (row) => List<CalcValue>.from(matrix.row(row).items),
    );
    CalcValue determinant = CalcQuantity.number(1);
    var sign = 1;
    for (var column = 0; column < size; column++) {
      var pivot = column;
      var bestMagnitude = _magnitudeOf(rows[pivot][column]);
      for (var row = column + 1; row < size; row++) {
        final magnitude = _magnitudeOf(rows[row][column]);
        if (magnitude > bestMagnitude) {
          bestMagnitude = magnitude;
          pivot = row;
        }
      }
      if (bestMagnitude == 0) return CalcQuantity.number(0);
      if (pivot != column) {
        final temporary = rows[pivot];
        rows[pivot] = rows[column];
        rows[column] = temporary;
        sign = -sign;
      }
      final pivotValue = rows[column][column];
      determinant = _multiplyValues(determinant, pivotValue);
      for (var row = column + 1; row < size; row++) {
        final factor = _divideValues(rows[row][column], pivotValue);
        for (var index = column; index < size; index++) {
          rows[row][index] = _subtractValues(
            rows[row][index],
            _multiplyValues(factor, rows[column][index]),
          );
        }
      }
    }
    if (sign < 0) {
      determinant = _negateValue(determinant);
    }
    return determinant;
  }

  CalcValue _inverseValue(CalcList matrix) {
    final size = _requireSquare(matrix);
    final rows = List<List<CalcValue>>.generate(size, (row) {
      final result = <CalcValue>[...matrix.row(row).items];
      for (var column = 0; column < size; column++) {
        result.add(CalcQuantity.number(row == column ? 1 : 0));
      }
      return result;
    });
    for (var column = 0; column < size; column++) {
      var pivot = column;
      var bestMagnitude = _magnitudeOf(rows[pivot][column]);
      for (var row = column + 1; row < size; row++) {
        final magnitude = _magnitudeOf(rows[row][column]);
        if (magnitude > bestMagnitude) {
          bestMagnitude = magnitude;
          pivot = row;
        }
      }
      if (bestMagnitude == 0) {
        throw domainError('matrix is singular and cannot be inverted');
      }
      if (pivot != column) {
        final temporary = rows[pivot];
        rows[pivot] = rows[column];
        rows[column] = temporary;
      }
      final pivotValue = rows[column][column];
      for (var index = 0; index < size * 2; index++) {
        rows[column][index] = _divideValues(rows[column][index], pivotValue);
      }
      for (var row = 0; row < size; row++) {
        if (row == column) continue;
        final factor = rows[row][column];
        for (var index = 0; index < size * 2; index++) {
          rows[row][index] = _subtractValues(
            rows[row][index],
            _multiplyValues(factor, rows[column][index]),
          );
        }
      }
    }
    return CalcList(
      List<CalcValue>.generate(
        size,
        (row) => CalcList(rows[row].sublist(size)),
      ),
    );
  }

  int _requireSquare(CalcList matrix) {
    if (!matrix.isMatrix) {
      throw argumentError('expected a matrix');
    }
    final size = matrix.items.length;
    for (final row in matrix.items) {
      if (row is! CalcList || row.items.length != size) {
        throw argumentError('expected a square matrix');
      }
    }
    if (size == 0) throw argumentError('matrix is empty');
    return size;
  }

  double _magnitudeOf(CalcValue value) {
    if (value is CalcQuantity) return value.si.magnitude;
    throw argumentError('matrix entries must be numbers');
  }

  CalcValue _normValue(CalcValue value) {
    final values = value is CalcList ? value.items : [value];
    CalcValue? sum;
    for (final item in values) {
      if (item is CalcList) {
        final inner = _normValue(item);
        sum = sum == null
            ? _multiplyValues(inner, inner)
            : _addValues(sum, _multiplyValues(inner, inner));
        continue;
      }
      final quantity = _requireQuantityValue(item);
      final squared = CalcQuantity(
        si: CalcComplex.real(quantity.si.magnitudeSquared),
        dimension: quantity.dimension * quantity.dimension,
      );
      sum = sum == null ? squared : _addValues(sum, squared);
    }
    if (sum == null) return CalcQuantity.number(0);
    return _sqrtValue(sum);
  }

  CalcValue _dotValue(CalcList a, CalcList b) {
    if (a.isMatrix || b.isMatrix) {
      throw argumentError('dot requires two vectors');
    }
    if (a.items.length != b.items.length) {
      throw argumentError('vectors must have the same length');
    }
    CalcValue? sum;
    for (var index = 0; index < a.items.length; index++) {
      final product = _multiplyValues(a.items[index], b.items[index]);
      sum = sum == null ? product : _addValues(sum, product);
    }
    return sum ?? CalcQuantity.number(0);
  }

  CalcValue _crossValue(CalcList a, CalcList b) {
    if (a.isMatrix ||
        b.isMatrix ||
        a.items.length != 3 ||
        b.items.length != 3) {
      throw argumentError('cross requires two vectors with three elements');
    }
    CalcValue component(int i, int j) => _subtractValues(
      _multiplyValues(a.items[i], b.items[j]),
      _multiplyValues(a.items[j], b.items[i]),
    );
    return CalcList([component(1, 2), component(2, 0), component(0, 1)]);
  }

  CalcValue _linsolveValue(CalcList matrix, CalcList vector) {
    final inverse = _inverseValue(matrix) as CalcList;
    return _matrixVectorMultiply(inverse, vector);
  }

  CalcValue _seqValue(List<CalcValue> arguments) {
    final start = _requireQuantityValue(arguments[0]);
    final stop = _requireQuantityValue(arguments[1]);
    final step = arguments.length > 2
        ? _requireQuantityValue(arguments[2])
        : CalcQuantity(si: const CalcComplex(1, 0), dimension: start.dimension);
    if (!start.dimension.isCompatibleWith(stop.dimension) ||
        !start.dimension.isCompatibleWith(step.dimension)) {
      throw dimensionError('seq requires compatible dimensions');
    }
    if (!start.si.isReal || !stop.si.isReal || !step.si.isReal) {
      throw unsupportedError('seq requires real values');
    }
    final startValue = start.si.re;
    final stopValue = stop.si.re;
    final stepValue = step.si.re;
    if (stepValue == 0) throw argumentError('seq step must not be zero');
    final values = <CalcValue>[];
    final direction = stepValue > 0 ? 1 : -1;
    var current = startValue;
    var guard = 0;
    while (direction > 0
        ? current <= stopValue + 1e-15
        : current >= stopValue - 1e-15) {
      values.add(
        CalcQuantity(si: CalcComplex(current, 0), dimension: start.dimension),
      );
      current += stepValue;
      if (++guard > 10000) {
        throw limitError('seq would produce more than 10000 values');
      }
    }
    return CalcList(values);
  }

  CalcValue _zerosValue(int rows, [int? columns]) {
    if (columns == null) {
      return CalcList(
        List<CalcValue>.generate(rows, (_) => CalcQuantity.number(0)),
      );
    }
    return CalcList(
      List<CalcValue>.generate(
        rows,
        (_) => CalcList(
          List<CalcValue>.generate(columns, (_) => CalcQuantity.number(0)),
        ),
      ),
    );
  }

  CalcValue _onesValue(int rows, [int? columns]) {
    if (columns == null) {
      return CalcList(
        List<CalcValue>.generate(rows, (_) => CalcQuantity.number(1)),
      );
    }
    return CalcList(
      List<CalcValue>.generate(
        rows,
        (_) => CalcList(
          List<CalcValue>.generate(columns, (_) => CalcQuantity.number(1)),
        ),
      ),
    );
  }

  CalcValue _identityValue(int size) {
    return CalcList(
      List<CalcValue>.generate(
        size,
        (row) => CalcList(
          List<CalcValue>.generate(
            size,
            (column) => CalcQuantity.number(row == column ? 1 : 0),
          ),
        ),
      ),
    );
  }

  CalcValue _shapeValue(CalcValue value) {
    if (value is CalcList) {
      if (value.isMatrix) {
        return CalcList([
          CalcQuantity.number(value.items.length),
          CalcQuantity.number(value.row(0).items.length),
        ]);
      }
      return CalcList([CalcQuantity.number(value.items.length)]);
    }
    return CalcList([CalcQuantity.number(1)]);
  }

  static String _typeName(CalcValue value) {
    if (value is CalcQuantity) return 'number';
    if (value is CalcList) return 'list';
    if (value is CalcBool) return 'boolean';
    if (value is CalcText) return 'text';
    return value.runtimeType.toString();
  }
}
