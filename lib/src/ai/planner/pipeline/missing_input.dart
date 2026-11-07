/// Missing-user-input model shared by stages 6 and 7.
library;

import '../catalog/param_spec.dart';
import '../models/action_plan.dart';
import 'plan_draft.dart';

/// Why a parameter is missing.
enum MissingInputReason { absent, invalid }

/// A resolved parameter value with its provenance.
class ResolvedInput {
  const ResolvedInput({
    required this.key,
    required this.value,
    required this.source,
  });

  /// Parameter key.
  final String key;

  /// Resolved JSON-safe value.
  final Object? value;

  /// Where the value came from.
  final InputSource source;
}

/// A parameter that still needs a user answer.
class MissingInput {
  const MissingInput({
    required this.key,
    required this.spec,
    required this.reason,
    this.validationMessage,
    this.originalValue,
  });

  /// Parameter key.
  final String key;

  /// Specification of the parameter.
  final ParamSpec spec;

  /// Why the value is missing.
  final MissingInputReason reason;

  /// English validation message for an invalid answer.
  final String? validationMessage;

  /// The rejected answer, when the reason is [MissingInputReason.invalid].
  final Object? originalValue;
}

/// A read step inserted before a consuming step.
class PlanReadStep {
  const PlanReadStep({
    required this.step,
    required this.beforeStepId,
    required this.parameterKey,
  });

  /// Read step to insert.
  final PlanStepDraft step;

  /// Step that consumes the read value.
  final String beforeStepId;

  /// Parameter supplied by the read step.
  final String parameterKey;
}

/// Result of stage 6.
class MissingInputPlan {
  const MissingInputPlan({
    required this.resolved,
    required this.missing,
    required this.readSteps,
    required this.references,
    required this.safetyNotes,
    required this.cancelled,
    required this.hasUnknownSentinel,
    this.unknownKeys = const <String>[],
  });

  /// Resolved values in parameter order.
  final Map<String, ResolvedInput> resolved;

  /// Parameters that still need an answer, in parameter order.
  final List<MissingInput> missing;

  /// Read steps to insert before their consuming steps.
  final List<PlanReadStep> readSteps;

  /// Readable parameters resolved through a read step.
  final Map<String, StepReferenceParameter> references;

  /// English safety notes from the danger assessment.
  final List<String> safetyNotes;

  /// Whether the user cancelled the form.
  final bool cancelled;

  /// Whether any answer used the unknown sentinel.
  final bool hasUnknownSentinel;

  /// Keys answered with the unknown sentinel.
  final List<String> unknownKeys;
}
