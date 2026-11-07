/// Deterministic execution of an approved action plan.
///
/// The executor is host-owned. It resolves `{fromStep, field}` references,
/// enforces step order and dependencies, pauses for approval, confirmation and
/// manual steps, and always runs the teardown step when the planner enabled the
/// generator.
library;

import 'dart:async';

import '../cancellation.dart';
import 'models/action_plan.dart';
import 'presentation/plan_presentation.dart';

/// Runs one plan step through a sub-agent.
typedef PlanStepDispatcher =
    Future<Map<String, dynamic>> Function(
      ActionStep step,
      String instruction,
      Map<String, Object?> resolvedParameters,
      CancellationToken? cancelToken,
    );

/// State of one plan execution.
enum PlanExecutionStatus {
  awaitingApproval('awaiting_approval'),
  awaitingConfirmation('awaiting_confirmation'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled'),
  unknownPlan('unknown_plan');

  const PlanExecutionStatus(this.wireName);

  /// Wire value used by the tool result.
  final String wireName;
}

/// Result of one `execute_plan` call.
class PlanExecutionOutcome {
  const PlanExecutionOutcome({
    required this.status,
    this.planRef,
    this.stepId,
    this.instruction,
    this.question,
    this.safetyNotes = const <String>[],
    this.completedStepIds = const <String>[],
    this.remainingStepIds = const <String>[],
    this.results = const <String, Map<String, dynamic>>{},
    this.error,
    this.errorCode,
  });

  /// Execution state.
  final PlanExecutionStatus status;

  /// Reference of the plan.
  final String? planRef;

  /// Step that needs attention, when applicable.
  final String? stepId;

  /// English instruction of that step.
  final String? instruction;

  /// English question to relay to the user.
  final String? question;

  /// English safety notes of the plan.
  final List<String> safetyNotes;

  /// Steps completed so far.
  final List<String> completedStepIds;

  /// Steps not completed yet.
  final List<String> remainingStepIds;

  /// Results of completed steps.
  final Map<String, Map<String, dynamic>> results;

  /// English error, when the plan failed.
  final String? error;

  /// Machine-readable error code.
  final String? errorCode;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.wireName,
    if (planRef != null) 'planRef': planRef,
    if (stepId != null) 'stepId': stepId,
    if (instruction != null) 'instruction': instruction,
    if (question != null) 'question': question,
    if (safetyNotes.isNotEmpty) 'safetyNotes': safetyNotes,
    'completedStepIds': completedStepIds,
    'remainingStepIds': remainingStepIds,
    'results': results,
    if (error != null) 'error': error,
    if (errorCode != null) 'errorCode': errorCode,
  };
}

/// Host-owned execution state of one stored plan.
class PlanSession {
  PlanSession({required this.plan, this.requestText});

  /// The approved or pending plan.
  final ActionPlan plan;

  /// Original request text the plan was created from.
  ///
  /// A correction entered in the approval dialog re-plans this text with the
  /// correction appended.
  final String? requestText;

  /// Whether the user approved the plan.
  bool approved = false;

  /// Steps that already completed.
  final Set<String> completedStepIds = <String>{};

  /// Results of completed steps, keyed by step id.
  final Map<String, Map<String, dynamic>> stepResults =
      <String, Map<String, dynamic>>{};

  /// Step waiting for a per-step confirmation.
  String? pendingConfirmationStepId;

  /// Whether the planner enabled the generator.
  bool generatorEnabled = false;
}

/// In-memory store of plans awaiting execution.
class PlanSessionStore {
  PlanSessionStore({this.maxEntries = 2});

  /// Maximum number of stored plans; the oldest is evicted first.
  final int maxEntries;

  final Map<String, PlanSession> _sessions = <String, PlanSession>{};
  final List<String> _order = <String>[];

  /// Number of stored plans.
  int get length => _sessions.length;

  /// Stored plan references, oldest first.
  List<String> get planRefs => List<String>.unmodifiable(_order);

  /// Saves or replaces [session].
  void save(PlanSession session) {
    final ref = session.plan.planId;
    _sessions[ref] = session;
    _order
      ..remove(ref)
      ..add(ref);
    while (_order.length > maxEntries) {
      final oldest = _order.removeAt(0);
      _sessions.remove(oldest);
    }
  }

