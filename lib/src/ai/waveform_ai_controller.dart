import 'package:flutter/foundation.dart' show VoidCallback;

import '../devices/device_agent_context.dart';
import 'ai_settings.dart';
import 'tools/audio/audio_tools.dart';
import 'tools/digital_frequency_series_tool.dart';
import 'tools/digital_measurement_tools.dart';
import 'tools/signal_generator_tool.dart';
import 'tools/spectrum_summary_tool.dart';
import 'tools/waveform_analysis_tools.dart';
import 'tools/waveform_fault_profile_tool.dart';
import 'tools/waveform_fault_tool.dart';
import 'tools/waveform_history_tool.dart';
import 'tools/waveform_report_tool.dart';
import 'tools/waveform_summary_tool.dart';
import 'waveform_chat_controller.dart';

/// Owns the Waveform AI assistant's open state and provider configuration.
///
/// The individual providers remain home-page adapters over the acquisition,
/// analysis, and instrument services; this controller wires them into the
/// chat controller and keeps the panel state.
class WaveformAiController {
  WaveformAiController({
    required this.chatController,
    required this.readSettings,
    required this.stopVoiceInput,
    required this.onChanged,
    required this.readVxi11Host,
    required this.instrumentDeviceContext,
    required this.readWaveformSummary,
    required this.readSpectrumSummary,
    this.readWaveformHistory,
    this.classifyWaveform,
    this.compareWaveformToReferences,
    this.readWaveformFeatures,
    this.compareWaveforms,
    this.generateReferenceWaveform,
    this.analyzeWaveformFaults,
    this.manageFaultProfile,
    this.createWaveformReport,
    this.acquireWaveform,
    this.clearMeasurementHistory,
    this.readSignalGeneratorStatus,
    this.applySignalGenerator,
    this.controlSignalGenerator,
    this.audioAnalysisContext,
    this.audioSweep,
    this.audioFrequencySeries,
    this.digitalMeasurement,
    this.digitalFrequencySeries,
  });

  final WaveformChatController chatController;
  final AiSettings? Function() readSettings;
  final void Function() stopVoiceInput;
  final void Function() onChanged;
  final String Function() readVxi11Host;
  final DeviceAgentContext? Function() instrumentDeviceContext;

  final WaveformSummaryProvider readWaveformSummary;
  final SpectrumSummaryProvider readSpectrumSummary;
  final WaveformHistoryProvider? readWaveformHistory;
  final WaveformClassificationProvider? classifyWaveform;
  final WaveformReferenceComparisonProvider? compareWaveformToReferences;
  final WaveformFeaturesProvider? readWaveformFeatures;
  final WaveformPairComparisonProvider? compareWaveforms;
  final ReferenceGenerationProvider? generateReferenceWaveform;
  final WaveformFaultAnalysisProvider? analyzeWaveformFaults;
  final WaveformFaultProfileProvider? manageFaultProfile;
  final WaveformReportProvider? createWaveformReport;
  final WaveformAcquisitionCallback? acquireWaveform;
  final VoidCallback? clearMeasurementHistory;
  final SignalGeneratorStatusProvider? readSignalGeneratorStatus;
  final SignalGeneratorApplyProvider? applySignalGenerator;
  final SignalGeneratorActionProvider? controlSignalGenerator;
  final AudioAnalysisContextProvider? audioAnalysisContext;
  final AudioSweepProvider? audioSweep;
  final AudioFrequencySeriesProvider? audioFrequencySeries;
  final DigitalMeasurementProvider? digitalMeasurement;
  final DigitalFrequencySeriesProvider? digitalFrequencySeries;

  bool _open = false;

  /// Whether the Waveform AI panel is open.
  bool get isOpen => _open;

  /// Opens or closes the panel.
  void toggle() {
    final open = !_open;
    if (!open) stopVoiceInput();
    _open = open;
    onChanged();
    chatController.setOpen(open);
  }

  /// Closes the panel if it is open.
  void close() {
    if (!_open) return;
    stopVoiceInput();
    _open = false;
    onChanged();
    chatController.setOpen(false);
  }

  /// Configures the Waveform AI assistant from the current AI settings.
  void configure() {
    chatController.configure(
      readSettings(),
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
      clearMeasurementHistory: clearMeasurementHistory,
      vxi11Host: readVxi11Host(),
      instrumentDeviceContext: instrumentDeviceContext(),
      readSignalGeneratorStatus: readSignalGeneratorStatus,
      applySignalGenerator: applySignalGenerator,
      controlSignalGenerator: controlSignalGenerator,
      audioAnalysisContext: audioAnalysisContext,
      audioSweep: audioSweep,
      audioFrequencySeries: audioFrequencySeries,
      digitalMeasurement: digitalMeasurement,
      digitalFrequencySeries: digitalFrequencySeries,
    );
  }
}
