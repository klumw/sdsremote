/// Structured measurement request filled by the PlannerAgent model.
library;

import 'json_value.dart';

/// Coupling of the measurement input.
enum Coupling {
  dc,
  ac,
  unknown;

  /// Wire value used by the tool schema and the session store.
  String get wireName => name;

  /// Parses a wire value, defaulting to [Coupling.unknown].
  static Coupling fromWire(Object? value) {
    return switch (value) {
      null => Coupling.unknown,
      'dc' => Coupling.dc,
      'ac' => Coupling.ac,
      'unknown' => Coupling.unknown,
      _ => throw PlannerFormatException('coupling', 'dc|ac|unknown', value),
    };
  }
}

/// Safety information stated by the user or collected by the input form.
class SafetyHints {
  const SafetyHints({
    this.maxVoltageV,
    this.coupling = Coupling.unknown,
    this.mainsReferenced,
    this.floatingDut,
  });

  /// Expected maximum voltage in volts, in any voltage base.
  final double? maxVoltageV;

  /// Input coupling.
  final Coupling coupling;

  /// Whether the DUT is referenced to mains potential.
  final bool? mainsReferenced;

  /// Whether the DUT is floating.
  final bool? floatingDut;

  factory SafetyHints.fromMap(Map<String, dynamic> map) {
    const allowed = {
      'maxVoltageV',
      'coupling',
      'mainsReferenced',
      'floatingDut',
    };
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw PlannerFormatException('safetyHints.$key', 'known field', key);
      }
    }
    return SafetyHints(
      maxVoltageV: optionalJsonDouble(
        map['maxVoltageV'],
        'safetyHints.maxVoltageV',
      ),
      coupling: Coupling.fromWire(map['coupling']),
      mainsReferenced: optionalJsonBool(
        map['mainsReferenced'],
        'safetyHints.mainsReferenced',
      ),
      floatingDut: optionalJsonBool(
        map['floatingDut'],
        'safetyHints.floatingDut',
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (maxVoltageV != null) 'maxVoltageV': maxVoltageV,
    'coupling': coupling.wireName,
    if (mainsReferenced != null) 'mainsReferenced': mainsReferenced,
    if (floatingDut != null) 'floatingDut': floatingDut,
  };
}

/// One request as returned by the `plan_measurement` tool.
class MeasurementRequest {
  const MeasurementRequest({
    required this.goal,
    required this.measurements,
    this.knownParameters = const <String, Object?>{},
    this.safetyHints = const SafetyHints(),
    this.stateRef,
    this.answers,
  });

  /// Short English description of the measurement goal.
  final String goal;

  /// Catalog ids, or `other:<free text>` for quantities outside the catalog.
  final List<String> measurements;

  /// Values stated by the user, keyed by parameter name.
  final Map<String, Object?> knownParameters;

  /// Safety information stated by the user.
  final SafetyHints safetyHints;

  /// Host-managed session reference. Never part of the LLM schema.
  final String? stateRef;

  /// Host-managed answers of an earlier form. Never part of the LLM schema.
  final Map<String, Object?>? answers;

  /// Parses the tool arguments.
  ///
  /// Snake_case aliases are accepted at the tool boundary for robustness;
  /// [toJson] always emits canonical camelCase keys.
  factory MeasurementRequest.fromMap(Map<String, dynamic> map) {
    final goal = (optionalJsonString(map['goal'], 'goal') ?? '').trim();
    final rawMeasurements =
        map['measurements'] ?? map['measurement'] ?? const <Object?>[];
    final measurements = optionalJsonStringList(
      rawMeasurements,
      'measurements',
    );
    final knownParameters = optionalJsonValueMap(
      map['knownParameters'] ?? map['known_parameters'],
      'knownParameters',
    );
    final hintsRaw = map['safetyHints'] ?? map['safety_hints'];
    final hints = hintsRaw == null
        ? const SafetyHints()
        : SafetyHints.fromMap(requireJsonMap(hintsRaw, 'safetyHints'));
    final answers = optionalJsonValueMap(map['answers'], 'answers');
    return MeasurementRequest(
      goal: goal,
      measurements: measurements ?? const <String>[],
      knownParameters: knownParameters ?? const <String, Object?>{},
      safetyHints: hints,
      stateRef: optionalJsonString(
        map['stateRef'] ?? map['state_ref'],
        'stateRef',
      ),
      answers: answers,
    );
  }

  /// Returns a copy with additional known parameters and answers merged in.
  ///
  /// Later values win; the original request is not modified.
  MeasurementRequest merged({
    Map<String, Object?> answers = const <String, Object?>{},
    Map<String, Object?> knownParameters = const <String, Object?>{},
  }) {
    return MeasurementRequest(
      goal: goal,
      measurements: measurements,
      knownParameters: <String, Object?>{
        ...this.knownParameters,
        ...knownParameters,
      },
      safetyHints: safetyHints,
      stateRef: stateRef,
      answers: <String, Object?>{...?this.answers, ...answers},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'goal': goal,
    'measurements': measurements,
    if (knownParameters.isNotEmpty) 'knownParameters': knownParameters,
    'safetyHints': safetyHints.toJson(),
    if (stateRef != null) 'stateRef': stateRef,
    if (answers != null) 'answers': answers,
  };
}
