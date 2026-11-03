import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import '../devices/device_agent_context.dart';
import 'agents/control_panel_agent.dart';
import 'tools/macro_tools.dart';
import 'tools/vxi11_tool.dart';
import 'tools/waveform_summary_tool.dart';

/// Service that wraps a [ControlPanelAgent] and streams the Control Panel AI
/// conversation into the chat overlay.
///
/// This is the Control Panel counterpart of [MacroAiService]. The main
/// [AiChatService] serves the application-wide AI chat; this service owns a
/// separate agent with the Control Panel system prompt and the oscilloscope
/// status tool.
class ControlPanelAiService {
  ControlPanelAgent? _agent;
  bool _isDisposed = false;

  /// The underlying [ControlPanelAgent] instance, if created.
  ControlPanelAgent? get agent => _agent;

  /// Whether the service has been initialized with an agent.
  bool get isInitialized => _agent != null;

  /// Creates or recreates the [ControlPanelAgent] with the given configuration.
  ///
  /// Call this whenever the AI settings or the instrument address change. The
  /// previous agent (if any) is discarded.
  ///
  /// [vxi11Host] is the instrument address used by the instrument sub-agent.
  /// [readOscilloscopeStatus] supplies the live connection and model state for
  /// the `read_oscilloscope_status` tool.
  void configure({
    required String apiKey,
    required String apiToken,
    required String model,
    String? vxi11Host,
    DeviceAgentContext? instrumentDeviceContext,
    MacroOscilloscopeStatusReader? readOscilloscopeStatus,
    ScpiCommandCallback? onCommandSent,
    WaveformSummaryProvider? readWaveformSummary,
  }) {
    if (_isDisposed) return;

    // Discard the old agent; it will be garbage-collected.
    _agent = null;

    final logger = AppLogger(
      agentName: 'ControlPanelAiService',
      toolName: 'configure',
    );
    logger.debug(
      'Configuring ControlPanelAgent: model=$model, vxi11Host=$vxi11Host',
    );

    // The dartantic_ai Agent reads API keys from Agent.environment (a static
    // mutable map that takes priority over Platform.environment).
    Agent.environment[apiKey] = apiToken;

    try {
      _agent = ControlPanelAgent(
        model: model,
        vxi11Host: vxi11Host,
        instrumentDeviceContext: instrumentDeviceContext,
        readOscilloscopeStatus: readOscilloscopeStatus,
        onCommandSent: onCommandSent,
        readWaveformSummary: readWaveformSummary,
      );
      logger.debug(
        'SUCCESS: ControlPanelAgent created, agent=${_agent != null}',
      );
    } catch (e) {
      logger.error('FAILURE: ControlPanelAgent constructor threw: $e');
      // _agent remains null — the chat input stays disabled.
    }
  }

  /// Sends a message to the Control Panel agent and returns a stream of
  /// response chunks.
  ///
  /// Throws if the service has not been configured or is disposed.
  Stream<String> sendMessageStream({required String text}) async* {
    AppLogger(
      agentName: 'ControlPanelAiService',
      toolName: 'sendMessageStream',
    ).debug('sendMessageStream called: isInitialized=$isInitialized');

    if (_isDisposed) throw Exception('Service is disposed');
    if (_agent == null) {
      AppLogger(
        agentName: 'ControlPanelAiService',
        toolName: 'sendMessageStream',
      ).error('Control panel agent not configured; API keys missing');
      yield 'Error: AI agent not configured. Please configure API keys in Settings.';
      return;
    }

    try {
      await for (final chunk in _agent!.sendStream(text)) {
        yield chunk;
      }
    } catch (e) {
      AppLogger(
        agentName: 'ControlPanelAiService',
        toolName: 'sendMessageStream',
      ).error('Error during control panel AI streaming: $e');
      yield 'Error: AI request failed ($e)';
    }
  }

  /// Disposes the service and releases the agent.
  void dispose() {
    _isDisposed = true;
    _agent = null;
  }
}
