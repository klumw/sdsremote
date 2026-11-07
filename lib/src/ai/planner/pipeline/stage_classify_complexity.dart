/// BPMN stage 4: reject requests that are too complex for one plan.
library;

import '../catalog/recipe.dart';
import '../models/action_plan.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import 'planner_state.dart';
import 'stage_result.dart';

/// Patterns that indicate protocol decoding.
final RegExp _protocolDecodePattern = RegExp(
  r'\b(decod(e|ing)|protocol\s+decod(e|ing))\b',
  caseSensitive: false,
);

/// Parameter keys that name a scope channel.
const Set<String> _channelKeys = <String>{
  PlannerKeys.channel,
  PlannerKeys.channelB,
  'aggressorChannel',
  'victimChannel',
  'inputChannel',
  'outputChannel',
};

/// Classifies the complexity of an audio or digital request and groups the
/// recipes into one step per sub-agent call.
///
/// Aborts `too_complex` when a sub-agent would need more than
/// [PlannerConfig.maxStepsPerSubAgent] steps, a single recipe exceeds the
/// sub-agent call limit minus the margin, the summed estimate exceeds the
/// request budget, more than [PlannerConfig.maxChannels] channels are used,
/// protocol decoding is requested, or more than one physical setup is needed.
StageResult<ComplexityAssessment> classifyComplexity({
  required TypeAssessment type,
  required MeasurementRequest request,
  required Map<String, Object?> mergedInputs,
  required PlannerConfig config,
}) {
  final channels = _mentionedChannels(request, mergedInputs);
  if (channels.length > config.maxChannels) {
    return StageResult.abort(
      AbortReason.tooComplex,
      message:
          'The request uses ${channels.length} scope channels; at most '
          '${config.maxChannels} are supported.',
      details: <String, Object?>{
        'reason': 'TOO_MANY_CHANNELS',
        'channels': channels,
        'maxChannels': config.maxChannels,
      },
    );
  }

  if (type.isSimple) {
    // One read of the waveform summary returns every time-domain value, so a
    // simple request is always one scope step.
    var largest = 0;
    for (final recipe in type.recipes) {
      if (recipe.estimatedToolCalls > largest) {
        largest = recipe.estimatedToolCalls;
      }
    }
    final estimate = config.stepOverheadToolCalls + largest;
    final budget = config.usableCallBudgetFor(PlanAgent.scopeAnalysis);
    if (estimate > budget) {
      return StageResult.abort(
        AbortReason.tooComplex,
        message:
            'The simple measurement needs $estimate tool calls; only $budget '
            'are available.',
        details: <String, Object?>{
          'reason': 'UNSPLITTABLE_BUDGET',
          'estimatedToolCalls': estimate,
          'budget': budget,
        },
      );
    }
    if (estimate > config.totalToolCallBudget) {
      return StageResult.abort(
        AbortReason.tooComplex,
        message:
            'The request needs $estimate tool calls; the budget is '
            '${config.totalToolCallBudget}.',
        details: <String, Object?>{
          'reason': 'TOTAL_BUDGET',
          'estimatedToolCalls': estimate,
          'budget': config.totalToolCallBudget,
        },
      );
    }
    return StageResult.ok(
      ComplexityAssessment(
        groups: <RecipeGroup>[
          RecipeGroup(
            agent: PlanAgent.scopeAnalysis,
            focus: 'measurement',
            recipes: List<Recipe>.unmodifiable(type.recipes),
            estimatedToolCalls: estimate,
          ),
        ],
        estimatedToolCalls: estimate,
        channels: channels,
      ),
    );
  }

  final protocolText = <String>[
    request.goal,
    ...request.measurements,
  ].join(' ');
  if (type.recipes.any((recipe) => recipe.requiresProtocolDecode) ||
      _protocolDecodePattern.hasMatch(protocolText)) {
    return StageResult.abort(
      AbortReason.tooComplex,
      message: 'Protocol decoding is not supported by the planner.',
      details: const <String, Object?>{'reason': 'PROTOCOL_DECODE'},
    );
  }

  final setups = <String>{for (final recipe in type.recipes) recipe.setupId};
  if (setups.length > 1) {
    final sorted = setups.toList()..sort();
    return StageResult.abort(
      AbortReason.tooComplex,
      message:
          'The request needs ${setups.length} different physical setups. Split '
          'it into one request per setup.',
      details: <String, Object?>{'reason': 'MULTIPLE_SETUPS', 'setups': sorted},
    );
  }

  final List<RecipeGroup> groups;
  try {
    groups = _groupRecipes(type.recipes, config);
  } on _ComplexityFailure catch (failure) {
    return StageResult.abort(
      failure.reason,
      message: failure.message,
      details: failure.details,
    );
  }

  var total = 0;
  for (final group in groups) {
    total += group.estimatedToolCalls;
  }
  if (total > config.totalToolCallBudget) {
    return StageResult.abort(
      AbortReason.tooComplex,
      message:
          'The request needs $total tool calls; the budget is '
          '${config.totalToolCallBudget}.',
      details: <String, Object?>{
        'reason': 'TOTAL_BUDGET',
        'estimatedToolCalls': total,
        'budget': config.totalToolCallBudget,
      },
    );
  }

  return StageResult.ok(
    ComplexityAssessment(
      groups: List<RecipeGroup>.unmodifiable(groups),
      estimatedToolCalls: total,
      channels: channels,
    ),
  );
}

