/// Pure, deterministic mathematics behind the `math_tool`.
///
/// Nothing in this file touches Dartantic, the AI layer or the instrument — it
/// is plain, testable arithmetic. The tool in `math_tool.dart` only parses
/// arguments, dispatches and formats.
///
/// Conventions used throughout:
/// - Every function returns a real (non-complex) result and throws
///   [MathException] when the operation is mathematically undefined. Nothing
///   is ever silently replaced by zero, NaN or infinity.
/// - Results that cannot be represented as a finite double (overflow) are
///   rejected rather than returned as infinity.
library;

import 'dart:math' as math;

import '../../instrument/measurement.dart' show formatMeasurementValue;

// =============================================================================
// Errors
// =============================================================================

/// A mathematical error that the agent should be told about verbatim.
///
/// Carries no stack trace and no internal detail — the message is written for
/// the model, e.g. `division by zero`.
class MathException implements Exception {
  final String message;
  MathException(this.message);

  @override
  String toString() => message;
}

// =============================================================================
// Input validation
// =============================================================================

/// Rejects NaN, infinities and non-finite results.
double _finite(double value, String label) {
  if (value.isNaN) {
    throw MathException('$label is not a number (NaN)');
  }
  if (value.isInfinite) {
    throw MathException('$label must be finite, but overflowed to infinity');
  }
  return value;
}

/// Rejects an empty sample array with a message naming the operation.
List<double> requireSamples(List<double> values, String operation) {
  if (values.isEmpty) {
    throw MathException('$operation requires at least one sample');
  }
  return values;
}

// =============================================================================
// Units
// =============================================================================

/// Physical dimension a unit belongs to.
///
/// Units of different dimensions cannot be converted into each other and are
/// rejected by [convertUnit].
enum UnitDimension {
  dimensionless,
  voltage,
  current,
  time,
  frequency,
  resistance,
  power,
  energy,
  angle,
}

/// A unit known to the tool: its canonical symbol, dimension and the factor
/// that converts a value in this unit into the dimension's base unit.
class UnitDef {
  /// Canonical spelling, e.g. `mV`.
  final String symbol;
  final UnitDimension dimension;

  /// `value_in_base_unit = value_in_this_unit * factor`.
  final double factor;

  const UnitDef(this.symbol, this.dimension, this.factor);
}

/// Base unit per dimension.
const Map<UnitDimension, String> baseUnits = {
  UnitDimension.dimensionless: '',
  UnitDimension.voltage: 'V',
  UnitDimension.current: 'A',
  UnitDimension.time: 's',
  UnitDimension.frequency: 'Hz',
  UnitDimension.resistance: 'ohm',
  UnitDimension.power: 'W',
  UnitDimension.energy: 'J',
  UnitDimension.angle: 'rad',
};

/// Accepted spellings per unit. Symbols are normalised before lookup (see
/// [_normalizeSymbol]), so micro and ohm variants need no separate entries.
const Map<String, UnitDef> _units = {
  // Voltage
  'v': UnitDef('V', UnitDimension.voltage, 1),
  'mv': UnitDef('mV', UnitDimension.voltage, 1e-3),
  'uv': UnitDef('uV', UnitDimension.voltage, 1e-6),
  // Current
  'a': UnitDef('A', UnitDimension.current, 1),
  'ma': UnitDef('mA', UnitDimension.current, 1e-3),
  'ua': UnitDef('uA', UnitDimension.current, 1e-6),
  // Time
  's': UnitDef('s', UnitDimension.time, 1),
  'ms': UnitDef('ms', UnitDimension.time, 1e-3),
  'us': UnitDef('us', UnitDimension.time, 1e-6),
  'ns': UnitDef('ns', UnitDimension.time, 1e-9),
  // Frequency
  'hz': UnitDef('Hz', UnitDimension.frequency, 1),
  'khz': UnitDef('kHz', UnitDimension.frequency, 1e3),
  'mhz': UnitDef('MHz', UnitDimension.frequency, 1e6),
  'ghz': UnitDef('GHz', UnitDimension.frequency, 1e9),
  // Resistance
  'ohm': UnitDef('ohm', UnitDimension.resistance, 1),
  'kohm': UnitDef('kohm', UnitDimension.resistance, 1e3),
  'mohm': UnitDef('Mohm', UnitDimension.resistance, 1e6),
  // Power
  'w': UnitDef('W', UnitDimension.power, 1),
  'mw': UnitDef('mW', UnitDimension.power, 1e-3),
  'uw': UnitDef('uW', UnitDimension.power, 1e-6),
  // Energy
  'j': UnitDef('J', UnitDimension.energy, 1),
  // Angle
  'rad': UnitDef('rad', UnitDimension.angle, 1),
  'deg': UnitDef('deg', UnitDimension.angle, math.pi / 180),
  // Dimensionless
  '': UnitDef('', UnitDimension.dimensionless, 1),
  '1': UnitDef('', UnitDimension.dimensionless, 1),
  'none': UnitDef('', UnitDimension.dimensionless, 1),
  '%': UnitDef('%', UnitDimension.dimensionless, 0.01),
};

