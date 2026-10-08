import 'package:dartantic_ai/dartantic_ai.dart';

import '../../../logger.dart';
import '../../measurement.dart';

/// Creates a deterministic tool that parses an oscilloscope PAVA measurement
/// response string into structured data.
///
/// This tool performs no AI/LLM work — parsing and unit handling are pure,
/// deterministic code ([parseMeasurement]). Invalid input is reported as a
/// structured error map instead of throwing, so the agent can react gracefully.
///
/// Success response:
/// ```json
/// {
///   "channel": "C1",
///   "measurement": "PKPK",
///   "value": 3.0,
///   "unit": "V",
///   "formatted": "3 V"
/// }
/// ```
///
/// Error response:
/// ```json
/// { "error": "Invalid measurement format", "raw": "...", "detail": "..." }
/// ```
Tool<Map<String, dynamic>> createMeasurementTool({
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'parse_measurement',
    description:
        'Deterministically parse a Siglent oscilloscope PAVA measurement '
        'response into structured data. Expects a raw string such as '
        '"C1:PAVA PKPK,3.000000E+00V" or "C1:PAVA FREQ,9.998900E+02Hz". '
        'Returns the channel, measurement type, numeric value, unit, and a '
        'human-readable formatted string. Invalid input returns an error.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'raw': {
          'type': 'string',
          'description':
              'The raw measurement response string to parse, e.g. '
              '"C1:PAVA PKPK,3.000000E+00V".',
        },
      },
      'required': ['raw'],
    }),
    onCall: (args) async {
      final raw = (args['raw'] as String?)?.trim() ?? '';
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'parse_measurement',
      );

      try {
        final measurement = parseMeasurement(raw);
        final result = <String, dynamic>{
          'channel': measurement.channel,
          'measurement': measurement.measurement,
          'value': measurement.value,
          'unit': measurement.unit,
          'formatted': formatMeasurement(measurement),
        };
        logger.logToolCall(input: args, output: result);
        return result;
      } on FormatException catch (e) {
        final errorResult = <String, dynamic>{
          'error': 'Invalid measurement format',
          'raw': raw,
          'detail': e.message,
        };
        logger.logToolCall(input: args, output: errorResult);
        return errorResult;
      }
    },
  );
}
