/// Step skeletons produced by stage 5 and resolved by stages 6-8.
library;

import '../catalog/recipe.dart';
import '../models/action_plan.dart';

/// One planned step before parameter values are resolved.
class PlanStepDraft {
  const PlanStepDraft({
    required this.id,
    required this.kind,
    required this.agent,
    required this.template,
    required this.parameterKeys,
    required this.dependsOn,
    required this.requiresUserConfirmation,
    required this.expectedOutput,
    required this.estimatedToolCalls,
    this.focus,
  });

  /// Unique step id inside the plan.
  final String id;

  /// Kind of work.
  final ActionStepKind kind;

  /// Executing agent.
  final PlanAgent agent;

  /// Executing agent.
  final String? focus;

  /// English template with `{key}` placeholders.
  final String template;

  /// Parameter keys needed by the step.
  final List<String> parameterKeys;

  /// Ids of steps that must complete first.
  final List<String> dependsOn;

  /// Whether the user must confirm before the step runs.
  final bool requiresUserConfirmation;

  /// English description of the produced result.
  final String expectedOutput;

  /// Estimated tool calls inside the executing sub-agent.
  final int estimatedToolCalls;

  /// Returns a copy with a different dependency list.
  PlanStepDraft copyWith({List<String>? dependsOn}) {
    return PlanStepDraft(
      id: id,
      kind: kind,
      agent: agent,
      focus: focus,
      template: template,
      parameterKeys: parameterKeys,
      dependsOn: dependsOn ?? this.dependsOn,
      requiresUserConfirmation: requiresUserConfirmation,
      expectedOutput: expectedOutput,
      estimatedToolCalls: estimatedToolCalls,
    );
  }
}

/// Ordered step skeletons of one plan.
class PlanDraft {
  PlanDraft({
    required this.type,
    required this.steps,
    required this.recipes,
    required this.subAgentSteps,
    required this.generatorEnabled,
  });

  /// Measurement category of the plan.
  final PlanType type;

  /// Mutable step list; stages 6-8 insert read and safety steps.
  final List<PlanStepDraft> steps;

  /// Recipes covered by the plan.
  final List<Recipe> recipes;

  /// Number of steps per sub-agent, excluding manual steps.
  final Map<PlanAgent, int> subAgentSteps;

  /// Whether the planner enables the generator and must tear it down.
  final bool generatorEnabled;

  /// Inserts [step] directly before [stepId], or at the end when not found.
  void insertBefore(String stepId, PlanStepDraft step) {
    final index = steps.indexWhere((existing) => existing.id == stepId);
    steps.insert(index < 0 ? steps.length : index, step);
  }

  /// Replaces the step at [index].
  void replaceAt(int index, PlanStepDraft step) {
    steps[index] = step;
  }
}
