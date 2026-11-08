/// Deterministic BPMN pipeline of the PlannerAgent.
///
/// Every invocation re-runs the complete pipeline. The only state that travels
/// between invocations is the request, the collected answers and the round
/// counter, which the session store keeps host-side.
library;

import '../catalog/planner_catalog.dart';
import '../models/action_plan.dart';
import '../models/input_form.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import '../planner_ids.dart';
import '../safety/safety_policy.dart';
import 'equipment_probe.dart';
import 'stage_ask_user.dart';
import 'stage_calculate_missing_input.dart';
import 'stage_check_equipment.dart';
import 'stage_classify_complexity.dart';
import 'stage_classify_request.dart';
import 'stage_create_action_plan.dart';
import 'planner_state.dart';
import 'stage_plan_audio.dart';
import 'stage_plan_digital.dart';
import 'stage_plan_simple.dart';

/// Result of one pipeline invocation, including the state to keep for the
/// next round.
class PlannerOutcome {
  const PlannerOutcome({
    required this.result,
    required this.request,
    required this.answers,
    required this.nextRound,
    this.form,
  });

  /// Tagged result returned to the model.
  final PlannerResult result;

  /// Request with the collected answers merged in.
  final MeasurementRequest request;

  /// Cumulative answers of all rounds.
  final Map<String, Object?> answers;

  /// Round to use for the next invocation.
  final int nextRound;

  /// Form of a `needs_input` result.
  final InputForm? form;
}

/// Composes stages 1-8.
class PlannerPipeline {
  PlannerPipeline({
    PlannerCatalog? catalog,
    SafetyPolicy? safetyPolicy,
    PlannerConfig? config,
    PlannerIdSource? idSource,
  }) : catalog = catalog ?? PlannerCatalog.standard,
       safetyPolicy = safetyPolicy ?? SafetyPolicy.defaults,
       config = config ?? PlannerConfig.defaults,
       idSource = idSource ?? SequentialIdSource();

  /// Recipe catalog.
  final PlannerCatalog catalog;

  /// Safety policy.
  final SafetyPolicy safetyPolicy;

  /// Budgets and limits.
  final PlannerConfig config;

  /// Deterministic identifier source.
  final PlannerIdSource idSource;

  /// Runs the pipeline for [request] with the cumulative [answers].
  ///
  /// [round] is the number of forms already shown. [probe] is the only device
  /// seam; [stateRef] lets a resumed session keep its opaque reference.
  Future<PlannerOutcome> run(
    MeasurementRequest request,
    Map<String, Object?> answers,
    int round,
    EquipmentProbe probe, {
    String? stateRef,
  }) async {
    final mergedRequest = request.merged(answers: answers);
    final effectiveAnswers = <String, Object?>{...?request.answers, ...answers};
    final effectiveStateRef =
        stateRef ?? request.stateRef ?? idSource('planner-state');

    PlannerOutcome outcome(PlannerResult result) => PlannerOutcome(
      result: result,
      request: mergedRequest,
      answers: effectiveAnswers,
      nextRound: round,
    );

    // Stage 1: danger, first pass. A correctable block continues so the form
    // can collect the missing safety data; stage 8 re-checks.
    final initialDanger = safetyPolicy.evaluate(
      request: mergedRequest,
      mergedInputs: effectiveAnswers,
    );
    if (initialDanger.isBlocked && !initialDanger.correctable) {
      return outcome(
        AbortedResult(
          reason: AbortReason.tooDangerous,
          message:
              'The setup is not safe to measure: '
              '${initialDanger.reasons.join(' ')}',
          details: initialDanger.toJson(),
        ),
      );
    }

    // Stage 2: equipment.
    final equipmentResult = await checkEquipment(
      request: mergedRequest,
      catalog: catalog,
      probe: probe,
    );
    if (equipmentResult.isAborted) {
      return outcome(equipmentResult.toPlannerResult());
    }
    final equipment = equipmentResult.requireValue;

    // Stage 3: classification. The automatic classification can hand the
    // request back to the user or route it to a specialist.
    final classificationResult = classifyRequest(
      request: mergedRequest,
      catalog: catalog,
      round: round,
      config: config,
      idSource: idSource,
    );
    if (classificationResult.isAborted) {
      return outcome(classificationResult.toPlannerResult());
    }
    final TypeAssessment type;
    switch (classificationResult.requireValue) {
      case PlanClassification(:final assessment):
        type = assessment;
      case RoutedClassification(
        :final category,
        :final confidence,
        :final source,
      ):
        return PlannerOutcome(
          result: ClassifiedResult(
            category: category,
            confidence: confidence,
            source: source,
          ),
          request: mergedRequest,
          answers: effectiveAnswers,
          nextRound: round + 1,
        );
      case UserClassificationRequired(:final form):
        return PlannerOutcome(
          result: NeedsInputResult(form: form, stateRef: effectiveStateRef),
          request: mergedRequest,
          answers: effectiveAnswers,
          nextRound: round + 1,
          form: form,
        );
    }

    // Stage 4: complexity.
    final complexityResult = classifyComplexity(
      type: type,
      request: mergedRequest,
      mergedInputs: effectiveAnswers,
      config: config,
    );
    if (complexityResult.isAborted) {
      return outcome(complexityResult.toPlannerResult());
    }
    final complexity = complexityResult.requireValue;

    // Stage 5: plan skeleton.
    final planResult = switch (type.planType) {
      PlanType.simpleReading => planSimple(
        type: type,
        complexity: complexity,
        config: config,
      ),
      PlanType.audio => planAudio(
        type: type,
        complexity: complexity,
        config: config,
      ),
      PlanType.digital => planDigital(
        type: type,
        complexity: complexity,
        config: config,
      ),
    };
    if (planResult.isAborted) {
      return outcome(planResult.toPlannerResult());
    }
    final draft = planResult.requireValue;

    // Stage 6: missing input.
    final missingResult = calculateMissingInput(
      request: mergedRequest,
      answers: effectiveAnswers,
      draft: draft,
      equipment: equipment,
      config: config,
      safetyPolicy: safetyPolicy,
      catalog: catalog,
    );
    if (missingResult.isAborted) {
      return outcome(missingResult.toPlannerResult());
    }
    final missing = missingResult.requireValue;

    // Stage 7: one bundled form.
    final askResult = askUser(
      missing: missing,
      round: round,
      config: config,
      idSource: idSource,
      catalog: catalog,
    );
    if (askResult.isAborted) {
      return outcome(askResult.toPlannerResult());
    }
    final decision = askResult.requireValue;
    if (decision.form != null) {
      return PlannerOutcome(
        result: NeedsInputResult(
          form: decision.form!,
          stateRef: effectiveStateRef,
        ),
        request: mergedRequest,
        answers: effectiveAnswers,
        nextRound: round + 1,
        form: decision.form,
      );
    }

    // Stage 8: final plan.
    final actionPlanResult = createActionPlan(
      request: mergedRequest,
      draft: draft,
      inputs: missing,
      equipment: equipment,
      safetyPolicy: safetyPolicy,
      config: config,
      idSource: idSource,
    );
    if (actionPlanResult.isAborted) {
      return outcome(actionPlanResult.toPlannerResult());
    }
    return PlannerOutcome(
      result: PlanReadyResult(actionPlanResult.requireValue),
      request: mergedRequest,
      answers: effectiveAnswers,
      nextRound: round + 1,
    );
  }
}
