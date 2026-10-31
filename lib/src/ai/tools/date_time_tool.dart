import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:intl/intl.dart';

import '../../core/logger.dart';

/// Supplies the current date and time; injectable for tests.
typedef DateTimeProvider = DateTime Function();

/// Creates the tool that reports the current date and time.
///
/// The `date_time` field uses the same local-time format as the timestamps
/// written by [AppLogger] (`yyyy-MM-dd HH:mm:ss.SSS`), so an agent can compare
/// it directly with lines from `sds.log`.
///
/// [now] overrides the clock and is primarily useful for tests; production
/// code uses [DateTime.now].
Tool<Map<String, dynamic>> createDateTimeTool({
  DateTimeProvider? now,
  String agentName = 'unknown',
  String name = 'current_date_time',
}) {
  final clock = now ?? DateTime.now;
  final logFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  final dateFormat = DateFormat('yyyy-MM-dd');
  final timeFormat = DateFormat('HH:mm:ss.SSS');

  return Tool<Map<String, dynamic>>(
    name: name,
    description:
        'Return the current date and time of the application host. The '
        '"date_time" field is formatted exactly like the timestamp at the '
        'start of every SDS-Remote log line (local time with milliseconds), '
        'so it can be compared directly with entries in sds.log. The result '
        'also contains the timezone name, the UTC offset, UTC in ISO 8601 and '
        'the Unix time in milliseconds. Use it whenever the user asks for the '
        'current time or when log entries must be placed in time relative to '
        'now.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, Object?>{},
    }),
    onCall: (args) async {
      final value = clock();
      final offset = value.timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
      final offsetMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(
        2,
        '0',
      );
      final result = <String, dynamic>{
        'date_time': logFormat.format(value),
        'date': dateFormat.format(value),
        'time': timeFormat.format(value),
        'timezone': value.timeZoneName,
        'utc_offset': '$sign$offsetHours:$offsetMinutes',
        'utc': value.toUtc().toIso8601String(),
        'unix_ms': value.millisecondsSinceEpoch,
      };
      AppLogger(
        agentName: agentName,
        toolName: name,
      ).logToolCall(input: const <String, dynamic>{}, output: result);
      return result;
    },
  );
}
