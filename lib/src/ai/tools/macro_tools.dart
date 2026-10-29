import 'package:dartantic_ai/dartantic_ai.dart';

import '../../app/app_preferences.dart';
import '../../core/logger.dart';
import '../../macro/macro_linter.dart';
import '../../macro/macro_oscope_status.dart';

/// Reads the macro currently open in the editor.
typedef MacroReader = String Function();

/// Replaces the macro currently open in the editor.
///
/// Returns `true` when the content was applied. The editor implementation
/// returns `false` when it has already been disposed.
typedef MacroWriter = bool Function(String content);

/// Runs the macro linter and converts its errors into agent-friendly maps.
///
/// The linter reports both syntax errors and semantic problems (undefined
/// variables, non-numeric relational comparisons, …). Line numbers are 1-based.
List<Map<String, dynamic>> _lintErrors(String content) {
  return [
    for (final error in lintMacro(content))
      {'line': error.line, 'message': error.message},
  ];
}

/// Number of lines in [text]. Matches the editor's gutter counting: an empty
/// document has one (empty) line, and a trailing newline opens another line.
int _lineCount(String text) => text.split('\n').length;

/// Creates the tool that lets the macro agent read the editor content.
///
/// The [readMacro] callback is captured so the tool always returns the current
/// editor text, not a snapshot taken when the agent was created.
Tool<Map<String, dynamic>> createReadMacroTool({
  required MacroReader readMacro,
  String? Function()? macroFileName,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_macro',
    description:
        'Return the complete content of the macro currently open in the Macro '
        'Editor, together with its line count and file name (if it has been '
        'saved). Call this before changing the macro and whenever you need to '
        're-check the current state.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final content = readMacro();
      final fileName = macroFileName?.call();
      final result = <String, dynamic>{
        'content': content,
        'line_count': _lineCount(content),
        'file_name': (fileName == null || fileName.isEmpty) ? null : fileName,
      };
      AppLogger(agentName: agentName, toolName: 'read_macro').logToolCall(
        input: const {},
        output: {
          'line_count': result['line_count'],
          'file_name': result['file_name'],
        },
      );
      return result;
    },
  );
}

/// Creates the tool that lets the macro agent replace the editor content.
///
/// The agent must send the complete file, never a fragment: the editor content
/// is replaced as a whole. Any lint errors in the new content are returned so
/// the model can fix them in a follow-up call.
Tool<Map<String, dynamic>> createWriteMacroTool({
  required MacroWriter writeMacro,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'write_macro',
    description:
        'Replace the COMPLETE content of the macro currently open in the '
        'Macro Editor with the given content. Send the whole file, never a '
        'fragment or a diff. The editor updates immediately and the macro is '
        'marked as modified. Returns whether the write was applied and the '
        'lint errors (with line numbers) found in the new content. If errors '
        'are returned, fix them and call write_macro again.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'content': {
          'type': 'string',
          'description':
              'The complete new macro file content, including the existing '
              'connect() line and all commands that should be kept.',
        },
      },
      'required': ['content'],
    }),
    onCall: (args) async {
      final content = args['content'] as String? ?? '';
      final applied = writeMacro(content);
      final errors = _lintErrors(content);
      final result = <String, dynamic>{
        'applied': applied,
        'line_count': _lineCount(content),
        'valid': errors.isEmpty,
        'errors': errors,
      };
      AppLogger(agentName: agentName, toolName: 'write_macro').logToolCall(
        input: {'content_length': content.length},
        output: {
          'applied': applied,
          'line_count': result['line_count'],
          'valid': result['valid'],
          'error_count': errors.length,
        },
      );
      return result;
    },
  );
}

/// Reads the current signal-generator settings and status for the agent.
///
/// The map uses the keys of [createReadSiggenStatusTool]: at least
/// `configured_device`, `supported`, `detected` and `connected`.
typedef MacroSiggenStatusReader = Future<Map<String, dynamic>> Function();

/// Fallback status source when the host did not register a live provider.
///
/// Reads the persisted generator selection. The live connection state is only
/// available from the application's signal-generator service, so it is
/// reported as disconnected.
Future<Map<String, dynamic>> readStoredSiggenStatus() async {
  final device = await AppPreferences.getString('siggen_device') ?? 'none';
  final port = await AppPreferences.getString('siggen_port');
  return <String, dynamic>{
    'configured_device': device,
    'supported': device == 'jds6600' || device == 'fy6900',
    'detected': false,
    'connected': false,
    'port': port,
    'model': null,
    'identity': null,
    'status_available': false,
  };
}

/// Creates the tool that reports the signal-generator settings and status.
///
/// The agent needs the configured type (JDS6600 or FY6900) to choose the
/// correct waveform list and to know whether `connect(SIG, usb)` will work.
Tool<Map<String, dynamic>> createReadSiggenStatusTool({
  MacroSiggenStatusReader? readStatus,
  String agentName = 'unknown',
}) {
  final reader = readStatus ?? readStoredSiggenStatus;
  return Tool<Map<String, dynamic>>(
    name: 'read_siggen_status',
    description:
        'Return the current signal-generator settings and status: the type '
        'selected in Settings -> Signal Generator (none, jds6600 or fy6900), '
        'whether it is detected and connected, the serial port, model, '
        'identity, cached channel settings, outputs and the last error. Call '
        'this before writing cmd(SIG, ...) or query(SIG, ...) commands, or '
        'when answering questions about the generator.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final result = await reader();
      AppLogger(
        agentName: agentName,
        toolName: 'read_siggen_status',
      ).logToolCall(
        input: const {},
        output: {
          'configured_device': result['configured_device'],
          'connected': result['connected'],
        },
      );
      return result;
    },
  );
}

