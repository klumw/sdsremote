/// Value types and unit-aware arithmetic of the engineering calculator.
///
/// A [CalcQuantity] stores its magnitude in coherent SI units and keeps an
/// optional display unit. Keeping the SI value as the source of truth makes
/// arithmetic and dimension checking independent of the unit the user chose.
/// Logarithmic units are stored as their linear SI equivalent and remember
/// their dB unit for formatting; their arithmetic follows level semantics so
/// `20 dBm + 3 dB` and `20 dBm - 10 dBm` behave like a calculator, not like
/// plain addition of the numbers 20 and 3.
library;

import 'dart:math' as math;

import 'calc_complex.dart';
import 'calc_dimension.dart';
import 'calc_error.dart';
import 'calc_units.dart';

/// How a complex result is shown.
enum CalcComplexForm { rectangular, polar }

/// Base of an integer display forced by `hex()`, `bin()` or `oct()`.
enum CalcIntegerBase { decimal, hexadecimal, octal, binary }

/// One calculator value.
sealed class CalcValue {
  const CalcValue();

  String toSource();
}

/// A number with a physical dimension.
class CalcQuantity extends CalcValue {
  const CalcQuantity({
    required this.si,
    required this.dimension,
    this.displayUnit,
    this.unitMarker = false,
    this.complexForm = CalcComplexForm.rectangular,
    this.forcedBase,
  });

  /// A plain dimensionless number.
  factory CalcQuantity.number(num value) =>
      CalcQuantity(si: CalcComplex(value.toDouble(), 0), dimension: _none);

  /// A quantity from an SI value, without a preferred display unit.
  factory CalcQuantity.siValue(CalcComplex si, CalcDimension dimension) =>
      CalcQuantity(si: si, dimension: dimension);

  /// A unit marker such as `kΩ` or `dBm`, used for implicit multiplication
  /// (`10 kΩ`) and as the right-hand side of `to(...)`.
  factory CalcQuantity.unitMarker(CalcUnit unit) {
    final si = unit.isLog
        ? CalcComplex(unit.logReference ?? 1.0, 0)
        : CalcComplex(unit.toSi(1.0), 0);
    return CalcQuantity(
      si: si,
      dimension: unit.dimension,
      displayUnit: unit,
      unitMarker: true,
    );
  }

  /// A value expressed in [unit], e.g. `230 mV`.
  factory CalcQuantity.fromUnit(double value, CalcUnit unit) {
    if (unit.isLog) {
      return CalcQuantity(
        si: CalcComplex(unit.levelToSi(value), 0),
        dimension: unit.dimension,
        displayUnit: unit,
      );
    }
    return CalcQuantity(
      si: CalcComplex(unit.toSi(value), 0),
      dimension: unit.dimension,
      displayUnit: unit,
    );
  }

  final CalcComplex si;
  final CalcDimension dimension;

  /// Unit used for display. Null means "choose automatically from the
  /// dimension".
  final CalcUnit? displayUnit;

  /// True when this value is exactly the unit itself, e.g. the `mV` in
  /// `230 mV`. Only unit markers can be the target of `to(...)`.
  final bool unitMarker;

  final CalcComplexForm complexForm;

  /// Set by `hex()`, `oct()` and `bin()` to force an integer base.
  final CalcIntegerBase? forcedBase;

  static final CalcDimension _none = CalcDimension.none;

  bool get isDimensionless => dimension.isDimensionless;

  bool get isReal => si.isReal;

  bool get isLogDisplay => displayUnit?.isLog == true;

  bool get isAbsoluteLevel => isLogDisplay && displayUnit!.absolute;

  bool get isLogRatio => isLogDisplay && !displayUnit!.absolute;

  CalcQuantity copyWith({
    CalcComplex? si,
    CalcDimension? dimension,
    CalcUnit? displayUnit,
    bool clearDisplayUnit = false,
    bool? unitMarker,
    CalcComplexForm? complexForm,
    CalcIntegerBase? forcedBase,
    bool clearForcedBase = false,
  }) {
    return CalcQuantity(
      si: si ?? this.si,
      dimension: dimension ?? this.dimension,
      displayUnit: clearDisplayUnit ? null : (displayUnit ?? this.displayUnit),
      unitMarker: unitMarker ?? this.unitMarker,
      complexForm: complexForm ?? this.complexForm,
      forcedBase: clearForcedBase ? null : (forcedBase ?? this.forcedBase),
    );
  }

  /// The numeric level of a logarithmic value in its display unit.
  double get levelValue {
    final unit = displayUnit;
    if (unit == null || !unit.isLog || !si.isReal) {
      throw unitError('value is not a real logarithmic level');
    }
    return unit.siToLevel(si.re);
  }

