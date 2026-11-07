/// Deterministic identifier source for forms, states and plans.
library;

/// Produces one identifier for a prefix.
///
/// Implemented as an interface rather than a function typedef so the pipeline
/// can hold one instance and reset it with the session.
abstract interface class PlannerIdSource {
  /// Returns the next identifier for [prefix].
  String call(String prefix);
}

/// Deterministic, monotonically increasing identifier source.
///
/// The sequence is owned by the pipeline invocation, so the same inputs and
/// the same starting value always produce the same ids. Tests inject a fresh
/// instance; the session store resets it when the session is cleared.
class SequentialIdSource implements PlannerIdSource {
  SequentialIdSource([int start = 0]) : _next = start;

  int _next;

  /// Value that the next call will use.
  int get nextValue => _next + 1;

  /// Returns `<prefix>-<n>` and advances the counter.
  @override
  String call(String prefix) => '$prefix-${++_next}';

  /// Resets the counter, for example at the start of a new session.
  void reset([int start = 0]) => _next = start;
}
