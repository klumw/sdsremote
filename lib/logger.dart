import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';

/// Application logger for the SDS-Remote application.
///
/// Writes log entries to a file in the system temp directory. Each instance
/// carries its own [agentName] and [toolName] context so that concurrent
/// loggers do not overwrite each other's identity. All instances share the
/// same underlying log file via static paths.
class AppLogger {
  /// Optional agent name for context in structured logging.
  final String? agentName;

  /// Optional tool name for context in structured logging.
  final String? toolName;

  /// Creates a logger instance with optional agent/tool context.
  ///
  /// The [agentName] and [toolName] identify the source of log messages and
  /// are included in every log line written through this instance.
  ///
  /// Usage:
  /// ```dart
  /// final logger = AppLogger(agentName: 'FrontendAgent', toolName: 'send');
  /// logger.log('Some message');
  /// logger.logToolCall(input: {...}, output: {...});
  /// ```
  AppLogger({this.agentName, this.toolName});

  static String get _logDir => '${Directory.systemTemp.path}/sds/logging';
  static String get _logFile => '$_logDir/sds.log';
  static const int _maxLogSize = 1024 * 1024; // 1MB

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  /// Builds a prefix string from agentName and toolName if set.
  String _buildPrefix() {
    if (agentName != null && toolName != null) {
      return '[$agentName.$toolName]';
    } else if (agentName != null) {
      return '[$agentName]';
    } else if (toolName != null) {
      return '[$toolName]';
    }
    return '';
  }

  Future<void> log(String message) async {
    try {
      final directory = Directory(_logDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File(_logFile);
      if (await file.exists()) {
        final size = await file.length();
        if (size > _maxLogSize) {
          await _rotateLogs(file);
        }
      }

      final timestamp = _dateFormat.format(DateTime.now());
      final prefix = _buildPrefix();
      final line = prefix.isNotEmpty ? '[$timestamp] $prefix $message\n' : '[$timestamp] $message\n';
      await file.writeAsString(
        line,
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Fallback to stderr if logging fails
      stderr.writeln('Failed to write to log file: $e');
    }
  }

  /// Logs a tool call with structured input/output data.
  ///
  /// This is used by AI agent tools to log their invocations with the
  /// input arguments and output results.
  Future<void> logToolCall({
    required Map<String, dynamic> input,
    required Map<String, dynamic> output,
  }) async {
    try {
      final directory = Directory(_logDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File(_logFile);
      if (await file.exists()) {
        final size = await file.length();
        if (size > _maxLogSize) {
          await _rotateLogs(file);
        }
      }

      final timestamp = _dateFormat.format(DateTime.now());
      final prefix = _buildPrefix();
      final inputJson = const JsonEncoder.withIndent('  ').convert(input);
      final outputJson = const JsonEncoder.withIndent('  ').convert(output);
      final line = prefix.isNotEmpty
          ? '[$timestamp] $prefix ToolCall:\n  Input: $inputJson\n  Output: $outputJson\n'
          : '[$timestamp] ToolCall:\n  Input: $inputJson\n  Output: $outputJson\n';
      await file.writeAsString(
        line,
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Fallback to stderr if logging fails
      stderr.writeln('Failed to write tool call log: $e');
    }
  }

  Future<void> _rotateLogs(File currentFile) async {
    try {
      final oldFile = File('$_logFile.old');
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      await currentFile.rename('$_logFile.old');
    } catch (e) {
      stderr.writeln('Failed to rotate logs: $e');
    }
  }
}