  /// Returns the session for [planRef], or `null`.
  PlanSession? load(String planRef) => _sessions[planRef];

  /// Returns the only stored session, or `null`.
  PlanSession? get single {
    if (_sessions.length != 1) return null;
    return _sessions[_order.single];
  }

  /// Removes the plan for [planRef].
  void remove(String planRef) {
    _sessions.remove(planRef);
    _order.remove(planRef);
  }

  /// Removes every stored plan.
  void clear() {
    _sessions.clear();
    _order.clear();
  }
}

/// Executes stored plans step by step.
class PlanExecutor {
  PlanExecutor({
    required this.store,
    required this.dispatch,
    this.maxEntries = 2,
  });

  /// Stored plans.
  final PlanSessionStore store;

  /// Dispatches one step to a sub-agent.
  final PlanStepDispatcher dispatch;

  /// Number of plans kept in [store].
  final int maxEntries;

  /// Advances the plan.
  ///
  /// [approve] approves the plan or a pending per-step confirmation, [cancel]
  /// cancels the plan, and [additionalInstructions] are appended to the next
  /// dispatched instruction. Manual setup steps are informational: the plan
  /// approval already covers them, so they are marked complete without a
  /// second prompt.
  Future<PlanExecutionOutcome> run({
    String? planRef,
    bool approve = false,
    String? additionalInstructions,
    bool cancel = false,
    CancellationToken? cancelToken,
  }) async {
    final session = planRef == null ? store.single : store.load(planRef);
    if (session == null) {
      return PlanExecutionOutcome(
        status: PlanExecutionStatus.unknownPlan,
        error: planRef == null
            ? 'No plan is awaiting execution.'
            : 'The plan reference "$planRef" is unknown or expired.',
        errorCode: 'UNKNOWN_PLAN',
      );
    }

    if (cancel || cancelToken?.isCancelled == true) {
      await _runTeardown(session);
      store.remove(session.plan.planId);
      return _outcome(
        session,
        PlanExecutionStatus.cancelled,
        error: 'The plan was cancelled.',
        errorCode: 'CANCELLED',
      );
    }

    if (!session.approved) {
      if (!approve) {
        return _outcome(
          session,
          PlanExecutionStatus.awaitingApproval,
          question: planApprovalQuestion(session.plan),
        );
      }
      session.approved = true;
    }

    final confirmedNow = <String>{};
    final pendingConfirmation = session.pendingConfirmationStepId;
    if (pendingConfirmation != null) {
      if (!approve) {
        final step = _stepById(session.plan, pendingConfirmation);
        return _outcome(
          session,
          PlanExecutionStatus.awaitingConfirmation,
          stepId: pendingConfirmation,
          instruction: step?.instruction,
          question: step == null ? null : stepConfirmationQuestion(step),
        );
      }
      confirmedNow.add(pendingConfirmation);
      session.pendingConfirmationStepId = null;
    }

    for (final step in session.plan.steps) {
      if (session.completedStepIds.contains(step.id)) continue;
      if (!step.dependsOn.every(session.completedStepIds.contains)) {
        return _outcome(
          session,
          PlanExecutionStatus.failed,
          error: 'Step "${step.id}" depends on a step that did not complete.',
          errorCode: 'STEP_DEPENDENCY_MISSING',
        );
      }
      if (step.kind == ActionStepKind.manual) {
        // The approved plan already contains the setup instruction. Record
        // the step as complete and continue without a second prompt.
        session.stepResults[step.id] = <String, dynamic>{
          'ok': true,
          'manual': true,
        };
        session.completedStepIds.add(step.id);
        continue;
      }
      if (step.requiresUserConfirmation && !confirmedNow.contains(step.id)) {
        session.pendingConfirmationStepId = step.id;
        return _outcome(
          session,
          PlanExecutionStatus.awaitingConfirmation,
          stepId: step.id,
          instruction: step.instruction,
          question: stepConfirmationQuestion(step),
        );
      }

      final parameters = _resolveParameters(step, session.stepResults);
      if (parameters == null) {
        return _outcome(
          session,
          PlanExecutionStatus.failed,
          error:
              'A parameter of step "${step.id}" could not be resolved from an '
              'earlier result.',
          errorCode: 'MISSING_STEP_VALUE',
        );
      }

      var instruction = step.instruction;
      final extra = additionalInstructions?.trim();
      if (extra != null && extra.isNotEmpty) {
        instruction = '$instruction\n$extra';
      }
      if (parameters.isNotEmpty) {
        final lines = parameters.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('\n');
        instruction = '$instruction\nRESOLVED PARAMETERS:\n$lines';
      }

      Map<String, dynamic> result;
      try {
        result = await dispatch(step, instruction, parameters, cancelToken);
      } on Object catch (error) {
        result = <String, dynamic>{'error': '$error'};
      }
      session.stepResults[step.id] = result;

      if (result['cancelled'] == true) {
        await _runTeardown(session);
        store.remove(session.plan.planId);
        return _outcome(
          session,
          PlanExecutionStatus.cancelled,
          error: 'The plan was cancelled while running step "${step.id}".',
          errorCode: 'CANCELLED',
        );
      }
      if (result['error'] != null) {
        await _runTeardown(session);
        return _outcome(
          session,
          PlanExecutionStatus.failed,
          stepId: step.id,
          error: '${result['error']}',
          errorCode: 'STEP_FAILED',
        );
      }

      session.completedStepIds.add(step.id);
      if (step.kind == ActionStepKind.configureGenerator) {
        session.generatorEnabled = true;
      }
      if (step.kind == ActionStepKind.teardown) {
        session.generatorEnabled = false;
      }
    }

    store.remove(session.plan.planId);
    return _outcome(session, PlanExecutionStatus.completed);
  }

