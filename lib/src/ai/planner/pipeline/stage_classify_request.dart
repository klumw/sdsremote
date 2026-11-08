/// BPMN stage 3: classify the request and fall back to the user.
///
/// The PlannerAgent model classifies every request. When the classification is
/// doubtful, contradicts the resolvable recipes, or the catalog has no recipe,
/// the stage returns a single-choice form. The user then picks one of four
/// categories and the orchestrator routes the original request to the matching
/// specialist.
library;

import '../catalog/planner_catalog.dart';
import '../models/input_form.dart';
import '../models/measurement_classification.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../planner_config.dart';
import '../planner_ids.dart';
import 'planner_state.dart';
import 'stage_classify_type.dart';
import 'stage_result.dart';

/// Why the planner asks the user to classify the request.
enum ClassificationTrigger {
  noResult('no_result'),
  lowConfidence('low_confidence'),
  mismatch('mismatch'),
  invalidAnswer('invalid_answer');

  const ClassificationTrigger(this.wireName);

  /// Machine-readable trigger name used in tests and diagnostics.
  final String wireName;
}

/// Options of the user-driven classification form.
final List<InputOption> measurementCategoryOptions =
    List<InputOption>.unmodifiable(<InputOption>[
      for (final category in MeasurementCategory.values)
        InputOption(value: category.wireName, label: category.label),
    ]);

/// Decision of stage 3.
sealed class ClassificationDecision {
  const ClassificationDecision();
}

/// Continue with the deterministic plan.
final class PlanClassification extends ClassificationDecision {
  const PlanClassification(this.assessment);

  /// Type assessment of the resolved recipes.
  final TypeAssessment assessment;
}

/// Return a `classified` result for the orchestrator to route.
final class RoutedClassification extends ClassificationDecision {
  const RoutedClassification({
    required this.category,
    required this.confidence,
    required this.source,
  });

  /// Category chosen by the model or the user.
  final MeasurementCategory category;

  /// Confidence in the category.
  final ClassificationConfidence confidence;

  /// Who supplied the category.
  final ClassificationSource source;
}

/// Ask the user to choose a category.
final class UserClassificationRequired extends ClassificationDecision {
  const UserClassificationRequired({required this.trigger, required this.form});

  /// Reason the user has to decide.
  final ClassificationTrigger trigger;

  /// Single-choice form with the four categories.
  final InputForm form;
}

/// Classifies [request] or asks the user when the classification is unusable.
///
/// Triggers for the user form:
/// - the model reported a low confidence,
/// - the model category contradicts the resolvable recipes,
/// - the catalog has no recipe for the requested measurements
///   (`input_incomplete` or `unsupported_method`),
/// - the submitted category is not one of the four options.
///
/// A model classification of `other` with medium or high confidence is
/// returned directly so the orchestrator handles the request itself.
StageResult<ClassificationDecision> classifyRequest({
  required MeasurementRequest request,
  required PlannerCatalog catalog,
  required int round,
  required PlannerConfig config,
  required PlannerIdSource idSource,
}) {
  final answers = request.answers ?? const <String, Object?>{};
  final answer = answers[PlannerKeys.measurementCategory];
  if (answer != null) {
    if (answer == unknownAnswerValue) {
      return StageResult.abort(
        AbortReason.userInputUnknown,
        message:
            'The user does not know which measurement category the request '
            'belongs to.',
        details: const <String, Object?>{
          'keys': <String>[PlannerKeys.measurementCategory],
        },
      );
    }
    final category = MeasurementCategory.tryFromWire(answer);
    if (category != null) {
      return StageResult.ok(
        RoutedClassification(
          category: category,
          confidence: ClassificationConfidence.high,
          source: ClassificationSource.user,
        ),
      );
    }
    if (round >= config.maxFormRounds) {
      return StageResult.abort(
        AbortReason.inputIncomplete,
        message:
            'The measurement category is still invalid after '
            '${config.maxFormRounds} rounds.',
        details: <String, Object?>{
          'reason': 'INVALID_CLASSIFICATION',
          'round': round,
          'maxRounds': config.maxFormRounds,
        },
      );
    }
    return StageResult.ok(
      UserClassificationRequired(
        trigger: ClassificationTrigger.invalidAnswer,
        form: _classificationForm(idSource),
      ),
    );
  }

  final classification = request.classification;
  final typeResult = classifyType(request: request, catalog: catalog);

  if (typeResult.isOk) {
    final assessment = typeResult.requireValue;
    if (classification == null) {
      // Without a model classification the catalog result is authoritative.
      return StageResult.ok(PlanClassification(assessment));
    }
    if (classification.category == MeasurementCategory.other) {
      // The model supplied recipes but classified the request as other.
      return StageResult.ok(
        UserClassificationRequired(
          trigger: ClassificationTrigger.mismatch,
          form: _classificationForm(idSource),
        ),
      );
    }
    if (classification.confidence == ClassificationConfidence.low) {
      return StageResult.ok(
        UserClassificationRequired(
          trigger: ClassificationTrigger.lowConfidence,
          form: _classificationForm(idSource),
        ),
      );
    }
    if (classification.category.planType != assessment.planType) {
      return StageResult.ok(
        UserClassificationRequired(
          trigger: ClassificationTrigger.mismatch,
          form: _classificationForm(idSource),
        ),
      );
    }
    return StageResult.ok(PlanClassification(assessment));
  }

  final reason = typeResult.reason;
  if (reason == null) {
    throw StateError('An unsuccessful classification has no abort reason.');
  }
  if (reason != AbortReason.inputIncomplete &&
      reason != AbortReason.unsupportedMethod) {
    // A mixed request stays too_complex; a category choice cannot fix it.
    return StageResult.abort(
      reason,
      message: typeResult.message,
      details: typeResult.details,
    );
  }

  if (classification != null &&
      classification.category == MeasurementCategory.other &&
      classification.isConfident) {
    return StageResult.ok(
      RoutedClassification(
        category: MeasurementCategory.other,
        confidence: classification.confidence,
        source: ClassificationSource.model,
      ),
    );
  }

  return StageResult.ok(
    UserClassificationRequired(
      trigger: classification?.confidence == ClassificationConfidence.low
          ? ClassificationTrigger.lowConfidence
          : ClassificationTrigger.noResult,
      form: _classificationForm(idSource),
    ),
  );
}

InputForm _classificationForm(PlannerIdSource idSource) {
  return InputForm(
    formId: idSource('planner-classification'),
    title: 'Measurement type',
    questions: <InputQuestion>[
      InputQuestion(
        key: PlannerKeys.measurementCategory,
        label: 'Which type of measurement is this?',
        help:
            'The automatic classification was not confident enough. Choose '
            'the category that matches your request.',
        type: InputQuestionType.singleChoice,
        options: measurementCategoryOptions,
      ),
    ],
  );
}
