import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../help/help_sections.dart';
import '../tools/date_time_tool.dart';
import '../tools/help_tools.dart';
import 'systemprompts.dart';

/// User-facing agent of the help window.
///
/// The complete manual is part of its system prompt, so it answers from the
/// document itself and links to the sections it cites. The section list in the
/// prompt holds the anchor slugs that the help window scrolls to, so every
/// link the model emits resolves to a heading.
///
/// Its tools are `read_log_file` and `current_date_time`: when the user
/// reports a problem with the application, the assistant inspects the
/// application log, places the entries in time and offers a concrete next
/// step.
class HelpAgent {
  /// Maximum number of history messages kept after the system prompt.
  ///
  /// Ten messages correspond to five user/assistant turns; the manual in the
  /// system prompt already consumes most of the context budget.
  static const int defaultMaxHistoryMessages = 10;

  final Agent _agent;
  late final ChatMessage _systemMessage;
  late List<ChatMessage> _history;

  /// Creates a [HelpAgent] whose knowledge is [manual] — the raw markdown of
  /// `docs/manual.md`.
  ///
  /// [readLog] is primarily useful for tests; production code reads the
  /// application log through the default [AppLogger] reader.
  HelpAgent({
    String model = 'deepseek:deepseek-v4-flash',
    required String manual,
    HelpLogReader? readLog,
  }) : _agent = Agent(
         model,
         displayName: 'HelpAgent',
         tools: [
           createReadLogFileTool(readLog: readLog, agentName: 'HelpAgent'),
           createDateTimeTool(agentName: 'HelpAgent'),
         ],
       ) {
    _systemMessage = ChatMessage.system(
      helpAgentSystemPrompt(
        manual: manual,
        sections: extractHelpSections(manual),
      ),
    );
    _history = [_systemMessage];
  }

  /// The display name of the agent.
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends [prompt] and streams the response chunks.
  ///
  /// The conversation history is maintained for multi-turn conversations and
  /// trimmed to [defaultMaxHistoryMessages] entries after each answer.
  Stream<String> sendStream(String prompt) async* {
    final allChunks = <String>[];

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      if (chunk.output.isEmpty) continue;
      allChunks.add(chunk.output);
      yield chunk.output;
    }

    final fullOutput = allChunks.join();
    if (fullOutput.isEmpty) return;

    _history.addAll([ChatMessage.user(prompt), ChatMessage.model(fullOutput)]);
    if (_history.length > defaultMaxHistoryMessages + 1) {
      _history = [
        _systemMessage,
        ..._history.sublist(_history.length - defaultMaxHistoryMessages),
      ];
    }
  }

  /// Clears the conversation history but keeps the system prompt.
  void clearHistory() {
    _history = [_systemMessage];
  }
}
