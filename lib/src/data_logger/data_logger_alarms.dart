/// Edge-triggered threshold alarms for Data Logger recordings.
///
/// A rule raises exactly one event when a parameter leaves its allowed range
/// and re-arms once the value is back inside it. Invalid samples (`null`,
/// out-of-range `***`, gain below the noise floor) neither raise nor clear an
/// alarm. The module is Flutter-free and performs no I/O.
library;

import 'data_logger_models.dart';
import 'data_logger_statistics.dart' show dataLoggerParameterLabel;

/// A single threshold crossing recorded during a Data Logger session.
class DataLoggerAlarmEvent {
  final DateTime timestamp;

  /// Recording time at which the crossing was observed.
  final double elapsedSeconds;

  final String parameterId;
  final String parameterLabel;

  /// Measured value at the crossing.
  final double value;

  final DataLoggerAlarmDirection direction;
  final double? lower;
  final double? upper;

  const DataLoggerAlarmEvent({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.parameterId,
    required this.parameterLabel,
    required this.value,
    required this.direction,
    this.lower,
    this.upper,
  });

  @override
  String toString() =>
      'DataLoggerAlarmEvent(t=${elapsedSeconds.toStringAsFixed(1)}s, '
      '$parameterId=$value, ${direction.name}, '
      'lower=$lower, upper=$upper)';
}

/// Result of evaluating all alarm rules for one sample.
class DataLoggerAlarmEvaluation {
  /// Parameter ids whose rule is violated at this sample.
  final Set<String> active;

  /// Rules that crossed from inside to outside at this sample.
  final List<DataLoggerAlarmEvent> events;

  const DataLoggerAlarmEvaluation({required this.active, required this.events});
}

/// Evaluates the configured alarm rules against one sample.
///
/// [previouslyActive] is the active set of the previous sample. Parameters
/// whose rule is disabled are dropped from the active set, so disabling a rule
/// during a session cancels its alarm.
DataLoggerAlarmEvaluation evaluateDataLoggerAlarms({
  required DataLoggerConfig config,
  required Map<String, double?> values,
  required DateTime timestamp,
  required double elapsedSeconds,
  required Set<String> previouslyActive,
}) {
  final active = <String>{};
  final events = <DataLoggerAlarmEvent>[];

  for (final entry in config.alarmRules.entries) {
    final rule = entry.value;
    if (!rule.isActive) continue;

    final parameterId = entry.key;
    final value = values[parameterId];
    final wasActive = previouslyActive.contains(parameterId);

    if (value == null || !value.isFinite) {
      // Invalid samples neither raise nor clear an existing alarm.
      if (wasActive) active.add(parameterId);
      continue;
    }

    final direction = rule.directionFor(value);
    if (direction == null) {
      // Back inside the allowed range: re-arm for the next crossing.
      continue;
    }

    active.add(parameterId);
    if (!wasActive) {
      events.add(
        DataLoggerAlarmEvent(
          timestamp: timestamp,
          elapsedSeconds: elapsedSeconds,
          parameterId: parameterId,
          parameterLabel: dataLoggerParameterLabel(parameterId),
          value: value,
          direction: direction,
          lower: rule.lower,
          upper: rule.upper,
        ),
      );
    }
  }

  return DataLoggerAlarmEvaluation(active: active, events: events);
}

/// Replays [points] and returns every alarm event in chronological order.
///
/// The result is identical to the events the live service produced, because
/// both use [evaluateDataLoggerAlarms] and the stored parameter values.
List<DataLoggerAlarmEvent> dataLoggerAlarmEvents({
  required DataLoggerConfig config,
  required List<DataLoggerPoint> points,
}) {
  if (!config.hasActiveAlarms) return const [];

  final active = <String>{};
  final events = <DataLoggerAlarmEvent>[];
  for (final point in points) {
    final evaluation = evaluateDataLoggerAlarms(
      config: config,
      values: dataLoggerPointValues(point),
      timestamp: point.timestamp,
      elapsedSeconds: point.elapsedSeconds,
      previouslyActive: active,
    );
    events.addAll(evaluation.events);
    active
      ..clear()
      ..addAll(evaluation.active);
  }
  return events;
}
