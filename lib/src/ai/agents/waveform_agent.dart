import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../devices/device_agent_context.dart';
import '../cancellation.dart';
import '../measurement_form.dart';
import '../planner/catalog/planner_catalog.dart';
import '../planner/models/action_plan.dart';
import '../planner/pipeline/equipment_probe.dart';
import '../planner/pipeline/planner_pipeline.dart';
import '../planner/plan_executor.dart';
import '../planner/planner_agent.dart';
import '../planner/planner_config.dart';
import '../planner/planner_session.dart';
import '../planner/safety/safety_policy.dart';
import '../tools/acquire_waveform_tool.dart';
import '../tools/audio/audio_tools.dart';
import '../tools/audio_agent_tool.dart';
import '../tools/chat_choice_tool.dart';
import '../tools/digital_agent_tool.dart';
import '../tools/digital_measurement_tools.dart';
import '../tools/execute_plan_tool.dart';
import '../tools/planner_agent_tool.dart';
import '../tools/present_input_form_tool.dart';
import '../tools/scope_analyst_tool.dart';
import '../tools/scpi_agent_tool.dart';
import '../tools/signal_generator_tool.dart';
import '../tools/spectrum_summary_tool.dart';
import '../tools/vxi11_tool.dart';
import '../tools/waveform_analysis_tools.dart';
import '../tools/waveform_fault_profile_tool.dart';
import '../tools/waveform_fault_tool.dart';
import '../tools/waveform_history_tool.dart';
import '../tools/waveform_report_tool.dart';
import '../tools/waveform_summary_tool.dart';
import 'answer_sanitizer.dart';
import 'audio_agent.dart';
import 'digital_agent.dart';
import 'instrument_agent.dart';
import 'scope_analyst_agent.dart';
import 'systemprompts.dart';

/// Orchestrator for the Acquire Waveform view.
///
/// The agent does not read the oscilloscope or analyze waveforms itself. It
/// routes every measurement, acquisition, spectrum, classification, fault
/// analysis and report request to the [ScopeAnalystAgent], audio requests to
/// the [AudioAgent], digital requests to the [DigitalAgent], and live
/// instrument access to the [InstrumentAgent]. It then presents the returned
/// structured results to the user and keeps the diagnostic dialog.
class WaveformAgent {
  static const int defaultMaxToolCalls = 16;
  static const int defaultInstrumentToolCalls = 8;
  static const int _maxHistoryMessages = 20;

  late final Agent _agent;
  List<ChatMessage> _history;
  InstrumentAgent? _instrumentAgent;
  late final AudioAgent _audioAgent;
  late final DigitalAgent _digitalAgent;
  late final ScopeAnalystAgent _scopeAnalystAgent;
  late final PlannerAgent _plannerAgent;
  late final PlannerSessionStore _plannerSessions;
  late final PlanSessionStore _planSessions;
  late final PlannerInvocationBudget _plannerBudget;
  late final PlanExecutor _planExecutor;
  late final EquipmentProbe _equipmentProbe;
  late final List<Tool> _tools;
  CancellationToken? _activeCancelToken;

  /// The instrument sub-agent, exposed for diagnostics and tests.
  InstrumentAgent? get instrumentAgent => _instrumentAgent;

  /// The audio measurement sub-agent, exposed for diagnostics and tests.
  AudioAgent get audioAgent => _audioAgent;

  /// The digital measurement sub-agent, exposed for diagnostics and tests.
  DigitalAgent get digitalAgent => _digitalAgent;

  /// The scope measurement sub-agent, exposed for diagnostics and tests.
  ScopeAnalystAgent get scopeAnalystAgent => _scopeAnalystAgent;

  /// The planner sub-agent, exposed for diagnostics and tests.
  PlannerAgent get plannerAgent => _plannerAgent;

  /// The plan executor, exposed for diagnostics and tests.
  PlanExecutor get planExecutor => _planExecutor;

  /// Tools registered with the orchestrator model.
  List<Tool> get tools => List<Tool>.unmodifiable(_tools);

  /// Names of the registered tools.
  List<String> get toolNames => <String>[for (final tool in _tools) tool.name];

