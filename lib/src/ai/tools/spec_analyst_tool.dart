/// AI tool exposing the SpecAnalyst sub-agent to the Waveform Agent.
///
/// The tool forwards the specification text to the sub-agent. All extraction,
/// unit normalization, table generation and fault-test mapping happen in the
/// sub-agent and the deterministic specification models; the Waveform Agent
/// never derives thresholds on its own.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Extracts electrical parameters from a pasted specification.
typedef SpecificationAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required String specText,
      String? reference,
      String? sourceName,
    });

/// Registers `analyze_specification` for the Waveform Agent.
Tool<Map<String, dynamic>> createSpecificationAnalysisTool({
  SpecificationAnalysisProvider? analyze,
  String agentName = 'unknown',
}) {
  final provider = analyze;
  return Tool<Map<String, dynamic>>(
    name: 'analyze_specification',
    description:
        'Sends a specification or datasheet excerpt to the SpecAnalyst '
        'sub-agent. The sub-agent extracts the electrical characteristics and '
        'returns (1) a Markdown table, (2) a fault-analysis mapping table and '
        '(3) a `specification` object compatible with '
        'analyze_waveform_faults. Use this tool when the user pastes a '
        'specification, datasheet excerpt or electrical characteristics table '
        'for a fault-analysis request. Pass the text verbatim in `specText`; '
        'never summarize, extract or convert values yourself. `sourceName` is '
        'the document name or section for citations. If the excerpt contains '
        'several rails, pins or signals, set `reference` to the one the '
        'measured channel belongs to; otherwise the tool selects the only '
        'reference group and returns a multiple-reference warning when '
        'several groups exist. The result contains `references`, the selected '
        '`reference`, `table`, `mappingTable`, `specification`, `groups`, '
        '`parameterCount`, `mappedFieldCount` and `warnings`. Pass '
        '`specification[<test id>]` unchanged to analyze_waveform_faults. '
        'Never invent missing limits; if the result warns that no value could '
        'be mapped, ask the user instead of assuming a threshold. This tool '
        'extracts electrical data only; temperature, thermal, mechanical and '
        'environmental data are out of scope.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'specText': {
          'type': 'string',
          'description':
              'Exact specification/datasheet excerpt. Paste the original '
              'text including table headers, values, units, conditions and '
              'source references; never paraphrase, summarize or extract the '
              'values yourself. Very long documents should be reduced to the '
              'relevant electrical characteristics section.',
        },
        'reference': {
          'type': 'string',
          'description':
              'Rail, pin or signal the measured channel belongs to (for '
              'example VDD, VDDIO, SDA). Omit it when the excerpt describes '
              'only one reference; the tool then selects that reference '
              'automatically.',
        },
        'sourceName': {
          'type': 'string',
          'description':
              'Document name, revision or section for citations, if known.',
        },
      },
      'required': ['specText'],
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'analyze_specification',
      );
      final specText = _stringArg(args, 'specText');
      final reference = _stringArg(args, 'reference');
      final sourceName = _stringArg(args, 'sourceName');
      final result = provider == null
          ? <String, dynamic>{
              'error':
                  'Specification analysis is not available in this context.',
            }
          : specText == null
          ? <String, dynamic>{
              'error':
                  'specText is required. Ask the user to paste the '
                  'specification text verbatim.',
            }
          : await provider(
              specText: specText,
              reference: reference,
              sourceName: sourceName,
            );
      // Never write the complete specification text to the application log.
      logger.logToolCall(
        input: {
          'specTextCharacters': specText?.length ?? 0,
          if (reference != null) 'reference': reference,
          if (sourceName != null) 'sourceName': sourceName,
        },
        output: {
          if (result['ok'] != null) 'ok': result['ok'],
          if (result['parameterCount'] != null)
            'parameterCount': result['parameterCount'],
          if (result['reference'] != null) 'reference': result['reference'],
          if (result['mappedFieldCount'] != null)
            'mappedFieldCount': result['mappedFieldCount'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