  /// Requires a real value and returns it.
  double requireReal([String label = 'value']) {
    if (!si.isReal) {
      throw argumentError('$label must be real, not complex');
    }
    return si.re;
  }

  /// Converts this value to [target].
  CalcQuantity convertTo(CalcUnit target) {
    if (!dimension.isCompatibleWith(target.dimension)) {
      throw dimensionError(
        'cannot convert ${dimension.describe()} to ${target.symbol} '
        '(${target.dimension.describe()})',
      );
    }
    return CalcQuantity(
      si: si,
      dimension: dimension,
      displayUnit: target,
      complexForm: complexForm,
    );
  }

  // -------------------------------------------------------------------------
  // Arithmetic
  // -------------------------------------------------------------------------

  CalcQuantity operator +(CalcQuantity other) => _add(other, subtract: false);

  CalcQuantity operator -(CalcQuantity other) => _add(other, subtract: true);

  CalcQuantity _add(CalcQuantity other, {required bool subtract}) {
    final aLog = isLogDisplay;
    final bLog = other.isLogDisplay;

    if (aLog || bLog) {
      return _addLog(other, subtract: subtract);
    }

    _requireCompatible(other, subtract ? 'subtract' : 'add');
    return CalcQuantity(
      si: subtract ? si - other.si : si + other.si,
      dimension: dimension,
      complexForm: _combinedComplexForm(other),
    );
  }

  CalcQuantity _addLog(CalcQuantity other, {required bool subtract}) {
    if (!isReal || !other.isReal) {
      throw unsupportedError('logarithmic levels cannot be complex');
    }

    final left = displayUnit!;
    final right = other.displayUnit;

    if (right == null || !right.isLog) {
      throw argumentError(
        'cannot combine ${left.symbol} with a linear value; convert one side '
        'with to(...) or use dB for a gain',
      );
    }

    final leftIsRatio = !left.absolute;
    final rightIsRatio = !right.absolute;

    // A gain (dB, dBi, …) is dimensionless and may be combined with an
    // absolute level of any dimension. Two levels must match dimensionally.
    if (!leftIsRatio && !rightIsRatio) {
      if (!dimension.isCompatibleWith(other.dimension)) {
        throw dimensionError(
          'cannot ${subtract ? 'subtract' : 'add'} ${left.symbol} and '
          '${right.symbol}: incompatible dimensions',
        );
      }
    }

    final double leftLevel;
    final double rightLevel;
    try {
      leftLevel = left.siToLevel(si.re);
      rightLevel = right.siToLevel(other.si.re);
    } on UnitConversionError catch (error) {
      throw domainError(error.message);
    }

    if (!subtract) {
      if (left.absolute && right.absolute) {
        throw dimensionError(
          'cannot add two absolute levels (${left.symbol} + ${right.symbol}); '
          'convert one to a linear unit or use subtraction to get a ratio',
        );
      }
      // Cascaded levels add: a level plus a gain, or two gains. The level of
      // the result is the sum, independent of whether dB uses 10 or 20 as its
      // factor; the unit decides how the level is converted back.
      final resultUnit = left.absolute ? left : (right.absolute ? right : left);
      final resultLevel = leftLevel + rightLevel;
      _requireFiniteLevel(resultLevel, resultUnit);
      return CalcQuantity(
        si: CalcComplex(resultUnit.levelToSi(resultLevel), 0),
        dimension: resultUnit.dimension,
        displayUnit: resultUnit,
      );
    }

    if (!left.absolute && right.absolute) {
      throw dimensionError(
        'cannot subtract an absolute level ${right.symbol} from a ratio '
        '${left.symbol}',
      );
    }

    if (left.absolute && right.absolute) {
      final ratio = si.re / other.si.re;
      if (!ratio.isFinite || ratio <= 0) {
        throw domainError('level ratio is not a positive finite number');
      }
      final decibel = CalcUnits.resolve('dB')!;
      final level = decibel.logFactor * math.log(ratio) / math.ln10;
      _requireFiniteLevel(level, decibel);
      return CalcQuantity(
        si: CalcComplex(decibel.levelToSi(level), 0),
        dimension: CalcDimension.none,
        displayUnit: decibel,
      );
    }

    if (!left.absolute && !right.absolute) {
      // Difference of two gains is a gain in dB.
      final decibel = CalcUnits.resolve('dB')!;
      final resultLevel = leftLevel - rightLevel;
      _requireFiniteLevel(resultLevel, decibel);
      return CalcQuantity(
        si: CalcComplex(decibel.levelToSi(resultLevel), 0),
        dimension: CalcDimension.none,
        displayUnit: decibel,
      );
    }

    // Absolute level minus a gain.
    final resultLevel = leftLevel - rightLevel;
    _requireFiniteLevel(resultLevel, left);
    return CalcQuantity(
      si: CalcComplex(left.levelToSi(resultLevel), 0),
      dimension: left.dimension,
      displayUnit: left,
    );
  }