  WaveformAgent({
    String model = 'deepseek:deepseek-v4-flash',
    WaveformSummaryProvider? readWaveformSummary,
    SpectrumSummaryProvider? readSpectrumSummary,
    WaveformAcquisitionProvider? acquireWaveform,
    WaveformHistoryProvider? readWaveformHistory,
    WaveformClassificationProvider? classifyWaveform,
    WaveformReferenceComparisonProvider? compareWaveformToReferences,
    WaveformFeaturesProvider? readWaveformFeatures,
    WaveformPairComparisonProvider? compareWaveforms,
    ReferenceGenerationProvider? generateReferenceWaveform,
    WaveformFaultAnalysisProvider? analyzeWaveformFaults,
    WaveformFaultProfileProvider? manageFaultProfile,
    WaveformReportProvider? createWaveformReport,
    String? vxi11Host,
    ScpiCommandCallback? onCommandSent,
    DeviceAgentContext? instrumentDeviceContext,
    SignalGeneratorStatusProvider? readSignalGeneratorStatus,
    SignalGeneratorApplyProvider? applySignalGenerator,
    SignalGeneratorActionProvider? controlSignalGenerator,
    SignalGeneratorIntentCheck? isSignalGeneratorIntentEnabled,
    AudioAnalysisContextProvider? audioAnalysisContext,
    AudioSweepProvider? audioSweep,
    DigitalMeasurementProvider? digitalMeasurement,
    MeasurementFormProvider? requestInputForm,
    ChatChoiceProvider? requestUserChoice,
    PlannerAgent? plannerAgent,
    PlannerModelRunner? plannerModelRunner,
    EquipmentProbe? equipmentProbe,
    PlanStepDispatcher? planStepDispatcher,
    PlannerCatalog plannerCatalog = PlannerCatalog.standard,
    SafetyPolicy safetyPolicy = SafetyPolicy.defaults,
    PlannerConfig plannerConfig = PlannerConfig.defaults,
    void Function()? suspendResponseTimeout,
    void Function()? resumeResponseTimeout,
    int instrumentToolCalls = defaultInstrumentToolCalls,
    int maxToolCalls = defaultMaxToolCalls,
  }) : _history = [ChatMessage.system(waveformAgentSystemPrompt)] {
    final instrumentAgent = vxi11Host == null
        ? null
        : InstrumentAgent(
            model: model,
            vxi11Host: vxi11Host,
            maxToolCalls: instrumentToolCalls,
            onCommandSent: onCommandSent,
            acquireWaveform: acquireWaveform,
            deviceContext: instrumentDeviceContext,
            readSignalGeneratorStatus: readSignalGeneratorStatus,
            applySignalGenerator: applySignalGenerator,
            controlSignalGenerator: controlSignalGenerator,
            isSignalGeneratorIntentEnabled: isSignalGeneratorIntentEnabled,
          );
    _instrumentAgent = instrumentAgent;
    _audioAgent = AudioAgent(
      model: model,
      contextProvider: audioAnalysisContext ?? () => null,
      sweepProvider: audioSweep,
      acquireWaveform: acquireWaveform,
      instrumentAgent: instrumentAgent,
    );
    _digitalAgent = DigitalAgent(
      model: model,
      readWaveformSummary: readWaveformSummary,
      readSpectrumSummary: readSpectrumSummary,
      readWaveformFeatures: readWaveformFeatures,
      classifyWaveform: classifyWaveform,
      analyzeWaveformFaults: analyzeWaveformFaults,
      manageFaultProfile: manageFaultProfile,
      acquireWaveform: acquireWaveform,
      instrumentAgent: instrumentAgent,
      digitalMeasurement: digitalMeasurement,
    );
    _scopeAnalystAgent = ScopeAnalystAgent(
      model: model,
      readWaveformSummary: readWaveformSummary,
      readSpectrumSummary: readSpectrumSummary,
      acquireWaveform: acquireWaveform,
      instrumentAgent: instrumentAgent,
      readWaveformHistory: readWaveformHistory,
      classifyWaveform: classifyWaveform,
      compareWaveformToReferences: compareWaveformToReferences,
      readWaveformFeatures: readWaveformFeatures,
      compareWaveforms: compareWaveforms,
      generateReferenceWaveform: generateReferenceWaveform,
      analyzeWaveformFaults: analyzeWaveformFaults,
      manageFaultProfile: manageFaultProfile,
      createWaveformReport: createWaveformReport,
    );
    _equipmentProbe =
        equipmentProbe ??
        CallbackEquipmentProbe(
          vxi11Host: vxi11Host,
          readGeneratorStatus: readSignalGeneratorStatus,
          readWaveformSummary: readWaveformSummary,
        );
    _plannerAgent =
        plannerAgent ??
        PlannerAgent(
          model: model,
          modelRunner: plannerModelRunner,
          pipeline: PlannerPipeline(
            catalog: plannerCatalog,
            safetyPolicy: safetyPolicy,
            config: plannerConfig,
          ),
          catalog: plannerCatalog,
          config: plannerConfig,
        );
    _plannerSessions = _plannerAgent.sessions;
    _planSessions = PlanSessionStore(maxEntries: plannerConfig.maxStoredPlans);
    _plannerBudget = PlannerInvocationBudget(
      plannerConfig.plannerInvocationsPerTurn,
    );
    _planExecutor = PlanExecutor(
      store: _planSessions,
      dispatch: planStepDispatcher ?? _defaultPlanStepDispatcher,
      maxEntries: plannerConfig.maxStoredPlans,
    );

    final tools = <Tool>[
      createScopeAnalysisAgentTool(
        analyze:
            ({
              required String request,
              bool reportConfirmed = false,
              bool autonomous = false,
              String? channel,
              String? focus,
            }) => _scopeAnalystAgent.analyze(
              request: request,
              reportConfirmed: reportConfirmed,
              autonomous: autonomous,
              channel: channel,
              focus: focus,
              cancelToken: _activeCancelToken,
            ),
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
        agentName: 'WaveformAgent',
      ),
      if (instrumentAgent != null)
        createScpiAgentTool(instrumentAgent, agentName: 'WaveformAgent'),
      createAudioAnalysisAgentTool(
        analyze:
            ({
              required String request,
              bool autonomous = false,
              String? channel,
              String? focus,
            }) => _audioAgent.analyze(
              request: request,
              autonomous: autonomous,
              channel: channel,
              focus: focus,
              cancelToken: _activeCancelToken,
            ),
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
        agentName: 'WaveformAgent',
      ),
      createDigitalAnalysisAgentTool(
        analyze:
            ({
              required String request,
              bool autonomous = false,
              String? channel,
              String? focus,
            }) => _digitalAgent.analyze(
              request: request,
              autonomous: autonomous,
              channel: channel,
              focus: focus,
              cancelToken: _activeCancelToken,
            ),
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
        agentName: 'WaveformAgent',
      ),
      createPlannerAgentTool(
        planner: _plannerAgent,
        sessions: _plannerSessions,
        planSessions: _planSessions,
        budget: _plannerBudget,
        probe: _equipmentProbe,
        agentName: 'WaveformAgent',
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
      ),
      createPresentInputFormTool(
        requestForm: requestInputForm,
        sessions: _plannerSessions,
        agentName: 'WaveformAgent',
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
      ),
      createExecutePlanTool(
        executor: _planExecutor,
        agentName: 'WaveformAgent',
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
      ),
      createChatChoiceTool(
        requestChoice: requestUserChoice,
        onCorrection: _handlePlanCorrection,
        agentName: 'WaveformAgent',
        onLongRunningStart: suspendResponseTimeout,
        onLongRunningEnd: resumeResponseTimeout,
      ),
    ];
    _tools = tools;
    _agent = Agent(
      model,
      displayName: 'WaveformAgent',
      maxToolCalls: maxToolCalls,
      tools: tools,
    );
  }

