/// BPMN stage 5a: build a plan for simple scope readings.
library;

import '../models/action_plan.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import 'plan_draft.dart';
import 'planner_state.dart';
import 'stage_plan_builder.dart';
import 'stage_result.dart';

/// Builds the step skeleton of a simple reading request.
StageResult<PlanDraft> planSimple({
  required TypeAssessment type,
  required ComplexityAssessment complexity,
  required PlannerConfig config,
}) {
  if (type.planType != PlanType.simpleReading) {
    return StageResult.abort(
      AbortReason.notFeasible,
      message: 'The request is not a simple reading.',
      details: const <String, Object?>{'reason': 'WRONG_PLANNER'},
    );
  }
  return StageResult.ok(
    buildPlanDraft(type: type, complexity: complexity, config: config),
  );
}
