/// Milestone 1 audio analysis tool set.
///
/// The agent is intentionally not built or wired here. Milestone 2 can call
/// [createAudioTools] with the acquisition context provider and an optional
/// Bode sweep provider, then register the returned tools with the Waveform
/// Agent.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'audio_advanced_tools.dart';
import 'audio_analysis_context.dart';
import 'audio_distortion_tools.dart';
import 'audio_frequency_tools.dart';
import 'audio_level_tools.dart';
import 'audio_time_domain_tools.dart';

export 'audio_analysis_context.dart';

/// All audio tool names in registration order.
const List<String> audioToolNames = [
  // A. Level and amplitude
  'measure_audio_level',
  'detect_clipping',
  'measure_dc_offset',
  'measure_frequency',
  'measure_noise_floor',
  'measure_snr',
  'measure_crest_factor',
  'measure_channel_balance',
  // B. Distortion
  'measure_thd',
  'measure_thdn',
  'measure_sinad',
  'analyze_harmonics',
  'detect_intermodulation',
  'analyze_distortion',
  // C. Frequency
  'measure_frequency_response',
  'measure_frequency_series',
  'detect_hum',
  'detect_interference',
  'analyze_spectral_peaks',
  'measure_bandwidth',
  // D. Time domain
  'measure_rise_fall_time',
  'measure_phase_difference',
  'measure_delay',
  'detect_transients',
  'detect_dropout',
  'measure_signal_stability',
  // E. Advanced
  'measure_crosstalk',
  'measure_dynamic_range',
  'measure_gain',
  'measure_phase_response',
  'measure_group_delay',
  'analyze_frequency_sweep',
  'measure_coherence',
];

/// Creates the complete Milestone 1 audio tool set.
List<Tool<Map<String, dynamic>>> createAudioTools({
  AudioAnalysisContextProvider? context,
  AudioSweepProvider? sweep,
  AudioFrequencySeriesProvider? series,
  String agentName = 'unknown',
}) {
  return [
    ...createAudioLevelTools(context: context, agentName: agentName),
    ...createAudioDistortionTools(context: context, agentName: agentName),
    ...createAudioFrequencyTools(
      context: context,
      sweep: sweep,
      series: series,
      agentName: agentName,
    ),
    ...createAudioTimeDomainTools(context: context, agentName: agentName),
    ...createAudioAdvancedTools(
      context: context,
      sweep: sweep,
      agentName: agentName,
    ),
  ];
}
