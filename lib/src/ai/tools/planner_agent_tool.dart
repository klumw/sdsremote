/// WaveformAgent tool exposing the PlannerAgent sub-agent.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../planner/models/action_plan.dart';
import '../planner/pipeline/equipment_probe.dart';
import '../planner/plan_executor.dart';
import '../planner/planner_agent.dart';
import '../planner/planner_session.dart';

/// Per-request budget of planner invocations.
class PlannerInvocationBudget {
  PlannerInvocationBudget(this.maxInvocations);

  /// Maximum number of planner tool calls in one user request.
  final int maxInvocations;

  int _used = 0;

  /// Calls already consumed.
  int get used => _used;

  /// Calls still available.
  int get remaining => maxInvocations - _used;

  /// Resets the counter at the start of a user request.
  void reset() => _used = 0;

  /// Consumes one call; returns `false` when the budget is exhausted.
  bool tryConsume() {
    if (_used >= maxInvocations) return false;
    _used++;
    return true;
  }
}

/// Registers `planner_agent` for the Waveform Agent.
Tool<Map<String, dynamic>> createPlannerAgentTool({
  PlannerAgent? planner,
  PlannerSessionStore? sessions,
  PlanSessionStore? planSessions,
  PlannerInvocationBudget? budget,
  EquipmentProbe? probe,
  String agentName = 'unknown',
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
}) {
  return Tool<Map<String, dynamic>>(
    name: 'planner_agent',
    description:
        'Plans a complex measurement with the deterministic PlannerAgent. '
        'Use it for requests that combine several quantities, need a '
        'generator-driven sequence such as a frequency-response or Bode '
        'sweep, mix audio or digital measurement blocks, or depend on safety '
        'and setup data. For a single direct readout the '
        'specialist agents are faster. The result is JSON with status '
        'plan_ready, needs_input, classified or aborted. Relay it verbatim: '
        'never add, remove or reorder steps and never change a value. On '
        'needs_input call present_input_form with the returned stateRef and '
        'the translated title, labels and help texts, then call planner_agent '
        'again without a request; the application carries the answers. On '
        'aborted explain the reason and what the user could change; do not '
        'retry blindly. On classified present no plan: route the original '
        'request to the agent named in `route` (scope_analysis_agent, '
        'audio_analysis_agent or digital_analysis_agent). Without a route the '
        'category is other and you handle the request yourself. On plan_ready '
        'present the plan in the user\'s language, ask for approval, then call '
        'execute_plan with the returned planRef.',
    inputSchema: Schema.fromMap(<String, dynamic>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, dynamic>{
        'request': <String, dynamic>{
          'type': 'string',
          'description':
              'The complete measurement request in the user\'s own words. '
              'After a form submission, omit it or pass a short continuation '
              'phrase.',
        },
        'stateRef': <String, dynamic>{
          'type': 'string',
          'description':
              'Optional stateRef of a pending planner form. Omit it when only '
              'one form is pending.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(agentName: agentName, toolName: 'planner_agent');
      if (planner == null || probe == null) {
        const result = <String, dynamic>{
          'error': 'The planner is not available in this context.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }
      if (budget != null && !budget.tryConsume()) {
        const result = <String, dynamic>{
          'error_code': 'PLANNER_BUDGET_EXHAUSTED',
          'error':
              'The planner call budget for this request is exhausted. Answer '
              'from the results already collected.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final stateRefArg = _stringArg(args, 'stateRef');
      final request = _stringArg(args, 'request');
      final session = _pendingSession(sessions, stateRefArg);
      if (session != null && session.submittedAnswers == null) {
        final result = <String, dynamic>{
          'error_code': 'FORM_PENDING',
          'error':
              'The input form is still open. Call present_input_form or ask '
              'the user to submit or cancel it.',
          'stateRef': session.stateRef,
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      onLongRunningStart?.call();
      try {
        Map<String, dynamic> result;
        if (session != null) {
          // Resume replaces or removes the session. Do not clear the answers
          // first: if the resume fails, the next call must still be able to
          // use them instead of asking the same questions again.
          final answers = session.submittedAnswers ?? const <String, Object?>{};
          result = await planner.resume(
            session.stateRef,
            answers,
            probe: probe,
          );
        } else {
          if (request == null || request.isEmpty) {
            const missing = <String, dynamic>{
              'error': 'request is required when no planner form is pending.',
            };
            await logger.logToolCall(input: args, output: missing);
            return missing;
          }
          result = await planner.plan(request, probe: probe);
        }

        if (result['status'] == 'plan_ready') {
          final planMap = result['plan'];
          if (planMap is Map) {
            final plan = ActionPlan.fromMap(Map<String, dynamic>.from(planMap));
            planSessions?.save(
              PlanSession(
                plan: plan,
                requestText: session?.requestText ?? request,
              ),
            );
            result = <String, dynamic>{...result, 'planRef': plan.planId};
          }
        }

        final questionKeys = <Object?>[];
        final form = result['form'];
        if (form is Map && form['questions'] is List) {
          for (final question in form['questions']! as List) {
            if (question is Map) questionKeys.add(question['key']);
          }
        }
        logger.log(
          'Planner call resumed=${session != null} '
          'status=${result['status']} '
          'reason=${result['reason'] ?? '-'}'
          '${questionKeys.isEmpty ? '' : ' questions=${questionKeys.join(',')}'}',
        );
        await logger.logToolCall(
          input: <String, dynamic>{
            'resumed': session != null,
            'requestCharacters': request?.length ?? 0,
          },
          output: <String, dynamic>{
            'status': result['status'],
            if (result['reason'] != null) 'reason': result['reason'],
            if (result['route'] != null) 'route': result['route'],
            if (result['planRef'] != null) 'planRef': result['planRef'],
            if (result['stateRef'] != null) 'stateRef': result['stateRef'],
          },
        );
        return result;
      } finally {
        onLongRunningEnd?.call();
      }
    },
  );
}

PlannerSession? _pendingSession(
  PlannerSessionStore? sessions,
  String? stateRef,
) {
  if (sessions == null) return null;
  if (stateRef != null && stateRef.isNotEmpty) {
    final explicit = sessions.load(stateRef);
    if (explicit != null) return explicit;
  }
  // Prefer a submitted form: resuming it prevents asking the same questions
  // again when the model forgets or omits the stateRef.
  return sessions.submitted ?? sessions.single;
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