  PlanExecutionOutcome _outcome(
    PlanSession session,
    PlanExecutionStatus status, {
    String? stepId,
    String? instruction,
    String? question,
    String? error,
    String? errorCode,
  }) {
    final remaining = <String>[
      for (final step in session.plan.steps)
        if (!session.completedStepIds.contains(step.id)) step.id,
    ];
    return PlanExecutionOutcome(
      status: status,
      planRef: session.plan.planId,
      stepId: stepId,
      instruction: instruction,
      question: question,
      safetyNotes: session.plan.safetyNotes,
      completedStepIds: <String>[...session.completedStepIds],
      remainingStepIds: remaining,
      results: <String, Map<String, dynamic>>{...session.stepResults},
      error: error,
      errorCode: errorCode,
    );
  }

  Future<void> _runTeardown(PlanSession session) async {
    if (!session.generatorEnabled) return;
    ActionStep? teardown;
    for (final step in session.plan.steps) {
      if (step.kind == ActionStepKind.teardown) {
        teardown = step;
        break;
      }
    }
    if (teardown == null || session.completedStepIds.contains(teardown.id)) {
      return;
    }
    try {
      final result = await dispatch(
        teardown,
        teardown.instruction,
        const <String, Object?>{},
        null,
      );
      session.stepResults[teardown.id] = result;
    } on Object {
      // A failing teardown must not hide the original failure.
    }
    session.completedStepIds.add(teardown.id);
    session.generatorEnabled = false;
  }

  Map<String, Object?>? _resolveParameters(
    ActionStep step,
    Map<String, Map<String, dynamic>> results,
  ) {
    final resolved = <String, Object?>{};
    for (final entry in step.parameters.entries) {
      final parameter = entry.value;
      if (parameter is LiteralParameter) {
        resolved[entry.key] = parameter.value;
        continue;
      }
      if (parameter is StepReferenceParameter) {
        final source = results[parameter.fromStep];
        if (source == null) return null;
        final value = _lookup(source, parameter.field);
        if (value == null) return null;
        resolved[entry.key] = value;
        continue;
      }
      return null;
    }
    return resolved;
  }

  static Object? _lookup(Object? root, String path) {
    Object? current = root;
    for (final segment in path.split('.')) {
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
      if (current == null) return null;
    }
    return current;
  }

  static ActionStep? _stepById(ActionPlan plan, String id) {
    for (final step in plan.steps) {
      if (step.id == id) return step;
    }
    return null;
  }
}
