import 'dart:async';

import '../../devices/device_agent_context.dart';
import '../tools/date_time_tool.dart';
import '../tools/macro_tools.dart';
import '../tools/vxi11_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'frontend_agent.dart';
import 'systemprompts.dart';

/// User-facing agent for the Control Panel's AI assistant.
///
/// The agent does not send SCPI itself. Its tools are:
/// - `scpi_instrument_agent` — delegates every setup action and measurement
///   to the instrument agent, which owns the authorized SCPI command list.
/// - `read_oscilloscope_status` — reports whether the oscilloscope is
///   connected and, while it is, the detected model, display name and channel
///   count.
/// - `search_agent` — answers knowledgebase questions about the oscilloscope.
/// - `read_waveform_summary` — returns the automatic measurements of the
///   currently displayed waveform for explanation.
/// - `current_date_time` — returns the current local date and time in the
///   application log format, plus the timezone and UTC, for placing events
///   in time.
///
/// It is built on [FrontendAgent] because that class already composes the
/// instrument and knowledgebase sub-agents and implements the buffered
/// streaming history. The custom [controlPanelAgentSystemPrompt] focuses it on
/// Control Panel setup and on asking clarifying questions.
class ControlPanelAgent {
  /// The underlying frontend agent with the Control Panel system prompt.
  final FrontendAgent _agent;

  /// Creates a [ControlPanelAgent].
  ///
  /// [vxi11Host] is the instrument address. Pass null to create the agent
  /// without instrument access (for example while no address is configured).
  ///
  /// [readOscilloscopeStatus] supplies the live connection and model state for
  /// the `read_oscilloscope_status` tool.
  ControlPanelAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? vxi11Host,
    DeviceAgentContext? instrumentDeviceContext,
    MacroOscilloscopeStatusReader? readOscilloscopeStatus,
    ScpiCommandCallback? onCommandSent,
    WaveformSummaryProvider? readWaveformSummary,
    int instrumentToolCalls = FrontendAgent.defaultInstrumentToolCalls,
    int searchToolCalls = FrontendAgent.defaultSearchToolCalls,
  }) : _agent = FrontendAgent(
         model: model,
         vxi11Host: vxi11Host,
         systemPrompt: controlPanelAgentSystemPrompt,
         instrumentDeviceContext: instrumentDeviceContext,
         onCommandSent: onCommandSent,
         instrumentToolCalls: instrumentToolCalls,
         searchToolCalls: searchToolCalls,
         tools: [
           createReadOscilloscopeStatusTool(
             readStatus: readOscilloscopeStatus,
             agentName: 'ControlPanelAgent',
           ),
           createWaveformSummaryTool(
             readSummary: readWaveformSummary,
             agentName: 'ControlPanelAgent',
           ),
           createDateTimeTool(agentName: 'ControlPanelAgent'),
         ],
       );

  /// The display name of the agent.
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends a [prompt] and streams the response chunks.
  Stream<String> sendStream(String prompt) => _agent.sendStream(prompt);

  /// Clears the conversation history so the next request starts a fresh
  /// session without the previous turns.
  void clearHistory() => _agent.clearHistory();
}
