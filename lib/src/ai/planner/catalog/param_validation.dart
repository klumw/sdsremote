/// Validation and normalization of planner parameter values.
///
/// The deterministic pipeline and the host-side session store share this
/// code, so a model-supplied value is normalized exactly like a form answer.
/// Choice values accept their option value or label in any letter case and a
/// numeric shorthand such as `2` or `Channel 2` for `ch2`.
library;

import '../models/input_form.dart';
import '../models/units.dart';
import 'param_spec.dart';

/// Result of validating one raw parameter value.
class ParameterValue {
  const ParameterValue.valid(this.value) : error = null;

  const ParameterValue.invalid(this.error) : value = null;

  /// Canonical value, when [isValid].
  final Object? value;

  /// English validation message, when invalid.
  final String? error;

  /// Whether the raw value was accepted.
  bool get isValid => error == null;
}

/// Validates [raw] against [spec] and returns the canonical value.
ParameterValue validateParameterValue(ParamSpec spec, Object? raw) {
  switch (spec.type) {
    case ParamType.number:
      final value = _parseNumber(spec, raw);
      if (value == null) {
        final unit = spec.unit == null ? '' : ' in ${spec.unit}';
        return ParameterValue.invalid('Enter a number$unit.');
      }
      if (!value.isFinite) {
        return const ParameterValue.invalid('Enter a finite number.');
      }
      final minimum = spec.min;
      if (minimum != null && value < minimum) {
        return ParameterValue.invalid(
          'Enter a value of at least ${_formatNumber(minimum)}'
          '${spec.unit ?? ''}.',
        );
      }
      final maximum = spec.max;
      if (maximum != null && value > maximum) {
        return ParameterValue.invalid(
          'Enter a value of at most ${_formatNumber(maximum)}'
          '${spec.unit ?? ''}.',
        );
      }
      return ParameterValue.valid(value);
    case ParamType.boolean:
      final value = _bool(raw);
      if (value == null) {
        return const ParameterValue.invalid('Choose yes or no.');
      }
      return ParameterValue.valid(value);
    case ParamType.text:
      if (raw is! String || raw.trim().isEmpty) {
        return const ParameterValue.invalid('Enter text.');
      }
      return ParameterValue.valid(raw.trim());
    case ParamType.singleChoice:
      final options = spec.options ?? const <InputOption>[];
      final value = _normalizeOption(options, raw);
      if (value == null) {
        return const ParameterValue.invalid(
          'Choose one of the listed options.',
        );
      }
      return ParameterValue.valid(value);
    case ParamType.multiChoice:
      if (raw is! List) {
        return const ParameterValue.invalid(
          'Choose at least one listed option.',
        );
      }
      final options = spec.options ?? const <InputOption>[];
      final values = <String>[];
      for (final entry in raw) {
        final value = _normalizeOption(options, entry);
        if (value == null) {
          return const ParameterValue.invalid('Choose only listed options.');
        }
        values.add(value);
      }
      if (values.isEmpty) {
        return const ParameterValue.invalid('Choose at least one option.');
      }
      return ParameterValue.valid(values);
  }
}

String? _normalizeOption(List<InputOption> options, Object? raw) {
  if (raw is! String && raw is! num) return null;
  final text = raw is String ? raw.trim() : '$raw';
  if (text.isEmpty) return null;

  for (final option in options) {
    if (option.value == text) return option.value;
  }

  final squashed = _squash(text);
  for (final option in options) {
    if (_squash(option.value) == squashed ||
        _squash(option.label) == squashed) {
      return option.value;
    }
  }

  // Numeric shorthand for a family such as ch1..ch4 or generator channel 1/2:
  // accept "2", "CH2" or "Channel 2" when exactly one option carries that
  // trailing number and every option shares the same non-numeric prefix.
  final numeric = RegExp(
    r'^(?:ch(?:annel)?|kanal)?(\d+)$',
  ).firstMatch(squashed);
  if (numeric == null) return null;
  final trailing = RegExp(r'^(.*?)(\d+)$');
  final prefixes = <String>{};
  final matches = <String>[];
  for (final option in options) {
    final match = trailing.firstMatch(option.value.trim().toLowerCase());
    if (match == null) return null;
    prefixes.add(match.group(1)!);
    if (match.group(2) == numeric.group(1)) matches.add(option.value);
  }
  if (prefixes.length != 1 || matches.length != 1) return null;
  return matches.single;
}

String _squash(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}

double? _parseNumber(ParamSpec spec, Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is! String) return null;
  final text = raw.trim();
  final unit = spec.unit;
  if (unit == null) return double.tryParse(text);
  final normalized = unit.toLowerCase();
  if (normalized == 'v' ||
      normalized == 'vpp' ||
      normalized == 'vpk' ||
      normalized == 'vrms') {
    final quantity = tryParseQuantity(text, expected: QuantityKind.voltagePeak);
    if (quantity == null) return null;
    if (normalized == 'vpp') return quantity.peakToPeakValue;
    if (normalized == 'v') return quantity.value;
    return quantity.peakValue;
  }
  if (normalized == 'hz') {
    return tryParseQuantity(text, expected: QuantityKind.frequency)?.siValue;
  }
  if (normalized == '%') {
    return tryParseQuantity(text, expected: QuantityKind.percent)?.siValue;
  }
  return double.tryParse(text);
}

bool? _bool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case 'yes':
        return true;
      case 'false':
      case 'no':
        return false;
    }
  }
  return null;
}

String _formatNumber(num value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}
