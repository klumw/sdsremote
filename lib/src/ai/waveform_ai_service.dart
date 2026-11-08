import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import '../devices/device_agent_context.dart';
import 'agents/waveform_agent.dart';
import 'cancellation.dart';
import 'measurement_form.dart';
import 'planner/planner_agent.dart';
import 'tools/acquire_waveform_tool.dart';
import 'tools/chat_choice_tool.dart';
import 'tools/audio/audio_tools.dart';
import 'tools/digital_frequency_series_tool.dart';
import 'tools/digital_measurement_tools.dart';
import 'tools/signal_generator_tool.dart';
import 'tools/spectrum_summary_tool.dart';
import 'tools/vxi11_tool.dart';
import 'tools/waveform_analysis_tools.dart';
import 'tools/waveform_fault_profile_tool.dart';
import 'tools/waveform_fault_tool.dart';
import 'tools/waveform_history_tool.dart';
import 'tools/waveform_report_tool.dart';
import 'tools/waveform_summary_tool.dart';

/// Streaming service for the Waveform AI assistant.
///
/// The agent reads the live waveform and spectrum through the injected
/// providers, so every request sees the current acquisition and spectrum
/// settings without reconfiguring the service.
class WaveformAiService {
  WaveformAgent? _agent;
  bool _isDisposed = false;
  Timer? _responseTimer;
  StreamController<String>? _activeTimeoutController;
  void Function()? _armResponseTimer;

  /// Number of active suspension requests.
  ///
  /// A counter keeps nested suspensions correct: the audio analysis suspends
  /// the timeout for its whole run and may itself call `acquire_waveform`,
  /// which suspends it again for a requested delay.
  int _timeoutSuspendCount = 0;

  static const Duration responseTimeout = Duration(seconds: 120);

  bool get isInitialized => _agent != null;

  void configure({
    required String apiKey,
    required String apiToken,
    required String model,
    required WaveformSummaryProvider readWaveformSummary,
    required SpectrumSummaryProvider readSpectrumSummary,
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
    AudioFrequencySeriesProvider? audioFrequencySeries,
    DigitalMeasurementProvider? digitalMeasurement,
    DigitalFrequencySeriesProvider? digitalFrequencySeries,
    MeasurementFormProvider? requestInputForm,
    ChatChoiceProvider? requestUserChoice,
    PlannerModelRunner? plannerModelRunner,
    int maxToolCalls = WaveformAgent.defaultMaxToolCalls,
  }) {
    if (_isDisposed) return;
    _agent = null;
    _timeoutSuspendCount = 0;

    Agent.environment[apiKey] = apiToken;
    try {
      _agent = WaveformAgent(
        model: model,
        readWaveformSummary: readWaveformSummary,
        readSpectrumSummary: readSpectrumSummary,
        acquireWaveform: acquireWaveform,
        readWaveformHistory: readWaveformHistory,
        classifyWaveform: classifyWaveform,
        compareWaveformToReferences: compareWaveformToReferences,
        readWaveformFeatures: readWaveformFeatures,
        compareWaveforms: compareWaveforms,
        generateReferenceWaveform: generateReferenceWaveform,
        analyzeWaveformFaults: analyzeWaveformFaults,
        manageFaultProfile: manageFaultProfile,
        createWaveformReport: createWaveformReport,
        vxi11Host: vxi11Host,
        onCommandSent: onCommandSent,
        instrumentDeviceContext: instrumentDeviceContext,
        readSignalGeneratorStatus: readSignalGeneratorStatus,
        applySignalGenerator: applySignalGenerator,
        controlSignalGenerator: controlSignalGenerator,
        isSignalGeneratorIntentEnabled: isSignalGeneratorIntentEnabled,
        audioAnalysisContext: audioAnalysisContext,
        audioSweep: audioSweep,
        audioFrequencySeries: audioFrequencySeries,
        digitalMeasurement: digitalMeasurement,
        digitalFrequencySeries: digitalFrequencySeries,
        requestInputForm: requestInputForm,
        requestUserChoice: requestUserChoice,
        plannerModelRunner: plannerModelRunner,
        suspendResponseTimeout: suspendResponseTimeout,
        resumeResponseTimeout: resumeResponseTimeout,
        maxToolCalls: maxToolCalls,
      );
      AppLogger(
        agentName: 'WaveformAiService',
        toolName: 'configure',
      ).log('WaveformAgent created: model=$model');
    } on Object catch (error) {
      AppLogger(
        agentName: 'WaveformAiService',
        toolName: 'configure',
      ).error('WaveformAgent creation failed: $error');
    }
  }

