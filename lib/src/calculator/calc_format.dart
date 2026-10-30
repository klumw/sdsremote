/// Result formatting for the engineering calculator.
///
/// Formatting is separated from evaluation so the same value can be shown as
/// engineering notation with an SI prefix, fixed-point, scientific notation
/// or an integer base without changing the stored SI value.
library;

import 'dart:math' as math;

import 'calc_complex.dart';
import 'calc_dimension.dart';
import 'calc_error.dart';
import 'calc_units.dart';
import 'calc_value.dart';

enum CalcNumberFormat { auto, fixed, scientific, engineering }

enum CalcAngleMode { degrees, radians }

/// User-selectable display settings.
class CalcFormatSettings {
  const CalcFormatSettings({
    this.format = CalcNumberFormat.auto,
    this.fractionDigits = 6,
    this.angleMode = CalcAngleMode.degrees,
    this.numberBase = CalcIntegerBase.decimal,
  });

  final CalcNumberFormat format;
  final int fractionDigits;
  final CalcAngleMode angleMode;
  final CalcIntegerBase numberBase;

  CalcFormatSettings copyWith({
    CalcNumberFormat? format,
    int? fractionDigits,
    CalcAngleMode? angleMode,
    CalcIntegerBase? numberBase,
  }) {
    return CalcFormatSettings(
      format: format ?? this.format,
      fractionDigits: fractionDigits ?? this.fractionDigits,
      angleMode: angleMode ?? this.angleMode,
      numberBase: numberBase ?? this.numberBase,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': format.name,
    'fractionDigits': fractionDigits,
    'angleMode': angleMode.name,
    'numberBase': numberBase.name,
  };

  static CalcFormatSettings fromJson(Map<String, dynamic> json) {
    return CalcFormatSettings(
      format: _enumByName(
        CalcNumberFormat.values,
        json['format'],
        CalcNumberFormat.auto,
      ),
      fractionDigits: switch (json['fractionDigits']) {
        final int value => value.clamp(0, 12),
        _ => 6,
      },
      angleMode: _enumByName(
        CalcAngleMode.values,
        json['angleMode'],
        CalcAngleMode.degrees,
      ),
      numberBase: _enumByName(
        CalcIntegerBase.values,
        json['numberBase'],
        CalcIntegerBase.decimal,
      ),
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is String) {
      for (final value in values) {
        if (value.name == name) return value;
      }
    }
    return fallback;
  }
}

/// Formats calculator values according to [settings].
class CalcFormatter {
  CalcFormatter([this.settings = const CalcFormatSettings()]);

  final CalcFormatSettings settings;

  String format(CalcValue value) {
    if (value is CalcBool) return value.value ? 'true' : 'false';
    if (value is CalcText) return value.text;
    if (value is CalcList) {
      return '[${value.items.map(format).join(', ')}]';
    }
    if (value is CalcQuantity) return _formatQuantity(value);
    throw argumentError('unsupported value type ${value.runtimeType}');
  }

  /// The unit symbol that [format] uses for [value], including an automatic
  /// SI prefix. Returns null for dimensionless values and non-numbers.
  ///
  /// History and the AI tool use this so their `unit` field matches the
  /// displayed result (`23 µA`, not the coherent base unit `A`).
  String? unitSymbol(CalcValue value) {
    if (value is! CalcQuantity) return null;
    final logUnit = value.displayUnit;
    if (logUnit != null && logUnit.isLog) return logUnit.symbol;
    if (value.unitMarker && logUnit != null) return logUnit.symbol;
    final scaled = _scale(value);
    if (scaled.unit != null) return scaled.unit!.symbol;
    return value.dimension.isDimensionless ? null : value.dimension.describe();
  }

