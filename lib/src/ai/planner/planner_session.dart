/// Host-owned planner sessions.
///
/// Tool results are not retained across chat turns: `WaveformAgent` keeps only
/// the last 20 user and model texts. A `needs_input` result therefore saves
/// its request, answers and round host-side under the opaque `stateRef`, so a
/// submitted form can resume the deterministic pipeline without the model
/// replaying any JSON.
library;

import 'models/input_form.dart';
import 'models/measurement_request.dart';

/// Pending planning session behind one opaque reference.
class PlannerSession {
  PlannerSession({
    required this.stateRef,
    required this.request,
    required this.answers,
    required this.form,
    required this.round,
    this.requestText,
  });

  /// Opaque reference returned in `needs_input`.
  final String stateRef;

  /// Request of the current planning run.
  final MeasurementRequest request;

  /// Cumulative answers of all completed rounds.
  final Map<String, Object?> answers;

  /// Form that is currently open.
  final InputForm form;

  /// Round to use for the next invocation.
  final int round;

  /// Original user request text that started this planning run.
  ///
  /// Kept so a plan created after a form submission can still be corrected
  /// before execution without reconstructing the request from chat history.
  final String? requestText;

  /// Answers submitted through the chat form, or `null` while the form is open.
  ///
  /// `present_input_form` writes this host-side; `planner_agent` consumes it on
  /// the next call. The answers never travel back through the model.
  Map<String, Object?>? submittedAnswers;
}

/// In-memory store of pending planner sessions.
class PlannerSessionStore {
  PlannerSessionStore({this.maxEntries = 8});

  /// Maximum number of stored sessions; the oldest is evicted first.
  final int maxEntries;

  final Map<String, PlannerSession> _sessions = <String, PlannerSession>{};
  final List<String> _order = <String>[];

  /// Number of stored sessions.
  int get length => _sessions.length;

  /// Stored references, oldest first.
  List<String> get stateRefs => List<String>.unmodifiable(_order);

  /// Saves or replaces [session].
  void save(PlannerSession session) {
    _sessions[session.stateRef] = session;
    _order
      ..remove(session.stateRef)
      ..add(session.stateRef);
    while (_order.length > maxEntries) {
      final oldest = _order.removeAt(0);
      _sessions.remove(oldest);
    }
  }

  /// Returns the session for [stateRef], or `null`.
  PlannerSession? load(String stateRef) => _sessions[stateRef];

  /// Returns the only session, or `null` when none or several exist.
  PlannerSession? get single {
    if (_sessions.length != 1) return null;
    return _sessions[_order.single];
  }

  /// Returns the most recently saved session, or `null`.
  PlannerSession? get latest {
    if (_order.isEmpty) return null;
    return _sessions[_order.last];
  }

  /// Returns the most recent session whose form was submitted, or `null`.
  ///
  /// A submitted form must be resumed even when the model omits the stateRef
  /// or several sessions are pending; otherwise the same questions are asked
  /// again.
  PlannerSession? get submitted {
    for (final stateRef in _order.reversed) {
      final session = _sessions[stateRef];
      if (session?.submittedAnswers != null) return session;
    }
    return null;
  }

  /// Removes the session for [stateRef].
  void remove(String stateRef) {
    _sessions.remove(stateRef);
    _order.remove(stateRef);
  }

  /// Removes every session.
  void clear() {
    _sessions.clear();
    _order.clear();
  }
}