  static void _requireFiniteLevel(double level, CalcUnit unit) {
    if (!level.isFinite) {
      throw domainError('${unit.symbol} level is not finite');
    }
  }

  CalcQuantity operator *(CalcQuantity other) => _multiply(other);

  CalcQuantity _multiply(CalcQuantity other) {
    if (unitMarker || other.unitMarker) {
      return _multiplyWithMarker(other);
    }

    final aLog = isLogDisplay;
    final bLog = other.isLogDisplay;
    if (aLog && bLog) {
      throw dimensionError(
        'cannot multiply two logarithmic levels; convert one side to a '
        'linear unit first',
      );
    }
    if (aLog || bLog) {
      final logSide = aLog ? this : other;
      final plainSide = aLog ? other : this;
      if (!plainSide.isDimensionless || plainSide.displayUnit != null) {
        throw dimensionError(
          'a ${logSide.displayUnit!.symbol} level can only be scaled by a '
          'plain number',
        );
      }
      if (!plainSide.isReal) {
        throw unsupportedError(
          'a logarithmic level cannot be scaled by a '
          'complex number',
        );
      }
      return CalcQuantity(
        si: si * other.si,
        dimension: dimension * other.dimension,
        displayUnit: logSide.displayUnit,
      );
    }

    return CalcQuantity(
      si: si * other.si,
      dimension: dimension * other.dimension,
      complexForm: _combinedComplexForm(other),
    );
  }

  CalcQuantity _multiplyWithMarker(CalcQuantity other) {
    if (unitMarker && other.unitMarker) {
      final a = displayUnit!;
      final b = other.displayUnit!;
      if (a.isLog || b.isLog) {
        throw unitError('logarithmic units cannot be combined into a product');
      }
      if (a.isAffine || b.isAffine) {
        throw unitError('affine temperature units cannot be multiplied');
      }
      final unit = _combinedUnit(a, b, divide: false);
      return CalcQuantity.unitMarker(unit);
    }

    final marker = unitMarker ? this : other;
    final scalar = unitMarker ? other : this;
    final unit = marker.displayUnit!;
    if (!scalar.isDimensionless || scalar.displayUnit != null) {
      if (unit.isLog || unit.isAffine) {
        throw unitError(
          '${unit.symbol} can only be combined with a plain number',
        );
      }
      return CalcQuantity(
        si: si * other.si,
        dimension: dimension * other.dimension,
        complexForm: _combinedComplexForm(other),
      );
    }
    if (unit.isLog) {
      final level = scalar.requireReal('the coefficient of ${unit.symbol}');
      return CalcQuantity(
        si: CalcComplex(unit.levelToSi(level), 0),
        dimension: unit.dimension,
        displayUnit: unit,
      );
    }
    if (unit.isAffine) {
      final value = scalar.requireReal('the coefficient of ${unit.symbol}');
      return CalcQuantity(
        si: CalcComplex(unit.toSi(value), 0),
        dimension: unit.dimension,
        displayUnit: unit,
      );
    }
    return CalcQuantity(
      si: si * other.si,
      dimension: unit.dimension,
      displayUnit: unit,
      complexForm: _combinedComplexForm(other),
    );
  }

  CalcQuantity operator /(CalcQuantity other) => _divide(other);