  /// Formats a quantity without any surrounding UI chrome.
  String _formatQuantity(CalcQuantity quantity) {
    final logUnit = quantity.displayUnit;
    if (logUnit != null && logUnit.isLog) {
      if (!quantity.si.isReal) {
        throw unsupportedError(
          'a complex value cannot be shown as ${logUnit.symbol}',
        );
      }
      final double level;
      try {
        level = logUnit.siToLevel(quantity.si.re);
      } on UnitConversionError catch (error) {
        throw domainError(error.message);
      }
      final number = _formatComponent(level);
      return '$number ${logUnit.symbol}';
    }

    if (quantity.unitMarker) {
      final unit = quantity.displayUnit;
      if (unit == null) return '1';
      if (unit.isLog) {
        final level = unit.siToLevel(quantity.si.re);
        return '${_formatComponent(level)} ${unit.symbol}';
      }
      final value = unit.fromSi(quantity.si.re);
      return '${_formatComponent(value)} ${unit.symbol}';
    }

    final forcedBase = quantity.forcedBase ?? settings.numberBase;
    if (forcedBase != CalcIntegerBase.decimal &&
        quantity.displayUnit == null &&
        quantity.dimension.isDimensionless &&
        quantity.si.isReal &&
        quantity.si.re == quantity.si.re.roundToDouble()) {
      return _formatIntegerBase(quantity.si.re.toInt(), forcedBase);
    }

    if (!quantity.si.isReal &&
        quantity.complexForm == CalcComplexForm.polar &&
        quantity.displayUnit?.isAffine != true) {
      return _formatPolar(quantity);
    }

    final scaled = _scale(quantity);
    final value = scaled.value;
    final unitText =
        scaled.unit?.symbol ??
        (quantity.dimension.isDimensionless
            ? null
            : quantity.dimension.describe());

    if (value.isReal || _formatComponent(value.im) == '0') {
      final number = _formatQuantityReal(value.re, scaled);
      return unitText == null ? number : '$number $unitText';
    }

    final realText = _formatQuantityReal(value.re, scaled);
    final imaginaryText = _formatComponentSigned(value.im.abs(), scaled);
    final unitPart = unitText == null ? '' : ' $unitText';

    if (value.re == 0) {
      final coefficient = _formatComponent(value.im.abs()) == '1'
          ? ''
          : imaginaryText;
      final sign = value.im < 0 ? '-' : '';
      return '${sign}j$coefficient$unitPart';
    }

    final sign = value.im < 0 ? '-' : '+';
    final coefficient = _formatComponent(value.im.abs()) == '1'
        ? ''
        : imaginaryText;
    final body = '$realText $sign j$coefficient';
    return unitText == null ? body : '($body) $unitText';
  }

  String _formatPolar(CalcQuantity quantity) {
    final unit = quantity.displayUnit;
    var magnitude = quantity.si.magnitude;
    double phase = quantity.si.phase;
    String phaseSuffix;
    if (settings.angleMode == CalcAngleMode.degrees) {
      phase = phase * 180 / math.pi;
      phaseSuffix = '°';
    } else {
      phaseSuffix = ' rad';
    }

    String? unitText;
    var scale = 1.0;
    if (unit != null) {
      scale = unit.scale;
      unitText = unit.symbol;
    } else if (quantity.dimension.isDimensionless) {
      unitText = null;
    } else {
      final preferred = CalcUnits.preferredUnitFor(quantity.dimension);
      if (preferred != null) {
        if (preferred.prefixable &&
            (settings.format == CalcNumberFormat.auto ||
                settings.format == CalcNumberFormat.engineering)) {
          final base = magnitude / preferred.scale;
          final exponent = _choosePrefixExponent(base);
          final factor = math.pow(10.0, exponent).toDouble();
          final prefixed = prefixedUnit(preferred, exponent);
          unitText = prefixed.symbol;
          magnitude = base / factor;
          scale = 1;
        } else {
          scale = preferred.scale;
          unitText = preferred.symbol;
        }
      } else {
        unitText = quantity.dimension.describe();
      }
    }
    magnitude /= scale;

    final magnitudeText = _formatComponent(magnitude);
    final phaseText = _formatComponent(phase);
    final suffix = unitText == null ? '' : ' $unitText';
    return '$magnitudeText∠$phaseText$phaseSuffix$suffix';
  }

  _Scaled _scale(CalcQuantity quantity) {
    final explicit = quantity.displayUnit;
    if (explicit != null) {
      return _Scaled(
        unit: explicit,
        value: CalcComplex(
          explicit.fromSi(quantity.si.re),
          quantity.si.im / explicit.scale,
        ),
        prefixed: false,
      );
    }

    if (quantity.dimension.isDimensionless) {
      return _Scaled(unit: null, value: quantity.si, prefixed: false);
    }

    final preferred = CalcUnits.preferredUnitFor(quantity.dimension);
    if (preferred == null) {
      return _Scaled(unit: null, value: quantity.si, prefixed: false);
    }

    final base = quantity.si / CalcComplex.real(preferred.scale);
    if (preferred.prefixable &&
        (settings.format == CalcNumberFormat.auto ||
            settings.format == CalcNumberFormat.engineering)) {
      final maximum = math.max(base.re.abs(), base.im.abs());
      final exponent = _choosePrefixExponent(maximum);
      final factor = math.pow(10.0, exponent).toDouble();
      return _Scaled(
        unit: prefixedUnit(preferred, exponent),
        value: base / CalcComplex.real(factor),
        prefixed: true,
      );
    }
    return _Scaled(unit: preferred, value: base, prefixed: false);
  }

  String _formatQuantityReal(double value, _Scaled scaled) {
    if (value.isNaN) throw domainError('result is not a number');
    if (value.isInfinite) throw domainError('result is infinite');

    switch (settings.format) {
      case CalcNumberFormat.fixed:
        return _plainFixed(value, settings.fractionDigits);
      case CalcNumberFormat.scientific:
        return _scientific(value);
      case CalcNumberFormat.engineering:
        return scaled.prefixed ? _plain(value) : _engineering(value);
      case CalcNumberFormat.auto:
        return _auto(value, hasUnit: scaled.unit != null);
    }
  }

