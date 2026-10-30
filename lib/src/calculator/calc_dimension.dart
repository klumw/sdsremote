/// Physical dimensions used by the engineering calculator.
///
/// A dimension is a product of powers of the SI base quantities. Units are
/// represented separately in `calc_units.dart`; this type only answers "which
/// physical quantity" a value has, so incompatible operations can be rejected.
library;

/// SI base quantity identifiers, in the order used for display.
class CalcBaseDimension {
  const CalcBaseDimension._();

  static const String length = 'm';
  static const String mass = 'kg';
  static const String time = 's';
  static const String current = 'A';
  static const String temperature = 'K';
  static const String amount = 'mol';
  static const String luminousIntensity = 'cd';
  static const String angle = 'rad';
  static const String information = 'bit';
  static const String baud = 'Bd';
  static const String sample = 'Sa';

  /// Display order: derived-unit names and compound dimensions read
  /// consistently when built from this order.
  static const List<String> order = [
    length,
    mass,
    time,
    current,
    temperature,
    amount,
    luminousIntensity,
    angle,
    information,
    baud,
    sample,
  ];
}

/// An immutable product of base dimensions.
class CalcDimension {
  const CalcDimension._(this._exponents);

  /// The dimensionless quantity (a pure number or ratio).
  static const CalcDimension none = CalcDimension._({});

  factory CalcDimension.base(String base, [int exponent = 1]) {
    if (!CalcBaseDimension.order.contains(base)) {
      throw ArgumentError.value(base, 'base', 'Unknown base dimension');
    }
    return CalcDimension._(exponent == 0 ? const {} : {base: exponent});
  }

  final Map<String, int> _exponents;

  Map<String, int> get exponents => Map.unmodifiable(_exponents);

  bool get isDimensionless => _exponents.isEmpty;

  int exponentOf(String base) => _exponents[base] ?? 0;

  CalcDimension operator *(CalcDimension other) {
    final result = <String, int>{..._exponents};
    for (final entry in other._exponents.entries) {
      final value = (result[entry.key] ?? 0) + entry.value;
      if (value == 0) {
        result.remove(entry.key);
      } else {
        result[entry.key] = value;
      }
    }
    return CalcDimension._(result);
  }

  CalcDimension operator /(CalcDimension other) {
    final result = <String, int>{..._exponents};
    for (final entry in other._exponents.entries) {
      final value = (result[entry.key] ?? 0) - entry.value;
      if (value == 0) {
        result.remove(entry.key);
      } else {
        result[entry.key] = value;
      }
    }
    return CalcDimension._(result);
  }

  /// Raises every exponent by [power].
  CalcDimension pow(int power) {
    if (power == 0) return none;
    if (power == 1) return this;
    if (power < 0) throw const DimensionPowerError();
    final result = <String, int>{};
    for (final entry in _exponents.entries) {
      result[entry.key] = entry.value * power;
    }
    return CalcDimension._(result);
  }

  /// Returns this dimension with a single base exponent decremented by one,
  /// used when taking an integer root.
  CalcDimension divideExponent(String base, int divisor) {
    final value = exponentOf(base);
    if (value == 0) return this;
    if (value % divisor != 0) throw const DimensionRootError();
    final result = <String, int>{..._exponents};
    final next = value ~/ divisor;
    if (next == 0) {
      result.remove(base);
    } else {
      result[base] = next;
    }
    return CalcDimension._(result);
  }

  /// True when [other] describes the same physical quantity.
  bool isCompatibleWith(CalcDimension other) =>
      _exponents.length == other._exponents.length &&
      _exponents.entries.every(
        (entry) => other._exponents[entry.key] == entry.value,
      );

  /// Human-readable name such as `V`, `A`, or `m²·kg/s³`.
  ///
  /// Unit-aware formatting in `calc_format.dart` is preferred for results;
  /// this is the fallback and is also used in error messages.
  String describe() {
    if (isDimensionless) return 'dimensionless';
    final parts = <String>[];
    for (final base in CalcBaseDimension.order) {
      final exponent = _exponents[base] ?? 0;
      if (exponent == 0) continue;
      parts.add(exponent == 1 ? base : '$base^$exponent');
    }
    return parts.join('·');
  }

  @override
  bool operator ==(Object other) =>
      other is CalcDimension && other.isCompatibleWith(this);

  @override
  int get hashCode {
    var hash = 0;
    for (final base in CalcBaseDimension.order) {
      hash = Object.hash(hash, base, _exponents[base] ?? 0);
    }
    return hash;
  }

  @override
  String toString() => describe();
}

/// A root of a dimension whose exponents are not divisible by the root.
class DimensionRootError implements Exception {
  const DimensionRootError();

  @override
  String toString() => 'unit exponents cannot be split by this root';
}

/// An invalid power applied to a dimension.
class DimensionPowerError implements Exception {
  const DimensionPowerError();

  @override
  String toString() => 'unit exponents must be non-negative integers';
}
