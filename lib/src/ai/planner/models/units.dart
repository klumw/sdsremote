/// Deterministic quantity parsing for planner parameters and safety hints.
///
/// The engineering calculator has its own unit registry
/// (`lib/src/calculator/calc_units.dart`). That registry is deliberately
/// case-sensitive and has no oscilloscope voltage bases such as `Vpp` or
/// `Vrms`, while planner input arrives as free text from the model and the
/// input form. This parser therefore normalizes case and understands the
/// voltage bases the safety policy needs. Ambiguous input is rejected instead
/// of guessed so the safety policy fails closed.
library;

import 'dart:math' as math;

/// Physical quantity understood by the planner.
enum QuantityKind {
  voltagePeak,
  voltageRms,
  voltagePeakToPeak,
  frequency,
  time,
  percent,
  dimensionless;

  /// Whether this kind is one of the voltage bases.
  bool get isVoltage =>
      this == voltagePeak || this == voltageRms || this == voltagePeakToPeak;
}

/// A parsed number with its physical quantity and normalized unit token.
class Quantity {
  const Quantity({required this.value, required this.kind, required this.unit});

  /// Numeric value in [unit].
  final double value;

  /// Physical quantity of the value.
  final QuantityKind kind;

  /// Normalized unit token, for example `khz`, `vpp` or an empty string for a
  /// dimensionless value.
  final String unit;

  /// Peak magnitude in volts.
  ///
  /// Peak-to-peak values are halved and RMS values multiplied by sqrt(2).
  /// The sign is dropped because a maximum voltage is a magnitude.
  double get peakValue {
    final magnitude = value.abs();
    return switch (kind) {
      QuantityKind.voltagePeak => magnitude,
      QuantityKind.voltageRms => magnitude * math.sqrt2,
      QuantityKind.voltagePeakToPeak => magnitude / 2,
      _ => magnitude,
    };
  }

  /// Peak-to-peak magnitude in volts.
  ///
  /// Peak values are doubled, RMS values multiplied by 2*sqrt(2), and
  /// peak-to-peak values kept as they are. The sign is dropped.
  double get peakToPeakValue {
    final magnitude = value.abs();
    return switch (kind) {
      QuantityKind.voltagePeak => magnitude * 2,
      QuantityKind.voltageRms => magnitude * 2 * math.sqrt2,
      QuantityKind.voltagePeakToPeak => magnitude,
      _ => magnitude,
    };
  }

  /// Value in coherent SI units for frequency (Hz) and time (s).
  double get siValue => value;
}

class _UnitInfo {
  const _UnitInfo(this.kind, this.factor);

  final QuantityKind kind;
  final double factor;
}

const Map<String, _UnitInfo> _units = <String, _UnitInfo>{
  '': _UnitInfo(QuantityKind.dimensionless, 1),
  '%': _UnitInfo(QuantityKind.percent, 1),
  'v': _UnitInfo(QuantityKind.voltagePeak, 1),
  'volt': _UnitInfo(QuantityKind.voltagePeak, 1),
  'volts': _UnitInfo(QuantityKind.voltagePeak, 1),
  'vp': _UnitInfo(QuantityKind.voltagePeak, 1),
  'vpk': _UnitInfo(QuantityKind.voltagePeak, 1),
  'vpeak': _UnitInfo(QuantityKind.voltagePeak, 1),
  'vrms': _UnitInfo(QuantityKind.voltageRms, 1),
  'vpp': _UnitInfo(QuantityKind.voltagePeakToPeak, 1),
  'vp-p': _UnitInfo(QuantityKind.voltagePeakToPeak, 1),
  'vptp': _UnitInfo(QuantityKind.voltagePeakToPeak, 1),
  'mv': _UnitInfo(QuantityKind.voltagePeak, 1e-3),
  'mvrms': _UnitInfo(QuantityKind.voltageRms, 1e-3),
  'mvpp': _UnitInfo(QuantityKind.voltagePeakToPeak, 1e-3),
  'uv': _UnitInfo(QuantityKind.voltagePeak, 1e-6),
  'uvrms': _UnitInfo(QuantityKind.voltageRms, 1e-6),
  'uvpp': _UnitInfo(QuantityKind.voltagePeakToPeak, 1e-6),
  'kv': _UnitInfo(QuantityKind.voltagePeak, 1e3),
  'kvrms': _UnitInfo(QuantityKind.voltageRms, 1e3),
  'kvpp': _UnitInfo(QuantityKind.voltagePeakToPeak, 1e3),
  'hz': _UnitInfo(QuantityKind.frequency, 1),
  'khz': _UnitInfo(QuantityKind.frequency, 1e3),
  'mhz': _UnitInfo(QuantityKind.frequency, 1e6),
  'ghz': _UnitInfo(QuantityKind.frequency, 1e9),
  's': _UnitInfo(QuantityKind.time, 1),
  'sec': _UnitInfo(QuantityKind.time, 1),
  'secs': _UnitInfo(QuantityKind.time, 1),
  'second': _UnitInfo(QuantityKind.time, 1),
  'seconds': _UnitInfo(QuantityKind.time, 1),
  'ms': _UnitInfo(QuantityKind.time, 1e-3),
  'us': _UnitInfo(QuantityKind.time, 1e-6),
  'ns': _UnitInfo(QuantityKind.time, 1e-9),
  'ps': _UnitInfo(QuantityKind.time, 1e-12),
};

