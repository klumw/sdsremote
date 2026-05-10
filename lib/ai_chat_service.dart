import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'src/frontend_agent.dart';
import 'logger.dart';

/// Service that wraps a [FrontendAgent] instance and provides a streaming
/// chat interface for the UI.
class AiChatService {
  FrontendAgent? _agent;
  bool _isDisposed = false;

  /// The underlying [FrontendAgent] instance, if created.
  FrontendAgent? get agent => _agent;

  /// Whether the service has been initialized with an agent.
  bool get isInitialized => _agent != null;

  /// Creates or recreates the [FrontendAgent] with the given configuration.
  ///
  /// Call this method when the user changes API keys, model, or device IP.
  /// The previous agent (if any) is discarded.
  ///
  /// The [apiKey] is the environment variable name for the API key
  /// (e.g., "DEEPSEEK_API_KEY", "OPENAI_API_KEY"). The [apiToken] is the
  /// actual API token value (e.g., "sk-...").
  void configure({
    required String apiKey,
    required String apiToken,
    String model = 'deepseek:deepseek-v4-flash',
    String? vxi11Host,
    int? maxToolCalls,
    int? instrumentToolCalls,
    int? searchToolCalls,
  }) {
    if (_isDisposed) return;

    // Discard the old agent; it will be garbage-collected.
    _agent = null;

    final logger = AppLogger(agentName: 'AiChatService', toolName: 'configure');
    logger.debug(
      'Configuring FrontendAgent: model=$model, vxi11Host=$vxi11Host, '
      'maxToolCalls=$maxToolCalls, '
      'instrumentToolCalls=$instrumentToolCalls, '
      'searchToolCalls=$searchToolCalls',
    );

    // The dartantic_ai Agent reads API keys from Agent.environment (a static
    // mutable map that takes priority over Platform.environment).
    // The [apiKey] parameter is the env var NAME (e.g. "DEEPSEEK_API_KEY"),
    // and [apiToken] is the actual token VALUE.
    Agent.environment[apiKey] = apiToken;

    try {
      _agent = FrontendAgent(
        model: model,
        vxi11Host: vxi11Host,
        maxToolCalls: maxToolCalls ?? FrontendAgent.defaultMaxToolCalls,
        instrumentToolCalls: instrumentToolCalls ?? FrontendAgent.defaultInstrumentToolCalls,
        searchToolCalls: searchToolCalls ?? FrontendAgent.defaultSearchToolCalls,
      );
      logger.debug(
        'SUCCESS: FrontendAgent created, agent=${_agent != null}',
      );
    } catch (e) {
      logger.debug(
        'FAILURE: FrontendAgent constructor threw: $e',
      );
      // _agent remains null — caller should handle this.
    }
  }

  /// Sends a message to the AI agent and returns a stream of response chunks.
  ///
  /// The [text] is the user's message. The response is streamed as chunks
  /// arrive from the agent.
  ///
  /// Throws if the service has not been configured or is disposed.
  Stream<String> sendMessageStream({
    required String text,
    String agentName = 'sds',
  }) async* {
    AppLogger(agentName: 'AiChatService', toolName: 'sendMessageStream').debug(
      'sendMessageStream called: isInitialized=$isInitialized, text="$text"',
    );
    if (_isDisposed) throw Exception('Service is disposed');
    if (_agent == null) {
      yield 'Error: AI agent not configured. Please configure API keys in Settings.';
      return;
    }

    try {
      await for (final chunk in _agent!.sendStream(text)) {
        yield chunk;
      }
    } catch (e) {
      AppLogger(agentName: 'AiChatService', toolName: 'sendMessageStream').debug(
        'Error during AI streaming: $e',
      );
      yield 'Error: AI request failed ($e)';
    }
  }

  /// Deactivates the service by clearing the agent without permanently
  /// disposing the service. The service can be re-activated later with
  /// [configure].
  void deactivate() {
    AppLogger(agentName: 'AiChatService', toolName: 'deactivate').debug(
      'Service deactivated',
    );
    _agent = null;
  }

  /// Disposes the service and releases the agent.
  void dispose() {
    _isDisposed = true;
    _agent = null;
  }
}
