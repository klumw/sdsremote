import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../devices/device_agent_context.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/calculator_tool.dart';
import '../tools/date_time_tool.dart';
import '../tools/log_tool.dart';
import '../tools/math_tool.dart';
import '../tools/measurement_tool.dart';
import '../tools/resolve_device_command_tool.dart';
import '../tools/signal_generator_tool.dart';
import '../tools/vxi11_tool.dart';
import 'max_tool_calls_handler.dart';
import 'systemprompts.dart';

/// A reusable AI agent for instrument control via an AI model.
///
/// This class wraps the dartantic_ai framework and provides a simple,
/// reusable interface for chat interactions. It can be used in both
/// console applications and Flutter apps.
///
/// By default, the agent is equipped with a VXI-11 tool that allows it
/// to send SCPI commands and queries to a remote instrument, a log tool that
/// lets it inspect the application log when a command fails, a date/time tool
/// that places log entries in time, plus three deterministic tools that need
/// no instrument connection:
/// [createMeasurementTool], which turns raw `PAVA` responses such as
/// `C1:PAVA PKPK,3.000000E+00V` into structured values,
/// [createMathTool], which calculates derived quantities such as the
/// voltage gain in dB between two channels, and [createCalculatorTool],
/// which evaluates unit-aware, complex and dB expressions and runs the
/// engineering formula library.
///
/// The agent limits the number of tool calls per user input to
/// [maxToolCalls] (default: 10). This prevents runaway tool loops.
///
/// Usage:
/// ```dart
/// final agent = InstrumentAgent();
/// await for (final chunk in agent.sendStream('Send C1:TRA OFF to the device')) {
///   print(chunk);
/// }
/// ```
class InstrumentAgent with MaxToolCallsHandler {
  /// Default maximum number of tool calls per user input.
  static const int defaultMaxToolCalls = 3;

  /// The underlying dartantic_ai Agent instance.
  final Agent _agent;

  /// The chat history for multi-turn conversations.
  final List<ChatMessage> _history = [];

  /// Shared validation hook used by the already constructed VXI-11 tool.
  final DeviceCommandGate _commandGate;

  /// Tools registered with the underlying agent, exposed for tests and
  /// diagnostics.
  final List<Tool> _tools;

  List<Tool> get tools => List.unmodifiable(_tools);

  /// The current system prompt.
  String get systemPrompt => _history.isEmpty ? '' : _history.first.text;

  /// Whether this class built the system prompt from the device context.
  ///
  /// A caller-supplied prompt is kept verbatim; only the validation hook is
  /// updated when the device context changes.
  final bool _ownsSystemPrompt;

  /// Whether the signal-generator tools are part of this agent.
  final bool _hasSignalGeneratorTools;

  /// Combines the user's keyword with an autonomous audio grant.
  final _GeneratorAccessGate _generatorGate;

  /// Carries the most recent automatic waveform refresh to the caller.
  final _WaveformUpdateSink _waveformUpdates;

  DeviceAgentContext? _deviceContext;

  /// Maximum number of tool calls allowed per user input.
  @override
  final int maxToolCalls;

  /// Result of the automatic waveform refresh after a successful scope write.
  ///
  /// `null` when the last request did not change a scope setting or no
  /// acquisition provider is available.
  Map<String, dynamic>? get lastWaveformUpdate => _waveformUpdates.value;

