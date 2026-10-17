/// Deterministic parser and formatter for oscilloscope PAVA measurement
/// responses.
///
/// This library is intentionally free of any AI/LLM dependency. Parsing and
/// unit conversion are pure, deterministic code so the same input string always
/// produces the same structured result. Parsing ([parseMeasurement]) and
/// presentation ([formatMeasurement]) are kept separate: the
/// [OscilloscopeMeasurement] model carries only semantic data and does not
/// depend on its later rendering.
///
/// Supported input format:
/// ```text
/// C1:PAVA PKPK,3.000000E+00V
/// C1:PAVA FREQ,9.998900E+02Hz
/// ```
library;

// =============================================================================
// Measurement type registry
// =============================================================================

/// Physical dimension of a measurement value.
enum MeasurementDimension {
  /// A voltage measurement (base unit: volt).
  voltage,

  /// A frequency measurement (base unit: hertz).
  frequency,
}

/// Describes a single measurement type supported by the parser.
///
/// A type maps the instrument's measurement token (e.g. `PKPK`) to its
/// canonical unit and physical dimension. New measurement types are added by
/// registering a [MeasurementType] in [measurementTypes] — no parser changes
/// are required, which keeps the design extensible for `PERIOD`, `DUTY`,
/// `RISE`, `FALL`, `WIDTH`, `AMPLITUDE`, `SKEW`, `PHASE`, `OVERSHOOT`,
/// `UNDERSHOOT`, etc.
class MeasurementType {
  /// Canonical (uppercase) measurement name, e.g. `PKPK`.
  final String name;

  /// Canonical base unit for this measurement, e.g. `V` or `Hz`.
  final String unit;

  /// The physical dimension this measurement belongs to.
  final MeasurementDimension dimension;

  /// Creates a measurement type description.
  const MeasurementType({
    required this.name,
    required this.unit,
    required this.dimension,
  });
}

/// Registry of all supported measurement types, keyed by canonical uppercase
/// measurement name.
const Map<String, MeasurementType> measurementTypes = {
  // Voltage measurements (base unit: volt).
  'PKPK': MeasurementType(
    name: 'PKPK',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),
  'MAX': MeasurementType(
    name: 'MAX',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),
  'MIN': MeasurementType(
    name: 'MIN',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),
  'AMPL': MeasurementType(
    name: 'AMPL',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),
  'MEAN': MeasurementType(
    name: 'MEAN',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),
  'RMS': MeasurementType(
    name: 'RMS',
    unit: 'V',
    dimension: MeasurementDimension.voltage,
  ),

  // Frequency measurements (base unit: hertz).
  'FREQ': MeasurementType(
    name: 'FREQ',
    unit: 'Hz',
    dimension: MeasurementDimension.frequency,
  ),
};

// =============================================================================
// Structured measurement model
// =============================================================================

/// A parsed oscilloscope measurement.
///
/// This is a pure data structure and is independent of any presentation
/// concern. Use [formatMeasurement] to obtain a human-readable string.
class OscilloscopeMeasurement {
  /// Channel the measurement belongs to, normalized to uppercase (e.g. `C1`).
  final String channel;

  /// Canonical uppercase measurement type (e.g. `PKPK`, `FREQ`).
  final String measurement;

  /// Numeric value in the measurement's base unit.
  final double value;

  /// Canonical base unit (e.g. `V`, `Hz`).
  final String unit;

  /// Creates a structured measurement.
  const OscilloscopeMeasurement({
    required this.channel,
    required this.measurement,
    required this.value,
    required this.unit,
  });

  /// The registry entry describing this measurement's type.
  MeasurementType get type => measurementTypes[measurement]!;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OscilloscopeMeasurement &&
          channel == other.channel &&
          measurement == other.measurement &&
          value == other.value &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(channel, measurement, value, unit);

  @override
  String toString() =>
      'OscilloscopeMeasurement(channel: $channel, measurement: $measurement, '
      'value: $value, unit: $unit)';
}

// =============================================================================
// Parsing
// =============================================================================

/// Matches `<channel>:PAVA <measurement>,<value><unit>` case-insensitively.
///
/// Groups:
/// - 1: channel (`C1`..`C4`)
/// - 2: measurement type token
/// - 3: numeric value (signed decimal / scientific notation)
/// - 4: unit suffix (letters only)
final RegExp _measurementPattern = RegExp(
  r'^(C[1-4]):PAVA[ \t]+([A-Za-z]+),'
  r'([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?)'
  r'([A-Za-z]+)$',
  caseSensitive: false,
);

