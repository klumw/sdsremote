/// Result of one pipeline stage: a value or a deterministic abort.
library;

import '../models/planner_result.dart';

/// Typed stage outcome used by every pipeline stage.
class StageResult<T> {
  const StageResult.ok(T this.value)
    : reason = null,
      message = null,
      details = const <String, Object?>{};

  const StageResult.abort(
    AbortReason this.reason, {
    this.message,
    this.details = const <String, Object?>{},
  }) : value = null;

  /// Stage value when the stage succeeded.
  final T? value;

  /// Abort reason when the stage failed.
  final AbortReason? reason;

  /// English abort message; defaults to the reason wire name.
  final String? message;

  /// Machine-readable abort details.
  final Map<String, Object?> details;

  /// Whether the stage succeeded.
  bool get isOk => reason == null;

  /// Whether the stage aborted.
  bool get isAborted => reason != null;

  /// The value of a successful stage.
  T get requireValue {
    if (value == null) {
      throw StateError('The stage did not produce a value.');
    }
    return value as T;
  }

  /// Converts an aborted stage into a planner result.
  PlannerResult toPlannerResult() {
    final abortReason = reason;
    if (abortReason == null) {
      throw StateError('A successful stage has no abort result.');
    }
    return AbortedResult(
      reason: abortReason,
      message: message ?? abortReason.wireName,
      details: details,
    );
  }
}
