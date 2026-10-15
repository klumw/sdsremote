import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../data_logger/data_logger_models.dart' show computeGainDb;

/// Operations currently implemented by the math tool.
///
/// Adding an operation is a three-step change: list it here, add the
/// parameters it needs to the `inputSchema`, and handle it in the `switch`
/// inside `onCall`.
const List<String> mathToolOperations = ['gain_db'];

/// Creates a deterministic tool for mathematical calculations on measurement
/// values.
///
/// This tool performs no AI/LLM work — every operation is plain, deterministic
/// code, so the agent reports exact numbers instead of "reasoned" ones. Invalid
/// input is reported as a structured error map instead of throwing, so the agent
/// can react gracefully.
///
/// The `gain_db` operation reuses [computeGainDb] — the same function the Data
/// Logger uses for its Gain (dB) measurement — so both features always report
/// identical values for identical measurements.
///
/// Success response (`gain_db`):
/// ```json
/// {
///   "operation": "gain_db",
///   "signal": 1.7,
///   "reference": 0.16985,
///   "ratio": 10.00883,
///   "result": 20.00767,
///   "unit": "dB",
///   "formatted": "20.01 dB",
///   "formula": "20 * log10(signal / reference)"
/// }
/// ```
///
/// Error response:
/// ```json
/// { "error": "...", "operation": "gain_db", "signal": ..., "reference": ... }
/// ```
Tool<Map<String, dynamic>> createMathTool({String agentName = 'unknown'}) {
  return Tool<Map<String, dynamic>>(
    name: 'math_tool',
    description:
        'Deterministically calculate a value from measurement numbers. '
        'Currently supports operation "gain_db": the voltage gain in decibels '
        'between a signal voltage and a reference voltage, computed as '
        '20 * log10(signal / reference). Pass the measured numbers, never a '
        'value you derived yourself. Returns the result plus the formula used. '
        'Invalid input returns an error.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'enum': mathToolOperations,
          'description':
              '"gain_db" calculates the voltage gain in dB from "signal" and '
              '"reference" (20 * log10(signal / reference)).',
        },
        'signal': {
          'type': 'number',
          'description':
              'The measured voltage on the signal channel (CH1), in volts. '
              'Required for "gain_db".',
        },
        'reference': {
          'type': 'number',
          'description':
              'The measured voltage on the reference channel (CH2), in volts. '
              'Required for "gain_db". Must be greater than zero.',
        },
      },
      'required': ['operation', 'signal', 'reference'],
    }),
    onCall: (args) async {
      final operation = (args['operation'] as String?)?.trim() ?? '';
      final logger = AppLogger(agentName: agentName, toolName: 'math_tool');

      final result = switch (operation) {
        'gain_db' => _gainDb(args),
        _ => <String, dynamic>{
          'error': 'Unknown operation',
          'operation': operation,
          'supported': mathToolOperations,
        },
      };

      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// `gain_db` — voltage gain in decibels from a signal and a reference voltage.
Map<String, dynamic> _gainDb(Map<String, dynamic> args) {
  final signal = _asDouble(args['signal']);
  final reference = _asDouble(args['reference']);

  if (signal == null || reference == null) {
    return {
      'error':
          'gain_db requires numeric "signal" and "reference" voltages in volts',
      'operation': 'gain_db',
      'signal': args['signal'],
      'reference': args['reference'],
    };
  }

  final gain = computeGainDb(signal, reference);
  if (gain == null) {
    return {
      'error':
          'Gain is undefined: both voltages must be greater than zero '
          '(got signal=$signal, reference=$reference)',
      'operation': 'gain_db',
      'signal': signal,
      'reference': reference,
    };
  }

  return {
    'operation': 'gain_db',
    'signal': signal,
    'reference': reference,
    'ratio': signal / reference,
    'result': gain,
    'unit': 'dB',
    'formatted': '${gain.toStringAsFixed(2)} dB',
    'formula': '20 * log10(signal / reference)',
  };
}

/// Reads a numeric argument that the model may supply as a JSON number or as
/// a string (models frequently quote numbers).
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