/// Parses a raw oscilloscope measurement string into a structured value.
///
/// Accepts strings such as `C1:PAVA PKPK,3.000000E+00V`. Channel, measurement
/// type and unit are treated case-insensitively; the returned model always
/// carries canonical uppercase values.
///
/// Throws a [FormatException] for any invalid input, including an empty string,
/// a malformed layout, an out-of-range channel, an unknown measurement type, a
/// missing/unparseable numeric value, or a unit that does not match the
/// measurement type. The parser never returns a silently incorrect value.
OscilloscopeMeasurement parseMeasurement(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw FormatException('Invalid measurement format: empty input', raw);
  }

  final match = _measurementPattern.firstMatch(trimmed);
  if (match == null) {
    throw FormatException(
      'Invalid measurement format: "$trimmed" does not match '
      '"<channel>:PAVA <measurement>,<value><unit>"',
      raw,
    );
  }

  final channel = match.group(1)!.toUpperCase();
  final measurement = match.group(2)!.toUpperCase();
  final numberText = match.group(3)!;
  final unitText = match.group(4)!;

  final type = measurementTypes[measurement];
  if (type == null) {
    throw FormatException('Unsupported measurement type "$measurement"', raw);
  }

  if (unitText.toLowerCase() != type.unit.toLowerCase()) {
    throw FormatException(
      'Unit mismatch for "$measurement": expected "${type.unit}" '
      'but got "$unitText"',
      raw,
    );
  }

  final value = double.tryParse(numberText);
  if (value == null) {
    throw FormatException('Invalid numeric value "$numberText"', raw);
  }

  return OscilloscopeMeasurement(
    channel: channel,
    measurement: type.name,
    value: value,
    unit: type.unit,
  );
}

// =============================================================================
// Formatting
// =============================================================================

/// SI prefix definition used when rendering a value.
class _SiPrefix {
  final String symbol;
  final double factor;

  const _SiPrefix(this.symbol, this.factor);
}

/// Supported SI prefixes, ordered from largest to smallest factor.
///
/// Micro uses the Unicode MICRO SIGN (U+00B5) as required for display.
const List<_SiPrefix> _siPrefixes = [
  _SiPrefix('G', 1e9),
  _SiPrefix('M', 1e6),
  _SiPrefix('k', 1e3),
  _SiPrefix('', 1.0),
  _SiPrefix('m', 1e-3),
  _SiPrefix('µ', 1e-6),
  _SiPrefix('n', 1e-9),
  _SiPrefix('p', 1e-12),
];

/// Number of decimal places used when rendering the mantissa.
const int _mantissaDecimals = 6;

/// Rounds [value] to [_mantissaDecimals] decimal places.
double _roundMantissa(double value) {
  const factor = 1000000.0; // 10^_mantissaDecimals
  return (value * factor).roundToDouble() / factor;
}

/// Returns the index into [_siPrefixes] whose scaled magnitude of [magnitude]
/// falls in the range `[1, 1000)`.
///
/// Falls back to the largest or smallest supported prefix when [magnitude] is
/// outside the `p`..`G` range.
int _prefixIndexFor(double magnitude) {
  for (var i = 0; i < _siPrefixes.length; i++) {
    final scaled = magnitude / _siPrefixes[i].factor;
    if (scaled >= 1 && scaled < 1000) return i;
  }
  return magnitude >= 1 ? 0 : _siPrefixes.length - 1;
}

/// Formats a mantissa, removing insignificant trailing zeros.
///
/// Examples: `3.000000` → `3`, `999.890000` → `999.89`, `1.500000` → `1.5`.
String _formatMantissa(double mantissa) {
  var text = mantissa.toStringAsFixed(_mantissaDecimals);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  return text;
}

/// Formats a numeric [value] with a [unit] into a human-readable string using
/// SI prefixes.
///
/// The value is scaled so the mantissa lies in `[1, 1000)`, insignificant
/// trailing zeros are removed, and the matching prefix is applied:
///
/// ```text
/// 3            V   → "3 V"
/// 0.003        V   → "3 mV"
/// 0.000003     V   → "3 µV"
/// 999.89       Hz  → "999.89 Hz"
/// 1500         Hz  → "1.5 kHz"
/// 1500000      Hz  → "1.5 MHz"
/// 0.001        Hz  → "1 mHz"
/// ```
String formatMeasurementValue(double value, String unit) {
  if (value.isNaN) return 'NaN $unit';
  if (value.isInfinite) return '${value.isNegative ? '-' : ''}∞ $unit';
  if (value == 0) return '0 $unit';

  var index = _prefixIndexFor(value.abs());
  var mantissa = value / _siPrefixes[index].factor;

  // Guard against display rounding pushing the mantissa to >= 1000
  // (e.g. 999.9999999 → "1000"). Promote to the next larger prefix.
  if (index > 0 &&
      mantissa.isFinite &&
      _roundMantissa(mantissa).abs() >= 1000) {
    index -= 1;
    mantissa = value / _siPrefixes[index].factor;
  }

  final prefix = _siPrefixes[index];
  return '${_formatMantissa(mantissa)} ${prefix.symbol}$unit';
}

/// Formats a structured [measurement] into a human-readable string.
///
/// This is a thin convenience wrapper around [formatMeasurementValue]; the
/// [OscilloscopeMeasurement] model itself remains presentation-independent.
String formatMeasurement(OscilloscopeMeasurement measurement) =>
    formatMeasurementValue(measurement.value, measurement.unit);
