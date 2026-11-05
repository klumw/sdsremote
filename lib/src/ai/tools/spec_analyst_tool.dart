/// AI tool exposing the SpecAnalyst sub-agent to the Waveform Agent.
///
/// The tool forwards the specification text to the sub-agent. All extraction,
/// unit normalization, table generation and fault-test mapping happen in the
/// sub-agent and the deterministic specification models; the Waveform Agent
/// never derives thresholds on its own.
///
/// After a successful extraction the tool asks the user for a component or
/// family name and saves the extracted rows as an IC reference document under
/// `<app data>/ic/data`. The save is skipped when the user cancels or when no
/// name prompt is available.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../ic/ic_reference_repository.dart';
import '../../ic/ic_reference_writer.dart';
import '../../waveform/analysis/specification_models.dart';
import '../component_name_prompt.dart';

/// Extracts electrical parameters from a pasted specification.
typedef SpecificationAnalysisProvider =
    Future<Map<String, dynamic>> Function({
      required String specText,
      String? reference,
      String? sourceName,
    });

/// Saves one extracted component and returns the save result.
typedef ComponentReferenceSaveCallback =
    Future<IcReferenceSaveResult> Function({
      required String label,
      required String id,
      required bool overwrite,
      required List<SpecParameterRow> rows,
      String? sourceName,
      String? summary,
      required List<String> warnings,
    });

/// Registers `analyze_specification` for the Waveform Agent.
Tool<Map<String, dynamic>> createSpecificationAnalysisTool({
  SpecificationAnalysisProvider? analyze,
  ComponentNameProvider? requestComponentName,
  ComponentReferenceSaveCallback? saveComponent,
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
        'be mapped, ask the user instead of assuming a threshold. '
        'After a successful extraction with at least one parameter, the app '
        'asks the user for a component or family name and saves the data as '
        'an IC reference under the application data directory. If the user '
        'cancels, nothing is saved. The result then contains `savedFile`, '
        '`savedComponentId` and `savedComponentName`, or `saveSkipped`/'
        '`saveError`. Report the save result briefly; never claim that a file '
        'was saved unless `savedFile` is present. The saved component is '
        'available to the DigitalAgent through read_logic_level_reference. '
        'If the saved component was requested for an unknown digital '
        'component, call digital_analysis_agent again with the saved '
        'component name. This tool extracts electrical data only; temperature, thermal, '
        'mechanical and environmental data are out of scope.',
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

      if (result['ok'] == true && _parameterCount(result) > 0) {
        await _saveAnalysis(
          result: result,
          sourceName: sourceName,
          requestComponentName: requestComponentName,
          saveComponent: saveComponent,
          logger: logger,
        );
      }

      // Never write the complete specification text to the application log.
      logger.logToolCall(
        input: {
          'specTextCharacters': specText?.length ?? 0,
          'reference': ?reference,
          'sourceName': ?sourceName,
        },
        output: {
          if (result['ok'] != null) 'ok': result['ok'],
          if (result['parameterCount'] != null)
            'parameterCount': result['parameterCount'],
          if (result['reference'] != null) 'reference': result['reference'],
          if (result['mappedFieldCount'] != null)
            'mappedFieldCount': result['mappedFieldCount'],
          if (result['savedFile'] != null) 'savedFile': result['savedFile'],
          if (result['savedComponentId'] != null)
            'savedComponentId': result['savedComponentId'],
          if (result['saveSkipped'] != null)
            'saveSkipped': result['saveSkipped'],
          if (result['saveError'] != null) 'saveError': result['saveError'],
          if (result['error'] != null) 'error': result['error'],
        },
      );
      return result;
    },
  );
}

Future<void> _saveAnalysis({
  required Map<String, dynamic> result,
  required String? sourceName,
  required ComponentNameProvider? requestComponentName,
  required ComponentReferenceSaveCallback? saveComponent,
  required AppLogger logger,
}) async {
  final prompt = requestComponentName;
  if (prompt == null) {
    result['saveSkipped'] =
        'The component name prompt is not available in this context; the '
        'extracted data was not saved.';
    return;
  }

  ComponentNameResult nameResult;
  try {
    nameResult = await prompt(
      ComponentNameRequest(
        question:
            'Under which component or family name should the extracted '
            'electrical data be saved?',
        fileExists: icReferenceFileExists,
      ),
    );
  } on Object catch (error) {
    result['saveError'] = 'The component name prompt failed ($error).';
    return;
  }

  final name = nameResult.name?.trim();
  final id = nameResult.id?.trim();
  if (nameResult.cancelled ||
      name == null ||
      name.isEmpty ||
      id == null ||
      id.isEmpty) {
    result['saveSkipped'] =
        'The user cancelled the component name prompt; nothing was saved.';
    return;
  }

  final rows = <SpecParameterRow>[];
  final rawParameters = result['parameters'];
  if (rawParameters is List) {
    for (final raw in rawParameters) {
      if (raw is! Map) continue;
      try {
        rows.add(SpecParameterRow.fromMap(Map<String, dynamic>.from(raw)));
      } on FormatException {
        // The analysis result already validated its rows; skip malformed ones.
      }
    }
  }

  final save = saveComponent ?? _defaultSaveComponent;
  IcReferenceSaveResult saveResult;
  try {
    saveResult = await save(
      label: name,
      id: id,
      overwrite: nameResult.overwrite,
      rows: rows,
      sourceName: sourceName,
      summary: result['summary'] is String ? result['summary'] as String : null,
      warnings: _stringList(result['warnings']),
    );
  } on Object catch (error) {
    result['saveError'] = 'The IC reference could not be saved ($error).';
    return;
  }

  result.addAll(saveResult.toMap());
  if (!saveResult.saved) return;
  result['savedComponentId'] = id;
  result['savedComponentName'] = name;

  try {
    await IcReferenceRepository.instance.reload();
    result['catalogReloaded'] = true;
    final catalogWarnings = IcReferenceRepository.instance.warnings;
    if (catalogWarnings.isNotEmpty) {
      result['catalogWarnings'] = catalogWarnings;
    }
  } on Object catch (error) {
    result['catalogReloadWarning'] =
        'The component was saved but the IC catalog could not be reloaded; '
        'it is available after the next restart ($error).';
  }
  logger.log('Saved IC reference "$id" to ${saveResult.filePath ?? 'unknown'}');
}

Future<IcReferenceSaveResult> _defaultSaveComponent({
  required String label,
  required String id,
  required bool overwrite,
  required List<SpecParameterRow> rows,
  String? sourceName,
  String? summary,
  required List<String> warnings,
}) => saveComponentReference(
  label: label,
  id: id,
  overwrite: overwrite,
  rows: rows,
  sourceName: sourceName,
  summary: summary,
  warnings: warnings,
);

int _parameterCount(Map<String, dynamic> result) {
  final value = result['parameterCount'];
  return value is num ? value.toInt() : 0;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is String && entry.trim().isNotEmpty) entry,
  ];
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
