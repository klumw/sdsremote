/// AI tool that shows a multi-select checkbox prompt in the chat.
///
/// The tool blocks until the user confirms a selection or cancels. The chat
/// panel observes the pending request through its checklist prompt controller
/// and renders the shared `ChatChecklistPrompt` widget. Use this tool for data
/// collection when several independent options can apply; use
/// `request_user_choice` when exactly one option is required.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../chat_checklist.dart';

/// Waits for the user to confirm a checkbox selection.
typedef ChecklistProvider =
    Future<ChatChecklistResult> Function(ChatChecklistRequest request);

/// Registers `request_user_checklist` for the Waveform Agent.
Tool<Map<String, dynamic>> createChecklistTool({
  ChecklistProvider? requestChecklist,
  String agentName = 'unknown',
}) {
  final provider = requestChecklist;
  return Tool<Map<String, dynamic>>(
    name: 'request_user_checklist',
    description:
        'Shows a checkbox list with a Confirm button in the chat and waits '
        'for the user to select one or more options. Use it for data '
        'collection when several independent options apply, for example '
        'which measurements, parameters, channels or report sections to '
        'collect. Use request_user_choice when exactly one option is '
        'required. The result contains `selected` (the selected values in '
        'option order) and `labels`; `cancelled` means the user dismissed '
        'the prompt. Never invent a selection; use only the returned values. '
        'At least one option must be checked to confirm; the user can cancel '
        'to skip the selection.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{
        'question': {
          'type': 'string',
          'description': 'Question shown above the checkbox list.',
        },
        'allow_cancel': {
          'type': 'boolean',
          'description':
              'Whether the user may dismiss the prompt without confirming. '
              'Defaults to true.',
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
                'description': 'Text shown next to the checkbox.',
              },
              'description': {
                'type': 'string',
                'description': 'Optional explanation below the label.',
              },
              'selected': {
                'type': 'boolean',
                'description':
                    'Whether the option is checked initially. Defaults to '
                    'false.',
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
        toolName: 'request_user_checklist',
      );

      if (provider == null) {
        const result = <String, dynamic>{
          'error':
              'Checkbox prompts are not available in this context. Ask the '
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

      final options = <ChatChecklistOption>[];
      for (final entry in rawOptions) {
        if (entry is! Map) continue;
        final value = entry['value'];
        final label = entry['label'];
        if (value is! String || value.trim().isEmpty) continue;
        if (label is! String || label.trim().isEmpty) continue;
        final description = entry['description'];
        options.add(
          ChatChecklistOption(
            value: value,
            label: label,
            description: description is String && description.trim().isNotEmpty
                ? description
                : null,
            selected: entry['selected'] == true,
          ),
        );
      }
      if (options.length < 2) {
        const result = <String, dynamic>{
          'error':
              'options must contain at least two valid entries with value '
              'and label',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final request = ChatChecklistRequest(
        question: question.trim(),
        options: options,
        allowCancel: args['allow_cancel'] != false,
      );

      logger.log('User checklist requested: ${request.question}');
      final result = await provider(request);
      if (result.cancelled) {
        const output = <String, dynamic>{
          'cancelled': true,
          'error': 'The user cancelled the checkbox prompt.',
        };
        await logger.logToolCall(
          input: {'options': options.length},
          output: {'cancelled': true},
        );
        return output;
      }

      final output = <String, dynamic>{
        'selected': result.values,
        'labels': result.labels,
      };
      await logger.logToolCall(
        input: {'options': options.length},
        output: {'selected': result.values},
      );
      return output;
    },
  );
}