  /// Applies free text from a plan approval dialog as a correction.
  ///
  /// The stored plan keeps the original request text. The correction is
  /// appended to it, the planner runs again and the new plan replaces the old
  /// one under a new `planRef`, so the user can approve the corrected plan
  /// before anything starts. Without a stored plan the text is passed back to
  /// the model as a generic `correction`.
  Future<Map<String, dynamic>> _handlePlanCorrection(
    String correction,
    Map<String, dynamic> args,
  ) async {
    final rawRef = args['plan_ref'];
    final planRef = rawRef is String && rawRef.trim().isNotEmpty
        ? rawRef.trim()
        : null;
    final session = planRef == null
        ? _planSessions.single
        : _planSessions.load(planRef);
    final requestText = session?.requestText?.trim();
    if (session == null || requestText == null || requestText.isEmpty) {
      return <String, dynamic>{'correction': correction};
    }

    final previousRef = session.plan.planId;
    // The corrected request replaces the old plan even when the new planning
    // run asks for more input, so a stale plan can never be executed.
    _planSessions.remove(previousRef);
    final result = await _plannerAgent.plan(
      '$requestText\n\nUser correction before the start: $correction',
      probe: _equipmentProbe,
      cancelToken: _activeCancelToken,
    );
    if (result['status'] == 'plan_ready') {
      final planMap = result['plan'];
      if (planMap is Map) {
        final plan = ActionPlan.fromMap(Map<String, dynamic>.from(planMap));
        _planSessions.save(PlanSession(plan: plan, requestText: requestText));
        AppLogger(
          agentName: 'WaveformAgent',
          toolName: 'request_user_choice',
        ).log(
          'Plan correction replanned: previous=$previousRef '
          'new=${plan.planId}',
        );
        return <String, dynamic>{
          ...result,
          'planRef': plan.planId,
          'previousPlanRef': previousRef,
          'replanned': true,
        };
      }
    }
    return result;
  }

