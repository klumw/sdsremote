import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

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

  static const Level traceLevel = Level('TRACE', 300);
  static const Level _defaultLevel = Level.INFO;
  static Level minimumLevel = _defaultLevel;

  /// Parses a user-provided log level name.
  ///
  /// Supported values: TRACE, DEBUG, INFO, WARNING, WARN, ERROR, SEVERE, OFF.
  /// Unrecognized values fall back to [Level.INFO].
  static Level parseLevel(String? levelName) {
    if (levelName == null || levelName.trim().isEmpty) {
      return _defaultLevel;
    }

    switch (levelName.trim().toUpperCase()) {
      case 'TRACE':
        return traceLevel;
      case 'DEBUG':
      case 'FINE':
        return Level.FINE;
      case 'INFO':
        return Level.INFO;
      case 'WARNING':
      case 'WARN':
        return Level.WARNING;
      case 'ERROR':
      case 'SEVERE':
        return Level.SEVERE;
      case 'OFF':
        return Level.OFF;
      default:
        return _defaultLevel;
    }
  }

  static String get _logDir => '${Directory.systemTemp.path}/sds/logging';
  static String get _logFile => '$_logDir/sds.log';
  static const int _maxLogSize = 1024 * 1024; // 1MB

  /// Sequential write queue — ensures concurrent log calls never interleave
  /// their byte output within the shared log file.
  static Future<void> _writeQueue = Future.value();

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

  bool _shouldLog(Level level) => level.value >= minimumLevel.value;

  Future<void> _writeLine(Level level, String message) {
    // Chain onto the static sequential queue so concurrent calls from
    // different loggers (or unawaited calls from the same logger) never
    // interleave their bytes in the shared log file.
    return _writeQueue = _writeQueue.then((_) async {
      if (!_shouldLog(level)) return;

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
        final levelName = _formatLevelName(level);
        final line = prefix.isNotEmpty
            ? '[$timestamp] [$levelName] $prefix $message\n'
            : '[$timestamp] [$levelName] $message\n';
        // NOTE: flush:true is omitted intentionally. On Windows,
        // FlushFileBuffers forces a synchronous disk sync on every write,
        // which is orders of magnitude slower than Linux's fsync and
        // causes 4-5 second delays during application close when the
        // write queue still has pending entries. The OS will flush the
        // file buffer on close anyway.
        await file.writeAsString(line, mode: FileMode.append);
      } catch (e) {
        // Fallback to stderr if logging fails
        stderr.writeln('Failed to write to log file: $e');
      }
    });
  }

  String _formatLevelName(Level level) {
    if (level == traceLevel) return 'TRACE';
    if (level == Level.FINE) return 'DEBUG';
    return level.name;
  }

  Future<void> log(String message) async => _writeLine(Level.INFO, message);
  Future<void> info(String message) async => _writeLine(Level.INFO, message);
  Future<void> debug(String message) async => _writeLine(Level.FINE, message);
  Future<void> trace(String message) async => _writeLine(traceLevel, message);
  Future<void> warning(String message) async =>
      _writeLine(Level.WARNING, message);
  Future<void> severe(String message) async =>
      _writeLine(Level.SEVERE, message);

  /// Logs a tool call with structured input/output data.
  ///
  /// This is used by AI agent tools to log their invocations with the
  /// input arguments and output results.
  Future<void> logToolCall({
    required Map<String, dynamic> input,
    required Map<String, dynamic> output,
  }) {
    return _writeQueue = _writeQueue.then((_) async {
      if (!_shouldLog(Level.FINE)) return;

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
            ? '[$timestamp] [DEBUG] $prefix ToolCall:\n  Input: $inputJson\n  Output: $outputJson\n'
            : '[$timestamp] [DEBUG] ToolCall:\n  Input: $inputJson\n  Output: $outputJson\n';
        await file.writeAsString(line, mode: FileMode.append);
      } catch (e) {
        // Fallback to stderr if logging fails
        stderr.writeln('Failed to write tool call log: $e');
      }
    });
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
