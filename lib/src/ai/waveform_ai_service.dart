import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import 'agents/waveform_agent.dart';
import 'tools/acquire_waveform_tool.dart';
import 'tools/spectrum_summary_tool.dart';
import 'tools/vxi11_tool.dart';
import 'tools/waveform_analysis_tools.dart';
import 'tools/waveform_history_tool.dart';
import 'tools/waveform_summary_tool.dart';

/// Streaming service for the Waveform AI assistant.
///
/// The agent reads the live waveform and spectrum through the injected
/// providers, so every request sees the current acquisition and spectrum
/// settings without reconfiguring the service.
class WaveformAiService {
  WaveformAgent? _agent;
  bool _isDisposed = false;

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
    String? vxi11Host,
    ScpiCommandCallback? onCommandSent,
    int instrumentToolCalls = WaveformAgent.defaultInstrumentToolCalls,
    int maxToolCalls = WaveformAgent.defaultMaxToolCalls,
  }) {
    if (_isDisposed) return;
    _agent = null;

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
        vxi11Host: vxi11Host,
        onCommandSent: onCommandSent,
        instrumentToolCalls: instrumentToolCalls,
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
  Stream<String> sendMessageStream({required String text}) async* {
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
      yield* agent
          .sendStream(text)
          .timeout(
            responseTimeout,
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'AI request timed out after ${responseTimeout.inSeconds} s',
                ),
              );
              sink.close();
            },
          );
      logger.log('Waveform AI request completed');
    } on Object catch (error) {
      logger.error('Waveform AI request failed: $error');
      yield 'Error: AI request failed ($error)';
    }
  }

  void dispose() {
    _isDisposed = true;
    _agent = null;
  }
}
