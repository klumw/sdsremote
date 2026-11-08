/// Result contract of the planner pipeline.
///
/// A run returns exactly one of: a complete action plan, one bundled input
/// form for missing data, a classification for the orchestrator to route, or
/// an abort with a machine-readable reason.
library;

import 'action_plan.dart';
import 'input_form.dart';
import 'json_value.dart';
import 'measurement_classification.dart';

/// Machine-readable reason of an aborted planning run.
enum AbortReason {
  tooDangerous('too_dangerous'),
  noScope('no_scope'),
  noGenerator('no_generator'),
  unsupportedMethod('unsupported_method'),
  tooComplex('too_complex'),
  notFeasible('not_feasible'),
  inputIncomplete('input_incomplete'),
  userInputUnknown('user_input_unknown'),
  userCancelled('user_cancelled');

  const AbortReason(this.wireName);

  /// Wire value of the reason.
  final String wireName;

  static AbortReason fromWire(Object? value) {
    for (final reason in values) {
      if (reason.wireName == value) return reason;
    }
    throw PlannerFormatException(
      'reason',
      'too_dangerous|no_scope|no_generator|unsupported_method|too_complex|'
          'not_feasible|input_incomplete|user_input_unknown|user_cancelled',
      value,
    );
  }
}

/// Tagged planner result.
sealed class PlannerResult {
  const PlannerResult();

  /// Wire status: `plan_ready`, `needs_input`, `classified` or `aborted`.
  String get status;

  /// JSON representation returned to the model verbatim.
  Map<String, dynamic> toJson();

  /// Builds an aborted result.
  static AbortedResult aborted(
    AbortReason reason,
    String message, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) => AbortedResult(reason: reason, message: message, details: details);

  /// Parses a serialized result.
  static PlannerResult fromMap(Map<String, dynamic> map) {
    final status = requireJsonString(map['status'], 'status');
    return switch (status) {
      'plan_ready' => PlanReadyResult(
        ActionPlan.fromMap(requireJsonMap(map['plan'], 'plan')),
      ),
      'needs_input' => NeedsInputResult(
        form: InputForm.fromMap(requireJsonMap(map['form'], 'form')),
        stateRef: requireJsonString(map['stateRef'], 'stateRef'),
      ),
      'classified' => ClassifiedResult.fromMap(
        requireJsonMap(map['classification'], 'classification'),
      ),
      'aborted' => AbortedResult(
        reason: AbortReason.fromWire(map['reason']),
        message: requireJsonString(map['message'], 'message'),
        details:
            optionalJsonValueMap(map['details'], 'details') ??
            const <String, Object?>{},
      ),
      _ => throw PlannerFormatException(
        'status',
        'plan_ready|needs_input|classified|aborted',
        status,
      ),
    };
  }
}

/// A complete, executable action plan.
final class PlanReadyResult extends PlannerResult {
  const PlanReadyResult(this.plan);

  /// The generated plan.
  final ActionPlan plan;

  @override
  String get status => 'plan_ready';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'plan': plan.toJson(),
  };
}

/// One bundled form for missing user data.
final class NeedsInputResult extends PlannerResult {
  const NeedsInputResult({required this.form, required this.stateRef});

  /// Form to present in the chat.
  final InputForm form;

  /// Opaque reference used to resume the plan after submission.
  final String stateRef;

  @override
  String get status => 'needs_input';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'form': form.toJson(),
    'stateRef': stateRef,
  };
}

/// A measurement classification that the orchestrator routes to a specialist.
///
/// The planner produces this result instead of a plan when the automatic
/// classification was uncertain and the user chose a category in the form.
final class ClassifiedResult extends PlannerResult {
  const ClassifiedResult({
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

  /// Specialist agent that handles the category, or `null` for
  /// [MeasurementCategory.other].
  String? get route => category.route;

  @override
  String get status => 'classified';

  factory ClassifiedResult.fromMap(Map<String, dynamic> map) {
    return ClassifiedResult(
      category: MeasurementCategory.fromWire(map['type']),
      confidence: ClassificationConfidence.fromWire(map['confidence']),
      source: ClassificationSource.fromWire(map['source']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'classification': <String, Object?>{
      'type': category.wireName,
      'confidence': confidence.wireName,
      'source': source.wireName,
    },
    if (route != null) 'route': route,
  };
}

/// Abort with a machine-readable reason and an English message.
final class AbortedResult extends PlannerResult {
  const AbortedResult({
    required this.reason,
    required this.message,
    this.details = const <String, Object?>{},
  });

  /// Machine-readable reason.
  final AbortReason reason;

  /// English explanation, translated by the WaveformAgent.
  final String message;

  /// Additional machine-readable context for the WaveformAgent.
  final Map<String, Object?> details;

  @override
  String get status => 'aborted';

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status,
    'reason': reason.wireName,
    'message': message,
    if (details.isNotEmpty) 'details': details,
  };
}
