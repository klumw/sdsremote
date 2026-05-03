import 'dart:io';
import 'package:intl/intl.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  static String get _logDir => '${Directory.systemTemp.path}/sds/logging';
  static String get _logFile => '$_logDir/sds.log';
  static const int _maxLogSize = 1024 * 1024; // 1MB

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

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
      await file.writeAsString(
        '[$timestamp] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      // Fallback to stderr if logging fails
      stderr.writeln('Failed to write to log file: $e');
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
