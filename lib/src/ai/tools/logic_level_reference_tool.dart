/// AI tool exposing the standard logic-level reference table.
///
/// The table is static and built into the application. The tool never measures
/// a signal and never invents values.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../waveform/analysis/logic_level_reference.dart';

/// Registers `read_logic_level_reference` for the DigitalAgent.
Tool<Map<String, dynamic>> createLogicLevelReferenceTool({
  String agentName = 'unknown',
}) {
  return Tool<Map<String, dynamic>>(
    name: 'read_logic_level_reference',
    description:
        'Returns the built-in standard logic-level reference table for TTL '
        '5 V, CMOS 5 V, LVTTL 3.3 V, CMOS 2.5 V, '
        'CMOS 1.8 V, ECL, RS-232 and HTL 10…30 V. Each entry contains the '
        'input thresholds VIL max / VIH min and the output levels '
        'VOL max / VOH min (or ranges for RS-232 and supply-scaled formulas '
        'for HTL). It also returns maximum edge times for Standard CMOS '
        '(4000 series), High-Speed CMOS 74HC/74HCT, Advanced CMOS '
        '74AC/74ACT, Very High-Speed CMOS 74VHC/74VHCT and Low-Voltage CMOS '
        '74LVC/74AUC, either as absolute limits at given supply voltages or '
        'as ns/V slope limits. Call it without `standard` when the user asks '
        'to check a digital signal, show the available standards and ask '
        'which one to check; then call it with the chosen `standard` (and '
        '`supplyVolts` for HTL). Use the returned logic levels as expected '
        'levels and the edge times as rise/fall limits for '
        'analyze_waveform_faults: convert absolute ns limits to seconds, and '
        'multiply a ns/V slope by the actual voltage swing. Never invent '
        'logic levels or edge times. The result names the reference source; '
        'the edge times are marked as user-provided values. '
        'For ESP32-family signals pass `esp32Variant` (esp32, esp32_s2, '
        'esp32_s3 or esp32_c3_c6) and the actual `supplyVolts` (VDD); the '
        'result contains supply-scaled VIL/VIH/VOL/VOH, drive currents, '
        'rise/fall ranges, internal pull resistors and the absolute maximum '
        'input voltage. The ESP32 values are user-provided reference values.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'standard': {
          'type': 'string',
          'enum': [for (final standard in logicLevelStandards) standard.id],
          'description':
              'Logic family to return. Omit it to list all standards and '
              'their ids.',
        },
        'supplyVolts': {
          'type': 'number',
          'description':
              'Actual supply voltage for HTL (10–30 V) or the ESP32 VDD. '
              'Ignored for the other standards.',
        },
        'esp32Variant': {
          'type': 'string',
          'enum': [for (final reference in esp32LogicReferences) reference.id],
          'description':
              'ESP32 variant whose logic and drive values are returned. '
              'Use supplyVolts for the actual VDD.',
        },
      },
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'read_logic_level_reference',
      );
      final standard = _stringArg(args, 'standard');
      final esp32Variant = _stringArg(args, 'esp32Variant');
      final supplyVolts = _numberArg(args, 'supplyVolts');
      final result = standard != null && esp32Variant != null
          ? <String, dynamic>{
              'error': 'Choose either standard or esp32Variant, not both.',
            }
          : standard != null
          ? _selectedStandard(standard, supplyVolts)
          : esp32Variant != null
          ? _selectedEsp32(esp32Variant, supplyVolts)
          : _fullTable();
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

Map<String, dynamic> _fullTable() => <String, dynamic>{
  'source': logicLevelSource,
  'unit': 'V',
  'note':
      'Values from the standard logic-level reference table (all values in '
      'volts). VIL/VIH are input thresholds; VOL/VOH are output levels. '
      'Levels between VIL and VIH are forbidden. HTL values are formulas '
      'until a supply voltage is provided.',
  'standards': [for (final standard in logicLevelStandards) standard.toMap()],
  ..._edgeTimeSection(),
  ..._esp32Section(),
};

Map<String, dynamic> _edgeTimeSection() => <String, dynamic>{
  'edgeTimeUnit': 'ns',
  'edgeTimeSource': logicEdgeTimeSource,
  'edgeTimes': [
    for (final reference in logicEdgeTimeReferences) reference.toMap(),
  ],
};

Map<String, dynamic> _esp32Section({double? supplyVolts}) => <String, dynamic>{
  'esp32Source': esp32LogicSource,
  'esp32': [
    for (final reference in esp32LogicReferences)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _selectedEsp32(String id, double? supplyVolts) {
  final reference = Esp32LogicReference.parse(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown ESP32 variant "$id". Valid variants: '
          '${esp32LogicReferences.map((entry) => entry.id).join(', ')}.',
    };
  }
  final effectiveSupply = supplyVolts ?? 3.3;
  final minimum = reference.supplyRangeVolts.first;
  final maximum = reference.supplyRangeVolts.last;
  if (effectiveSupply < minimum || effectiveSupply > maximum) {
    return <String, dynamic>{
      'error':
          '${reference.label} VDD must be between $minimum and $maximum V.',
    };
  }
  return <String, dynamic>{
    'source': esp32LogicSource,
    'unit': 'V',
    'esp32': reference.toMap(supplyVolts: effectiveSupply),
    if (supplyVolts == null) 'assumedSupplyVolts': effectiveSupply,
    if (supplyVolts == null)
      'note':
          'No VDD was supplied. The values were computed for an assumed '
          '3.3 V supply; ask the user for the actual VDD.',
  };
}

Map<String, dynamic> _selectedStandard(String id, double? supplyVolts) {
  final standard = LogicLevelStandard.parse(id);
  if (standard == null) {
    return <String, dynamic>{
      'error':
          'Unknown standard "$id". Valid standards: '
          '${logicLevelStandards.map((entry) => entry.id).join(', ')}.',
    };
  }
  final isHtl = standard.id == 'htl_10_30v';
  if (isHtl && supplyVolts != null && (supplyVolts < 10 || supplyVolts > 30)) {
    return <String, dynamic>{
      'error': 'HTL supplyVolts must be between 10 and 30 V.',
    };
  }
  final assumedSupply = isHtl && supplyVolts == null ? 24.0 : null;
  final effectiveSupply = isHtl ? supplyVolts ?? assumedSupply : null;
  return <String, dynamic>{
    'source': logicLevelSource,
    'unit': 'V',
    'standard': standard.toMap(supplyVolts: effectiveSupply),
    ..._edgeTimeSection(),
    'assumedSupplyVolts': ?assumedSupply,
    if (assumedSupply != null)
      'note':
          'HTL thresholds are supply-dependent. The values were computed for '
          'an assumed 24 V supply; ask the user for the actual supply voltage '
          '(10–30 V).',
    if (!isHtl && supplyVolts != null)
      'note': 'supplyVolts is only used for HTL and was ignored.',
  };
}

double? _numberArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

String? _stringArg(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
