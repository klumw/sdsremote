import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import 'agents/macro_agent.dart';
import 'tools/macro_tools.dart';

/// Service that wraps a [MacroAgent] and provides a streaming chat interface
/// for the Macro Editor's AI panel.
///
/// This is the macro-specific counterpart of [AiChatService]. The main chat
/// service is bound to [FrontendAgent] and knows about the instrument and the
/// knowledgebase; the macro assistant must only see the macro editor, so it
/// gets its own agent and tool set.
class MacroAiService {
  MacroAgent? _agent;
  bool _isDisposed = false;

  /// The underlying [MacroAgent] instance, if created.
  MacroAgent? get agent => _agent;

  /// Whether the service has been initialized with an agent.
  bool get isInitialized => _agent != null;

  /// Creates or recreates the [MacroAgent] with the given configuration.
  ///
  /// Call this whenever the AI settings change while the editor is open. The
  /// previous agent (if any) is discarded.
  ///
  /// The [apiKey] parameter is the environment variable name for the API key
  /// (e.g. "DEEPSEEK_API_KEY"); [apiToken] is the actual token value.
  ///
  /// [readMacro] and [writeMacro] are captured by the agent's tools and must
  /// operate on the live editor state.
  void configure({
    required String apiKey,
    required String apiToken,
    required String model,
    required MacroReader readMacro,
    required MacroWriter writeMacro,
    String? Function()? macroFileName,
    int maxToolCalls = MacroAgent.defaultMaxToolCalls,
  }) {
    if (_isDisposed) return;

    // Discard the old agent; it will be garbage-collected.
    _agent = null;

    final logger = AppLogger(
      agentName: 'MacroAiService',
      toolName: 'configure',
    );
    logger.debug(
      'Configuring MacroAgent: model=$model, maxToolCalls=$maxToolCalls',
    );

    // The dartantic_ai Agent reads API keys from Agent.environment (a static
    // mutable map that takes priority over Platform.environment).
    Agent.environment[apiKey] = apiToken;

    try {
      _agent = MacroAgent(
        model: model,
        readMacro: readMacro,
        writeMacro: writeMacro,
        macroFileName: macroFileName,
        maxToolCalls: maxToolCalls,
      );
      logger.debug('SUCCESS: MacroAgent created, agent=${_agent != null}');
    } catch (e) {
      logger.error('FAILURE: MacroAgent constructor threw: $e');
      // _agent remains null — the chat input stays disabled.
    }
  }

  /// Sends a message to the macro agent and returns a stream of response
  /// chunks.
  ///
  /// Throws if the service has not been configured or is disposed.
  Stream<String> sendMessageStream({required String text}) async* {
    AppLogger(
      agentName: 'MacroAiService',
      toolName: 'sendMessageStream',
    ).debug('sendMessageStream called: isInitialized=$isInitialized');

    if (_isDisposed) throw Exception('Service is disposed');
    if (_agent == null) {
      AppLogger(
        agentName: 'MacroAiService',
        toolName: 'sendMessageStream',
      ).error('Macro agent not configured; API keys missing');
      yield 'Error: AI agent not configured. Please configure API keys in Settings.';
      return;
    }

    try {
      await for (final chunk in _agent!.sendStream(text)) {
        yield chunk;
      }
    } catch (e) {
      AppLogger(
        agentName: 'MacroAiService',
        toolName: 'sendMessageStream',
      ).error('Error during macro AI streaming: $e');
      yield 'Error: AI request failed ($e)';
    }
  }

  /// Disposes the service and releases the agent.
  void dispose() {
    _isDisposed = true;
    _agent = null;
  }
}
