/// BPMN stage 8: merge inputs, re-check safety and build the action plan.
library;

import '../catalog/param_spec.dart';
import '../models/action_plan.dart';
import '../models/json_value.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import '../planner_ids.dart';
import '../safety/safety_policy.dart';
import 'equipment_report.dart';
import 'missing_input.dart';
import 'plan_draft.dart';
import 'plan_rendering.dart';
import 'stage_result.dart';

/// Builds the final [ActionPlan] with provenance, a fresh danger assessment,
/// a deterministic instruction rendering and structural validation.
StageResult<ActionPlan> createActionPlan({
  required MeasurementRequest request,
  required PlanDraft draft,
  required MissingInputPlan inputs,
  required EquipmentReport equipment,
  required SafetyPolicy safetyPolicy,
  required PlannerConfig config,
  required PlannerIdSource idSource,
}) {
  final values = <String, Object?>{
    for (final entry in inputs.resolved.entries) entry.key: entry.value.value,
  };

  final danger = safetyPolicy.evaluate(
    request: request,
    mergedInputs: values,
    generator: PlannedGeneratorSettings(
      amplitudeVpp: _number(values[PlannerKeys.amplitudeVpp]),
      offsetV: _number(values[PlannerKeys.offsetV]),
    ),
  );
  if (danger.isBlocked) {
    return StageResult.abort(
      AbortReason.tooDangerous,
      message: 'The setup is not safe to measure: ${danger.reasons.join(' ')}',
      details: danger.toJson(),
    );
  }

  String? safetyStepId;
  PlanStepDraft? safetyStep;
  if (danger.isWarning && danger.safetyNotes.isNotEmpty) {
    safetyStepId = 'safety-confirmation';
    safetyStep = PlanStepDraft(
      id: safetyStepId,
      kind: ActionStepKind.manual,
      agent: PlanAgent.user,
      template:
          'Confirm the following safety notes before the measurement: '
          '${danger.safetyNotes.join(' ')}',
      parameterKeys: const <String>[],
      dependsOn: const <String>[],
      requiresUserConfirmation: false,
      expectedOutput: 'The user confirmed the safety notes.',
      estimatedToolCalls: 0,
    );
  }

  // Place manual setup steps first, then the safety confirmation, then the
  // remaining steps.
  final steps = <PlanStepDraft>[];
  var safetyInserted = safetyStep == null;
  for (final step in draft.steps) {
    if (!safetyInserted && step.agent != PlanAgent.user) {
      steps.add(safetyStep!);
      safetyInserted = true;
    }
    steps.add(step);
  }
  if (!safetyInserted) steps.add(safetyStep!);

  // Insert read steps directly before their consuming step and make the
  // consumer depend on the read step.
  for (final read in inputs.readSteps) {
    final before = steps.indexWhere((step) => step.id == read.beforeStepId);
    steps.insert(before < 0 ? steps.length : before, read.step);
    final consumer = steps.indexWhere((step) => step.id == read.beforeStepId);
    if (consumer >= 0 && consumer < steps.length) {
      final step = steps[consumer];
      if (!step.dependsOn.contains(read.step.id)) {
        steps[consumer] = step.copyWith(
          dependsOn: <String>[...step.dependsOn, read.step.id],
        );
      }
    }
  }

  // Every executable step waits for the safety confirmation.
  final safety = safetyStepId;
  if (safety != null) {
    for (var index = 0; index < steps.length; index++) {
      final step = steps[index];
      if (step.id == safety || step.agent == PlanAgent.user) continue;
      if (step.dependsOn.contains(safety)) continue;
      steps[index] = step.copyWith(
        dependsOn: <String>[...step.dependsOn, safety],
      );
    }
  }

  final actionSteps = <ActionStep>[];
  for (final step in steps) {
    final parameters = <String, StepParameter>{};
    for (final key in step.parameterKeys) {
      final reference = inputs.references[key];
      if (reference != null) {
        parameters[key] = reference;
        continue;
      }
      final resolved = inputs.resolved[key];
      if (resolved == null) {
        // An optional parameter that the user did not provide is simply
        // omitted. It must not fail the whole plan.
        final spec = _specFor(draft, key);
        if (spec != null && !spec.required) continue;
        return StageResult.abort(
          AbortReason.notFeasible,
          message: 'The plan is missing a value for "$key".',
          details: <String, Object?>{
            'reason': 'MISSING_RESOLVED_INPUT',
            'key': key,
            'step': step.id,
          },
        );
      }
      parameters[key] = LiteralParameter(jsonSafe(resolved.value, key));
    }

    final String instruction;
    try {
      instruction = renderTemplate(
        step.template,
        values,
        references: inputs.references,
      );
    } on PlannerFormatException catch (error) {
      return StageResult.abort(
        AbortReason.notFeasible,
        message: 'The plan instruction could not be rendered.',
        details: <String, Object?>{
          'reason': 'TEMPLATE_ERROR',
          'step': step.id,
          'error': error.toString(),
        },
      );
    }

    actionSteps.add(
      ActionStep(
        id: step.id,
        kind: step.kind,
        agent: step.agent,
        focus: step.focus,
        instruction: instruction,
        parameters: parameters,
        dependsOn: step.dependsOn,
        requiresUserConfirmation: step.requiresUserConfirmation,
        expectedOutput: step.expectedOutput,
        estimatedToolCalls: step.estimatedToolCalls,
      ),
    );
  }

  final budgetCounts = <PlanAgent, int>{};
  for (final step in actionSteps) {
    if (step.agent == PlanAgent.user) continue;
    budgetCounts.update(step.agent, (value) => value + 1, ifAbsent: () => 1);
  }

  final plan = ActionPlan(
    planId: idSource('plan'),
    goal: request.goal,
    type: draft.type,
    inputs: _planInputs(draft, inputs),
    safetyNotes: danger.safetyNotes,
    steps: actionSteps,
    budget: PlanBudget(subAgentSteps: budgetCounts),
    equipment: _planEquipment(equipment),
  );

  final errors = plan.validate(maxStepsPerSubAgent: config.maxStepsPerSubAgent);
  if (errors.isNotEmpty) {
    return StageResult.abort(
      AbortReason.notFeasible,
      message: 'The generated plan is structurally invalid.',
      details: <String, Object?>{'reason': 'PLAN_INVALID', 'errors': errors},
    );
  }
  if (actionSteps.length > config.maxPlanSteps) {
    return StageResult.abort(
      AbortReason.notFeasible,
      message:
          'The plan needs ${actionSteps.length} steps; at most '
          '${config.maxPlanSteps} are allowed.',
      details: <String, Object?>{
        'reason': 'PLAN_TOO_LONG',
        'steps': actionSteps.length,
        'maxSteps': config.maxPlanSteps,
      },
    );
  }

  return StageResult.ok(plan);
}