List<RecipeGroup> _groupRecipes(List<Recipe> recipes, PlannerConfig config) {
  final byAgent = <PlanAgent, List<Recipe>>{};
  for (final recipe in recipes) {
    byAgent.putIfAbsent(recipe.agent, () => <Recipe>[]).add(recipe);
  }

  final groups = <RecipeGroup>[];
  for (final entry in byAgent.entries) {
    final agent = entry.key;
    final agentRecipes = entry.value;
    if (agent == PlanAgent.user || agent == PlanAgent.scpiInstrument) {
      continue;
    }
    final budget = config.usableCallBudgetFor(agent);
    final overhead = config.stepOverheadToolCalls;

    var sum = 0;
    for (final recipe in agentRecipes) {
      sum += recipe.estimatedToolCalls;
    }
    if (overhead + sum <= budget) {
      groups.add(
        RecipeGroup(
          agent: agent,
          focus: 'full',
          recipes: List<Recipe>.unmodifiable(agentRecipes),
          estimatedToolCalls: overhead + sum,
        ),
      );
      continue;
    }

    final byFocus = <String, List<Recipe>>{};
    for (final recipe in agentRecipes) {
      byFocus.putIfAbsent(recipe.focus, () => <Recipe>[]).add(recipe);
    }
    final focusGroups = <RecipeGroup>[];
    for (final focusEntry in byFocus.entries) {
      var focusSum = 0;
      for (final recipe in focusEntry.value) {
        focusSum += recipe.estimatedToolCalls;
      }
      if (overhead + focusSum <= budget) {
        focusGroups.add(
          RecipeGroup(
            agent: agent,
            focus: focusEntry.key,
            recipes: List<Recipe>.unmodifiable(focusEntry.value),
            estimatedToolCalls: overhead + focusSum,
          ),
        );
        continue;
      }
      for (final recipe in focusEntry.value) {
        final single = overhead + recipe.estimatedToolCalls;
        if (single > budget) {
          throw _ComplexityFailure(
            AbortReason.tooComplex,
            'Recipe "${recipe.id}" needs $single tool calls; only $budget are '
            'available for ${agent.wireName}. Split the request.',
            <String, Object?>{
              'reason': 'UNSPLITTABLE_BUDGET',
              'recipe': recipe.id,
              'estimatedToolCalls': single,
              'budget': budget,
            },
          );
        }
        focusGroups.add(
          RecipeGroup(
            agent: agent,
            focus: focusEntry.key,
            recipes: <Recipe>[recipe],
            estimatedToolCalls: single,
          ),
        );
      }
    }
    if (focusGroups.length > config.maxStepsPerSubAgent) {
      throw _ComplexityFailure(
        AbortReason.tooComplex,
        'The request needs ${focusGroups.length} steps for '
        '${agent.wireName}; at most ${config.maxStepsPerSubAgent} are allowed.',
        <String, Object?>{
          'reason': 'TOO_MANY_STEPS',
          'agent': agent.wireName,
          'steps': focusGroups.length,
          'maxSteps': config.maxStepsPerSubAgent,
        },
      );
    }
    groups.addAll(focusGroups);
  }
  return groups;
}

List<String> _mentionedChannels(
  MeasurementRequest request,
  Map<String, Object?> mergedInputs,
) {
  final values = <String>{};
  final sources = <Map<String, Object?>>[
    request.knownParameters,
    if (request.answers != null) request.answers!,
    mergedInputs,
  ];
  for (final source in sources) {
    for (final key in _channelKeys) {
      final value = source[key];
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized.isNotEmpty) values.add(normalized);
      } else if (value is Iterable) {
        for (final entry in value) {
          if (entry is String && entry.trim().isNotEmpty) {
            values.add(entry.trim().toLowerCase());
          }
        }
      }
    }
  }
  final sorted = values.toList()..sort();
  return List<String>.unmodifiable(sorted);
}

class _ComplexityFailure implements Exception {
  const _ComplexityFailure(this.reason, this.message, this.details);

  final AbortReason reason;
  final String message;
  final Map<String, Object?> details;
}
