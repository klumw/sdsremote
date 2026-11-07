/// BPMN stage 5b: build a plan for audio measurements.
library;

import '../models/action_plan.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import 'plan_draft.dart';
import 'planner_state.dart';
import 'stage_plan_builder.dart';
import 'stage_result.dart';

/// Builds the step skeleton of an audio request.
StageResult<PlanDraft> planAudio({
  required TypeAssessment type,
  required ComplexityAssessment complexity,
  required PlannerConfig config,
}) {
  if (type.planType != PlanType.audio) {
    return StageResult.abort(
      AbortReason.notFeasible,
      message: 'The request is not an audio measurement.',
      details: const <String, Object?>{'reason': 'WRONG_PLANNER'},
    );
  }
  return StageResult.ok(
    buildPlanDraft(type: type, complexity: complexity, config: config),
  );
}
