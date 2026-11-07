/// BPMN stage 7: build one bundled form for the missing user data.
library;

import '../catalog/param_spec.dart';
import '../catalog/planner_catalog.dart';
import '../models/input_form.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import '../planner_ids.dart';
import 'missing_input.dart';
import 'stage_result.dart';

/// Decision of stage 7.
class AskUserDecision {
  const AskUserDecision.proceed() : form = null;

  const AskUserDecision.form(this.form);

  /// Form to present, or `null` to continue with the plan.
  final InputForm? form;
}

/// Builds a form with at most [PlannerConfig.maxFormQuestions] questions.
///
/// Questions are ordered safety first, then dependency order and catalog
/// order. Cancelling aborts `user_cancelled`, the unknown sentinel aborts
/// `user_input_unknown`, and exceeding [PlannerConfig.maxFormRounds] aborts
/// `input_incomplete`.
StageResult<AskUserDecision> askUser({
  required MissingInputPlan missing,
  required int round,
  required PlannerConfig config,
  required PlannerIdSource idSource,
  required PlannerCatalog catalog,
}) {
  if (missing.cancelled) {
    return StageResult.abort(
      AbortReason.userCancelled,
      message: 'The user cancelled the input form.',
      details: const <String, Object?>{'reason': 'FORM_CANCELLED'},
    );
  }
  if (missing.hasUnknownSentinel) {
    return StageResult.abort(
      AbortReason.userInputUnknown,
      message:
          'A required safety or measurement value is unknown to the user, so '
          'the plan cannot be completed safely.',
      details: <String, Object?>{'keys': missing.unknownKeys},
    );
  }
  if (missing.missing.isEmpty) {
    return const StageResult.ok(AskUserDecision.proceed());
  }
  if (round >= config.maxFormRounds) {
    return StageResult.abort(
      AbortReason.inputIncomplete,
      message:
          'The required measurement data is still incomplete after '
          '${config.maxFormRounds} rounds.',
      details: <String, Object?>{
        'reason': 'ROUND_LIMIT',
        'round': round,
        'maxRounds': config.maxFormRounds,
        'missingKeys': <String>[for (final entry in missing.missing) entry.key],
      },
    );
  }

  final ordered = _order(missing.missing, catalog);
  final selected = ordered.take(config.maxFormQuestions).toList();
  final form = InputForm(
    formId: idSource('planner-form'),
    title: 'Measurement setup details',
    questions: <InputQuestion>[
      for (final entry in selected)
        entry.spec.toInputQuestion(validationMessage: entry.validationMessage),
    ],
  );
  return StageResult.ok(AskUserDecision.form(form));
}

List<MissingInput> _order(List<MissingInput> missing, PlannerCatalog catalog) {
  final safetyIndex = <String, int>{
    for (var index = 0; index < catalog.safetyParameters.length; index++)
      catalog.safetyParameters[index].key: index,
  };
  final specsByKey = <String, ParamSpec>{
    for (final entry in missing) entry.key: entry.spec,
  };
  final depthCache = <String, int>{};

  int depth(ParamSpec spec, Set<String> visiting) {
    final cached = depthCache[spec.key];
    if (cached != null) return cached;
    if (spec.dependsOn.isEmpty || !visiting.add(spec.key)) return 0;
    var result = 0;
    for (final dependency in spec.dependsOn) {
      final dependencySpec = specsByKey[dependency];
      if (dependencySpec == null) continue;
      final value = 1 + depth(dependencySpec, visiting);
      if (value > result) result = value;
    }
    visiting.remove(spec.key);
    depthCache[spec.key] = result;
    return result;
  }

  final indexed = missing.asMap().entries.toList();
  indexed.sort((a, b) {
    final aSafety = safetyIndex[a.value.key];
    final bSafety = safetyIndex[b.value.key];
    final aTier = aSafety == null ? 1 : 0;
    final bTier = bSafety == null ? 1 : 0;
    if (aTier != bTier) return aTier - bTier;
    if (aSafety != null && bSafety != null) return aSafety - bSafety;
    final aDepth = depth(a.value.spec, <String>{});
    final bDepth = depth(b.value.spec, <String>{});
    if (aDepth != bDepth) return aDepth - bDepth;
    final priority = a.value.spec.priority.compareTo(b.value.spec.priority);
    if (priority != 0) return priority;
    return a.key.compareTo(b.key);
  });
  return <MissingInput>[for (final entry in indexed) entry.value];
}
