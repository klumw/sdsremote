/// BPMN stage 3: classify the requested measurement type.
library;

import '../catalog/planner_catalog.dart';
import '../catalog/recipe.dart';
import '../models/action_plan.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import 'planner_state.dart';
import 'stage_result.dart';

/// Classifies the request as simple reading, audio or digital.
///
/// Anything outside the catalog — including pure spectrum, fault-analysis,
/// classification and report requests — aborts `unsupported_method`; the
/// WaveformAgent routes those directly to the specialists. A request that
/// mixes audio and digital measurements aborts `too_complex`.
StageResult<TypeAssessment> classifyType({
  required MeasurementRequest request,
  required PlannerCatalog catalog,
}) {
  if (request.measurements.isEmpty) {
    return StageResult.abort(
      AbortReason.inputIncomplete,
      message: 'The request does not name any measurement.',
      details: const <String, Object?>{'reason': 'EMPTY_MEASUREMENTS'},
    );
  }

  final recipes = <Recipe>[];
  final unknownIds = <String>[];
  for (final id in request.measurements) {
    if (id.startsWith(otherMeasurementPrefix)) continue;
    final recipe = catalog.recipeFor(id);
    if (recipe == null) {
      unknownIds.add(id);
    } else if (!recipes.any((existing) => existing.id == recipe.id)) {
      recipes.add(recipe);
    }
  }
  final otherMeasurements = catalog.otherMeasurements(request.measurements);

  if (unknownIds.isNotEmpty || otherMeasurements.isNotEmpty) {
    return StageResult.abort(
      AbortReason.unsupportedMethod,
      message:
          'The request contains a measurement that the planner does not '
          'support. Ask for a catalog measurement or split the request.',
      details: <String, Object?>{
        if (unknownIds.isNotEmpty) 'unknownIds': unknownIds,
        if (otherMeasurements.isNotEmpty)
          'otherMeasurements': otherMeasurements,
      },
    );
  }

  if (recipes.isEmpty) {
    return StageResult.abort(
      AbortReason.unsupportedMethod,
      message: 'The request does not contain a supported measurement.',
      details: <String, Object?>{'measurements': request.measurements},
    );
  }

  final hasAudio = recipes.any((recipe) => recipe.type == RecipeType.audio);
  final hasDigital = recipes.any((recipe) => recipe.type == RecipeType.digital);
  if (hasAudio && hasDigital) {
    return StageResult.abort(
      AbortReason.tooComplex,
      message:
          'The request mixes audio and digital measurements. Split it into two '
          'requests.',
      details: <String, Object?>{
        'audio': <String>[
          for (final recipe in recipes)
            if (recipe.type == RecipeType.audio) recipe.id,
        ],
        'digital': <String>[
          for (final recipe in recipes)
            if (recipe.type == RecipeType.digital) recipe.id,
        ],
      },
    );
  }

  final planType = hasAudio
      ? PlanType.audio
      : hasDigital
      ? PlanType.digital
      : PlanType.simpleReading;

  return StageResult.ok(
    TypeAssessment(
      planType: planType,
      recipes: List<Recipe>.unmodifiable(recipes),
      otherMeasurements: otherMeasurements,
    ),
  );
}