  CalcQuantity _divide(CalcQuantity other) {
    if (other.si == CalcComplex.zero) {
      throw divisionByZero();
    }
    if (unitMarker || other.unitMarker) {
      if (unitMarker && other.unitMarker) {
        final a = displayUnit!;
        final b = other.displayUnit!;
        if (a.isLog || b.isLog) {
          throw unitError('logarithmic units cannot be divided as units');
        }
        if (a.isAffine || b.isAffine) {
          throw unitError('affine temperature units cannot be divided');
        }
        return CalcQuantity.unitMarker(_combinedUnit(a, b, divide: true));
      }
      if (unitMarker) {
        final unit = displayUnit!;
        if (unit.isLog || unit.isAffine) {
          throw unitError(
            '${unit.symbol} can only be combined with a plain number by '
            'multiplication',
          );
        }
        return CalcQuantity(
          si: si / other.si,
          dimension: unit.dimension / other.dimension,
          displayUnit: other.isDimensionless ? unit : null,
          complexForm: _combinedComplexForm(other),
        );
      }
      final unit = other.displayUnit!;
      if (unit.isLog || unit.isAffine) {
        throw unitError('${unit.symbol} cannot be used as a divisor');
      }
      return CalcQuantity(
        si: si / other.si,
        dimension: dimension / other.dimension,
        complexForm: _combinedComplexForm(other),
      );
    }

    final aLog = isLogDisplay;
    final bLog = other.isLogDisplay;
    if (aLog && bLog) {
      final ratio = si.re / other.si.re;
      if (!ratio.isFinite || ratio <= 0) {
        throw domainError('level ratio is not a positive finite number');
      }
      final decibel = CalcUnits.resolve('dB')!;
      final level = decibel.logFactor * math.log(ratio) / math.ln10;
      return CalcQuantity(
        si: CalcComplex(decibel.levelToSi(level), 0),
        dimension: CalcDimension.none,
        displayUnit: decibel,
      );
    }
    if (aLog || bLog) {
      final logSide = aLog ? this : other;
      final plainSide = aLog ? other : this;
      if (!plainSide.isDimensionless || plainSide.displayUnit != null) {
        throw dimensionError(
          'a ${logSide.displayUnit!.symbol} level can only be scaled by a '
          'plain number',
        );
      }
      if (!plainSide.isReal) {
        throw unsupportedError(
          'a logarithmic level cannot be scaled by a '
          'complex number',
        );
      }
      // Only a level in the numerator keeps its dB display. A level in the
      // denominator produces an inverse dimension without a meaningful dB
      // representation.
      return CalcQuantity(
        si: si / other.si,
        dimension: dimension / other.dimension,
        displayUnit: aLog ? displayUnit : null,
      );
    }

    return CalcQuantity(
      si: si / other.si,
      dimension: dimension / other.dimension,
      complexForm: _combinedComplexForm(other),
    );
  }

  CalcComplexForm _combinedComplexForm(CalcQuantity other) {
    if (complexForm == CalcComplexForm.polar ||
        other.complexForm == CalcComplexForm.polar) {
      return CalcComplexForm.polar;
    }
    return CalcComplexForm.rectangular;
  }

  CalcQuantity pow(CalcQuantity exponent) {
    if (!exponent.isDimensionless || exponent.displayUnit != null) {
      throw dimensionError('the exponent must be a dimensionless number');
    }
    if (!exponent.isReal) {
      throw unsupportedError('the exponent must be real');
    }
    final realExponent = exponent.si.re;

    if (realExponent == 1.0) return this;

    if (isLogDisplay && realExponent != 1.0) {
      throw unitError(
        'convert ${displayUnit!.symbol} to a linear unit before raising it to '
        'a power',
      );
    }

    if (!dimension.isDimensionless) {
      if (realExponent != realExponent.roundToDouble()) {
        throw dimensionError(
          'a value with unit ${dimension.describe()} can only be raised to an '
          'integer power',
        );
      }
      final integerExponent = realExponent.toInt();
      if (integerExponent < 0) {
        if (si == CalcComplex.zero) throw divisionByZero();
      }
      final resultDimension = integerExponent >= 0
          ? dimension.pow(integerExponent)
          : CalcDimension.none / dimension.pow(-integerExponent);
      final result = si.pow(CalcComplex.real(realExponent));
      if (unitMarker && integerExponent > 0) {
        final unit = displayUnit!;
        if (unit.isLog || unit.isAffine) {
          throw unitError('${unit.symbol} cannot be raised to a power');
        }
        final powered = CalcUnit(
          symbol: _poweredSymbol(unit.symbol, integerExponent),
          dimension: resultDimension,
          scale: math.pow(unit.scale, integerExponent).toDouble(),
        );
        return CalcQuantity.unitMarker(powered);
      }
      return CalcQuantity(si: result, dimension: resultDimension);
    }

    return CalcQuantity(
      si: si.pow(CalcComplex.real(realExponent)),
      dimension: CalcDimension.none,
    );
  }

  /// Square root with dimension halving.
  CalcQuantity sqrtValue() {
    var resultDimension = CalcDimension.none;
    for (final base in CalcBaseDimension.order) {
      final exponent = dimension.exponentOf(base);
      if (exponent == 0) continue;
      if (exponent % 2 != 0) {
        throw dimensionError(
          'cannot take the square root of ${dimension.describe()}: unit '
          'exponents are odd',
        );
      }
      if (exponent ~/ 2 != 0) {
        resultDimension =
            resultDimension * CalcDimension.base(base, exponent ~/ 2);
      }
    }
    return CalcQuantity(si: si.sqrt(), dimension: resultDimension);
  }

