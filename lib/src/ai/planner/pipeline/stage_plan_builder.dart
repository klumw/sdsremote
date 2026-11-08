/// Shared plan construction used by the three planner stages (BPMN stage 5).
library;

import '../catalog/recipe.dart';
import '../models/action_plan.dart';
import '../planner_config.dart';
import 'plan_draft.dart';
import 'plan_rendering.dart';
import 'planner_state.dart';

/// Builds ordered step skeletons for [type] using the groups of [complexity].
///
/// Manual setup steps come first and never count against the sub-agent
/// budget. A generator that is not managed by the host adds one configure
/// step and one teardown step so the two-step instrument budget is not
/// exceeded. One measure step is emitted per recipe group.
PlanDraft buildPlanDraft({
  required TypeAssessment type,
  required ComplexityAssessment complexity,
  required PlannerConfig config,
}) {
  final recipes = type.recipes;
  final steps = <PlanStepDraft>[];
  final manualIds = <String>[];
  final seenInstructions = <String>{};

  for (final recipe in recipes) {
    for (final instruction in recipe.manualInstructions) {
      if (!seenInstructions.add(instruction)) continue;
      final id = 'manual-${manualIds.length + 1}';
      manualIds.add(id);
      steps.add(
        PlanStepDraft(
          id: id,
          kind: ActionStepKind.manual,
          agent: PlanAgent.user,
          template: instruction,
          parameterKeys: templatePlaceholders(instruction).toList(),
          dependsOn: const <String>[],
          requiresUserConfirmation: false,
          expectedOutput: 'The described setup is connected.',
          estimatedToolCalls: 0,
        ),
      );
    }
  }

  final generatorRecipes = <Recipe>[
    for (final recipe in recipes)
      if (recipe.needsGenerator && !recipe.hostManagesGenerator) recipe,
  ];
  final generatorIds = <String>[];
  if (generatorRecipes.isNotEmpty) {
    final keys = <String>{
      for (final recipe in generatorRecipes) ...recipe.parameterKeys,
    };
    final parts = <String>[
      if (keys.contains(PlannerKeys.generatorChannel))
        'channel {generatorChannel}',
      if (keys.contains(PlannerKeys.generatorWaveform))
        '{generatorWaveform} waveform',
      if (keys.contains(PlannerKeys.frequencyHz)) '{frequencyHz} Hz',
      if (keys.contains(PlannerKeys.amplitudeVpp))
        '{amplitudeVpp} Vpp amplitude',
      if (keys.contains(PlannerKeys.offsetV)) '{offsetV} V offset',
    ];
    final template = parts.isEmpty
        ? 'Configure the signal generator for the measurement and enable its '
              'output.'
        : 'Set the signal generator to ${parts.join(', ')} and enable the '
              'output.';
    const id = 'configure-generator-1';
    generatorIds.add(id);
    steps.add(
      PlanStepDraft(
        id: id,
        kind: ActionStepKind.configureGenerator,
        agent: PlanAgent.scpiInstrument,
        focus: 'signal_generator',
        template: template,
        parameterKeys: templatePlaceholders(template).toList(),
        dependsOn: List<String>.of(manualIds),
        // The plan approval already authorizes this listed setup change.
        requiresUserConfirmation: false,
        expectedOutput:
            'The generator is configured and its output is enabled.',
        estimatedToolCalls: 1,
      ),
    );
  }

  final measureIds = <String>[];
  for (var index = 0; index < complexity.groups.length; index++) {
    final group = complexity.groups[index];
    final id = 'measure-${index + 1}';
    measureIds.add(id);
    final keys = <String>[];
    final seenKeys = <String>{};
    for (final recipe in group.recipes) {
      for (final parameter in recipe.parameters) {
        if (seenKeys.add(parameter.key)) keys.add(parameter.key);
      }
    }
    steps.add(
      PlanStepDraft(
        id: id,
        kind: ActionStepKind.measure,
        agent: group.agent,
        focus: group.focus,
        template: group.recipes
            .map((recipe) => recipe.requestTemplate)
            .join(' '),
        parameterKeys: keys,
        dependsOn: <String>[...manualIds, ...generatorIds],
        requiresUserConfirmation: false,
        expectedOutput: group.recipes
            .map((recipe) => recipe.expectedOutput)
            .join('; '),
        estimatedToolCalls: group.estimatedToolCalls,
      ),
    );
  }

  final generatorEnabled = generatorRecipes.isNotEmpty;
  if (generatorEnabled) {
    steps.add(
      PlanStepDraft(
        id: 'teardown',
        kind: ActionStepKind.teardown,
        agent: PlanAgent.scpiInstrument,
        focus: 'signal_generator',
        template:
            'Switch both signal-generator outputs off and restore a safe '
            'state.',
        parameterKeys: const <String>[],
        dependsOn: List<String>.of(measureIds),
        requiresUserConfirmation: false,
        expectedOutput: 'Both generator outputs are off.',
        estimatedToolCalls: 1,
      ),
    );
  }

  final subAgentSteps = <PlanAgent, int>{};
  for (final step in steps) {
    if (step.agent == PlanAgent.user) continue;
    subAgentSteps.update(step.agent, (value) => value + 1, ifAbsent: () => 1);
  }

  return PlanDraft(
    type: type.planType,
    steps: steps,
    recipes: recipes,
    subAgentSteps: subAgentSteps,
    generatorEnabled: generatorEnabled,
  );
}