  /// Sends a prompt and streams the final answer. A timeout is reported as a
  /// stream error so the chat can stop the response and show a message.
  Stream<String> sendMessageStream({
    required String text,
    CancellationToken? cancelToken,
  }) async* {
    if (_isDisposed) throw StateError('Waveform AI service is disposed');
    final agent = _agent;
    if (agent == null) {
      yield 'Error: AI assistant is not configured. Configure the AI provider, '
          'token and model in SDS-Remote Settings.';
      return;
    }
    final logger = AppLogger(
      agentName: 'WaveformAiService',
      toolName: 'sendMessageStream',
    );
    logger.log('Waveform AI request started (model=${agent.model})');
    try {
      yield* _withResponseTimeout(
        agent.sendStream(text, cancelToken: cancelToken),
        cancelToken,
      );
      logger.log('Waveform AI request completed');
    } on Object catch (error) {
      logger.error('Waveform AI request failed: $error');
      yield 'Error: AI request failed ($error)';
    } finally {
      // A cancelled request can leave a tool suspension behind. The next
      // request must start with an armed response timeout.
      _timeoutSuspendCount = 0;
    }
  }

  /// Clears the agent conversation history so the next request starts a
  /// fresh session without the previous turns.
  void clearSession() {
    _agent?.clearHistory();
  }

  /// Applies the response timeout while no user input is pending.
  ///
  /// The timeout is suspended with [suspendResponseTimeout] while a tool
  /// waits for a file upload, because the user can take longer than the
  /// normal response window.
  Stream<String> _withResponseTimeout(
    Stream<String> source,
    CancellationToken? cancelToken,
  ) {
    final controller = StreamController<String>();
    StreamSubscription<String>? subscription;
    var closed = false;

    void closeController() {
      if (closed) return;
      closed = true;
      // The request is over (normal completion, error or timeout). Stop any
      // long-running sub-agent tool that may still be executing.
      cancelToken?.cancel();
      if (identical(_activeTimeoutController, controller)) {
        _responseTimer?.cancel();
        _responseTimer = null;
        _armResponseTimer = null;
        _activeTimeoutController = null;
      }
      if (!controller.isClosed) controller.close();
      // Stop the agent when the timeout closed the output stream.
      unawaited(subscription?.cancel());
    }

    void armTimer() {
      _responseTimer?.cancel();
      if (closed || _timeoutSuspendCount > 0) {
        _responseTimer = null;
        return;
      }
      _responseTimer = Timer(responseTimeout, () {
        if (closed || _timeoutSuspendCount > 0) return;
        AppLogger(agentName: 'WaveformAiService', toolName: 'timeout').error(
          'Waveform AI request timed out after '
          '${responseTimeout.inSeconds} s',
        );
        controller.addError(
          TimeoutException(
            'AI request timed out after ${responseTimeout.inSeconds} s',
          ),
        );
        closeController();
      });
    }

    controller.onListen = () {
      _activeTimeoutController = controller;
      _armResponseTimer = armTimer;
      armTimer();
      subscription = source.listen(
        (chunk) {
          if (closed) return;
          armTimer();
          controller.add(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (closed) return;
          controller.addError(error, stackTrace);
          closeController();
        },
        onDone: () {
          if (!closed) closeController();
        },
        cancelOnError: true,
      );
    };
    controller.onCancel = () async {
      closed = true;
      // The chat cancelled this request; stop the audio sub-agent and any
      // running Bode sweep before the source subscription is torn down.
      cancelToken?.cancel();
      if (identical(_activeTimeoutController, controller)) {
        _responseTimer?.cancel();
        _responseTimer = null;
        _armResponseTimer = null;
        _activeTimeoutController = null;
      }
      await subscription?.cancel();
    };
    return controller.stream;
  }

  /// Stops the response timeout while a tool runs or waits for user input.
  ///
  /// Suspensions nest: each call must be paired with [resumeResponseTimeout].
  void suspendResponseTimeout() {
    _timeoutSuspendCount++;
    _responseTimer?.cancel();
    _responseTimer = null;
  }

  /// Restarts the response timeout after the tool or user input finished.
  void resumeResponseTimeout() {
    if (_timeoutSuspendCount == 0) return;
    _timeoutSuspendCount--;
    if (_timeoutSuspendCount > 0) return;
    _armResponseTimer?.call();
  }

  void dispose() {
    _isDisposed = true;
    _agent = null;
    _timeoutSuspendCount = 0;
    _responseTimer?.cancel();
    _responseTimer = null;
    _armResponseTimer = null;
    final controller = _activeTimeoutController;
    _activeTimeoutController = null;
    if (controller != null && !controller.isClosed) controller.close();
  }
}
