/// AI tool that creates the existing waveform PDF measurement report.
///
/// The tool only forwards the report name and an optional plain-text analysis
/// to the provider. The provider is implemented by the Acquire Waveform view,
/// because the report needs the rendered chart image and the current
/// acquisition state.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Generates and saves the waveform PDF report.
///
/// Returns `saved: true` with `fileName` and `path` on success, or an `error`
/// entry when no waveform is displayed or the report cannot be written.
typedef WaveformReportProvider =
    Future<Map<String, dynamic>> Function({
      String? reportName,
      String? analysis,
    });

/// Registers `create_waveform_report` for the Waveform Agent.
Tool<Map<String, dynamic>> createWaveformReportTool({
  WaveformReportProvider? createReport,
  String agentName = 'unknown',
}) {
  final provider = createReport;
  return Tool<Map<String, dynamic>>(
    name: 'create_waveform_report',
    description:
        'Creates and saves the existing waveform measurement PDF report for '
        'the current acquisition. The report contains the chart image, the '
        'automatic time-domain measurements, the spectrum analysis, the '
        'device parameters, the reference comparison and the mask result. '
        'Optionally pass `reportName` (used as the default file name prefix, '
        'or as the pre-filled value in the filename dialog) and a short '
        'plain-text `analysis`; the analysis is added to the PDF as an Agent '
        'Analysis section and must be written in English. The PDF report is '
        'English-only. Call this tool only after the user has explicitly '
        'confirmed that a PDF report should be created. If no waveform is '
        'displayed, the tool returns an error; ask the user to acquire a '
        'waveform first. When the application setting "Ask for filename on '
        'save" is enabled, the tool opens the filename dialog; if the user '
        'cancels, the result contains `cancelled` and no report is saved. The '
        'tool returns `saved`, `fileName` and `path` on success. Never claim '
        'that a report was saved unless the result contains saved true.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'reportName': {
          'type': 'string',
          'description':
              'Optional report name. Used as the default file name prefix, or '
              'as the pre-filled value in the filename dialog. Keep it short '
              'and avoid path separators.',
        },
        'analysis': {
          'type': 'string',
          'description':
              'Optional short plain-text summary of the measurement and '
              'findings. Do not use Markdown or HTML. It is added to the PDF '
              'as an Agent Analysis section and must be written in English.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'create_waveform_report',
      );
      if (provider == null) {
        const result = <String, dynamic>{
          'error':
              'Report generation is not available in this context. Ask the '
              'user to use the application save action instead.',
        };
        await logger.logToolCall(
          input: args,
          output: {'error': result['error']},
        );
        return result;
      }

      final reportName = _trimmedOrNull(args['reportName']);
      final analysis = _trimmedOrNull(args['analysis']);
      final result = await provider(reportName: reportName, analysis: analysis);
      await logger.logToolCall(
        input: {
          'reportName': ?reportName,
          'analysisCharacters': ?analysis?.length,
        },
        output: result,
      );
      return result;
    },
  );
}

String? _trimmedOrNull(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
