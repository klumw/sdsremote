import 'package:dartantic_ai/dartantic_ai.dart';

import '../../calculator/calculator_service.dart';
import '../../core/logger.dart';

/// Creates the engineering-calculator tool.
///
/// The tool exposes the same engine as the calculator window through a small,
/// JSON-only operation surface. It is deterministic and has no instrument or
/// file side effects; the workspace of [service] lives in memory unless the
/// caller supplies a persistent session.
Tool<Map<String, dynamic>> createCalculatorTool({
  String agentName = 'unknown',
  CalculatorService? service,
  void Function(Map<String, dynamic> result)? onResult,
}) {
  final calculator = service ?? CalculatorService();

  return Tool<Map<String, dynamic>>(
    name: 'calculator_tool',
    description:
        'Unit-aware engineering calculator. Use it instead of calculating '
        'in your head whenever a value has a physical unit, a dB level, a '
        'complex number, or an electronics/RF/audio/digital formula. '
        'It parses expressions with SI prefixes and dimensional checking, '
        'for example "230 mV / 10 kΩ" -> 23 µA, "20 dBm + 3 dB" -> 23 dBm, '
        '"(50 + j25) Ω", "75∠30° Ω", "1/(2*pi*10 kHz*100 nF)" and '
        '"to(20 dBm, W)". Level arithmetic rejects adding two absolute '
        'levels but permits level plus gain. '
        'Operations: evaluate an expression or program; define_variable; '
        'run_formula with a formula id from list_formulas; convert to a '
        'unit; list_variables; history. Use list_formulas to discover '
        'electronics, measurement, audio, digital and RF formula ids and '
        'their input names. For assistant use, set strict_inputs=true and '
        'provide every value the user supplied; the tool then rejects '
        'library defaults and reports missing_inputs. Never invent a result '
        'when the tool returns an error; report the error or ask for the '
        'missing input.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'enum': [
            'evaluate',
            'define_variable',
            'run_formula',
            'convert',
            'list_variables',
            'list_formulas',
            'history',
          ],
          'description':
              'evaluate: calculate an expression or multi-statement '
              'program; define_variable: store name = expression; '
              'run_formula: run a library formula; convert: convert an '
              'expression to a unit; list_variables: show stored variables; '
              'list_formulas: show the formula catalogue; history: recent '
              'calculations.',
        },
        'expression': {
          'type': 'string',
          'description':
              'Expression for evaluate or convert, or the value for '
              'define_variable, e.g. "230 mV / 10 kΩ", "R1 = 10 kΩ; '
              '1/(2*pi*R1*100 nF)" or "20 dBm".',
        },
        'name': {
          'type': 'string',
          'description': 'Variable name for define_variable, e.g. "R1".',
        },
        'formula_id': {
          'type': 'string',
          'description':
              'Formula id for run_formula, e.g. "rc_cutoff", "fspl", '
              '"link_budget". Discover ids with list_formulas.',
        },
        'inputs': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description':
              'Formula input expressions keyed by input name, e.g. '
              '{"r": "10 kΩ", "c": "100 nF"}. Omitted inputs use the '
              'library defaults unless strict_inputs is true.',
        },
        'strict_inputs': {
          'type': 'boolean',
          'description':
              'For run_formula: when true, require an explicit value for '
              'every formula input and return missing_inputs instead of '
              'using library defaults. Use true unless the user explicitly '
              'asked to use the defaults.',
        },
        'unit': {
          'type': 'string',
          'description':
              'Target unit for convert, e.g. "W", "mV", "µA", "dBm", "°C".',
        },
        'query': {
          'type': 'string',
          'description': 'Optional text filter for list_formulas.',
        },
        'category': {
          'type': 'string',
          'description':
              'Optional formula category, e.g. "RF and Antennas", '
              '"Measurement and Uncertainty", "Digital and Embedded".',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum history entries (default 20, at most 100).',
        },
      },
      'required': ['operation'],
    }),
    onCall: (args) async {
      final operation = '${args['operation'] ?? ''}';
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'calculator_tool',
      );
      Map<String, dynamic> finish(Map<String, dynamic> value) {
        final enriched = {...value, 'operation': operation};
        try {
          onResult?.call(enriched);
        } on Object catch (error) {
          logger.error('calculator_tool result callback failed: $error');
        }
        return enriched;
      }

      try {
        final Map<String, dynamic> result;
        switch (operation) {
          case 'evaluate':
            final expression = '${args['expression'] ?? ''}';
            result = calculator.evaluate(expression);
          case 'define_variable':
            final name = '${args['name'] ?? ''}'.trim();
            final expression = '${args['expression'] ?? ''}';
            if (name.isEmpty) {
              result = _error('define_variable requires a name');
            } else {
              result = calculator.defineVariable(name, expression);
            }
          case 'run_formula':
            final formulaId = '${args['formula_id'] ?? ''}'.trim();
            if (formulaId.isEmpty) {
              result = _error('run_formula requires formula_id');
            } else {
              final rawInputs = args['inputs'];
              final inputs = <String, String>{};
              if (rawInputs is Map) {
                for (final entry in rawInputs.entries) {
                  inputs['${entry.key}'] = '${entry.value}';
                }
              }
              if (args['strict_inputs'] == true) {
                final missing = _missingFormulaInputs(
                  calculator,
                  formulaId,
                  inputs,
                );
                if (missing != null && missing.isNotEmpty) {
                  result = {
                    'ok': false,
                    'error':
                        'missing formula inputs: ${missing.join(', ')}. '
                        'Ask the user for these values instead of assuming '
                        'them.',
                    'error_type': 'argument',
                    'formula_id': formulaId,
                    'missing_inputs': missing,
                  };
                } else {
                  result = calculator.runFormula(formulaId, inputs);
                }
              } else {
                result = calculator.runFormula(formulaId, inputs);
              }
            }
          case 'convert':
            final expression = '${args['expression'] ?? ''}';
            final unit = '${args['unit'] ?? ''}'.trim();
            if (unit.isEmpty) {
              result = _error('convert requires a unit');
            } else {
              result = calculator.convert(expression, unit);
            }
          case 'list_variables':
            final variables = calculator.listVariables();
            result = {
              'ok': true,
              'count': variables.length,
              'variables': variables,
            };
          case 'list_formulas':
            final formulas = calculator.listFormulas(
              query: args['query'] as String?,
              category: args['category'] as String?,
            );
            result = {
              'ok': true,
              'count': formulas.length,
              'categories': calculator.listCategories(),
              'formulas': formulas,
            };
          case 'history':
            final requested = args['limit'];
            final limit = requested is int
                ? requested.clamp(1, 100).toInt()
                : 20;
            final entries = calculator.history(limit: limit);
            result = {'ok': true, 'count': entries.length, 'entries': entries};
          default:
            result = {
              'ok': false,
              'error': 'unknown operation "$operation"',
              'error_type': 'argument',
            };
        }
        logger.logToolCall(
          input: {
            'operation': operation,
            if (args['formula_id'] != null) 'formula_id': args['formula_id'],
            if (args['expression'] != null) 'expression': args['expression'],
          },
          output: {'ok': result['ok'] == true},
        );
        return finish(result);
      } on Object catch (error) {
        logger.error('calculator_tool failed: $error');
        return finish(_error('calculator tool failed: $error'));
      }
    },
  );
}

Map<String, dynamic> _error(String message) => {
  'ok': false,
  'error': message,
  'error_type': 'argument',
};

/// Returns the formula inputs that [inputs] does not provide explicitly.
///
/// A null result means the formula id is unknown; in that case the normal
/// formula runner reports the structured "unknown formula" error.
List<String>? _missingFormulaInputs(
  CalculatorService calculator,
  String formulaId,
  Map<String, String> inputs,
) {
  Map<String, dynamic>? formula;
  for (final candidate in calculator.listFormulas(query: formulaId)) {
    if (candidate['id'] == formulaId) {
      formula = candidate;
      break;
    }
  }
  if (formula == null) return null;

  final rawInputs = formula['inputs'];
  if (rawInputs is! List) return const [];
  return [
    for (final rawInput in rawInputs)
      if (rawInput is Map &&
          '${rawInput['name'] ?? ''}'.isNotEmpty &&
          (inputs['${rawInput['name']}'] ?? '').trim().isEmpty)
        '${rawInput['name']}',
  ];
}