/// Normalises a unit spelling so that `µV`, `μV`, `uV` and `UV` all resolve,
/// as do `Ω`, `ω` and `Ohm`.
String _normalizeSymbol(String symbol) => symbol
    .trim()
    .replaceAll('µ', 'u') // micro sign
    .replaceAll('μ', 'u') // greek small mu
    .replaceAll('Ω', 'ohm') // greek capital omega
    .replaceAll('ω', 'ohm') // greek small omega
    .toLowerCase();

/// Looks up a unit, or throws a [MathException] naming the unknown symbol.
UnitDef resolveUnit(String symbol) {
  final unit = _units[_normalizeSymbol(symbol)];
  if (unit == null) {
    throw MathException('unknown unit "$symbol"');
  }
  return unit;
}

/// Result of a successful unit conversion.
class UnitConversion {
  /// The converted value, expressed in [to]'s symbol.
  final double value;
  final UnitDef from;
  final UnitDef to;

  /// The converted value expressed in the dimension's base unit.
  final double baseValue;

  const UnitConversion(this.value, this.from, this.to, this.baseValue);
}

/// Converts [value] from one unit to another of the same dimension.
///
/// Throws when either symbol is unknown or the dimensions differ.
UnitConversion convertUnit(double value, String fromSymbol, String toSymbol) {
  final from = resolveUnit(fromSymbol);
  final to = resolveUnit(toSymbol);
  if (from.dimension != to.dimension) {
    throw MathException(
      'incompatible units: "$fromSymbol" (${from.dimension.name}) cannot be '
      'converted to "$toSymbol" (${to.dimension.name})',
    );
  }
  final baseValue = _finite(value * from.factor, 'converted value');
  return UnitConversion(
    _finite(baseValue / to.factor, 'converted value'),
    from,
    to,
    baseValue,
  );
}

// =============================================================================
// Formatting
// =============================================================================

/// Formats a result for the `formatted` field.
///
/// Units that take SI prefixes (V, A, s, Hz, W, J, ohm) go through the shared
/// measurement formatter, so the tool and the rest of the app render values
/// identically. Logarithmic and ratio-like units (dB, %, dimensionless) must
/// not take prefixes — "20 mdB" would be nonsense — so they are printed with
/// plain decimal places instead.
String formatMathResult(double value, String unit, {int decimals = 4}) {
  if (unit.isEmpty || unit == '%' || unit == 'dB' || unit == 'deg') {
    final text = _trimZeros(value.toStringAsFixed(decimals));
    return unit.isEmpty ? text : '$text $unit';
  }
  return formatMeasurementValue(value, unit);
}

