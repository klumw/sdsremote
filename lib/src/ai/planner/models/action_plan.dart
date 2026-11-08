/// Executable action plan returned by a `plan_ready` planner result.
library;

import 'json_value.dart';

/// Measurement category of a plan.
enum PlanType {
  simpleReading('simple_reading'),
  audio('audio'),
  digital('digital');

  const PlanType(this.wireName);

  /// Wire value used by the tool result and the session store.
  final String wireName;

  static PlanType fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw PlannerFormatException('type', 'simple_reading|audio|digital', value);
  }
}

/// Agent that executes one plan step.
enum PlanAgent {
  user('user'),
  scopeAnalysis('scope_analysis_agent'),
  scpiInstrument('scpi_instrument_agent'),
  audioAnalysis('audio_analysis_agent'),
  digitalAnalysis('digital_analysis_agent');

  const PlanAgent(this.wireName);

  /// Wire value used by the tool result and the session store.
  final String wireName;

  static PlanAgent fromWire(Object? value) {
    for (final agent in values) {
      if (agent.wireName == value) return agent;
    }
    throw PlannerFormatException(
      'agent',
      'user|scope_analysis_agent|scpi_instrument_agent|'
          'audio_analysis_agent|digital_analysis_agent',
      value,
    );
  }
}

/// Kind of work performed by one plan step.
enum ActionStepKind {
  manual('manual'),
  configureGenerator('configure_generator'),
  configureScope('configure_scope'),
  measure('measure'),
  read('read'),
  teardown('teardown');

  const ActionStepKind(this.wireName);

  /// Wire value used by the tool result and the session store.
  final String wireName;

  static ActionStepKind fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw PlannerFormatException(
      'kind',
      'manual|configure_generator|configure_scope|measure|read|teardown',
      value,
    );
  }
}

/// Provenance of one plan input.
enum InputSource {
  user('user'),
  defaulted('default'),
  device('device'),
  derived('derived');

  const InputSource(this.wireName);

  /// Wire value used by the tool result and the session store.
  final String wireName;

  static InputSource fromWire(Object? value) {
    for (final source in values) {
      if (source.wireName == value) return source;
    }
    throw PlannerFormatException(
      'source',
      'user|default|device|derived',
      value,
    );
  }
}

/// Parameter value of a plan step: a literal or a reference to an earlier step.
sealed class StepParameter {
  const StepParameter();

  /// Parses a parameter value.
  ///
  /// A map with exactly `fromStep` and `field` is a step reference; any other
  /// JSON value is a literal. A map that mixes both is rejected so a
  /// mis-shaped reference cannot silently become a literal.
  factory StepParameter.fromJson(Object? value, String field) {
    if (value is Map) {
      final map = requireJsonMap(value, field);
      final hasFromStep = map.containsKey('fromStep');
      final hasField = map.containsKey('field');
      if (hasFromStep || hasField) {
        if (!hasFromStep || !hasField || map.length != 2) {
          throw PlannerFormatException(
            field,
            'reference {fromStep, field} or a literal JSON value',
            value,
          );
        }
        final fromStep = requireJsonString(map['fromStep'], '$field.fromStep');
        final target = requireJsonString(map['field'], '$field.field');
        if (fromStep.isEmpty || target.isEmpty) {
          throw PlannerFormatException(
            field,
            'non-empty fromStep and field',
            value,
          );
        }
        return StepReferenceParameter(fromStep: fromStep, field: target);
      }
    }
    return LiteralParameter(jsonSafe(value, field));
  }

  /// JSON representation of this parameter.
  Object? toJson();
}

/// A fixed parameter value.
final class LiteralParameter extends StepParameter {
  const LiteralParameter(this.value);

  /// JSON-safe literal value.
  final Object? value;

  @override
  Object? toJson() => value;
}

/// A parameter read from the result of an earlier plan step.
final class StepReferenceParameter extends StepParameter {
  const StepReferenceParameter({required this.fromStep, required this.field});

  /// Id of the step that produces the value.
  final String fromStep;

  /// Dot path inside the step result, for example `channels.ch1.vppVolts`.
  final String field;

  @override
  Object? toJson() => <String, Object?>{'fromStep': fromStep, 'field': field};
}

/// One resolved plan input with its provenance.
class PlanInput {
  const PlanInput({
    required this.key,
    required this.value,
    required this.source,
  });

  /// Parameter key.
  final String key;

  /// Resolved JSON-safe value.
  final Object? value;

  /// Where the value came from.
  final InputSource source;

