import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Reads recent lines of the application log.
///
/// [maxLines] caps the returned entries; with [errorsOnly] only WARNING and
/// ERROR lines are returned.
typedef LogReader =
    Future<List<String>> Function({
      required int maxLines,
      required bool errorsOnly,
    });

/// Creates the tool that lets an agent inspect the application log.
///
/// The implementation is shared by the help assistant and the instrument
/// agent; [description] phrases the tool for the owning agent. Besides the
/// error-only mode and the line limit, the agent may pass `contains` to narrow
/// the result to text it already knows — for example the SCPI command that
/// failed.
///
/// [readLog] overrides how the log is read and is primarily useful for tests;
/// production code uses [AppLogger.recentLog].
Tool<Map<String, dynamic>> createLogFileTool({
  LogReader? readLog,
  String agentName = 'unknown',
  String name = 'read_log_file',
  required String description,
  int defaultMaxLines = 80,
  int maxLinesLimit = 200,
}) {
  final reader = readLog ?? AppLogger.recentLog;
  return Tool<Map<String, dynamic>>(
    name: name,
    description: description,
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'errors_only': {
          'type': 'boolean',
          'description': 'Return only WARNING and ERROR lines (default true).',
        },
        'max_lines': {
          'type': 'integer',
          'description':
              'Maximum number of lines to return (default $defaultMaxLines, '
              'at most $maxLinesLimit).',
        },
        'contains': {
          'type': 'string',
          'description':
              'Return only lines containing this text (case-insensitive), '
              'for example the SCPI command that failed.',
        },
      },
    }),
    onCall: (args) async {
      final errorsOnly = args['errors_only'] is bool
          ? args['errors_only'] as bool
          : true;
      final requested = args['max_lines'];
      final maxLines = requested is int
          ? requested.clamp(1, maxLinesLimit).toInt()
          : defaultMaxLines;
      final containsArg = args['contains'];
      final contains = containsArg is String && containsArg.trim().isNotEmpty
          ? containsArg.trim().toLowerCase()
          : null;

      // A text filter reduces the line count after reading, so read the whole
      // window first; otherwise a sparse match could hide behind the most
      // recent non-matching lines.
      final entries = await reader(
        maxLines: contains == null ? maxLines : maxLinesLimit,
        errorsOnly: errorsOnly,
      );
      final matching = contains == null
          ? entries
          : entries
                .where((line) => line.toLowerCase().contains(contains))
                .toList();
      // Entries arrive oldest first; keep the most recent ones when the
      // filter still matches more lines than requested.
      final limited = matching.length > maxLines
          ? matching.sublist(matching.length - maxLines)
          : matching;

      AppLogger(agentName: agentName, toolName: name).logToolCall(
        input: {
          'errors_only': errorsOnly,
          'max_lines': maxLines,
          'contains': ?contains,
        },
        output: {'count': limited.length},
      );
      return {
        'count': limited.length,
        'errors_only': errorsOnly,
        'contains': ?contains,
        'entries': limited,
      };
    },
  );
}