String _trimZeros(String text) {
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

// =============================================================================
// Calculator — arithmetic
// =============================================================================

double mathAdd(double a, double b) => _finite(a + b, 'sum');

double mathSubtract(double a, double b) => _finite(a - b, 'difference');

double mathMultiply(double a, double b) => _finite(a * b, 'product');

double mathDivide(double a, double b) {
  if (b == 0) throw MathException('division by zero');
  return _finite(a / b, 'quotient');
}

/// Truncating division: `mathIntDivide(-7, 2) == -3` (truncation toward zero).
double mathIntDivide(double a, double b) {
  if (b == 0) throw MathException('division by zero');
  return _finite((a / b).truncateToDouble(), 'quotient');
}

/// Euclidean modulo, matching Dart's `%` operator: the result is always
/// non-negative and smaller than `b.abs()`, whatever the signs of the
/// operands. So `modulo(-5, 3) == 1` and `modulo(5, -3) == 2`.
///
/// This is *not* the truncated remainder some calculators produce (which
/// would give `-2` and `2`); use [mathIntDivide] plus multiplication to
/// reconstruct the truncated form if it is ever needed.
double mathModulo(double a, double b) {
  if (b == 0) throw MathException('modulo by zero');
  return _finite(a % b, 'remainder');
}

double mathNegate(double a) => _finite(-a, 'result');

double mathAbs(double a) => _finite(a.abs(), 'result');

// =============================================================================
// Calculator — powers and roots
// =============================================================================

double mathSquare(double a) => _finite(a * a, 'square');

/// [a] raised to [b].
///
/// A negative base with a non-integral exponent has no real result and is
/// rejected instead of returning NaN.
double mathPower(double a, double b) {
  if (a == 0 && b < 0) {
    throw MathException('zero cannot be raised to a negative power');
  }
  if (a < 0 && b != b.roundToDouble()) {
    throw MathException(
      'a negative base with a fractional exponent ($b) has no real result',
    );
  }
  return _finite(math.pow(a, b).toDouble(), 'power');
}

double mathSqrt(double a) {
  if (a < 0) throw MathException('square root of a negative value ($a)');
  return _finite(math.sqrt(a), 'square root');
}

/// Cube root. Unlike [mathSqrt] this is defined for negative values.
double mathCbrt(double a) {
  if (a == 0) return 0;
  final magnitude = math.pow(a.abs(), 1 / 3).toDouble();
  return _finite(a.isNegative ? -magnitude : magnitude, 'cube root');
}

/// The real n-th root of [a].
///
/// Even roots of negative values have no real result; odd roots do.
double mathNthRoot(double a, double n) {
  if (n == 0) throw MathException('the root degree must not be zero');
  if (a == 0) {
    if (n < 0) {
      throw MathException('the n-th root of zero is undefined for n < 0');
    }
    return 0;
  }
  if (a < 0) {
    final isOddIntegerDegree =
        n == n.roundToDouble() && n.round().isOdd;
    if (!isOddIntegerDegree) {
      throw MathException(
        'the n-th root of a negative value ($a) has no real result',
      );
    }
    return _finite(-math.pow(-a, 1 / n).toDouble(), 'n-th root');
  }
  return _finite(math.pow(a, 1 / n).toDouble(), 'n-th root');
}

double mathReciprocal(double a) {
  if (a == 0) throw MathException('division by zero (reciprocal of zero)');
  return _finite(1 / a, 'reciprocal');
}

// =============================================================================
// Calculator — logarithms and exponentials
// =============================================================================

double mathLn(double a) {
  if (a <= 0) {
    throw MathException(
      'the logarithm is defined for positive values only (got $a)',
    );
  }
  return _finite(math.log(a), 'natural logarithm');
}

double mathLog10(double a) {
  if (a <= 0) {
    throw MathException(
      'the logarithm is defined for positive values only (got $a)',
    );
  }
  return _finite(math.log(a) / math.ln10, 'base-10 logarithm');
}

/// Logarithm of [a] to an arbitrary [base].
double mathLog(double a, double base) {
  if (a <= 0) {
    throw MathException(
      'the logarithm is defined for positive values only (got $a)',
    );
  }
  if (base <= 0) {
    throw MathException('the logarithm base must be positive (got $base)');
  }
  if (base == 1) throw MathException('the logarithm base must not be 1');
  return _finite(math.log(a) / math.log(base), 'logarithm');
}

double mathExp(double a) => _finite(math.exp(a), 'exponential');

double mathPow10(double a) =>
    _finite(math.pow(10, a).toDouble(), 'power of ten');

// =============================================================================
// Calculator — trigonometry
// =============================================================================

/// Converts [value] from [angleUnit] (`rad` or `deg`) to radians.
double toRadians(double value, String angleUnit) {
  final unit = resolveUnit(angleUnit);
  if (unit.dimension != UnitDimension.angle) {
    throw MathException(
      '"$angleUnit" is not an angle unit (use "rad" or "deg")',
    );
  }
  return value * unit.factor;
}

/// Converts [radians] into [angleUnit] (`rad` or `deg`).
double fromRadians(double radians, String angleUnit) {
  final unit = resolveUnit(angleUnit);
  if (unit.dimension != UnitDimension.angle) {
    throw MathException(
      '"$angleUnit" is not an angle unit (use "rad" or "deg")',
    );
  }
  return radians / unit.factor;
}

double mathSin(double a, String angleUnit) =>
    _finite(math.sin(toRadians(a, angleUnit)), 'sine');

double mathCos(double a, String angleUnit) =>
    _finite(math.cos(toRadians(a, angleUnit)), 'cosine');

double mathTan(double a, String angleUnit) =>
    _finite(math.tan(toRadians(a, angleUnit)), 'tangent');

double mathAsin(double a, String angleUnit) {
  if (a < -1 || a > 1) {
    throw MathException('the argument of asin must be within [-1, 1] (got $a)');
  }
  return _finite(fromRadians(math.asin(a), angleUnit), 'arc sine');
}

double mathAcos(double a, String angleUnit) {
  if (a < -1 || a > 1) {
    throw MathException('the argument of acos must be within [-1, 1] (got $a)');
  }
  return _finite(fromRadians(math.acos(a), angleUnit), 'arc cosine');
}

double mathAtan(double a, String angleUnit) =>
    _finite(fromRadians(math.atan(a), angleUnit), 'arc tangent');

/// Two-argument arc tangent: [y] over [x], in [angleUnit].
///
/// The quadrant follows the signs of both arguments, so the result lies in
/// (-180°, 180°] or (-π, π].
double mathAtan2(double y, double x, String angleUnit) {
  if (x == 0 && y == 0) {
    throw MathException('atan2 is undefined for x = 0 and y = 0');
  }
  return _finite(fromRadians(math.atan2(y, x), angleUnit), 'arc tangent');
}

// =============================================================================
// Calculator — rounding, aggregates and misc
// =============================================================================

double mathFloor(double a) => _finite(a.floorToDouble(), 'result');

double mathCeil(double a) => _finite(a.ceilToDouble(), 'result');

/// Rounds half away from zero, matching `double.round()`.
double mathRound(double a) => _finite(a.roundToDouble(), 'result');

double mathMinOf(List<double> values) {
  requireSamples(values, 'min');
  var best = values.first;
  for (final v in values) {
    if (v < best) best = v;
  }
  return _finite(best, 'minimum');
}

double mathMaxOf(List<double> values) {
  requireSamples(values, 'max');
  var best = values.first;
  for (final v in values) {
    if (v > best) best = v;
  }
  return _finite(best, 'maximum');
}

double mathSum(List<double> values) {
  requireSamples(values, 'sum');
  var total = 0.0;
  for (final v in values) {
    total = _finite(total + v, 'sum');
  }
  return total;
}

/// Arithmetic mean. For uniformly sampled data this equals the time-weighted
/// mean, which is how oscilloscope measurements are defined.
double mathMean(List<double> values) {
  requireSamples(values, 'mean');
  return _finite(mathSum(values) / values.length, 'mean');
}

/// Restricts [a] to the inclusive range [low]..[high].
double mathClamp(double a, double low, double high) {
  if (low > high) {
    throw MathException('clamp bounds are inverted: low ($low) > high ($high)');
  }
  return _finite(a.clamp(low, high).toDouble(), 'clamped value');
}

/// Length of the hypotenuse, computed with scaling so that large intermediate
/// squares cannot overflow.
double mathHypot(double a, double b) {
  if (a == 0 && b == 0) return 0;
  final scale = math.max(a.abs(), b.abs());
  final na = a / scale;
  final nb = b / scale;
  return _finite(scale * math.sqrt(na * na + nb * nb), 'hypotenuse');
}

/// Factorial of a non-negative integer.
///
/// Limited to 170 — beyond that the result exceeds the range of a double.
double mathFactorial(double a) {
  if (a < 0) {
    throw MathException(
      'factorial is defined for non-negative values (got $a)',
    );
  }
  if (a != a.roundToDouble()) {
    throw MathException('factorial requires a whole number (got $a)');
  }
  if (a > 170) {
    throw MathException('factorial is limited to 170 (got $a)');
  }
  var result = 1.0;
  for (var i = 2; i <= a.round(); i++) {
    result *= i;
  }
  return _finite(result, 'factorial');
}

// =============================================================================
// Oscilloscope — voltage measurements
// =============================================================================

/// `v_max - v_min`. Always non-negative.
double peakToPeak(List<double> values) {
  return _finite(
    mathMaxOf(values) - mathMinOf(values),
    'peak-to-peak voltage',
  );
}

/// `v_max - reference`.
double peakPositive(List<double> values, double reference) {
  return _finite(mathMaxOf(values) - reference, 'positive peak');
}

/// `v_min - reference` — negative for a signal that dips below the reference.
double peakNegative(List<double> values, double reference) {
  return _finite(mathMinOf(values) - reference, 'negative peak');
}

/// Largest deviation from [reference]: `max(|v_max - ref|, |ref - v_min|)`.
///
/// For a signal that is symmetric about the reference this equals half the
/// peak-to-peak voltage; for an asymmetric one it does not, which is why the
/// reference is an explicit argument rather than being assumed.
double peakAmplitude(List<double> values, double reference) {
  final top = mathMaxOf(values) - reference;
  final bottom = reference - mathMinOf(values);
  return _finite(math.max(top.abs(), bottom.abs()), 'peak amplitude');
}

/// Arithmetic mean of the samples.
///
/// Uniform sampling makes this identical to the time-weighted mean, which is
/// the definition the oscilloscope uses for its MEAN measurement. For
/// irregular sampling it is an approximation.
double meanVoltage(List<double> values) => mathMean(values);

/// Root mean square including the DC component: `sqrt(sum(v^2) / N)`.
double rmsVoltage(List<double> values) {
  requireSamples(values, 'rms_voltage');
  var squares = 0.0;
  for (final v in values) {
    squares = _finite(squares + v * v, 'sum of squares');
  }
  return _finite(math.sqrt(squares / values.length), 'RMS voltage');
}

/// RMS of the AC component only, with the DC component removed:
/// `sqrt(mean((v - mean(v))^2))`.
///
/// This is what an oscilloscope reports as "AC RMS" or "RMS of the AC part".
double acRmsVoltage(List<double> values) {
  requireSamples(values, 'ac_rms_voltage');
  final mean = mathMean(values);
  var squares = 0.0;
  for (final v in values) {
    final deviation = v - mean;
    squares = _finite(squares + deviation * deviation, 'sum of squares');
  }
  return _finite(math.sqrt(squares / values.length), 'AC RMS voltage');
}

/// Peak magnitude divided by RMS: `max(|v|) / rms(v)`.
///
/// The peak is the largest magnitude relative to zero. For a sine wave this is
/// ~1.414, for a square wave 1.0 and for a pure DC signal 1.0.
double crestFactor(List<double> values) {
  requireSamples(values, 'crest_factor');
  var peak = 0.0;
  for (final v in values) {
    final magnitude = v.abs();
    if (magnitude > peak) peak = magnitude;
  }
  final rms = rmsVoltage(values);
  if (rms == 0) {
    throw MathException('crest factor is undefined: the RMS value is zero');
  }
  return _finite(peak / rms, 'crest factor');
}

/// RMS divided by the mean absolute value: `rms(v) / mean(|v|)`.
///
/// For a sine wave this is ~1.111, for a square wave 1.0.
double formFactor(List<double> values) {
  requireSamples(values, 'form_factor');
  var absoluteSum = 0.0;
  for (final v in values) {
    absoluteSum = _finite(absoluteSum + v.abs(), 'sum of magnitudes');
  }
  final meanAbsolute = absoluteSum / values.length;
  if (meanAbsolute == 0) {
    throw MathException(
      'form factor is undefined: the mean absolute voltage is zero',
    );
  }
  return _finite(rmsVoltage(values) / meanAbsolute, 'form factor');
}

// =============================================================================
// Oscilloscope — time and frequency
// =============================================================================

double periodFromFrequency(double frequency) {
  if (frequency <= 0) {
    throw MathException(
      'the frequency must be greater than zero (got $frequency)',
    );
  }
  return _finite(1 / frequency, 'period');
}

double frequencyFromPeriod(double period) {
  if (period <= 0) {
    throw MathException('the period must be greater than zero (got $period)');
  }
  return _finite(1 / period, 'frequency');
}

/// Frequency from a number of complete cycles and the time they took.
double frequencyFromCycles(double cycles, double elapsedTime) {
  if (cycles <= 0) {
    throw MathException(
      'the number of cycles must be greater than zero (got $cycles)',
    );
  }
  if (elapsedTime <= 0) {
    throw MathException(
      'the elapsed time must be greater than zero (got $elapsedTime)',
    );
  }
  return _finite(cycles / elapsedTime, 'frequency');
}

/// `t2 - t1`. The operand order is preserved, so the result can be negative.
double timeDifference(double t2, double t1) =>
    _finite(t2 - t1, 'time difference');

/// `100 * high_time / period`, in percent.
double dutyCycle(double highTime, double period) {
  if (period <= 0) {
    throw MathException('the period must be greater than zero (got $period)');
  }
  if (highTime < 0) {
    throw MathException('the high time must not be negative (got $highTime)');
  }
  if (highTime > period) {
    throw MathException(
      'impossible timing: the high time ($highTime) exceeds the period '
      '($period)',
    );
  }
  return _finite(100 * highTime / period, 'duty cycle');
}

/// Duration of a pulse between its rising and falling edges.
double pulseWidth(double riseTimestamp, double fallTimestamp) {
  if (fallTimestamp < riseTimestamp) {
    throw MathException(
      'impossible timing: the falling edge ($fallTimestamp) precedes the '
      'rising edge ($riseTimestamp)',
    );
  }
  return _finite(fallTimestamp - riseTimestamp, 'pulse width');
}

/// Time of the first crossing of [level] in the given direction, starting at
/// sample [from], interpolated between the two neighbouring samples.
/// Returns null when no such crossing exists.
double? _crossingTime(
  List<double> values,
  double sampleInterval,
  double level,
  int from,
  bool rising,
) {
  for (var i = from; i < values.length - 1; i++) {
    final first = values[i];
    final second = values[i + 1];
    // The segment must actually move in the expected direction, so a flat
    // run that merely touches the level does not count as an edge. The
    // comparisons are inclusive at both ends so that a threshold sitting
    // exactly on the minimum (0 %) or maximum (100 %) is still found.
    final crosses = rising
        ? first <= level && second >= level && second > first
        : first >= level && second <= level && second < first;
    if (!crosses) continue;
    final fraction = (level - first) / (second - first);
    return (i + fraction) * sampleInterval;
  }
  return null;
}

/// Rise time between configurable thresholds, defaulting to 10 % and 90 % of
/// the waveform's own range (min..max).
///
/// The first rising edge in the record is used, and the crossing is
/// interpolated between the two neighbouring samples so the result is not
/// quantised to the sample interval.
double riseTime(
  List<double> values,
  double sampleInterval, {
  double lowPercent = 10,
  double highPercent = 90,
}) => _edgeTime(
  values,
  sampleInterval,
  lowPercent: lowPercent,
  highPercent: highPercent,
  rising: true,
  operation: 'rise_time',
);

/// Fall time between configurable thresholds, defaulting to 90 % and 10 % of
/// the waveform's own range. The first falling edge is used.
double fallTime(
  List<double> values,
  double sampleInterval, {
  double lowPercent = 10,
  double highPercent = 90,
}) => _edgeTime(
  values,
  sampleInterval,
  lowPercent: lowPercent,
  highPercent: highPercent,
  rising: false,
  operation: 'fall_time',
);

double _edgeTime(
  List<double> values,
  double sampleInterval, {
  required double lowPercent,
  required double highPercent,
  required bool rising,
  required String operation,
}) {
  requireSamples(values, operation);
  if (values.length < 2) {
    throw MathException('$operation needs at least two samples');
  }
  if (sampleInterval <= 0) {
    throw MathException(
      'the sample interval must be greater than zero (got $sampleInterval)',
    );
  }
  if (lowPercent < 0 || highPercent > 100 || lowPercent >= highPercent) {
    throw MathException(
      '$operation requires 0 <= low_percent < high_percent <= 100 '
      '(got $lowPercent and $highPercent)',
    );
  }

  final top = mathMaxOf(values);
  final bottom = mathMinOf(values);
  if (top == bottom) {
    throw MathException(
      '$operation is undefined for a flat waveform: there is no amplitude to '
      'measure the thresholds against',
    );
  }

  final span = top - bottom;
  final lowLevel = bottom + span * lowPercent / 100;
  final highLevel = bottom + span * highPercent / 100;

  // A rising edge starts at the low threshold, a falling edge at the high one.
  final startLevel = rising ? lowLevel : highLevel;
  final endLevel = rising ? highLevel : lowLevel;

  final start = _crossingTime(values, sampleInterval, startLevel, 0, rising);
  if (start == null) {
    throw MathException(
      '$operation found no ${rising ? 'rising' : 'falling'} crossing of the '
      '$lowPercent % level',
    );
  }
  final startIndex = (start / sampleInterval).floor();
  final end = _crossingTime(
    values,
    sampleInterval,
    endLevel,
    startIndex,
    rising,
  );
  if (end == null) {
    throw MathException(
      '$operation found no ${rising ? 'rising' : 'falling'} crossing of the '
      '$highPercent % level',
    );
  }
  return _finite(end - start, operation);
}

// =============================================================================
// Oscilloscope — phase and gain
// =============================================================================

/// Linear voltage gain `vout / vin`.
///
/// Signed: it is negative when the output is inverted, and no absolute value
/// is taken.
double voltageGain(double vout, double vin) {
  if (vin == 0) {
    throw MathException('voltage gain is undefined: the input voltage is zero');
  }
  return _finite(vout / vin, 'voltage gain');
}

/// Power gain in decibels: `10 * log10(pout / pin)`.
///
/// Both powers must be positive and expressed in the same unit against the
/// same impedance.
double powerGainDb(double pout, double pin) {
  if (pin <= 0) {
    throw MathException(
      'power gain requires a positive input power (got $pin)',
    );
  }
  if (pout <= 0) {
    throw MathException(
      'power gain requires a positive output power (got $pout)',
    );
  }
  return _finite(10 * (math.log(pout / pin) / math.ln10), 'power gain');
}

/// Phase shift in degrees from a time delay: `360 * delta_t / period`.
///
/// Sign convention: [deltaT] is the delay of the measured signal relative to
/// the reference, so a signal that lags gives a positive phase shift and a
/// signal that leads gives a negative one. The result is not wrapped into
/// [0, 360).
double phaseShiftDegrees(double deltaT, double period) {
  if (period <= 0) {
    throw MathException('the period must be greater than zero (got $period)');
  }
  return _finite(360 * deltaT / period, 'phase shift');
}

/// Phase shift in radians from a time delay: `2 * pi * frequency * delta_t`.
///
/// Same sign convention as [phaseShiftDegrees].
double phaseShiftRadians(double frequency, double deltaT) {
  if (frequency <= 0) {
    throw MathException(
      'the frequency must be greater than zero (got $frequency)',
    );
  }
  return _finite(2 * math.pi * frequency * deltaT, 'phase shift');
}
