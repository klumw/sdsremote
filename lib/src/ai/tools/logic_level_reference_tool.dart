/// AI tool exposing the logic-level and IC reference tables.
///
/// All reference values are loaded from `assets/ic/data`. The tool never
/// measures a signal and never invents values.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../../ic/ic_reference_catalog.dart';
import '../../ic/ic_reference_repository.dart';
import '../../waveform/analysis/logic_level_reference.dart';

/// Registers `read_logic_level_reference` for the DigitalAgent.
///
/// MCU values come from the catalog loaded from `assets/ic/data`. When
/// [catalog] is omitted, the process-wide repository is used. If neither is
/// available, the tool returns an error instead of inventing values.
Tool<Map<String, dynamic>> createLogicLevelReferenceTool({
  String agentName = 'unknown',
  IcReferenceCatalog? catalog,
}) {
  final icCatalog = catalog ?? IcReferenceRepository.instance.catalogOrNull;
  final standards = icCatalog?.standards ?? const <LogicLevelStandard>[];
  final esp32Variants =
      icCatalog?.esp32Variants ?? const <Esp32LogicReference>[];
  final stm32Series = icCatalog?.stm32Series ?? const <Stm32LogicReference>[];
  final raspberryPiMcus =
      icCatalog?.raspberryPiMcus ?? const <RaspberryPiLogicReference>[];
  final gowinFpgas = icCatalog?.gowinFpgas ?? const <GowinFpgaReference>[];
  final xilinxFpgas = icCatalog?.xilinxFpgas ?? const <XilinxFpgaReference>[];
  final latticeFpgas =
      icCatalog?.latticeFpgas ?? const <LatticeFpgaReference>[];
  return Tool<Map<String, dynamic>>(
    name: 'read_logic_level_reference',
    description:
        'Returns the bundled standard logic-level reference table for TTL '
        '5 V, TTL-compatible CMOS 5 V, CMOS 5 V, CMOS 2.5 V, CMOS 1.8 V, '
        'CMOS 1.2 V, CMOS 0.8 V, LVTTL 3.3 V, ECL, RS-232, HTL 10…30 V and '
        'the 5 V Schmitt-trigger variants. Each entry contains the input '
        'thresholds VIL max / VIH min and the output levels '
        'VOL max / VOH min (or ranges for RS-232 and supply-scaled formulas '
        'for HTL), plus the typical switching threshold Vt or the '
        'Schmitt-trigger thresholds Vt+ max / Vt- min when available. It '
        'also returns maximum edge times for Standard CMOS '
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
        'the TI Logic Guide values, the switching-threshold values and the '
        'edge times each carry their own source label. '
        'For ESP32-family signals pass `esp32Variant` with one of the ids '
        'listed in its enum and the actual `supplyVolts` (VDD); the result '
        'contains supply-scaled VIL/VIH/VOL/VOH, drive currents, rise/fall '
        'ranges, internal pull resistors and the absolute maximum input '
        'voltage. The ESP32 values are user-provided reference values. '
        'For STM32-family signals pass `stm32Series` with one of the ids '
        'listed in its enum and the actual `supplyVolts` (VDD); the result '
        'contains supply-scaled VIL/VIH/VOL/VOH, drive currents, pull '
        'resistors and the absolute maximum input voltage. The STM32 values '
        'come from the STMicroelectronics datasheets on st.com. '
        'For Raspberry Pi MCUs pass `raspberryPiMcu` with one of the ids '
        'listed in its enum and the actual IOVDD; the result contains the '
        '1.8 V, 2.5 V and 3.3 V I/O points, drive strengths, pull resistors '
        'and the absolute maximum input voltage. The values come from the '
        'official RP2040/RP2350 datasheets on raspberrypi.com. '
        'For Gowin FPGAs pass `gowinFpga` with one of the ids listed in its '
        'enum and optionally the bank VCCIO; the result contains the '
        'supported LVCMOS33/25/18/15/12, LVTTL33, VIL/VIH/VOL/VOH, drive '
        'strengths and absolute maximum input voltage. The values come from '
        'the official Gowin GW1N/GW2A/GW5A datasheets on gowinsemi.com. '
        'For AMD/Xilinx FPGAs pass `xilinxFpga` with one of the ids listed '
        'in its enum and optionally the bank VCCO; the result contains the '
        'supported LVCMOS/LVTTL levels, drive strengths and absolute maximum '
        'input voltage. The values come from the AMD/Xilinx 7 Series (DS181) '
        'and UltraScale+ (DS925) datasheets on docs.amd.com. '
        'For Lattice FPGAs pass `latticeFpga` with one of the ids listed in '
        'its enum and optionally the bank VCCIO; the result contains the '
        'supported LVCMOS/LVTTL levels, drive strengths and absolute maximum '
        'input voltage. The values come from the official Lattice '
        'iCE40/MachXO2/MachXO3/ECP5 datasheets on latticesemi.com.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': {
        'standard': {
          'type': 'string',
          'enum': [for (final standard in standards) standard.id],
          'description':
              'Logic family to return. Omit it to list all standards and '
              'their ids.',
        },
        'supplyVolts': {
          'type': 'number',
          'description':
              'Actual supply voltage for HTL (10–30 V), the ESP32 VDD, the '
              'STM32 VDD, the Raspberry Pi IOVDD, the Gowin bank VCCIO, the '
              'AMD/Xilinx bank VCCO or the Lattice bank VCCIO. Ignored for '
              'the other standards.',
        },
        'esp32Variant': {
          'type': 'string',
          'enum': [for (final reference in esp32Variants) reference.id],
          'description':
              'ESP32 variant whose logic and drive values are returned. '
              'Use supplyVolts for the actual VDD.',
        },
        'stm32Series': {
          'type': 'string',
          'enum': [for (final reference in stm32Series) reference.id],
          'description':
              'STM32 series whose logic, drive and pull values are returned. '
              'Use supplyVolts for the actual VDD.',
        },
        'raspberryPiMcu': {
          'type': 'string',
          'enum': [for (final reference in raspberryPiMcus) reference.id],
          'description':
              'Raspberry Pi MCU whose logic, drive and pull values are '
              'returned. Use supplyVolts for the actual IOVDD.',
        },
        'gowinFpga': {
          'type': 'string',
          'enum': [for (final reference in gowinFpgas) reference.id],
          'description':
              'Gowin FPGA family whose I/O standards are returned. Use '
              'supplyVolts for the bank VCCIO to filter and scale the '
              'standards.',
        },
        'xilinxFpga': {
          'type': 'string',
          'enum': [for (final reference in xilinxFpgas) reference.id],
          'description':
              'AMD/Xilinx FPGA bank type whose I/O standards are returned. '
              'Use supplyVolts for the bank VCCO to filter and scale the '
              'standards.',
        },
        'latticeFpga': {
          'type': 'string',
          'enum': [for (final reference in latticeFpgas) reference.id],
          'description':
              'Lattice FPGA family whose I/O standards are returned. Use '
              'supplyVolts for the bank VCCIO to filter and scale the '
              'standards.',
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
      final stm32Series = _stringArg(args, 'stm32Series');
      final raspberryPiMcu = _stringArg(args, 'raspberryPiMcu');
      final gowinFpga = _stringArg(args, 'gowinFpga');
      final xilinxFpga = _stringArg(args, 'xilinxFpga');
      final latticeFpga = _stringArg(args, 'latticeFpga');
      final supplyVolts = _numberArg(args, 'supplyVolts');
      if (icCatalog == null) {
        return <String, dynamic>{
          'error':
              'IC reference data is not loaded. The reference tables are '
              'unavailable.',
        };
      }
      final selectors = [
        standard,
        esp32Variant,
        stm32Series,
        raspberryPiMcu,
        gowinFpga,
        xilinxFpga,
        latticeFpga,
      ].whereType<String>().toList();
      final result = selectors.length > 1
          ? <String, dynamic>{
              'error':
                  'Choose only one of standard, esp32Variant, stm32Series, '
                  'raspberryPiMcu, gowinFpga, xilinxFpga or latticeFpga.',
            }
          : standard != null
          ? _selectedStandard(icCatalog, standard, supplyVolts)
          : esp32Variant != null
          ? _selectedEsp32(icCatalog, esp32Variant, supplyVolts)
          : stm32Series != null
          ? _selectedStm32(icCatalog, stm32Series, supplyVolts)
          : raspberryPiMcu != null
          ? _selectedRaspberryPi(icCatalog, raspberryPiMcu, supplyVolts)
          : gowinFpga != null
          ? _selectedGowin(icCatalog, gowinFpga, supplyVolts)
          : xilinxFpga != null
          ? _selectedXilinx(icCatalog, xilinxFpga, supplyVolts)
          : latticeFpga != null
          ? _selectedLattice(icCatalog, latticeFpga, supplyVolts)
          : _fullTable(icCatalog);
      logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}

Map<String, dynamic> _fullTable(
  IcReferenceCatalog catalog,
) => <String, dynamic>{
  'source': catalog.logicSource,
  'tiSource': tiLogicGuideSource,
  'unit': 'V',
  'note':
      'Values from the standard logic-level reference table, the TI Logic '
      'Guide SDYU001AC, the STMicroelectronics STM32 datasheets, the '
      'Raspberry Pi RP2040/RP2350 datasheets, the Gowin GW1N/GW2A/GW5A '
      'datasheets, the AMD/Xilinx 7 Series/UltraScale+ datasheets and the '
      'Lattice iCE40/MachXO2/MachXO3/ECP5 datasheets (all values in volts). '
      'VIL/VIH are input thresholds; VOL/VOH are output levels. For '
      'Schmitt-trigger inputs, VIL max equals Vt-(min) and VIH min equals '
      'Vt+(max). Levels between VIL and VIH are forbidden. HTL values are '
      'formulas until a supply voltage is provided.',
  'standards': [for (final standard in catalog.standards) standard.toMap()],
  ..._edgeTimeSection(catalog),
  ..._esp32Section(catalog),
  ..._stm32Section(catalog),
  ..._raspberryPiSection(catalog),
  ..._gowinSection(catalog),
  ..._xilinxSection(catalog),
  ..._latticeSection(catalog),
};

Map<String, dynamic> _edgeTimeSection(
  IcReferenceCatalog catalog,
) => <String, dynamic>{
  'edgeTimeUnit': 'ns',
  'edgeTimeSource': catalog.edgeTimeSource,
  'edgeTimes': [for (final reference in catalog.edgeTimes) reference.toMap()],
};

Map<String, dynamic> _esp32Section(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'esp32Source': catalog.esp32Source,
  'esp32': [
    for (final reference in catalog.esp32Variants)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _stm32Section(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'stm32Source': catalog.stm32Source,
  'stm32Note':
      'Output levels use the nominal 8 mA (6 mA for STM32G0) CMOS-port '
      'specification at VDD ≥ 2.7 V; below 2.7 V the datasheets specify '
      '4 mA or 6 mA with VOL ≤ 0.4 V and VOH ≥ VDD − 0.45 V. Values are '
      'representative of the cited datasheet for each series; check the '
      'exact part datasheet for sub-variants and special I/O types. Pass '
      'supplyVolts to compute the absolute thresholds.',
  'stm32': [
    for (final reference in catalog.stm32Series)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _raspberryPiSection(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'raspberryPiSource': catalog.raspberryPiSource,
  'raspberryPiNote':
      'The input and output levels are specified at 1.8 V, 2.5 V and '
      '3.3 V. An intermediate IOVDD uses the next lower specified point.',
  'raspberryPi': [
    for (final reference in catalog.raspberryPiMcus)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _gowinSection(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'gowinSource': catalog.gowinSource,
  'gowinNote':
      'Each single-ended standard carries its own VCCIO range. Without a '
      'supply, all standards are returned with values at their nominal '
      'VCCIO. With a supply, only standards whose VCCIO range contains it '
      'are returned and factor-based thresholds are computed at that '
      'supply.',
  'gowin': [
    for (final reference in catalog.gowinFpgas)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _xilinxSection(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'xilinxSource': catalog.xilinxSource,
  'xilinxNote':
      'Each bank type carries its own VCCO range. Without a supply, all '
      'standards are returned with values at their nominal VCCO. With a '
      'supply, only standards whose VCCO range contains it are returned '
      'and factor-based thresholds are computed at that supply.',
  'xilinx': [
    for (final reference in catalog.xilinxFpgas)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _latticeSection(
  IcReferenceCatalog catalog, {
  double? supplyVolts,
}) => <String, dynamic>{
  'latticeSource': catalog.latticeSource,
  'latticeNote':
      'Each family carries its own VCCIO ranges. Without a supply, all '
      'standards are returned with values at their nominal VCCIO. With a '
      'supply, only standards whose VCCIO range contains it are returned '
      'and factor-based thresholds are computed at that supply.',
  'lattice': [
    for (final reference in catalog.latticeFpgas)
      reference.toMap(supplyVolts: supplyVolts),
  ],
};

Map<String, dynamic> _selectedLattice(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findLatticeFpga(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown Lattice FPGA "$id". Valid ids: '
          '${catalog.latticeFpgas.map((entry) => entry.id).join(', ')}.',
    };
  }
  if (supplyVolts != null &&
      (supplyVolts < reference.vccioRangeVolts.first ||
          supplyVolts > reference.vccioRangeVolts.last)) {
    return <String, dynamic>{
      'error':
          '${reference.label} VCCIO must be between '
          '${reference.vccioRangeVolts.first} and '
          '${reference.vccioRangeVolts.last} V.',
    };
  }
  final map = reference.toMap(supplyVolts: supplyVolts);
  final standards = map['standards'] as List<dynamic>;
  if (supplyVolts != null && standards.isEmpty) {
    return <String, dynamic>{
      'error':
          'No ${reference.label} I/O standard uses a VCCIO of $supplyVolts '
          'V. Valid ranges are listed in the full table.',
    };
  }
  return <String, dynamic>{
    'source': reference.source,
    'unit': 'V',
    'lattice': map,
    if (supplyVolts == null)
      'note':
          'No VCCIO was supplied. All standards are returned at their '
          'nominal VCCIO; ask the user for the bank VCCIO to filter them.',
  };
}

Map<String, dynamic> _selectedXilinx(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findXilinxFpga(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown AMD/Xilinx FPGA "$id". Valid ids: '
          '${catalog.xilinxFpgas.map((entry) => entry.id).join(', ')}.',
    };
  }
  if (supplyVolts != null &&
      (supplyVolts < reference.vccioRangeVolts.first ||
          supplyVolts > reference.vccioRangeVolts.last)) {
    return <String, dynamic>{
      'error':
          '${reference.label} VCCO must be between '
          '${reference.vccioRangeVolts.first} and '
          '${reference.vccioRangeVolts.last} V.',
    };
  }
  final map = reference.toMap(supplyVolts: supplyVolts);
  final standards = map['standards'] as List<dynamic>;
  if (supplyVolts != null && standards.isEmpty) {
    return <String, dynamic>{
      'error':
          'No ${reference.label} I/O standard uses a VCCO of $supplyVolts V. '
          'Valid ranges are listed in the full table.',
    };
  }
  return <String, dynamic>{
    'source': reference.source,
    'unit': 'V',
    'xilinx': map,
    if (supplyVolts == null)
      'note':
          'No VCCO was supplied. All standards are returned at their '
          'nominal VCCO; ask the user for the bank VCCO to filter them.',
  };
}

Map<String, dynamic> _selectedGowin(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findGowinFpga(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown Gowin FPGA "$id". Valid ids: '
          '${catalog.gowinFpgas.map((entry) => entry.id).join(', ')}.',
    };
  }
  if (supplyVolts != null &&
      (supplyVolts < reference.vccioRangeVolts.first ||
          supplyVolts > reference.vccioRangeVolts.last)) {
    return <String, dynamic>{
      'error':
          '${reference.label} VCCIO must be between '
          '${reference.vccioRangeVolts.first} and '
          '${reference.vccioRangeVolts.last} V.',
    };
  }
  final map = reference.toMap(supplyVolts: supplyVolts);
  final standards = map['standards'] as List<dynamic>;
  if (supplyVolts != null && standards.isEmpty) {
    return <String, dynamic>{
      'error':
          'No ${reference.label} single-ended I/O standard uses a VCCIO of '
          '$supplyVolts V. Valid ranges are listed in the full table.',
    };
  }
  return <String, dynamic>{
    'source': reference.source,
    'unit': 'V',
    'gowin': map,
    if (supplyVolts == null)
      'note':
          'No VCCIO was supplied. All standards are returned at their '
          'nominal VCCIO; ask the user for the bank VCCIO to filter them.',
  };
}

Map<String, dynamic> _selectedRaspberryPi(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findRaspberryPiMcu(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown Raspberry Pi MCU "$id". Valid ids: '
          '${catalog.raspberryPiMcus.map((entry) => entry.id).join(', ')}.',
    };
  }
  final effectiveSupply = supplyVolts ?? 3.3;
  final minimum = reference.supplyRangeVolts.first;
  final maximum = reference.supplyRangeVolts.last;
  if (effectiveSupply < minimum || effectiveSupply > maximum) {
    return <String, dynamic>{
      'error':
          '${reference.label} IOVDD must be between $minimum and $maximum V.',
    };
  }
  return <String, dynamic>{
    'source': reference.source,
    'unit': 'V',
    'raspberryPi': reference.toMap(supplyVolts: effectiveSupply),
    if (supplyVolts == null) 'assumedSupplyVolts': effectiveSupply,
    if (supplyVolts == null)
      'note':
          'No IOVDD was supplied. The values were computed for an assumed '
          '3.3 V supply; ask the user for the actual IOVDD.',
  };
}

Map<String, dynamic> _selectedStm32(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findStm32Series(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown STM32 series "$id". Valid series: '
          '${catalog.stm32Series.map((entry) => entry.id).join(', ')}.',
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
    'source': reference.source,
    'unit': 'V',
    'stm32': reference.toMap(supplyVolts: effectiveSupply),
    if (supplyVolts == null) 'assumedSupplyVolts': effectiveSupply,
    if (supplyVolts == null)
      'note':
          'No VDD was supplied. The values were computed for an assumed '
          '3.3 V supply; ask the user for the actual VDD.',
  };
}

Map<String, dynamic> _selectedEsp32(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final reference = catalog.findEsp32Variant(id);
  if (reference == null) {
    return <String, dynamic>{
      'error':
          'Unknown ESP32 variant "$id". Valid variants: '
          '${catalog.esp32Variants.map((entry) => entry.id).join(', ')}.',
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
    'source': reference.source,
    'unit': 'V',
    'esp32': reference.toMap(supplyVolts: effectiveSupply),
    if (supplyVolts == null) 'assumedSupplyVolts': effectiveSupply,
    if (supplyVolts == null)
      'note':
          'No VDD was supplied. The values were computed for an assumed '
          '3.3 V supply; ask the user for the actual VDD.',
  };
}

Map<String, dynamic> _selectedStandard(
  IcReferenceCatalog catalog,
  String id,
  double? supplyVolts,
) {
  final standard = catalog.findStandard(id);
  if (standard == null) {
    return <String, dynamic>{
      'error':
          'Unknown standard "$id". Valid standards: '
          '${catalog.standards.map((entry) => entry.id).join(', ')}.',
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
    'source': standard.source,
    'unit': 'V',
    'standard': standard.toMap(supplyVolts: effectiveSupply),
    ..._edgeTimeSection(catalog),
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