  /// Converts a real dimensionless value to a boolean for conditions.
  bool truthy() {
    if (!isDimensionless) {
      throw dimensionError('a condition must be dimensionless');
    }
    if (!isReal) throw argumentError('a condition must be real');
    return si.re != 0.0;
  }

  int compareTo(CalcQuantity other) {
    _requireCompatible(other, 'compare');
    if (!isReal || !other.isReal) {
      throw unsupportedError('complex values cannot be ordered');
    }
    return si.re.compareTo(other.si.re);
  }

  void _requireCompatible(CalcQuantity other, String operation) {
    if (!dimension.isCompatibleWith(other.dimension)) {
      final leftName = displayUnit?.symbol ?? dimension.describe();
      final rightName = other.displayUnit?.symbol ?? other.dimension.describe();
      throw dimensionError(
        'cannot $operation $leftName and $rightName: '
        'incompatible dimensions',
      );
    }
  }

  @override
  String toSource() {
    final unit = displayUnit;
    if (unit == null) {
      final number = si.isReal ? _doubleSource(si.re) : si.toString();
      if (dimension.isDimensionless) return number;
      return '$number * ${_dimensionSource(dimension)}';
    }
    if (unit.isLog) {
      if (!si.isReal || si.re <= 0) {
        return '${si.toString()} ${unit.symbol}';
      }
      return '${_doubleSource(unit.siToLevel(si.re))} ${unit.symbol}';
    }
    final display = CalcComplex(unit.fromSi(si.re), si.im / unit.scale);
    final number = display.isReal
        ? _doubleSource(display.re)
        : display.toString();
    return '$number ${unit.symbol}';
  }

  /// Builds a parseable unit expression from base dimensions, used to persist
  /// variables whose result has no preferred display unit.
  static String _dimensionSource(CalcDimension dimension) {
    final numerator = <String>[];
    final denominator = <String>[];
    for (final base in CalcBaseDimension.order) {
      final exponent = dimension.exponentOf(base);
      if (exponent == 0) continue;
      final term = exponent.abs() == 1 ? base : '$base^${exponent.abs()}';
      if (exponent > 0) {
        numerator.add(term);
      } else {
        denominator.add(term);
      }
    }
    final top = numerator.isEmpty ? '1' : numerator.join('*');
    if (denominator.isEmpty) return top;
    return '($top)/(${denominator.join('*')})';
  }

  static String _doubleSource(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static CalcUnit _combinedUnit(
    CalcUnit a,
    CalcUnit b, {
    required bool divide,
  }) {
    final dimension = divide
        ? a.dimension / b.dimension
        : a.dimension * b.dimension;
    final scale = divide ? a.scale / b.scale : a.scale * b.scale;
    final symbol = divide
        ? '${_wrapSymbol(a.symbol)}/${_wrapSymbol(b.symbol)}'
        : '${_wrapSymbol(a.symbol)}·${_wrapSymbol(b.symbol)}';
    return CalcUnit(symbol: symbol, dimension: dimension, scale: scale);
  }

  static String _wrapSymbol(String symbol) {
    if (symbol.contains('/') || symbol.contains('·')) return '($symbol)';
    return symbol;
  }

  static String _poweredSymbol(String symbol, int exponent) {
    final wrapped = _wrapSymbol(symbol);
    if (exponent == 2 && !wrapped.contains('(')) return '$wrapped²';
    if (exponent == 3 && !wrapped.contains('(')) return '$wrapped³';
    return '$wrapped^$exponent';
  }
}

/// A short text value, used for definitions and informational results.
class CalcText extends CalcValue {
  const CalcText(this.text);

  final String text;

  @override
  String toSource() => text;
}

/// A boolean value produced by comparisons or `if(...)`.
class CalcBool extends CalcValue {
  const CalcBool(this.value);

  final bool value;

  @override
  String toSource() => value ? 'true' : 'false';
}

/// A vector or matrix of calculator values.
class CalcList extends CalcValue {
  const CalcList(this.items);

  final List<CalcValue> items;

  bool get isEmpty => items.isEmpty;

  bool get isMatrix =>
      items.isNotEmpty && items.every((item) => item is CalcList);

  int get rowCount => items.length;

  int get columnCount {
    if (!isMatrix) return items.length;
    final first = items.first;
    return first is CalcList ? first.items.length : 0;
  }

  CalcList row(int index) {
    final value = items[index];
    if (value is! CalcList) {
      throw argumentError('list is not a matrix');
    }
    return value;
  }

  @override
  String toSource() => '[${items.map((item) => item.toSource()).join(', ')}]';
}