  String get displayName => _agent.displayName;

  String get model => _agent.model;

  /// Streams only the final answer.
  ///
  /// Text that precedes a tool call is discarded, so status messages such as
  /// "Session permission noted — I will ..." never reach the chat.
  Stream<String> sendStream(
    String prompt, {
    CancellationToken? cancelToken,
  }) async* {
    _plannerBudget.reset();
    _audioAgent.clearSweepCache();
    _activeCancelToken = cancelToken;
    // A cancelled or abandoned audio analysis must not leave generator access
    // open for the next request. The AudioAgent also resets the grant in its
    // own cleanup path.
    _instrumentAgent?.setAutonomousGeneratorAccess(false);
    try {
      // Buffer the text until the turn ends. Text that precedes a tool call is
      // a "thinking aloud" preface such as "Session permission noted, I will
      // change the sample rate ..."; it is discarded. Only the text after the
      // last tool call — the actual answer — is emitted.
      final textBuffer = <String>[];

      await for (final chunk in _agent.sendStream(prompt, history: _history)) {
        final hasToolCalls = chunk.messages.any(
          (message) => message.hasToolCalls,
        );
        if (hasToolCalls) {
          textBuffer.clear();
        }
        if (chunk.output.isNotEmpty) {
          textBuffer.add(chunk.output);
        }
      }

      // The final answer is emitted once, after the tool-limit wording has
      // been removed. The model can see the orchestrator's rejected tool
      // results in its history and sometimes quotes the technical message; the
      // user must never receive it as the answer.
      final output = sanitizeInternalAgentNames(
        _sanitizeToolLimitText(textBuffer.join()),
      );
      if (output.isNotEmpty) {
        yield output;
        _history.addAll([ChatMessage.user(prompt), ChatMessage.model(output)]);
        if (_history.length > _maxHistoryMessages + 1) {
          _history = [
            _history.first,
            ..._history.sublist(_history.length - _maxHistoryMessages),
          ];
        }
      }
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
    }
  }

  void clearHistory() {
    _history = [ChatMessage.system(waveformAgentSystemPrompt)];
    _plannerAgent.clearSession();
    _planSessions.clear();
    _plannerBudget.reset();
  }

  /// Dispatches one plan step to the matching sub-agent.
  Future<Map<String, dynamic>> _defaultPlanStepDispatcher(
    ActionStep step,
    String instruction,
    Map<String, Object?> resolvedParameters,
    CancellationToken? cancelToken,
  ) async {
    switch (step.agent) {
      case PlanAgent.scopeAnalysis:
        return _scopeAnalystAgent.analyze(
          request: instruction,
          focus: step.focus,
          cancelToken: cancelToken,
        );
      case PlanAgent.audioAnalysis:
        // The approved plan covers the listed generator and scope changes.
        return _audioAgent.analyze(
          request: instruction,
          autonomous: true,
          focus: step.focus,
          cancelToken: cancelToken,
        );
      case PlanAgent.digitalAnalysis:
        return _digitalAgent.analyze(
          request: instruction,
          autonomous: true,
          focus: step.focus,
          cancelToken: cancelToken,
        );
      case PlanAgent.scpiInstrument:
        final agent = _instrumentAgent;
        if (agent == null) {
          return <String, dynamic>{
            'error': 'The instrument agent is not available.',
          };
        }
        final response = await agent.send(instruction);
        return <String, dynamic>{'ok': true, 'text': response};
      case PlanAgent.user:
        return <String, dynamic>{
          'error': 'Manual steps are handled by the plan executor.',
        };
    }
  }
}

/// Removes technical tool-limit wording from the final assistant answer.
String _sanitizeToolLimitText(String text) {
  return text
      .replaceAll(
        RegExp(r'Maximum tool calls \(\d+\) reached\.?', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(
          r'Please try rephrasing your request to be more specific\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'Please respond with what you have so far\.?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\b(?:the\s+)?(?:'
          r'per-request\s+(?:tool[-\s]?call\s+)?limit|'
          r'tool[-\s]?call\s+limit|'
          r'call\s+limit'
          r')\b',
          caseSensitive: false,
        ),
        'a request restriction',
      )
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
