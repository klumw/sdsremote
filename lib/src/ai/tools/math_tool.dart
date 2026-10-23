import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../data_logger/data_logger_models.dart' show computeGainDb;
import 'math_functions.dart';

/// Names of all operations the math tool supports, in registration order.
///
/// Kept as a top-level list because the tool's error response and the tests
/// reference it directly.
List<String> get mathToolOperations => mathOperations.values
    .map((operation) => operation.name)
    .toList(growable: false);

/// One calculator or oscilloscope operation.
///
/// [signature] and [summary] are combined into the catalogue that documents
/// the `operation` argument for the model, so the schema never has to be
/// updated separately when an operation is added.
class MathOperation {
  final String name;

  /// Argument list, e.g. `a, b` — used verbatim in the catalogue.
  final String signature;

  /// What the operation computes, including its unit and any default.
  final String summary;

  final Map<String, dynamic> Function(MathArgs args) run;

  const MathOperation({
    required this.name,
    required this.signature,
    required this.summary,
    required this.run,
  });

  /// `name(signature) -> summary`, the single line describing this operation.
  String get catalogueLine => '$name($signature) -> $summary';
}

/// All operations, keyed by name. Dispatch is a map lookup, so adding an
/// operation is one entry here — no growing switch statement.
final Map<String, MathOperation> mathOperations = {
  // ---- Arithmetic ----
  'add': MathOperation(
    name: 'add',
    signature: 'a, b',
    summary: 'a + b',
    run: (args) => _ok('add', mathAdd(args.number('a'), args.number('b'))),
  ),
  'subtract': MathOperation(
    name: 'subtract',
    signature: 'a, b',
    summary: 'a - b (operand order preserved)',
    run: (args) =>
        _ok('subtract', mathSubtract(args.number('a'), args.number('b'))),
  ),
  'multiply': MathOperation(
    name: 'multiply',
    signature: 'a, b',
    summary: 'a * b',
    run: (args) =>
        _ok('multiply', mathMultiply(args.number('a'), args.number('b'))),
  ),
  'divide': MathOperation(
    name: 'divide',
    signature: 'a, b',
    summary: 'a / b (operand order preserved, b must not be zero)',
    run: (args) =>
        _ok('divide', mathDivide(args.number('a'), args.number('b'))),
  ),
  'int_divide': MathOperation(
    name: 'int_divide',
    signature: 'a, b',
    summary: 'integer division, truncated toward zero',
    run: (args) =>
        _ok('int_divide', mathIntDivide(args.number('a'), args.number('b'))),
  ),
  'modulo': MathOperation(
    name: 'modulo',
    signature: 'a, b',
    summary:
        'Euclidean modulo; the result is always non-negative and below |b|',
    run: (args) =>
        _ok('modulo', mathModulo(args.number('a'), args.number('b'))),
  ),
  'negate': MathOperation(
    name: 'negate',
    signature: 'a',
    summary: '-a',
    run: (args) => _ok('negate', mathNegate(args.number('a'))),
  ),
  'abs': MathOperation(
    name: 'abs',
    signature: 'a',
    summary: '|a|',
    run: (args) => _ok('abs', mathAbs(args.number('a'))),
  ),

  // ---- Powers and roots ----
  'square': MathOperation(
    name: 'square',
    signature: 'a',
    summary: 'a squared',
    run: (args) => _ok('square', mathSquare(args.number('a'))),
  ),
  'power': MathOperation(
    name: 'power',
    signature: 'a, b',
    summary: 'a to the power of b; a negative base needs a whole exponent',
    run: (args) => _ok('power', mathPower(args.number('a'), args.number('b'))),
  ),
  'sqrt': MathOperation(
    name: 'sqrt',
    signature: 'a',
    summary: 'square root; a must not be negative',
    run: (args) => _ok('sqrt', mathSqrt(args.number('a'))),
  ),
  'cbrt': MathOperation(
    name: 'cbrt',
    signature: 'a',
    summary: 'cube root, defined for negative values too',
    run: (args) => _ok('cbrt', mathCbrt(args.number('a'))),
  ),
  'nth_root': MathOperation(
    name: 'nth_root',
    signature: 'a, b',
    summary: 'b-th root of a; an even root of a negative value is rejected',
    run: (args) =>
        _ok('nth_root', mathNthRoot(args.number('a'), args.number('b'))),
  ),
  'reciprocal': MathOperation(
    name: 'reciprocal',
    signature: 'a',
    summary: '1 / a',
    run: (args) => _ok('reciprocal', mathReciprocal(args.number('a'))),
  ),

  // ---- Logarithms and exponentials ----
  'ln': MathOperation(
    name: 'ln',
    signature: 'a',
    summary: 'natural logarithm; a > 0',
    run: (args) => _ok('ln', mathLn(args.number('a'))),
  ),
  'log10': MathOperation(
    name: 'log10',
    signature: 'a',
    summary: 'base-10 logarithm; a > 0',
    run: (args) => _ok('log10', mathLog10(args.number('a'))),
  ),
  'log': MathOperation(
    name: 'log',
    signature: 'a, b',
    summary: 'logarithm of a to base b; a > 0, b > 0 and b != 1',
    run: (args) => _ok('log', mathLog(args.number('a'), args.number('b'))),
  ),
  'exp': MathOperation(
    name: 'exp',
    signature: 'a',
    summary: 'e to the power of a',
    run: (args) => _ok('exp', mathExp(args.number('a'))),
  ),
  'pow10': MathOperation(
    name: 'pow10',
    signature: 'a',
    summary: '10 to the power of a',
    run: (args) => _ok('pow10', mathPow10(args.number('a'))),
  ),

  // ---- Trigonometry ----
  'sin': MathOperation(
    name: 'sin',
    signature: 'a, angle_unit',
    summary: 'sine; angle_unit is "rad" (default) or "deg"',
    run: (args) => _ok('sin', mathSin(args.number('a'), args.angleUnit)),
  ),
  'cos': MathOperation(
    name: 'cos',
    signature: 'a, angle_unit',
    summary: 'cosine; angle_unit is "rad" (default) or "deg"',
    run: (args) => _ok('cos', mathCos(args.number('a'), args.angleUnit)),
  ),
  'tan': MathOperation(
    name: 'tan',
    signature: 'a, angle_unit',
    summary: 'tangent; angle_unit is "rad" (default) or "deg"',
    run: (args) => _ok('tan', mathTan(args.number('a'), args.angleUnit)),
  ),
  'asin': MathOperation(
    name: 'asin',
    signature: 'a, angle_unit',
    summary: 'arc sine in angle_unit; -1 <= a <= 1',
    run: (args) => _ok('asin', mathAsin(args.number('a'), args.angleUnit)),
  ),
  'acos': MathOperation(
    name: 'acos',
    signature: 'a, angle_unit',
    summary: 'arc cosine in angle_unit; -1 <= a <= 1',
    run: (args) => _ok('acos', mathAcos(args.number('a'), args.angleUnit)),
  ),
  'atan': MathOperation(
    name: 'atan',
    signature: 'a, angle_unit',
    summary: 'arc tangent in angle_unit',
    run: (args) => _ok('atan', mathAtan(args.number('a'), args.angleUnit)),
  ),
  'atan2': MathOperation(
    name: 'atan2',
    signature: 'a, b, angle_unit',
    summary: 'arc tangent of a (y) over b (x) in angle_unit, quadrant-correct',
    run: (args) => _ok(
      'atan2',
      mathAtan2(args.number('a'), args.number('b'), args.angleUnit),
    ),
  ),

  // ---- Rounding, aggregates and misc ----
  'floor': MathOperation(
    name: 'floor',
    signature: 'a',
    summary: 'largest integer <= a',
    run: (args) => _ok('floor', mathFloor(args.number('a'))),
  ),
  'ceil': MathOperation(
    name: 'ceil',
    signature: 'a',
    summary: 'smallest integer >= a',
    run: (args) => _ok('ceil', mathCeil(args.number('a'))),
  ),
  'round': MathOperation(
    name: 'round',
    signature: 'a',
    summary: 'rounds half away from zero',
    run: (args) => _ok('round', mathRound(args.number('a'))),
  ),
  'min': MathOperation(
    name: 'min',
    signature: 'values, or a and b',
    summary: 'smallest value',
    run: (args) => _ok('min', args.binaryOrValues(mathMinOf, 'min')),
  ),
  'max': MathOperation(
    name: 'max',
    signature: 'values, or a and b',
    summary: 'largest value',
    run: (args) => _ok('max', args.binaryOrValues(mathMaxOf, 'max')),
  ),
  'sum': MathOperation(
    name: 'sum',
    signature: 'values',
    summary: 'sum of all samples',
    run: (args) => _ok('sum', mathSum(args.samples('values'))),
  ),
  'mean': MathOperation(
    name: 'mean',
    signature: 'values',
    summary: 'arithmetic mean of all samples',
    run: (args) => _ok('mean', mathMean(args.samples('values'))),
  ),
  'clamp': MathOperation(
    name: 'clamp',
    signature: 'a, b, c',
    summary: 'a limited to the range b (low) .. c (high)',
    run: (args) => _ok(
      'clamp',
      mathClamp(args.number('a'), args.number('b'), args.number('c')),
    ),
  ),
  'hypot': MathOperation(
    name: 'hypot',
    signature: 'a, b',
    summary: 'sqrt(a^2 + b^2) without intermediate overflow',
    run: (args) => _ok('hypot', mathHypot(args.number('a'), args.number('b'))),
  ),
  'factorial': MathOperation(
    name: 'factorial',
    signature: 'a',
    summary: 'a! for whole numbers 0..170',
    run: (args) => _ok('factorial', mathFactorial(args.number('a'))),
  ),
  'deg_to_rad': MathOperation(
    name: 'deg_to_rad',
    signature: 'a',
    summary: 'converts an angle from degrees to radians',
    run: (args) =>
        _ok('deg_to_rad', toRadians(args.number('a'), 'deg'), unit: 'rad'),
  ),
  'rad_to_deg': MathOperation(
    name: 'rad_to_deg',
    signature: 'a',
    summary: 'converts an angle from radians to degrees',
    run: (args) =>
        _ok('rad_to_deg', fromRadians(args.number('a'), 'deg'), unit: 'deg'),
  ),

  // ---- Units ----
  'convert_units': MathOperation(
    name: 'convert_units',
    signature: 'a, from_unit, to_unit',
    summary:
        'converts a from one unit to another of the same dimension; both '
        'units must be known and compatible',
    run: (args) {
      final conversion = convertUnit(
        args.number('a'),
        args.text('from_unit'),
        args.text('to_unit'),
      );
      return _ok(
        'convert_units',
        conversion.value,
        unit: conversion.to.symbol,
        inputs: {
          'value_in_base_unit': conversion.baseValue,
          'base_unit': baseUnits[conversion.to.dimension],
          'from': conversion.from.symbol,
        },
      );
    },
  ),

  // ---- Oscilloscope: voltage ----
  'peak_to_peak': MathOperation(
    name: 'peak_to_peak',
    signature: 'values, or a (v_max) and b (v_min)',
    summary: 'v_max - v_min, in V',
    run: (args) => _ok(
      'peak_to_peak',
      args.peakPair((max, min) => max - min, 'peak_to_peak'),
      unit: 'V',
      formula: 'v_max - v_min',
    ),
  ),
  'peak_positive': MathOperation(
    name: 'peak_positive',
    signature: 'values, reference',
    summary: 'v_max - reference, in V; reference defaults to 0',
    run: (args) => _ok(
      'peak_positive',
      peakPositive(args.samples('values'), args.reference),
      unit: 'V',
      formula: 'v_max - reference',
    ),
  ),
  'peak_negative': MathOperation(
    name: 'peak_negative',
    signature: 'values, reference',
    summary:
        'v_min - reference, in V (negative below the reference); '
        'reference defaults to 0',
    run: (args) => _ok(
      'peak_negative',
      peakNegative(args.samples('values'), args.reference),
      unit: 'V',
      formula: 'v_min - reference',
    ),
  ),
  'peak_amplitude': MathOperation(
    name: 'peak_amplitude',
    signature: 'values, reference',
    summary:
        'largest deviation from the reference in V; equals half the '
        'peak-to-peak only for a symmetric signal',
    run: (args) => _ok(
      'peak_amplitude',
      peakAmplitude(args.samples('values'), args.reference),
      unit: 'V',
      formula: 'max(|v_max - reference|, |reference - v_min|)',
    ),
  ),
  'mean_voltage': MathOperation(
    name: 'mean_voltage',
    signature: 'values',
    summary:
        'arithmetic mean in V; equals the time-weighted mean for uniform '
        'sampling',
    run: (args) => _ok(
      'mean_voltage',
      meanVoltage(args.samples('values')),
      unit: 'V',
      formula: 'mean(values)',
    ),
  ),
  'rms_voltage': MathOperation(
    name: 'rms_voltage',
    signature: 'values',
    summary: 'RMS voltage in V, including the DC component',
    run: (args) => _ok(
      'rms_voltage',
      rmsVoltage(args.samples('values')),
      unit: 'V',
      formula: 'sqrt(sum(v^2) / N)',
    ),
  ),
  'ac_rms_voltage': MathOperation(
    name: 'ac_rms_voltage',
    signature: 'values',
    summary: 'RMS of the AC part only, with the DC component removed, in V',
    run: (args) => _ok(
      'ac_rms_voltage',
      acRmsVoltage(args.samples('values')),
      unit: 'V',
      formula: 'sqrt(mean((v - mean(v))^2))',
    ),
  ),
  'crest_factor': MathOperation(
    name: 'crest_factor',
    signature: 'values',
    summary: 'peak magnitude max(|v|) divided by RMS; dimensionless',
    run: (args) => _ok(
      'crest_factor',
      crestFactor(args.samples('values')),
      formula: 'max(|v|) / rms(v)',
    ),
  ),
  'form_factor': MathOperation(
    name: 'form_factor',
    signature: 'values',
    summary: 'RMS divided by the mean absolute voltage; dimensionless',
    run: (args) => _ok(
      'form_factor',
      formFactor(args.samples('values')),
      formula: 'rms(v) / mean(|v|)',
    ),
  ),

  // ---- Oscilloscope: time and frequency ----
  'period_from_frequency': MathOperation(
    name: 'period_from_frequency',
    signature: 'a',
    summary: '1 / a in s; a is a frequency in Hz and must be positive',
    run: (args) => _ok(
      'period_from_frequency',
      periodFromFrequency(args.number('a')),
      unit: 's',
      formula: 'T = 1 / f',
    ),
  ),
  'frequency_from_period': MathOperation(
    name: 'frequency_from_period',
    signature: 'a',
    summary: '1 / a in Hz; a is a period in s and must be positive',
    run: (args) => _ok(
      'frequency_from_period',
      frequencyFromPeriod(args.number('a')),
      unit: 'Hz',
      formula: 'f = 1 / T',
    ),
  ),
  'frequency_from_cycles': MathOperation(
    name: 'frequency_from_cycles',
    signature: 'a (cycles), b (elapsed time)',
    summary: 'a / b in Hz; both must be positive',
    run: (args) => _ok(
      'frequency_from_cycles',
      frequencyFromCycles(args.number('a'), args.number('b')),
      unit: 'Hz',
      formula: 'f = cycles / time',
    ),
  ),
  'time_difference': MathOperation(
    name: 'time_difference',
    signature: 'a (t2), b (t1)',
    summary: 'a - b in s; the operand order is preserved',
    run: (args) => _ok(
      'time_difference',
      timeDifference(args.number('a'), args.number('b')),
      unit: 's',
      formula: 'delta_t = t2 - t1',
    ),
  ),
  'duty_cycle': MathOperation(
    name: 'duty_cycle',
    signature: 'a (high time), b (period)',
    summary: '100 * a / b in %; a must not exceed b',
    run: (args) => _ok(
      'duty_cycle',
      dutyCycle(args.number('a'), args.number('b')),
      unit: '%',
      formula: '100 * high_time / period',
    ),
  ),
  'pulse_width': MathOperation(
    name: 'pulse_width',
    signature: 'a (rise timestamp), b (fall timestamp)',
    summary: 'b - a in s; the falling edge must not precede the rising one',
    run: (args) => _ok(
      'pulse_width',
      pulseWidth(args.number('a'), args.number('b')),
      unit: 's',
      formula: 't_fall - t_rise',
    ),
  ),
  'rise_time': MathOperation(
    name: 'rise_time',
    signature: 'values, sample_interval, low_percent, high_percent',
    summary:
        'time in s between the low and high thresholds of the first rising '
        'edge; the thresholds are a percentage of the waveform range and '
        'default to 10 and 90',
    run: (args) => _ok(
      'rise_time',
      riseTime(
        args.samples('values'),
        args.number('sample_interval'),
        lowPercent: args.numberOr('low_percent', 10),
        highPercent: args.numberOr('high_percent', 90),
      ),
      unit: 's',
      formula: 't(high threshold) - t(low threshold)',
    ),
  ),
  'fall_time': MathOperation(
    name: 'fall_time',
    signature: 'values, sample_interval, low_percent, high_percent',
    summary:
        'time in s between the high and low thresholds of the first falling '
        'edge; the thresholds default to 90 and 10 percent of the waveform '
        'range',
    run: (args) => _ok(
      'fall_time',
      fallTime(
        args.samples('values'),
        args.number('sample_interval'),
        lowPercent: args.numberOr('low_percent', 10),
        highPercent: args.numberOr('high_percent', 90),
      ),
      unit: 's',
      formula: 't(low threshold) - t(high threshold)',
    ),
  ),

  // ---- Oscilloscope: phase and gain ----
  'voltage_gain': MathOperation(
    name: 'voltage_gain',
    signature: 'a (v_out), b (v_in)',
    summary: 'a / b as a linear ratio, signed; b must not be zero',
    run: (args) => _ok(
      'voltage_gain',
      voltageGain(args.number('a'), args.number('b')),
      formula: 'v_out / v_in',
    ),
  ),
  'gain_db': MathOperation(
    name: 'gain_db',
    signature: 'signal, reference',
    summary:
        'voltage gain in dB, 20 * log10(signal / reference); both voltages '
        'must be greater than zero',
    run: (args) => _gainDb(args.raw),
  ),
  'power_gain_db': MathOperation(
    name: 'power_gain_db',
    signature: 'a (p_out), b (p_in)',
    summary: '10 * log10(a / b) in dB; both powers must be positive',
    run: (args) => _ok(
      'power_gain_db',
      powerGainDb(args.number('a'), args.number('b')),
      unit: 'dB',
      formula: '10 * log10(p_out / p_in)',
    ),
  ),
  'phase_shift_deg': MathOperation(
    name: 'phase_shift_deg',
    signature: 'a (delta_t), b (period)',
    summary:
        'phase shift in degrees, 360 * a / b; a positive delay means the '
        'signal lags and gives a positive shift',
    run: (args) => _ok(
      'phase_shift_deg',
      phaseShiftDegrees(args.number('a'), args.number('b')),
      unit: 'deg',
      formula: '360 * delta_t / period',
    ),
  ),
  'phase_shift_rad': MathOperation(
    name: 'phase_shift_rad',
    signature: 'a (frequency), b (delta_t)',
    summary:
        'phase shift in radians, 2 * pi * a * b; same sign convention as '
        'phase_shift_deg',
    run: (args) => _ok(
      'phase_shift_rad',
      phaseShiftRadians(args.number('a'), args.number('b')),
      unit: 'rad',
      formula: '2 * pi * frequency * delta_t',
    ),
  ),
};