  /// Creates an [InstrumentAgent] configured for the specified model.
  ///
  /// The [model] parameter specifies the model to use in `provider:model`
  /// format.
  ///
  /// The [deviceContext] parameter binds the agent to a loaded device profile.
  /// Its command definitions and knowledge form the device-specific part of
  /// the system prompt, and the same registry validates every command sent by
  /// the VXI-11 tool. When it is null the prompt fails closed: the agent is
  /// told not to send commands until a profile is configured.
  ///
  /// The [systemPrompt] parameter overrides the generated prompt. The
  /// validation hook from [deviceContext] still applies.
  ///
  /// The [vxi11Host] parameter sets the default VXI-11 instrument IP.
  /// If null, no VXI-11 tool is added.
  ///
  /// The [tools] parameter allows adding additional custom tools.
  ///
  /// The [readLog] parameter overrides how the `read_log_file` tool reads the
  /// application log. It is primarily useful for tests; production code uses
  /// the default reader for `sds/logging/sds.log`.
  ///
  /// The [maxToolCalls] parameter limits the number of tool calls per
  /// user input. Defaults to [defaultMaxToolCalls] (3).
  factory InstrumentAgent({
    String model = 'deepseek:deepseek-v4-flash',
    String? systemPrompt,
    String? vxi11Host,
    List<Tool>? tools,
    ScpiCommandCallback? onCommandSent,
    WaveformAcquisitionProvider? acquireWaveform,
    LogReader? readLog,
    DeviceAgentContext? deviceContext,
    DeviceCommandGate? commandGate,
    SignalGeneratorStatusProvider? readSignalGeneratorStatus,
    SignalGeneratorApplyProvider? applySignalGenerator,
    SignalGeneratorActionProvider? controlSignalGenerator,
    SignalGeneratorIntentCheck? isSignalGeneratorIntentEnabled,
    int maxToolCalls = defaultMaxToolCalls,
  }) {
    final gate =
        commandGate ?? DeviceCommandGate(deviceContext, vxi11Host != null);
    final generatorGate = _GeneratorAccessGate(isSignalGeneratorIntentEnabled);
    final hasSignalGeneratorTools =
        readSignalGeneratorStatus != null &&
        applySignalGenerator != null &&
        controlSignalGenerator != null;
    final waveformUpdates = _WaveformUpdateSink();
    final prompt =
        systemPrompt ??
        buildInstrumentAgentSystemPrompt(
          deviceContext: deviceContext?.buildPromptSection(),
          includeSignalGenerator: hasSignalGeneratorTools,
        );
    final agentTools = <Tool>[
      if (vxi11Host != null)
        createVxi11Tool(
          host: vxi11Host,
          agentName: 'InstrumentAgent',
          onCommandSent: onCommandSent,
          commandGate: gate,
          afterWrite: acquireWaveform == null
              ? null
              : (command) async {
                  try {
                    final update = await acquireWaveform(delaySeconds: 0);
                    waveformUpdates.value = update;
                    return update;
                  } on Object catch (error) {
                    final update = <String, dynamic>{
                      'error': 'The waveform refresh failed ($error).',
                    };
                    waveformUpdates.value = update;
                    return update;
                  }
                },
        ),
      // Resolves a semantic command against the active device profile. It
      // never sends anything; the returned string goes through the
      // communication tool and its validator.
      createResolveDeviceCommandTool(
        contextProvider: () => gate.context,
        agentName: 'InstrumentAgent',
      ),
      // Deterministic measurement parser; needs no instrument connection.
      createMeasurementTool(agentName: 'InstrumentAgent'),
      // Deterministic math on measured numbers (gain in dB, and any
      // operation added later); needs no instrument connection.
      createMathTool(agentName: 'InstrumentAgent'),
      // Unit-aware, complex-capable engineering calculator with the
      // electronics, measurement, audio and RF formula library.
      createCalculatorTool(agentName: 'InstrumentAgent'),
      // Lets the agent inspect the application log when a SCPI command or
      // the communication itself fails.
      createLogFileTool(
        readLog: readLog,
        agentName: 'InstrumentAgent',
        description:
            'Return the most recent lines of the SDS-Remote application '
            'log (sds.log in the application temp directory). Call this '
            'when a SCPI command fails, the communication tool returns an '
            'error, or the instrument reports an unexpected error: search '
            'for the failing command with "contains", quote the matching '
            'lines and explain the failure with one concrete next step. '
            'By default only warning and error lines are returned; set '
            'errors_only to false to include all recent lines for '
            'context.',
      ),
      createDateTimeTool(agentName: 'InstrumentAgent'),
      if (readSignalGeneratorStatus != null)
        createReadSignalGeneratorStatusTool(
          readStatus: readSignalGeneratorStatus,
          isEnabled: generatorGate.isEnabled,
          agentName: 'InstrumentAgent',
        ),
      if (applySignalGenerator != null)
        createSetSignalGeneratorTool(
          apply: applySignalGenerator,
          isEnabled: generatorGate.isEnabled,
          agentName: 'InstrumentAgent',
        ),
      if (controlSignalGenerator != null)
        createSignalGeneratorActionTool(
          control: controlSignalGenerator,
          isEnabled: generatorGate.isEnabled,
          agentName: 'InstrumentAgent',
        ),
      ...?tools,
    ];
    return InstrumentAgent._(
      model: model,
      agentTools: agentTools,
      deviceContext: deviceContext,
      commandGate: gate,
      systemPrompt: prompt,
      ownsSystemPrompt: systemPrompt == null,
      hasSignalGeneratorTools: hasSignalGeneratorTools,
      generatorGate: generatorGate,
      waveformUpdates: waveformUpdates,
      maxToolCalls: maxToolCalls,
    );
  }

  InstrumentAgent._({
    required String model,
    required List<Tool> agentTools,
    required DeviceAgentContext? deviceContext,
    required DeviceCommandGate commandGate,
    required String systemPrompt,
    required bool ownsSystemPrompt,
    required bool hasSignalGeneratorTools,
    required _GeneratorAccessGate generatorGate,
    required _WaveformUpdateSink waveformUpdates,
    required this.maxToolCalls,
  }) : _deviceContext = deviceContext,
       _commandGate = commandGate,
       _ownsSystemPrompt = ownsSystemPrompt,
       _hasSignalGeneratorTools = hasSignalGeneratorTools,
       _generatorGate = generatorGate,
       _waveformUpdates = waveformUpdates,
       _tools = List.unmodifiable(agentTools),
       _agent = Agent(
         model,
         displayName: 'InstrumentAgent',
         tools: agentTools,
         maxToolCalls: maxToolCalls,
       ) {
    _history.add(ChatMessage.system(systemPrompt));
  }

