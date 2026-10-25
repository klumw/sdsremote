/// Formats the output of macro `print()` statements for display.
///
/// Oscilloscope responses use scientific notation (`8.000000E+3`). The print
/// panel shows readable values instead:
/// - frequencies use Hz, kHz or MHz,
/// - voltages use mV or V,
/// - every other number is expanded so no exponent reaches the output.
///
/// A value's unit is taken from the SCPI query that produced it when that is
/// known. Values without source information use the label before the number
/// (for example `"Frequency: "` or `"Vpp: "`). Unknown values are still
/// printed without scientific notation.
library;

import 'dart:math' as math;

/// Factors that convert a unit spelling to its base unit.
const Map<String, double> _unitFactors = <String, double>{
  'hz': 1,
  'khz': 1e3,
  'mhz': 1e6,
  'ghz': 1e9,
  'v': 1,
  'mv': 1e-3,
  'uv': 1e-6,
  'µv': 1e-6,
};

const Set<String> _voltageUnits = <String>{'v', 'mv', 'uv', 'µv'};
const Set<String> _frequencyUnits = <String>{'hz', 'khz', 'mhz', 'ghz'};

/// A number with an optional immediately following unit.
///
/// The lookbehind prevents matching digits inside identifiers such as `C1`,
/// `CH1` or `SDS1202X-E`. The unit alternatives are followed by a
/// non-letter so words like "and" are not mistaken for an ampere unit.
final RegExp _numberWithUnit = RegExp(
  r'(?<![A-Za-z0-9_.])'
  r'([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)'
  r'(\s*)'
  r'(Hz|kHz|MHz|GHz|mV|V|uV|µV|mA|A|uA|ms|s|us|µs|ns|dBm|dB|deg|%)?'
  r'(?![A-Za-z])',
  caseSensitive: false,
);

final RegExp _frequencyHint = RegExp(
  r'freq|frequenz|\bhz\b',
  caseSensitive: false,
);

final RegExp _voltageHint = RegExp(
  r'volt|spannung|spitze|effektivwert|pegel'
  r'|\bv(?:pp|rms|max|min|avg|top|base|div|off)?\b'
  r'|\bpkpk\b|\bampl(?:itude)?\b|\brms\b|\bpeak\b|\bmean\b',
  caseSensitive: false,
);

/// Formats [hz] using Hz, kHz or MHz, without scientific notation.
String formatMacroFrequency(double hz) {
  final magnitude = hz.abs();
  if (magnitude >= 1e6) return _scaled(hz, 1e6, 'MHz');
  if (magnitude >= 1e3) {
    // A value just below 1 MHz must not round to "1000 kHz".
    if (_round6(hz / 1e3).abs() >= 1000) return _scaled(hz, 1e6, 'MHz');
    return _scaled(hz, 1e3, 'kHz');
  }
  if (_round6(hz).abs() >= 1000) return _scaled(hz, 1e3, 'kHz');
  return _scaled(hz, 1, 'Hz');
}

/// Formats [volts] using mV or V, without scientific notation.
String formatMacroVoltage(double volts) {
  if (volts == 0) return '0 V';
  final magnitude = volts.abs();
  if (magnitude >= 1) return _scaled(volts, 1, 'V');
  // A value just below 1 V must not round to "1000 mV".
  if (_round6(volts * 1e3).abs() >= 1000) return _scaled(volts, 1, 'V');
  return _scaled(volts, 1e-3, 'mV');
}

/// Formats a plain number without scientific notation and trailing zeros.
String formatMacroPlain(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
  if (value == 0) return '0';
  final magnitude = value.abs();
  final decimals = magnitude >= 1
      ? 6
      : math.min(12, 6 - (math.log(magnitude) / math.ln10).floor());
  return _trimZeros(value.toStringAsFixed(decimals));
}

/// Formats [value] with the given display unit.
///
/// Supported units are `Hz` (Hz/kHz/MHz) and `V` (mV/V). Any other unit is
/// formatted as a plain decimal number.
String formatMacroNumber(double value, String? unit) {
  if (unit == 'Hz') return formatMacroFrequency(value);
  if (unit == 'V') return formatMacroVoltage(value);
  return formatMacroPlain(value);
}

