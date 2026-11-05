import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import 'agents/help_agent.dart';

/// Service that wraps a [HelpAgent] and provides the streaming chat interface
/// for the help window's AI assistant.
///
/// This is the help-window counterpart of [MacroAiService]. Its agent has no
/// tools; the complete user manual is embedded in the system prompt instead.
class HelpAiService {
  HelpAgent? _agent;
  bool _isDisposed = false;

  /// The underlying [HelpAgent] instance, if created.
  HelpAgent? get agent => _agent;

  /// Whether the service has been initialized with an agent.
  bool get isInitialized => _agent != null;

  /// Creates or recreates the [HelpAgent] with the given configuration.
  ///
  /// [manual] is the complete markdown of `assets/manuals/sds_manual.md`.
  /// While it is empty (the manual is still loading) no agent is created; the
  /// next call with the loaded manual sets it up.
  ///
  /// The [apiKey] parameter is the environment variable name for the API key
  /// (e.g. "DEEPSEEK_API_KEY"); [apiToken] is the actual token value.
  void configure({
    required String apiKey,
    required String apiToken,
    required String model,
    required String manual,
  }) {
    if (_isDisposed) return;

    // Discard the old agent; it will be garbage-collected.
    _agent = null;

    final logger = AppLogger(agentName: 'HelpAiService', toolName: 'configure');
    logger.debug(
      'Configuring HelpAgent: model=$model, manualChars=${manual.length}',
    );

    if (manual.trim().isEmpty) {
      logger.debug('Manual is empty; HelpAgent not created yet');
      return;
    }

    // The dartantic_ai Agent reads API keys from Agent.environment (a static
    // mutable map that takes priority over Platform.environment).
    Agent.environment[apiKey] = apiToken;

    try {
      _agent = HelpAgent(model: model, manual: manual);
      logger.debug('SUCCESS: HelpAgent created, agent=${_agent != null}');
    } catch (e) {
      logger.error('FAILURE: HelpAgent constructor threw: $e');
      // _agent remains null — the chat input stays disabled.
    }
  }

  /// Sends a message to the help agent and returns a stream of response
  /// chunks.
  ///
  /// Throws if the service has not been configured or is disposed.
  Stream<String> sendMessageStream({required String text}) async* {
    AppLogger(
      agentName: 'HelpAiService',
      toolName: 'sendMessageStream',
    ).debug('sendMessageStream called: isInitialized=$isInitialized');

    if (_isDisposed) throw Exception('Service is disposed');
    if (_agent == null) {
      AppLogger(
        agentName: 'HelpAiService',
        toolName: 'sendMessageStream',
      ).error('Help agent not configured');
      yield 'Error: AI agent not configured. Please configure API keys in Settings.';
      return;
    }

    try {
      await for (final chunk in _agent!.sendStream(text)) {
        yield chunk;
      }
    } catch (e) {
      AppLogger(
        agentName: 'HelpAiService',
        toolName: 'sendMessageStream',
      ).error('Error during help AI streaming: $e');
      yield 'Error: AI request failed ($e)';
    }
  }

  /// Clears the agent conversation history so the next request starts a fresh
  /// session without the previous turns.
  void clearSession() {
    _agent?.clearHistory();
  }

  /// Disposes the service and releases the agent.
  void dispose() {
    _isDisposed = true;
    _agent = null;
  }
}
