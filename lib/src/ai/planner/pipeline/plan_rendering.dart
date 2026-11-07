/// Deterministic, locale-free rendering of plan instructions.
library;

import '../models/action_plan.dart';
import '../models/json_value.dart';

final RegExp _placeholderPattern = RegExp(r'\{([a-zA-Z0-9_]+)\}');

/// Returns the placeholder keys used by [template].
Iterable<String> templatePlaceholders(String template) {
  return _placeholderPattern
      .allMatches(template)
      .map((match) => match.group(1)!);
}

/// Renders [template] by substituting `{key}` placeholders.
///
/// A key in [references] is rendered as a description of its source step; a
/// key in [values] is rendered with [formatPlannerValue]. An undeclared
/// placeholder throws a [PlannerFormatException], which the plan builder maps
/// to `not_feasible`.
String renderTemplate(
  String template,
  Map<String, Object?> values, {
  Map<String, StepReferenceParameter> references =
      const <String, StepReferenceParameter>{},
}) {
  return template.replaceAllMapped(_placeholderPattern, (match) {
    final key = match.group(1)!;
    final reference = references[key];
    if (reference != null) {
      return 'the ${reference.field} from step ${reference.fromStep}';
    }
    if (values.containsKey(key)) {
      return formatPlannerValue(values[key]);
    }
    throw PlannerFormatException(
      'template',
      'a declared placeholder for {$key}',
      template,
    );
  });
}

/// Formats a parameter value for an English instruction.
String formatPlannerValue(Object? value) {
  if (value is num) return formatPlannerNumber(value);
  if (value is bool) return value ? 'yes' : 'no';
  if (value is Iterable) {
    return value.map(formatPlannerValue).join(', ');
  }
  if (value is String) return value;
  if (value == null) return 'unknown';
  return value.toString();
}

/// Formats a number with at most six significant digits.
///
/// The output is locale-free: no grouping, no localized decimal separator and
/// no trailing zeros in the fraction.
String formatPlannerNumber(num value) {
  if (!value.isFinite) return value.toString();
  if (value == 0) return '0';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var text = value.toStringAsPrecision(6);
  if (text.contains('e') || text.contains('E')) return text;
  final dot = text.indexOf('.');
  if (dot >= 0) {
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  return text;
}
