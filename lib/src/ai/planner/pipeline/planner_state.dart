/// Intermediate context shared by the later pipeline stages.
library;

import '../catalog/recipe.dart';
import '../models/action_plan.dart';

/// Result of stage 3.
class TypeAssessment {
  const TypeAssessment({
    required this.planType,
    required this.recipes,
    required this.otherMeasurements,
  });

  /// Measurement category of the request.
  final PlanType planType;

  /// Selected recipes, in request order.
  final List<Recipe> recipes;

  /// Free-text measurements that are not in the catalog.
  ///
  /// The classification stage asks the user for a category when these are
  /// present. The field is kept so the details can list them.
  final List<String> otherMeasurements;

  /// Whether the request is a simple scope reading.
  bool get isSimple => planType == PlanType.simpleReading;

  /// Whether the request contains an audio measurement.
  bool get isAudio => planType == PlanType.audio;

  /// Whether the request contains a digital measurement.
  bool get isDigital => planType == PlanType.digital;
}

/// Recipes executed by one sub-agent in one step.
class RecipeGroup {
  const RecipeGroup({
    required this.agent,
    required this.focus,
    required this.recipes,
    required this.estimatedToolCalls,
  });

  /// Executing sub-agent.
  final PlanAgent agent;

  /// Focus block passed to the sub-agent.
  final String focus;

  /// Recipes covered by the step.
  final List<Recipe> recipes;

  /// Estimated tool calls including the step overhead.
  final int estimatedToolCalls;
}

/// Result of stage 4.
class ComplexityAssessment {
  const ComplexityAssessment({
    required this.groups,
    required this.estimatedToolCalls,
    required this.channels,
  });

  /// Final measurement groups, one per sub-agent step.
  final List<RecipeGroup> groups;

  /// Summed tool-call estimate of all groups.
  final int estimatedToolCalls;

  /// Distinct scope channels mentioned by the request.
  final List<String> channels;
}
