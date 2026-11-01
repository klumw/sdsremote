import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Supplies the current spectrum analysis for the AI tool.
///
/// Returns `null` when no spectrum is available, for example before the first
/// acquisition. The provider may compute the spectrum on demand.
typedef SpectrumSummaryProvider = Future<Map<String, dynamic>?> Function();

/// Creates the deterministic `read_spectrum_summary` tool.
///
/// The tool performs no analysis itself: the provider hands over the already
/// computed FFT result (settings, per-channel metrics and peaks). Without a
/// spectrum it returns a structured error instead of inventing values.
Tool<Map<String, dynamic>> createSpectrumSummaryTool({
  SpectrumSummaryProvider? readSummary,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_spectrum_summary',
    description:
        'Returns the windowed FFT analysis of the waveform currently '
        'displayed in the Acquire Waveform view. Per channel it contains the '
        'FFT size, sample rate, frequency resolution and full scale, the '
        'spectral metrics (fundamental frequency and level, THD, THD+N, SNR, '
        'SINAD, ENOB, SFDR and noise floor) and the automatic peak markers '
        'with frequency, amplitude, dBFS and dBc values. Use it for any '
        'question about frequency content, harmonics, distortion, noise or '
        'spectral peaks. Quote the returned values with their units; never '
        'invent or recalculate spectrum values. Returns an error if no '
        'spectrum is available.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'read_spectrum_summary',
      );
      final summary = await readSummary?.call();
      final result =
          summary ??
          <String, dynamic>{
            'error':
                'No spectrum available. Acquire a waveform first; the spectrum '
                'is computed from the raw acquisition.',
          };
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