final RegExp _quantityPattern = RegExp(
  r'^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([a-zA-Zµμ%_-]*)\s*$',
);

/// Parses a number, optionally followed by a unit, into a [Quantity].
///
/// Returns `null` when the value is missing, not finite, uses an unknown unit
/// or does not match [expected] (voltage kinds accept any voltage base).
Quantity? tryParseQuantity(
  Object? raw, {
  QuantityKind? expected,
  String field = 'value',
}) {
  if (raw == null) return null;

  if (raw is num) {
    final value = raw.toDouble();
    if (!value.isFinite) return null;
    final kind = expected ?? QuantityKind.dimensionless;
    return Quantity(value: value, kind: kind, unit: '');
  }

  if (raw is! String) return null;
  final match = _quantityPattern.firstMatch(raw);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null || !number.isFinite) return null;

  final unit = _normalizeUnit(match.group(2)!);
  final info = _units[unit];
  if (info == null) return null;

  // A bare number typed into a field that declares its unit belongs to that
  // unit, for example "50" in a percent field or "1000" in a frequency field.
  var kind = info.kind;
  if (kind == QuantityKind.dimensionless && expected != null) {
    kind = expected;
  }
  if (expected != null) {
    final compatible =
        expected == kind || (expected.isVoltage && kind.isVoltage);
    if (!compatible) return null;
  }

  return Quantity(value: number * info.factor, kind: kind, unit: unit);
}

/// Parses an optional maximum voltage into its peak magnitude in volts.
///
/// Accepts `V`, `Vpk`, `Vrms`, `Vpp` and prefixed forms. Returns `null` for
/// every value the parser cannot classify, which the safety policy treats as
/// unknown and therefore never safe.
double? tryParsePeakVoltage(Object? raw) =>
    tryParseQuantity(raw, expected: QuantityKind.voltagePeak)?.peakValue;

/// Parses an optional frequency into hertz.
double? tryParseFrequencyHz(Object? raw) =>
    tryParseQuantity(raw, expected: QuantityKind.frequency)?.siValue;

/// Parses an optional duration into seconds.
double? tryParseTimeSeconds(Object? raw) =>
    tryParseQuantity(raw, expected: QuantityKind.time)?.siValue;

/// Parses an optional percentage into percent (0-100).
double? tryParsePercent(Object? raw) {
  final quantity = tryParseQuantity(raw, expected: QuantityKind.percent);
  if (quantity == null) return null;
  return quantity.siValue;
}

String _normalizeUnit(String raw) {
  var unit = raw.trim().toLowerCase().replaceAll('μ', 'u');
  unit = unit.replaceAll('µ', 'u');
  return unit;
}
