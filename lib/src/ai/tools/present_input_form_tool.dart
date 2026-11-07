/// WaveformAgent tool that shows a planner input form in the chat.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../measurement_form.dart';
import '../planner/models/input_form.dart';
import '../planner/planner_session.dart';
import '../planner/presentation/input_form_guard.dart';

/// Registers `present_input_form` for the Waveform Agent.
///
/// The model supplies only the translated title, labels and help texts. The
/// guard rejects any difference in machine fields and the canonical form is
/// rendered. Answers are stored host-side and never returned to the model.
Tool<Map<String, dynamic>> createPresentInputFormTool({
  MeasurementFormProvider? requestForm,
  PlannerSessionStore? sessions,
  String agentName = 'unknown',
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
}) {
  return Tool<Map<String, dynamic>>(
    name: 'present_input_form',
    description:
        'Shows the planner input form in the chat and waits for the user. Call '
        'it only after planner_agent returned status needs_input. Pass the '
        'stateRef from that result and translate the title, every question '
        'label and every help text into the user\'s language. Keep the '
        'question order, keys, types, option values, ranges and units exactly '
        'as returned; the application rejects any other difference. Never add '
        'or remove questions. On submission the application stores the answers '
        'and returns submitted true; then call planner_agent again without a '
        'request. If the user cancels, the result has cancelled true.',
    inputSchema: Schema.fromMap(<String, dynamic>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, dynamic>{
        'stateRef': <String, dynamic>{
          'type': 'string',
          'description':
              'The stateRef from the needs_input result. Optional when only '
              'one form is pending.',
        },
        'title': <String, dynamic>{
          'type': 'string',
          'description': 'Translated form title.',
        },
        'questions': <String, dynamic>{
          'type': 'array',
          'minItems': 1,
          'items': <String, dynamic>{
            'type': 'object',
            'additionalProperties': false,
            'properties': <String, dynamic>{
              'key': <String, dynamic>{
                'type': 'string',
                'description': 'Machine key; must not change.',
              },
              'label': <String, dynamic>{
                'type': 'string',
                'description': 'Translated question label.',
              },
              'help': <String, dynamic>{
                'type': 'string',
                'description': 'Translated help text.',
              },
            },
            'required': <String>['key', 'label'],
          },
        },
      },
      'required': <String>['questions'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'present_input_form',
      );
      if (requestForm == null) {
        const result = <String, dynamic>{
          'error':
              'Input forms are not available in this context. Ask the '
              'question as plain chat text instead.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final stateRef = _stringArg(args, 'stateRef');
      final session = _resolveSession(sessions, stateRef);
      if (session == null) {
        const result = <String, dynamic>{
          'error_code': 'UNKNOWN_FORM_STATE',
          'error': 'No planner input form is pending.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      // A form that was already submitted must not be shown again. The model
      // sometimes repeats the tool call before calling planner_agent; showing
      // the same questions twice is exactly what the user should not see.
      final submittedAnswers = session.submittedAnswers;
      if (submittedAnswers != null) {
        final result = <String, dynamic>{
          'submitted': true,
          'alreadySubmitted': true,
          'stateRef': session.stateRef,
          'answerCount': submittedAnswers.length,
        };
        logger.log(
          'Input form already submitted for ${session.stateRef}; not shown '
          'again',
        );
        await logger.logToolCall(
          input: <String, dynamic>{'stateRef': session.stateRef},
          output: result,
        );
        return result;
      }

      final guard = guardTranslatedForm(
        canonical: session.form,
        translated: args,
      );
      if (!guard.isOk) {
        final result = <String, dynamic>{
          'error_code': 'INVALID_FORM_TRANSLATION',
          'field': guard.field,
          'error':
              '${guard.error} Translate only the title, labels and help '
              'texts; keep every machine field exactly as returned.',
        };
        await logger.logToolCall(
          input: <String, dynamic>{'stateRef': session.stateRef},
          output: <String, dynamic>{
            'error_code': result['error_code'],
            'field': result['field'],
          },
        );
        return result;
      }

      onLongRunningStart?.call();
      try {
        final result = await requestForm(guard.form!);
        if (result.cancelled) {
          session.submittedAnswers = <String, Object?>{
            cancelledAnswerKey: true,
          };
          logger.log('Input form cancelled for ${session.stateRef}');
          const cancelled = <String, dynamic>{
            'submitted': false,
            'cancelled': true,
            'answerCount': 0,
          };
          await logger.logToolCall(
            input: <String, dynamic>{'stateRef': session.stateRef},
            output: cancelled,
          );
          return <String, dynamic>{...cancelled, 'stateRef': session.stateRef};
        }
        session.submittedAnswers = result.answers;
        logger.log(
          'Input form submitted for ${session.stateRef} '
          '(${result.answers.length} answers)',
        );
        final output = <String, dynamic>{
          'submitted': true,
          'cancelled': false,
          'stateRef': session.stateRef,
          'answerCount': result.answers.length,
        };
        await logger.logToolCall(
          input: <String, dynamic>{'stateRef': session.stateRef},
          output: output,
        );
        return output;
      } finally {
        onLongRunningEnd?.call();
      }
    },
  );
}

PlannerSession? _resolveSession(
  PlannerSessionStore? sessions,
  String? stateRef,
) {
  if (sessions == null) return null;
  if (stateRef != null && stateRef.isNotEmpty) {
    final explicit = sessions.load(stateRef);
    if (explicit != null) return explicit;
  }
  // Prefer a submitted form so a repeated call reports the submission instead
  // of opening the same questions again.
  return sessions.submitted ?? sessions.single ?? sessions.latest;
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