/// Reads the current oscilloscope connection and model for the agent.
///
/// The host registers a live provider that reports whether the connection is
/// active and, while it is, the model detected from `*IDN?`, the display name,
/// the channel count, the transport and the address.
typedef MacroOscilloscopeStatusReader = Future<Map<String, dynamic>> Function();

/// Creates the tool that reports the oscilloscope connection and model.
///
/// This is the oscilloscope counterpart of [createReadSiggenStatusTool].
/// Without a registered provider it reports a disconnected instrument.
Tool<Map<String, dynamic>> createReadOscilloscopeStatusTool({
  MacroOscilloscopeStatusReader? readStatus,
  String agentName = 'unknown',
}) {
  final reader = readStatus ?? readUnavailableOscilloscopeStatus;
  return Tool<Map<String, dynamic>>(
    name: 'read_oscilloscope_status',
    description:
        'Return whether the oscilloscope connection is active and, when it '
        'is, the detected model (for example SDS1202X-E), its display name, '
        'the channel count, the transport (network or usb) and the address. '
        'Call this before answering questions about the connected '
        'oscilloscope or before writing commands that depend on its model or '
        'channel count.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final result = await reader();
      AppLogger(
        agentName: agentName,
        toolName: 'read_oscilloscope_status',
      ).logToolCall(
        input: const {},
        output: {'connected': result['connected'], 'model': result['model']},
      );
      return result;
    },
  );
}

/// Creates the tool that lints macro source without changing the editor.
///
/// With no `content` argument it validates the macro currently open in the
/// editor; with `content` it validates a candidate version before writing it.
Tool<Map<String, dynamic>> createValidateMacroTool({
  required MacroReader readMacro,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'validate_macro',
    description:
        'Parse and lint macro source and return syntax or semantic errors with '
        '1-based line numbers. Omit "content" to validate the macro currently '
        'open in the editor, or pass "content" to check a candidate version '
        'before writing it.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'content': {
          'type': 'string',
          'description':
              'Optional macro source to validate. When omitted, the macro '
              'currently open in the editor is validated.',
        },
      },
    }),
    onCall: (args) async {
      final supplied = args['content'];
      final checksCurrentContent = supplied is! String;
      final content = checksCurrentContent ? readMacro() : supplied;
      final errors = _lintErrors(content);
      final result = <String, dynamic>{
        'valid': errors.isEmpty,
        'errors': errors,
        'checked_current_content': checksCurrentContent,
        'line_count': _lineCount(content),
      };
      AppLogger(agentName: agentName, toolName: 'validate_macro').logToolCall(
        input: {'content_length': content.length},
        output: {
          'valid': result['valid'],
          'error_count': errors.length,
          'checked_current_content': checksCurrentContent,
        },
      );
      return result;
    },
  );
}

/// Reads the variables of the current macro run — the same name/value pairs
/// the Macro Editor shows in its Variables panel.
typedef MacroVariablesReader = Map<String, String> Function();

/// Reads the `print()` output of the current macro run — the same lines the
/// Macro Editor shows in its Print Output panel.
typedef MacroPrintOutputReader = List<String> Function();

/// Reads the recent warning and error lines of the application log.
typedef MacroErrorLogReader = Future<List<String>> Function();

/// Creates the tool that returns the variables of the current macro run.
Tool<Map<String, dynamic>> createReadMacroVariablesTool({
  required MacroVariablesReader readVariables,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_macro_variables',
    description:
        'Return the variables of the current macro run — the same name/value '
        'pairs the Macro Editor shows in its Variables panel. Call this after '
        'a playback or debug step to inspect the values a macro produced '
        'instead of asking the user. Returns an empty list before any run has '
        'assigned variables.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final variables = readVariables();
      final entries = [
        for (final entry in variables.entries)
          {'name': entry.key, 'value': entry.value},
      ];
      AppLogger(
        agentName: agentName,
        toolName: 'read_macro_variables',
      ).logToolCall(
        input: const {},
        output: {'count': entries.length, 'names': variables.keys.toList()},
      );
      return {'count': entries.length, 'variables': entries};
    },
  );
}

/// Creates the tool that returns the print output of the current macro run.
Tool<Map<String, dynamic>> createReadPrintOutputTool({
  required MacroPrintOutputReader readPrintOutput,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_print_output',
    description:
        'Return the output of the print() statements of the current macro run '
        '— the same lines the Macro Editor shows in its Print Output panel, in '
        'output order. Call this to read computed or measured values a macro '
        'logged. Returns an empty list before any print() statement ran.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final messages = readPrintOutput();
      AppLogger(
        agentName: agentName,
        toolName: 'read_print_output',
      ).logToolCall(input: const {}, output: {'count': messages.length});
      return {'count': messages.length, 'messages': messages};
    },
  );
}

/// Creates the tool that returns the current warning/error log.
Tool<Map<String, dynamic>> createReadErrorLogTool({
  required MacroErrorLogReader readErrorLog,
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_error_log',
    description:
        'Return the most recent warning and error entries of the application '
        'log, oldest first. This includes macro playback errors and the SCPI '
        'errors that stopped a run. Call this when a macro failed or the user '
        'reports an error, to quote the exact message instead of guessing.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final entries = await readErrorLog();
      AppLogger(
        agentName: agentName,
        toolName: 'read_error_log',
      ).logToolCall(input: const {}, output: {'count': entries.length});
      return {'count': entries.length, 'entries': entries};
    },
  );
}
