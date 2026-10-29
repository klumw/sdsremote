import 'package:dartantic_ai/dartantic_ai.dart';

import 'log_tool.dart';

/// Reads recent lines of the application log for the help assistant.
///
/// [maxLines] caps the returned entries; with [errorsOnly] only WARNING and
/// ERROR lines are returned.
typedef HelpLogReader = LogReader;

/// Creates the tool that lets the help assistant inspect the application log.
///
/// The tool turns "the application behaved strangely" into a concrete answer:
/// the assistant can quote the relevant log lines and derive a next step from
/// them, instead of guessing.
Tool<Map<String, dynamic>> createReadLogFileTool({
  HelpLogReader? readLog,
  String agentName = 'unknown',
}) {
  return createLogFileTool(
    readLog: readLog,
    agentName: agentName,
    description:
        'Return the most recent lines of the SDS-Remote application log. Use '
        'this when the user reports a problem with the application (an error '
        'message, a failed operation, a crash): inspect the log, quote the '
        'relevant lines and offer a concrete next step. By default only '
        'warning and error lines are returned; set errors_only to false to '
        'include all recent lines for context. The log file lives in the '
        'application temp directory under sds/logging/sds.log.',
  );
}