  String _formatComponent(double value) {
    final normalized = _normalizeZero(value);
    switch (settings.format) {
      case CalcNumberFormat.fixed:
        return _plainFixed(normalized, settings.fractionDigits);
      case CalcNumberFormat.scientific:
        return _scientific(normalized);
      case CalcNumberFormat.engineering:
      case CalcNumberFormat.auto:
        return _auto(normalized, hasUnit: false);
    }
  }

  String _formatComponentSigned(double value, _Scaled scaled) =>
      _formatComponent(value);

  static double _normalizeZero(double value) {
    if (value == 0.0 || value.abs() < 5e-13) return 0.0;
    return value;
  }

  static int _choosePrefixExponent(double value) {
    if (!value.isFinite || value == 0) return 0;
    final exponent = (math.log(value.abs()) / math.ln10).floor();
    var engineering = (exponent / 3).floor() * 3;
    if (engineering < -24) engineering = -24;
    if (engineering > 12) engineering = 12;
    return engineering;
  }

  static const Map<int, String> _prefixSymbols = {
    -24: 'y',
    -21: 'z',
    -18: 'a',
    -15: 'f',
    -12: 'p',
    -9: 'n',
    -6: 'µ',
    -3: 'm',
    0: '',
    3: 'k',
    6: 'M',
    9: 'G',
    12: 'T',
  };

  /// Returns the prefixed display unit; exported for unit pickers.
  static CalcUnit prefixedUnit(CalcUnit unit, int exponent) {
    if (exponent == 0) return unit;
    final symbol = _prefixSymbols[exponent];
    if (symbol == null || symbol.isEmpty) return unit;
    final factor = math.pow(10.0, exponent).toDouble();
    return unit.prefixed(symbol, factor);
  }

  static String _auto(double value, {required bool hasUnit}) {
    if (value == 0) return '0';
    final magnitude = value.abs();
    if (magnitude >= 1e12 || magnitude < 1e-9) {
      return _scientific(value);
    }
    return _plain(value);
  }

  static String _plain(double value) {
    final normalized = _normalizeZero(value);
    if (normalized == normalized.roundToDouble() && normalized.abs() < 1e15) {
      return normalized.toInt().toString();
    }
    var text = normalized.toStringAsFixed(10);
    text = _trimZeros(text);
    return text;
  }

  static String _plainFixed(double value, int digits) {
    final normalized = _normalizeZero(value);
    return normalized.toStringAsFixed(digits);
  }

  static String _scientific(double value) {
    final normalized = _normalizeZero(value);
    if (normalized == 0) return '0';
    final exponent = (math.log(normalized.abs()) / math.ln10).floor();
    final mantissa = normalized / math.pow(10.0, exponent);
    final mantissaText = _trimZeros(mantissa.toStringAsFixed(10));
    final sign = exponent >= 0 ? '+' : '';
    return '${mantissaText}e$sign$exponent';
  }

  static String _engineering(double value) {
    final normalized = _normalizeZero(value);
    if (normalized == 0) return '0';
    final exponent = (math.log(normalized.abs()) / math.ln10).floor();
    var engineering = (exponent / 3).floor() * 3;
    if (engineering < -24) engineering = -24;
    if (engineering > 12) engineering = 12;
    final mantissa = normalized / math.pow(10.0, engineering);
    final mantissaText = _trimZeros(mantissa.toStringAsFixed(10));
    if (engineering == 0) return mantissaText;
    final sign = engineering >= 0 ? '+' : '';
    return '${mantissaText}e$sign$engineering';
  }

  static String _trimZeros(String text) {
    if (!text.contains('.')) return text;
    var result = text;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    if (result == '-0') return '0';
    return result;
  }

  static String _formatIntegerBase(int value, CalcIntegerBase base) {
    final negative = value < 0;
    final absolute = value.abs();
    final (String digits, String prefix) = switch (base) {
      CalcIntegerBase.hexadecimal => (
        absolute.toRadixString(16).toUpperCase(),
        '0x',
      ),
      CalcIntegerBase.octal => (absolute.toRadixString(8), '0o'),
      CalcIntegerBase.binary => (absolute.toRadixString(2), '0b'),
      CalcIntegerBase.decimal => (absolute.toString(), ''),
    };
    return negative ? '-$prefix$digits' : '$prefix$digits';
  }
}

class _Scaled {
  const _Scaled({
    required this.unit,
    required this.value,
    required this.prefixed,
  });

  final CalcUnit? unit;
  final CalcComplex value;
  final bool prefixed;
}

/// A compact textual dimension for machine-readable results.
String dimensionName(CalcDimension dimension, {CalcUnit? unit}) {
  if (unit != null) return unit.symbol;
  final preferred = CalcUnits.preferredUnitFor(dimension);
  if (preferred != null) return preferred.symbol;
  return dimension.describe();
}