  /// Replaces the active device context.
  ///
  /// Updates the validation hook used by the VXI-11 tool immediately. When this
  /// agent owns its system prompt, the prompt is regenerated with the new
  /// device context (for example after `*IDN?` reported the instrument model).
  void updateDeviceContext(DeviceAgentContext? context) {
    _deviceContext = context;
    _commandGate.update(context);
    if (!_ownsSystemPrompt) return;
    final prompt = buildInstrumentAgentSystemPrompt(
      deviceContext: context?.buildPromptSection(),
      includeSignalGenerator: _hasSignalGeneratorTools,
    );
    if (_history.isEmpty) {
      _history.add(ChatMessage.system(prompt));
    } else {
      _history[0] = ChatMessage.system(prompt);
    }
  }

  /// The active device context, if one is bound.
  DeviceAgentContext? get deviceContext => _deviceContext;

  /// Allows signal-generator changes for the duration of an autonomous audio
  /// analysis.
  ///
  /// The Waveform Agent asks once whether the audio measurements may make the
  /// scope and generator changes they need. The AudioAgent enables this grant
  /// while it runs; afterwards the regular keyword gate applies again.
  void setAutonomousGeneratorAccess(bool granted) {
    _generatorGate.autonomous = granted;
  }

  /// The display name of the agent.
  String get displayName => _agent.displayName;

  /// The current model name being used.
  String get model => _agent.model;

  /// Sends a [prompt] and returns the full response as a single string.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// Tool calls are counted and limited to [maxToolCalls] per input.
  /// When the limit is reached, the agent receives a tool result message
  /// telling it the limit was reached so it can respond gracefully.
  Future<String> send(String prompt) async {
    // Use sendStream which has the maxToolCalls enforcement,
    // then accumulate the results into a single string.
    final chunks = <String>[];
    await for (final chunk in sendStream(prompt)) {
      chunks.add(chunk);
    }
    return chunks.join().trim();
  }

  /// Sends a [prompt] and streams the response chunks.
  ///
  /// The conversation history is automatically maintained for multi-turn
  /// conversations.
  ///
  /// Tool calls are counted and limited to [maxToolCalls] per input.
  /// When the limit is reached, the agent is forced to respond without
  /// further tool calls.
  Stream<String> sendStream(String prompt) async* {
    final chunks = <String>[];
    _waveformUpdates.value = null;

    await for (final chunk in _agent.sendStream(prompt, history: _history)) {
      // Yield text output. Tool calls and results are handled internally
      // by the inner Agent's orchestrator, including max tool calls
      // enforcement.
      if (chunk.output.isNotEmpty) {
        chunks.add(chunk.output);
        yield chunk.output;
      }
    }

    // Only add the user prompt and final text response to _history.
    // The dartantic_ai Agent internally manages tool call/result message pairs
    // in its StreamingState. Adding them here would cause duplicates and
    // "tool result without matching tool call" API errors on subsequent calls.
    final fullOutput = chunks.join();
    if (fullOutput.isNotEmpty) {
      _history.addAll([
        ChatMessage.user(prompt),
        ChatMessage.model(fullOutput),
      ]);
      // The instrument agent must not retain history between calls. Keep only
      // the system prompt (if any) so each command starts fresh.
      if (_history.length > 1) {
        final systemPrompt = _history[0];
        _history.clear();
        _history.add(systemPrompt);
      } else {
        _history.clear();
      }
    }
  }

  /// Clears the conversation history but keeps the system prompt.
  void clearHistory() {
    if (_history.length > 1) {
      _history.removeRange(1, _history.length);
    }
  }
}

/// Mutable holder shared between the VXI-11 write hook and the agent.
class _WaveformUpdateSink {
  Map<String, dynamic>? value;
}

/// Combines the user's signal-generator keyword with an autonomous grant.
class _GeneratorAccessGate {
  _GeneratorAccessGate(this._userIntent) {
    isEnabled = _userIntent == null ? null : () => autonomous || _userIntent();
  }

  final SignalGeneratorIntentCheck? _userIntent;

  /// Gate passed to the signal-generator tools.
  ///
  /// Null keeps the tools ungated, matching a host that provides no check.
  late final SignalGeneratorIntentCheck? isEnabled;

  /// Whether the AudioAgent received one-time autonomous permission.
  bool autonomous = false;
}