PlanEquipment _planEquipment(EquipmentReport report) {
  final generator = report.generator;
  return PlanEquipment(
    scope: PlanScopeEquipment(
      reachable: report.scope.reachable,
      model: report.scope.model,
      profile: report.scope.profile,
      host: report.scope.host,
      error: report.scope.error,
    ),
    generator: generator == null
        ? const PlanGeneratorEquipment(
            configured: false,
            connected: false,
            supported: false,
            error: 'The signal generator was not probed.',
          )
        : PlanGeneratorEquipment(
            configured: generator.configured,
            connected: generator.connected,
            supported: generator.supported,
            detected: generator.detected,
            model: generator.model,
            identity: generator.identity,
            family: generator.family?.wireName,
            port: generator.port,
            error: generator.error,
          ),
  );
}

List<PlanInput> _planInputs(PlanDraft draft, MissingInputPlan inputs) {
  final result = <PlanInput>[];
  final added = <String>{};

  void add(String key) {
    if (!added.add(key)) return;
    final reference = inputs.references[key];
    if (reference != null) {
      result.add(
        PlanInput(
          key: key,
          value: reference.toJson(),
          source: InputSource.device,
        ),
      );
      return;
    }
    final resolved = inputs.resolved[key];
    if (resolved == null) return;
    result.add(
      PlanInput(
        key: key,
        value: jsonSafe(resolved.value, key),
        source: resolved.source,
      ),
    );
  }

  for (final recipe in draft.recipes) {
    for (final parameter in recipe.parameters) {
      add(parameter.key);
    }
  }
  for (final key in inputs.resolved.keys) {
    add(key);
  }
  for (final key in inputs.references.keys) {
    add(key);
  }
  return result;
}

ParamSpec? _specFor(PlanDraft draft, String key) {
  for (final recipe in draft.recipes) {
    final spec = recipe.parameterFor(key);
    if (spec != null) return spec;
  }
  return null;
}

double? _number(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}