/// Formats one print value (a variable value or a query response).
///
/// When [unit] is known (`Hz` or `V`), every number in [value] is formatted
/// with that unit. Otherwise numbers are printed as readable decimals.
String prettyPrintMacroValue(String value, {String? unit}) {
  final direct = double.tryParse(value.trim());
  if (direct != null) {
    return formatMacroNumber(direct, unit);
  }

  return value.replaceAllMapped(_numberWithUnit, (match) {
    final number = double.tryParse(match.group(1)!);
    if (number == null) return match.group(0)!;

    if (unit != null) return formatMacroNumber(number, unit);

    final existingUnit = match.group(3);
    if (existingUnit != null) {
      return _normalizeNumberWithUnit(
        number,
        match.group(2)!,
        existingUnit,
        hasExponent: _hasExponent(match.group(1)!),
        original: match.group(0)!,
      );
    }
    return formatMacroPlain(number);
  });
}

/// Post-processes a complete print line.
///
/// Values already carrying a unit are normalized. Numbers without a unit use
/// the nearest preceding label ("Frequency:", "Vpp:", ...) to choose Hz or V.
/// Remaining exponential values are expanded to plain decimals.
String prettyPrintMacroText(String text) {
  return text.replaceAllMapped(_numberWithUnit, (match) {
    final token = match.group(1)!;
    final number = double.tryParse(token);
    if (number == null) return match.group(0)!;

    final existingUnit = match.group(3);
    if (existingUnit != null) {
      return _normalizeNumberWithUnit(
        number,
        match.group(2)!,
        existingUnit,
        hasExponent: _hasExponent(token),
        original: match.group(0)!,
      );
    }

    final contextUnit = _unitFromLabel(_labelBefore(text, match.start));
    if (contextUnit != null) return formatMacroNumber(number, contextUnit);
    if (_hasExponent(token)) return formatMacroPlain(number);
    return match.group(0)!;
  });
}

/// Infers the display unit of a SCPI query command.
///
/// Only frequency and voltage measurements are recognized; other commands
/// return null and are formatted as plain numbers.
String? inferMacroUnit(String scpiCommand) {
  final command = scpiCommand.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  if (command.contains('FREQ')) return 'Hz';

  if (command.contains('PAVA?')) {
    const voltageParameters = <String>[
      'PKPK',
      'AMPL',
      'RMS',
      'MEAN',
      'MAX',
      'MIN',
      'TOP',
      'BASE',
    ];
    if (voltageParameters.any(command.contains)) return 'V';
  }

  if (command.contains(':VDIV?') ||
      command.contains(':OFST?') ||
      command.contains(':TRLV?') ||
      command.contains(':CGND?')) {
    return 'V';
  }

  return null;
}

String _normalizeNumberWithUnit(
  double value,
  String spacing,
  String unit, {
  required bool hasExponent,
  required String original,
}) {
  final canonical = unit.toLowerCase();
  final factor = _unitFactors[canonical];
  if (factor != null) {
    final baseValue = value * factor;
    if (_voltageUnits.contains(canonical)) {
      return formatMacroVoltage(baseValue);
    }
    if (_frequencyUnits.contains(canonical)) {
      return formatMacroFrequency(baseValue);
    }
  }

  // Units without a dedicated formatter keep their spelling; only the
  // exponential notation is expanded.
  if (hasExponent) return '${formatMacroPlain(value)}$spacing$unit';
  return original;
}

String? _unitFromLabel(String label) {
  final frequency = _lastMatch(_frequencyHint, label);
  final voltage = _lastMatch(_voltageHint, label);
  if (frequency == null && voltage == null) return null;
  if (voltage != null && (frequency == null || voltage.end > frequency.end)) {
    return 'V';
  }
  return 'Hz';
}

/// Returns the text between the previous list delimiter and [index].
///
/// This is the label that most directly belongs to the number at [index].
String _labelBefore(String text, int index) {
  var start = 0;
  for (final delimiter in const <String>[',', ';', '|', '\n', '\t']) {
    final position = text.lastIndexOf(delimiter, index);
    if (position >= start) start = position + 1;
  }
  final segment = text.substring(start, index);
  return segment.length > 80 ? segment.substring(segment.length - 80) : segment;
}

Match? _lastMatch(RegExp pattern, String text) {
  Match? last;
  for (final match in pattern.allMatches(text)) {
    last = match;
  }
  return last;
}

bool _hasExponent(String token) => token.toLowerCase().contains('e');

String _scaled(double value, double factor, String unit) =>
    '${_formatMantissa(value / factor)} $unit';

double _round6(double value) => (value * 1e6).roundToDouble() / 1e6;

String _formatMantissa(double value) => _trimZeros(value.toStringAsFixed(6));

String _trimZeros(String text) {
  if (!text.contains('.')) return text;
  var result = text.replaceFirst(RegExp(r'0+$'), '');
  if (result.endsWith('.')) {
    result = result.substring(0, result.length - 1);
  }
  if (result == '-0') return '0';
  return result;
}