  factory PlanInput.fromMap(Map<String, dynamic> map, String field) {
    return PlanInput(
      key: requireJsonString(map['key'], '$field.key'),
      value: jsonSafe(map['value'], '$field.value'),
      source: InputSource.fromWire(map['source']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'value': value,
    'source': source.wireName,
  };
}

/// One ordered step of an action plan.
class ActionStep {
  const ActionStep({
    required this.id,
    required this.kind,
    required this.agent,
    required this.instruction,
    required this.parameters,
    required this.dependsOn,
    required this.requiresUserConfirmation,
    required this.expectedOutput,
    required this.estimatedToolCalls,
    this.focus,
  });

  /// Unique id inside the plan.
  final String id;

  /// Kind of work.
  final ActionStepKind kind;

  /// Executing agent.
  final PlanAgent agent;

  /// Optional focus block for the executing sub-agent.
  final String? focus;

  /// Fully rendered English instruction.
  final String instruction;

  /// Parameter bindings.
  final Map<String, StepParameter> parameters;

  /// Ids of steps that must complete first.
  final List<String> dependsOn;

  /// Whether the user must confirm before the step runs.
  final bool requiresUserConfirmation;

  /// English description of the produced result.
  final String expectedOutput;

  /// Upper estimate of tool calls inside the executing sub-agent.
  final int estimatedToolCalls;

  factory ActionStep.fromMap(Map<String, dynamic> map, String field) {
    final rawParameters = optionalJsonMap(
      map['parameters'],
      '$field.parameters',
    );
    final parameters = <String, StepParameter>{};
    if (rawParameters != null) {
      for (final entry in rawParameters.entries) {
        parameters[entry.key] = StepParameter.fromJson(
          entry.value,
          '$field.parameters.${entry.key}',
        );
      }
    }
    return ActionStep(
      id: requireJsonString(map['id'], '$field.id'),
      kind: ActionStepKind.fromWire(map['kind']),
      agent: PlanAgent.fromWire(map['agent']),
      focus: optionalJsonString(map['focus'], '$field.focus'),
      instruction: requireJsonString(map['instruction'], '$field.instruction'),
      parameters: parameters,
      dependsOn:
          optionalJsonStringList(map['dependsOn'], '$field.dependsOn') ??
          const <String>[],
      requiresUserConfirmation:
          optionalJsonBool(
            map['requiresUserConfirmation'],
            '$field.requiresUserConfirmation',
          ) ??
          false,
      expectedOutput:
          optionalJsonString(map['expectedOutput'], '$field.expectedOutput') ??
          '',
      estimatedToolCalls:
          optionalJsonInt(
            map['estimatedToolCalls'],
            '$field.estimatedToolCalls',
          ) ??
          1,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.wireName,
    'agent': agent.wireName,
    if (focus != null) 'focus': focus,
    'instruction': instruction,
    'parameters': <String, Object?>{
      for (final entry in parameters.entries) entry.key: entry.value.toJson(),
    },
    'dependsOn': dependsOn,
    'requiresUserConfirmation': requiresUserConfirmation,
    'expectedOutput': expectedOutput,
    'estimatedToolCalls': estimatedToolCalls,
  };
}

/// Sub-agent step counts of a plan.
class PlanBudget {
  const PlanBudget({required this.subAgentSteps});

  /// Number of steps per executing sub-agent. Manual steps are excluded.
  final Map<PlanAgent, int> subAgentSteps;

  factory PlanBudget.fromMap(Map<String, dynamic> map, String field) {
    final raw = requireJsonMap(map['subAgentSteps'], '$field.subAgentSteps');
    final steps = <PlanAgent, int>{};
    for (final entry in raw.entries) {
      final agent = PlanAgent.fromWire(entry.key);
      final count = optionalJsonInt(
        entry.value,
        '$field.subAgentSteps.${entry.key}',
      );
      if (count == null || count < 0) {
        throw PlannerFormatException(
          '$field.subAgentSteps.${entry.key}',
          'non-negative integer',
          entry.value,
        );
      }
      steps[agent] = count;
    }
    return PlanBudget(subAgentSteps: steps);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'subAgentSteps': <String, Object?>{
      for (final entry in subAgentSteps.entries)
        entry.key.wireName: entry.value,
    },
  };
}

/// Equipment facts recorded when the plan was created.
class PlanEquipment {
  const PlanEquipment({required this.scope, required this.generator});

  /// Oscilloscope facts.
  final PlanScopeEquipment scope;

  /// Signal-generator facts.
  final PlanGeneratorEquipment generator;

  factory PlanEquipment.fromMap(Map<String, dynamic> map) {
    return PlanEquipment(
      scope: PlanScopeEquipment.fromMap(
        requireJsonMap(map['scope'], 'equipment.scope'),
        'equipment.scope',
      ),
      generator: PlanGeneratorEquipment.fromMap(
        requireJsonMap(map['generator'], 'equipment.generator'),
        'equipment.generator',
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'scope': scope.toJson(),
    'generator': generator.toJson(),
  };
}

/// Oscilloscope facts recorded in the plan.
class PlanScopeEquipment {
  const PlanScopeEquipment({
    required this.reachable,
    this.model,
    this.profile,
    this.host,
    this.error,
  });

  /// Whether the scope was reachable.
  final bool reachable;

  /// Detected model designation from `*IDN?`, when known.
  final String? model;

  /// Configured device profile display name, when known.
  final String? profile;

  /// Configured VXI-11 host, when known.
  final String? host;

  /// English reason when the scope is not reachable.
  final String? error;

  factory PlanScopeEquipment.fromMap(Map<String, dynamic> map, String field) {
    return PlanScopeEquipment(
      reachable:
          optionalJsonBool(map['reachable'], '$field.reachable') ?? false,
      model: optionalJsonString(map['model'], '$field.model'),
      profile: optionalJsonString(map['profile'], '$field.profile'),
      host: optionalJsonString(map['host'], '$field.host'),
      error: optionalJsonString(map['error'], '$field.error'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'reachable': reachable,
    if (model != null) 'model': model,
    if (profile != null) 'profile': profile,
    if (host != null) 'host': host,
    if (error != null) 'error': error,
  };
}

/// Signal-generator facts recorded in the plan.
class PlanGeneratorEquipment {
  const PlanGeneratorEquipment({
    required this.configured,
    required this.connected,
    required this.supported,
    this.detected = false,
    this.model,
    this.identity,
    this.family,
    this.port,
    this.error,
  });

  /// Whether a generator device is selected in the settings.
  final bool configured;

  /// Whether the generator was connected.
  final bool connected;

  /// Whether the configured device is supported.
  final bool supported;

  /// Whether the device was detected on a serial port.
  final bool detected;

  /// Reported model name.
  final String? model;

  /// Reported SCPI identity.
  final String? identity;

  /// Detected device family.
  final String? family;

  /// Serial port of the connection.
  final String? port;

  /// English reason when the generator is unavailable.
  final String? error;

  factory PlanGeneratorEquipment.fromMap(
    Map<String, dynamic> map,
    String field,
  ) {
    return PlanGeneratorEquipment(
      configured:
          optionalJsonBool(map['configured'], '$field.configured') ?? false,
      connected:
          optionalJsonBool(map['connected'], '$field.connected') ?? false,
      supported:
          optionalJsonBool(map['supported'], '$field.supported') ?? false,
      detected: optionalJsonBool(map['detected'], '$field.detected') ?? false,
      model: optionalJsonString(map['model'], '$field.model'),
      identity: optionalJsonString(map['identity'], '$field.identity'),
      family: optionalJsonString(map['family'], '$field.family'),
      port: optionalJsonString(map['port'], '$field.port'),
      error: optionalJsonString(map['error'], '$field.error'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'configured': configured,
    'connected': connected,
    'supported': supported,
    'detected': detected,
    if (model != null) 'model': model,
    if (identity != null) 'identity': identity,
    if (family != null) 'family': family,
    if (port != null) 'port': port,
    if (error != null) 'error': error,
  };
}

/// Complete executable measurement plan.
class ActionPlan {
  const ActionPlan({
    required this.planId,
    required this.goal,
    required this.type,
    required this.inputs,
    required this.safetyNotes,
    required this.steps,
    required this.budget,
    this.equipment,
  });

  /// Opaque identifier, also used as the plan reference.
  final String planId;

  /// English goal, copied from the request.
  final String goal;

  /// Measurement category.
  final PlanType type;

  /// Resolved inputs with provenance.
  final List<PlanInput> inputs;

  /// English safety notes shown before execution.
  final List<String> safetyNotes;

  /// Ordered steps.
  final List<ActionStep> steps;

  /// Sub-agent step counts.
  final PlanBudget budget;

  /// Equipment facts recorded when the plan was created.
  ///
  /// `null` only for plans parsed from an older payload that did not carry the
  /// field; plans built by the pipeline always record it.
  final PlanEquipment? equipment;

  factory ActionPlan.fromMap(Map<String, dynamic> map) {
    final rawInputs =
        optionalJsonList(map['inputs'], 'inputs') ?? const <Object?>[];
    final rawSteps = requireJsonList(map['steps'], 'steps');
    return ActionPlan(
      planId: requireJsonString(map['planId'], 'planId'),
      goal: requireJsonString(map['goal'], 'goal'),
      type: PlanType.fromWire(map['type']),
      inputs: <PlanInput>[
        for (var index = 0; index < rawInputs.length; index++)
          PlanInput.fromMap(
            requireJsonMap(rawInputs[index], 'inputs[$index]'),
            'inputs[$index]',
          ),
      ],
      safetyNotes:
          optionalJsonStringList(map['safetyNotes'], 'safetyNotes') ??
          const <String>[],
      steps: <ActionStep>[
        for (var index = 0; index < rawSteps.length; index++)
          ActionStep.fromMap(
            requireJsonMap(rawSteps[index], 'steps[$index]'),
            'steps[$index]',
          ),
      ],
      budget: PlanBudget.fromMap(
        requireJsonMap(map['budget'], 'budget'),
        'budget',
      ),
      equipment: map['equipment'] == null
          ? null
          : PlanEquipment.fromMap(
              requireJsonMap(map['equipment'], 'equipment'),
            ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'planId': planId,
    'goal': goal,
    'type': type.wireName,
    'inputs': [for (final input in inputs) input.toJson()],
    'safetyNotes': safetyNotes,
    'steps': [for (final step in steps) step.toJson()],
    'budget': budget.toJson(),
    if (equipment != null) 'equipment': equipment!.toJson(),
  };

  /// Structural validation of the plan.
  ///
  /// Returns an empty list when the plan satisfies the contract. The plan
  /// builder calls this before returning `plan_ready`; tests use it directly.
  List<String> validate({int maxStepsPerSubAgent = 2}) {
    final errors = <String>[];
    final ids = <String>{};
    for (final step in steps) {
      if (step.id.isEmpty) errors.add('A step has an empty id.');
      if (!ids.add(step.id)) errors.add('Duplicate step id "${step.id}".');
      if (step.estimatedToolCalls < 0) {
        errors.add('Step "${step.id}" has a negative tool-call estimate.');
      }
    }
    for (final step in steps) {
      for (final dependency in step.dependsOn) {
        if (dependency == step.id) {
          errors.add('Step "${step.id}" depends on itself.');
        } else if (!ids.contains(dependency)) {
          errors.add(
            'Step "${step.id}" depends on unknown step "$dependency".',
          );
        }
      }
    }

    // Kahn's algorithm over the dependency graph.
    final indegree = <String, int>{for (final step in steps) step.id: 0};
    final outgoing = <String, List<String>>{
      for (final step in steps) step.id: [],
    };
    for (final step in steps) {
      for (final dependency in step.dependsOn) {
        if (!ids.contains(dependency) || dependency == step.id) continue;
        indegree[step.id] = (indegree[step.id] ?? 0) + 1;
        outgoing[dependency]!.add(step.id);
      }
    }
    final queue = <String>[
      for (final entry in indegree.entries)
        if (entry.value == 0) entry.key,
    ];
    var visited = 0;
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      visited++;
      for (final next in outgoing[current]!) {
        final remaining = (indegree[next] ?? 0) - 1;
        indegree[next] = remaining;
        if (remaining == 0) queue.add(next);
      }
    }
    if (visited != steps.length) {
      errors.add('The step dependency graph contains a cycle.');
    }

    final counts = <PlanAgent, int>{};
    for (final step in steps) {
      if (step.agent == PlanAgent.user) continue;
      counts.update(step.agent, (value) => value + 1, ifAbsent: () => 1);
    }
    for (final entry in counts.entries) {
      if (entry.value > maxStepsPerSubAgent) {
        errors.add(
          'Agent ${entry.key.wireName} has ${entry.value} steps '
          '(maximum $maxStepsPerSubAgent).',
        );
      }
    }
    for (final entry in budget.subAgentSteps.entries) {
      if (entry.key == PlanAgent.user) {
        errors.add('Manual steps must not appear in the sub-agent budget.');
      } else if ((counts[entry.key] ?? 0) != entry.value) {
        errors.add(
          'Budget for ${entry.key.wireName} is ${entry.value}, '
          'but the plan has ${counts[entry.key] ?? 0} steps.',
        );
      }
    }
    for (final entry in counts.entries) {
      if (!budget.subAgentSteps.containsKey(entry.key)) {
        errors.add('Budget is missing ${entry.key.wireName}.');
      }
    }
    return errors;
  }
}