/// Catalogue of every operation, one line each, used as the schema description
/// of the `operation` argument so the model can pick without guessing.
String get mathOperationCatalogue =>
    mathOperations.values.map((op) => op.catalogueLine).join('\n');

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
/// identical values for identical measurements. Its arguments (`signal`,
/// `reference`) and its result shape are unchanged from the first version of
/// this tool.
///
/// Success response:
/// ```json
/// { "operation": "...", "result": 1.5, "unit": "V",
///   "formatted": "1.5 V", "formula": "..." }
/// ```
///
/// Error response:
/// ```json
/// { "error": "<operation>: <reason>", "operation": "...", "supported": [...] }
/// ```
Tool<Map<String, dynamic>> createMathTool({String agentName = 'unknown'}) {
  return Tool<Map<String, dynamic>>(
    name: 'math_tool',
    description:
        'Deterministically calculate a value from measurement numbers or '
        'samples. Covers general arithmetic, powers, roots, logarithms, '
        'trigonometry, rounding, aggregates and unit conversion, plus '
        'oscilloscope quantities (peak, peak-to-peak, amplitude, mean, RMS, '
        'AC RMS, crest and form factor, period, frequency, duty cycle, pulse '
        'width, rise and fall time, phase shift, voltage gain in dB and power '
        'gain in dB). Pass the measured numbers, never a value you derived '
        'yourself. Returns the result with its unit and the formula used; '
        'invalid input returns a structured error.\n\n'
        'Operations:\n$mathOperationCatalogue',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'enum': mathToolOperations,
          'description':
              'The calculation to perform. See the operation '
              'catalogue in the tool description for the arguments, result '
              'unit and formula of each entry.',
        },
        'a': {
          'type': 'number',
          'description':
              'First number or operand. Its meaning depends on the '
              'operation — see the catalogue (e.g. for "divide" it is the '
              'numerator, for "period_from_frequency" the frequency in Hz).',
        },
        'b': {
          'type': 'number',
          'description':
              'Second number or operand (e.g. the denominator of '
              '"divide", the base of "log", the exponent of "power").',
        },
        'c': {
          'type': 'number',
          'description': 'Third operand, used by "clamp" as the upper bound.',
        },
        'values': {
          'type': 'array',
          'items': {'type': 'number'},
          'description':
              'Sampled measurement data, in volts for the voltage '
              'operations. Required by the operations that take "values" — '
              'see the catalogue.',
        },
        'signal': {
          'type': 'number',
          'description':
              'The measured voltage on the signal channel (CH2), in '
              'volts. Used by "gain_db" only.',
        },
        'reference': {
          'type': 'number',
          'description':
              'Either the reference voltage of "gain_db" (CH1), '
              'which must be greater than zero, or the reference level the '
              'peak operations measure against, which defaults to 0 V.',
        },
        'angle_unit': {
          'type': 'string',
          'enum': ['rad', 'deg'],
          'description':
              'Angle unit for the trigonometric operations. '
              'Defaults to "rad"; degrees are never assumed silently.',
        },
        'from_unit': {
          'type': 'string',
          'description':
              'Source unit of "convert_units", e.g. "mV". Known '
              'units: V, mV, uV, A, mA, uA, s, ms, us, ns, Hz, kHz, MHz, GHz, '
              'ohm, kohm, Mohm, W, mW, uW, J, rad, deg, %.',
        },
        'to_unit': {
          'type': 'string',
          'description':
              'Target unit of "convert_units". Must have the same '
              'dimension as from_unit, otherwise the conversion is rejected.',
        },
        'sample_interval': {
          'type': 'number',
          'description':
              'Time between two consecutive samples in seconds. '
              'Required by "rise_time" and "fall_time".',
        },
        'low_percent': {
          'type': 'number',
          'description':
              'Lower threshold as a percentage of the waveform '
              'range for "rise_time" and "fall_time". Defaults to 10.',
        },
        'high_percent': {
          'type': 'number',
          'description':
              'Upper threshold as a percentage of the waveform '
              'range for "rise_time" and "fall_time". Defaults to 90.',
        },
      },
      'required': ['operation'],
    }),
    onCall: (args) async {
      final operation = (args['operation'] as String?)?.trim() ?? '';
      final logger = AppLogger(agentName: agentName, toolName: 'math_tool');

      final entry = mathOperations[operation];
      final result = entry == null
          ? <String, dynamic>{
              'error': 'Unknown operation',
              'operation': operation,
              'supported': mathToolOperations,
            }
          : _run(entry, MathArgs(args), logger, agentName);

      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

/// Runs [operation], turning a [MathException] into a structured error that
/// names the operation. Any other exception is logged for the app and reported
/// to the agent without internals.
Map<String, dynamic> _run(
  MathOperation operation,
  MathArgs args,
  AppLogger logger,
  String agentName,
) {
  try {
    return operation.run(args);
  } on MathException catch (e) {
    return {
      'error': '${operation.name}: ${e.message}',
      'operation': operation.name,
    };
  } catch (e) {
    AppLogger(
      agentName: agentName,
      toolName: 'math_tool',
    ).log('Unexpected failure in ${operation.name}: $e');
    return {
      'error': '${operation.name}: the calculation failed unexpectedly',
      'operation': operation.name,
    };
  }
}

/// Builds a successful result with the fields every operation reports.
Map<String, dynamic> _ok(
  String operation,
  double result, {
  String unit = '',
  String? formula,
  Map<String, dynamic>? inputs,
}) {
  return {
    'operation': operation,
    'result': result,
    if (unit.isNotEmpty) 'unit': unit,
    'formatted': formatMathResult(result, unit),
    'formula': ?formula,
    ...?inputs,
  };
}

/// `gain_db` — voltage gain in decibels from a signal and a reference voltage.
///
/// Deliberately unchanged from the first version of the tool: the argument
/// names (`signal`, `reference`), the rejection of non-positive voltages and
/// the result shape all stay exactly as they were, and the calculation is the
/// shared [computeGainDb] so the Data Logger agrees.
///
/// Note that this is stricter than the generic `20 * log10(|v_out / v_in|)`:
/// amplitude and RMS quantities are never negative, so a zero or negative
/// value here means the measurement is unusable rather than a signed gain.
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
    // The voltages formatted the way the rest of the app displays them
    // ("1.71 V", "173.34 mV"), so the agent can report the measurement without
    // ever echoing the raw exponential form from the PAVA response
    // ("1.710000E+00 V").
    'signal_formatted': formatMathResult(signal, 'V'),
    'reference_formatted': formatMathResult(reference, 'V'),
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

/// Typed view over the raw tool arguments.
///
/// Accessors throw [MathException] with a message the agent can act on, and
/// never substitute a default for a value that was supplied but is invalid.
class MathArgs {
  final Map<String, dynamic> raw;
  MathArgs(this.raw);

  /// A required finite number.
  double number(String name) {
    if (!raw.containsKey(name) || raw[name] == null) {
      throw MathException('missing required argument "$name"');
    }
    return _finiteOrThrow(name, raw[name]);
  }

  /// An optional number that falls back to [fallback] only when [name] is
  /// absent. A present but invalid value is an error, not a fallback.
  double numberOr(String name, double fallback) {
    if (!raw.containsKey(name) || raw[name] == null) return fallback;
    return _finiteOrThrow(name, raw[name]);
  }

  double _finiteOrThrow(String name, Object? value) {
    final parsed = _asDouble(value);
    if (parsed == null) {
      throw MathException('"$name" must be a number (got ${_describe(value)})');
    }
    if (parsed.isNaN) {
      throw MathException('"$name" is not a number (NaN)');
    }
    if (parsed.isInfinite) {
      throw MathException('"$name" must be finite');
    }
    return parsed;
  }

  /// A required, non-empty array of finite numbers.
  List<double> samples(String name) {
    if (!raw.containsKey(name) || raw[name] == null) {
      throw MathException(
        'missing required argument "$name" (an array of numbers)',
      );
    }
    final value = raw[name];
    if (value is! List) {
      throw MathException(
        '"$name" must be an array of numbers (got ${_describe(value)})',
      );
    }
    if (value.isEmpty) {
      throw MathException('"$name" must contain at least one sample');
    }
    final parsed = <double>[];
    for (var i = 0; i < value.length; i++) {
      parsed.add(_finiteOrThrow('$name[$i]', value[i]));
    }
    return parsed;
  }

  /// [aggregate] over the `values` array when it is supplied, otherwise over
  /// the pair `a`, `b`.
  double binaryOrValues(
    double Function(List<double>) aggregate,
    String operation,
  ) {
    if (raw.containsKey('values') && raw['values'] != null) {
      return aggregate(samples('values'));
    }
    return aggregate([number('a'), number('b')]);
  }

  /// [difference] of the `values` array when supplied, otherwise of the pair
  /// `a` (maximum) and `b` (minimum).
  double peakPair(
    double Function(double max, double min) difference,
    String operation,
  ) {
    if (raw.containsKey('values') && raw['values'] != null) {
      final values = samples('values');
      return difference(mathMaxOf(values), mathMinOf(values));
    }
    return difference(number('a'), number('b'));
  }

  /// A required string.
  String text(String name) {
    final value = raw[name];
    if (value == null) {
      throw MathException('missing required argument "$name"');
    }
    if (value is! String || value.trim().isEmpty) {
      throw MathException(
        '"$name" must be a non-empty string (got ${_describe(value)})',
      );
    }
    return value.trim();
  }

  /// The angle unit for the trigonometric operations; radians by default.
  String get angleUnit {
    final value = raw['angle_unit'];
    if (value == null) return 'rad';
    if (value is! String) {
      throw MathException(
        '"angle_unit" must be "rad" or "deg" (got ${_describe(value)})',
      );
    }
    return value.trim();
  }

  /// The reference level of the peak operations; 0 V by default.
  double get reference => numberOr('reference', 0);

  static String _describe(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    return value.toString();
  }
}
