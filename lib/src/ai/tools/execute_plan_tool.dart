/// WaveformAgent tool that advances an approved action plan.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../planner/plan_executor.dart';

/// Registers `execute_plan` for the Waveform Agent.
Tool<Map<String, dynamic>> createExecutePlanTool({
  PlanExecutor? executor,
  String agentName = 'unknown',
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
}) {
  return Tool<Map<String, dynamic>>(
    name: 'execute_plan',
    description:
        'Advances an approved measurement plan. Call it after the user '
        'approved the plan from planner_agent; pass the planRef. The result '
        'has status awaiting_approval, awaiting_confirmation, completed, '
        'failed, cancelled or unknown_plan. Relay awaiting_* questions to the '
        'user and call again with approve true only after an explicit yes. '
        'Manual setup steps are informational and already covered by the plan '
        'approval; the executor completes them without a separate prompt. On '
        'completed present the step results faithfully. On failed present the '
        'error and the remaining steps. Never claim a step result the tool did '
        'not return.',
    inputSchema: Schema.fromMap(<String, dynamic>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, dynamic>{
        'planRef': <String, dynamic>{
          'type': 'string',
          'description':
              'The planRef returned by planner_agent. Optional when only one '
              'plan is pending.',
        },
        'approve': <String, dynamic>{
          'type': 'boolean',
          'description':
              'True after the user approved the plan or the pending step.',
        },
        'additionalInstructions': <String, dynamic>{
          'type': 'string',
          'description':
              'Optional extra information for the next step, for example a '
              'corrected channel.',
        },
        'cancel': <String, dynamic>{
          'type': 'boolean',
          'description':
              'True to cancel the plan and switch the generator off.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(agentName: agentName, toolName: 'execute_plan');
      if (executor == null) {
        const result = <String, dynamic>{
          'error': 'Plan execution is not available in this context.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }
      onLongRunningStart?.call();
      try {
        final outcome = await executor.run(
          planRef: _stringArg(args, 'planRef'),
          approve: args['approve'] == true,
          additionalInstructions: _stringArg(args, 'additionalInstructions'),
          cancel: args['cancel'] == true,
        );
        await logger.logToolCall(
          input: <String, dynamic>{
            'planRef': outcome.planRef,
            'approve': args['approve'] == true,
            'cancel': args['cancel'] == true,
          },
          output: <String, dynamic>{
            'status': outcome.status.wireName,
            if (outcome.stepId != null) 'stepId': outcome.stepId,
            if (outcome.error != null) 'error': outcome.error,
          },
        );
        return outcome.toJson();
      } finally {
        onLongRunningEnd?.call();
      }
    },
  );
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
