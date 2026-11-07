/// AI tool that shows a reusable radio-button question in the chat.
///
/// The tool blocks until the user selects an option or cancels. The owning
/// chat panel observes the pending request through its
/// `ChatChoicePromptController` and renders the shared `ChatChoicePrompt`
/// widget. An option can be marked as a session-wide answer, which the
/// controller returns immediately on later requests with the same id.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../chat_choice.dart';

/// Waits for the user to select one option of [request].
typedef ChatChoiceProvider =
    Future<ChatChoiceResult> Function(ChatChoiceRequest request);

/// Handles free text the user entered in a choice prompt.
///
/// [args] are the tool arguments, so a host can read context such as a plan
/// reference. The returned map becomes the tool result.
typedef ChatChoiceCorrectionHandler =
    Future<Map<String, dynamic>> Function(
      String correction,
      Map<String, dynamic> args,
    );

/// Registers `request_user_choice` for a chat agent.
Tool<Map<String, dynamic>> createChatChoiceTool({
  ChatChoiceProvider? requestChoice,
  ChatChoiceCorrectionHandler? onCorrection,
  String agentName = 'unknown',
  void Function()? onLongRunningStart,
  void Function()? onLongRunningEnd,
}) {
  final provider = requestChoice;
  return Tool<Map<String, dynamic>>(
    name: 'request_user_choice',
    description:
        'Shows a question with radio-button options in the chat and waits '
        'for the user to select one. Use it for EVERY question whose answer '
        'is a small set of options — yes/no, a channel, an option, a '
        'confirmation, a choice between approaches — instead of asking that '
        'question as plain chat text. This also applies to choices relayed '
        'from sub-agent results. Set `allow_text: true` to add a free-text '
        'field for corrections or answers outside the options; translate '
        '`text_label`, `text_hint` and `text_submit_label` for the user. For '
        'a plan approval also pass `plan_ref`; a correction entered there is '
        'applied by the application before the plan starts. Pass a stable '
        '`id` when one option grants the answer for the rest of the session; '
        'mark that option with `remember_for_session: true` so later calls '
        'with the same id return it immediately without showing the prompt. '
        'Returns `selected` with the chosen value and label, `correction` '
        'with the free text, or `cancelled` when the user dismisses the '
        'prompt. Never invent an answer; use only the returned value.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{
        'id': {
          'type': 'string',
          'description':
              'Stable identifier for this kind of question, for example '
              '"waveform_permission". Required to remember a session-wide '
              'answer.',
        },
        'question': {
          'type': 'string',
          'description': 'Question shown above the radio buttons.',
        },
        'allow_cancel': {
          'type': 'boolean',
          'description':
              'Whether the user may dismiss the prompt without answering. '
              'Defaults to true.',
        },
        'allow_text': {
          'type': 'boolean',
          'description':
              'Whether to show a free-text field in addition to the options. '
              'Use it for corrections so the user can change a value before '
              'confirming. Text takes precedence over a selected option.',
        },
        'text_label': {
          'type': 'string',
          'description':
              'Label of the free-text field, translated into the user\'s '
              'language.',
        },
        'text_hint': {
          'type': 'string',
          'description':
              'Placeholder of the free-text field, translated into the '
              'user\'s language.',
        },
        'text_submit_label': {
          'type': 'string',
          'description':
              'Label of the button that submits the free text, translated '
              'into the user\'s language.',
        },
        'plan_ref': {
          'type': 'string',
          'description':
              'Plan reference when this question approves or confirms a '
              'stored plan. Enables the application to apply a correction '
              'from the free-text field to that plan.',
        },
        'options': {
          'type': 'array',
          'minItems': 2,
          'items': {
            'type': 'object',
            'properties': <String, dynamic>{
              'value': {
                'type': 'string',
                'description': 'Machine-readable value returned to you.',
              },
              'label': {
                'type': 'string',
                'description': 'Text shown next to the radio button.',
              },
              'description': {
                'type': 'string',
                'description': 'Optional explanation below the label.',
              },
              'remember_for_session': {
                'type': 'boolean',
                'description':
                    'When true and this option is selected, remember it for '
                    'the rest of the session. Later calls with the same id '
                    'return it immediately without showing the prompt.',
              },
            },
            'required': <String>['value', 'label'],
          },
        },
      },
      'required': <String>['question', 'options'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'request_user_choice',
      );

      if (provider == null) {
        const result = <String, dynamic>{
          'error':
              'Choice prompts are not available in this context. Ask the '
              'question as plain chat text instead.',
        };
        await logger.logToolCall(
          input: const <String, dynamic>{},
          output: {'error': result['error']},
        );
        return result;
      }

      final question = args['question'];
      final rawOptions = args['options'];
      if (question is! String || question.trim().isEmpty) {
        const result = <String, dynamic>{'error': 'question is required'};
        await logger.logToolCall(input: args, output: result);
        return result;
      }
      if (rawOptions is! List) {
        const result = <String, dynamic>{
          'error': 'options must contain at least two entries',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final options = <ChatChoiceOption>[];
      for (final entry in rawOptions) {
        if (entry is! Map) continue;
        final value = entry['value'];
        final label = entry['label'];
        if (value is! String || value.trim().isEmpty) continue;
        if (label is! String || label.trim().isEmpty) continue;
        final description = entry['description'];
        options.add(
          ChatChoiceOption(
            value: value,
            label: label,
            description: description is String && description.trim().isNotEmpty
                ? description
                : null,
            rememberForSession: entry['remember_for_session'] == true,
          ),
        );
      }
      if (options.length < 2) {
        const result = <String, dynamic>{
          'error':
              'options must contain at least two valid entries with '
              'value and label',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final id = args['id'];
      final request = ChatChoiceRequest(
        id: id is String && id.trim().isNotEmpty ? id.trim() : null,
        question: question.trim(),
        options: options,
        allowCancel: args['allow_cancel'] != false,
        allowText: args['allow_text'] == true,
        textLabel: _optionalText(args['text_label']),
        textHint: _optionalText(args['text_hint']),
        textSubmitLabel: _optionalText(args['text_submit_label']),
      );

      logger.log('User choice requested: ${request.id ?? request.question}');
      final result = await provider(request);
      if (result.cancelled) {
        const output = <String, dynamic>{
          'cancelled': true,
          'error': 'The user cancelled the choice prompt.',
        };
        await logger.logToolCall(
          input: {'id': request.id, 'options': options.length},
          output: {'cancelled': true},
        );
        return output;
      }

      final correction = result.text?.trim();
      if (correction != null && correction.isNotEmpty) {
        onLongRunningStart?.call();
        final Map<String, dynamic> handled;
        try {
          handled = onCorrection == null
              ? <String, dynamic>{'correction': correction}
              : await onCorrection(correction, args);
        } finally {
          onLongRunningEnd?.call();
        }
        await logger.logToolCall(
          input: {'id': request.id, 'planRef': args['plan_ref']},
          output: {
            'correction': true,
            if (handled['status'] != null) 'status': handled['status'],
            if (handled['error'] != null) 'error': handled['error'],
          },
        );
        return handled;
      }

      final selectedOption = result.value == null
          ? null
          : request.optionFor(result.value!);
      final output = <String, dynamic>{
        'selected': result.value,
        'label': result.label,
        if (selectedOption?.rememberForSession == true) 'session_answer': true,
      };
      await logger.logToolCall(
        input: {'id': request.id, 'options': options.length},
        output: {'selected': result.value},
      );
      return output;
    },
  );
}

String? _optionalText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
