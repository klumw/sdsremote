/// Standard logic-level reference table.
///
/// Values are taken from the German Wikipedia article "Logikpegel", section
/// "Standardwerte", table "gängige Logikpegel (alle Angaben in Volt)".
/// VIL/VIH are input thresholds; VOL/VOH are output levels. Levels between
/// VIL and VIH are forbidden and have no defined logic value.
library;

import 'dart:math' as math;

const String logicLevelSourceUrl = 'https://de.wikipedia.org/wiki/Logikpegel';
const String logicLevelSourceTitle = 'Wikipedia: Logikpegel';

/// One logic family from the reference table.
class LogicLevelStandard {
  const LogicLevelStandard({
    required this.id,
    required this.label,
    required this.family,
    this.supplyVolts,
    this.supplyRangeVolts,
    this.vilMaxVolts,
    this.vihMinVolts,
    this.volMaxVolts,
    this.vohMinVolts,
    this.vilRangeVolts,
    this.vihRangeVolts,
    this.volRangeVolts,
    this.vohRangeVolts,
    this.vilMaxFactorOfSupply,
    this.vihMinFactorOfSupply,
    this.vohTypicalFactorOfSupply,
    this.negativeLogic = false,
    this.volNotStated = false,
    this.vohNotStated = false,
    this.notes = '',
  });

  final String id;
  final String label;
  final String family;

  /// Nominal supply voltage in volts, when the table names one.
  final double? supplyVolts;

  /// Supply range in volts for supply-dependent families (HTL).
  final List<double>? supplyRangeVolts;

  final double? vilMaxVolts;
  final double? vihMinVolts;
  final double? volMaxVolts;
  final double? vohMinVolts;

  /// Ranges used by RS-232 instead of fixed limits.
  final List<double>? vilRangeVolts;
  final List<double>? vihRangeVolts;
  final List<double>? volRangeVolts;
  final List<double>? vohRangeVolts;

  /// Folded thresholds for HTL: VIL ≤ factor × UB, VIH ≥ factor × UB.
  final double? vilMaxFactorOfSupply;
  final double? vihMinFactorOfSupply;

  /// Typical VOH for HTL: ≈ factor × UB.
  final double? vohTypicalFactorOfSupply;

  final bool negativeLogic;
  final bool volNotStated;
  final bool vohNotStated;
  final String notes;

  /// Parses an [id] or label (case-insensitive).
  static LogicLevelStandard? parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final standard in logicLevelStandards) {
      if (standard.id == normalized ||
          standard.label.toLowerCase() == normalized ||
          standard.family.toLowerCase() == normalized) {
        return standard;
      }
    }
    return null;
  }

  /// JSON-safe representation.
  ///
  /// [supplyVolts] is used only for supply-dependent families (HTL). Without
  /// it, the formulas are returned instead of computed thresholds.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final effectiveSupply = supplyVolts ?? this.supplyVolts;
    final vilMax =
        vilMaxVolts ??
        (vilMaxFactorOfSupply == null || effectiveSupply == null
            ? null
            : vilMaxFactorOfSupply! * effectiveSupply);
    final vihMin =
        vihMinVolts ??
        (vihMinFactorOfSupply == null || effectiveSupply == null
            ? null
            : vihMinFactorOfSupply! * effectiveSupply);
    final vohTypical =
        vohTypicalFactorOfSupply == null || effectiveSupply == null
        ? null
        : vohTypicalFactorOfSupply! * effectiveSupply;
    return <String, dynamic>{
      'id': id,
      'label': label,
      'family': family,
      'supplyVolts': ?effectiveSupply,
      'supplyRangeVolts': ?supplyRangeVolts,
      if (vilMaxFactorOfSupply != null)
        'vilMaxFormula': '$vilMaxFactorOfSupply × UB',
      if (vihMinFactorOfSupply != null)
        'vihMinFormula': '$vihMinFactorOfSupply × UB',
      if (vohTypicalFactorOfSupply != null)
        'vohTypicalFormula': '≈ $vohTypicalFactorOfSupply × UB',
      'input': <String, dynamic>{
        'vilMaxVolts': ?vilMax,
        'vihMinVolts': ?vihMin,
        'vilRangeVolts': ?vilRangeVolts,
        'vihRangeVolts': ?vihRangeVolts,
      },
      'output': <String, dynamic>{
        'volMaxVolts': ?volMaxVolts,
        'vohMinVolts': ?vohMinVolts,
        'vohTypicalVolts': ?vohTypical,
        'volRangeVolts': ?volRangeVolts,
        'vohRangeVolts': ?vohRangeVolts,
        if (volNotStated) 'volNote': 'not stated in the source table',
        if (vohNotStated) 'vohNote': 'not stated in the source table',
      },
      'logic': negativeLogic
          ? 'negative (low=1, high=0)'
          : 'positive (low=0, high=1)',
      'notes': notes,
      'source': logicLevelSourceUrl,
    };
  }
}

/// The table rows in the order used by the Wikipedia article.
const List<LogicLevelStandard> logicLevelStandards = [
  LogicLevelStandard(
    id: 'ttl_5v',
    label: 'TTL 5 V',
    family: 'TTL',
    supplyVolts: 5.0,
    vilMaxVolts: 0.8,
    vihMinVolts: 2.0,
    volMaxVolts: 0.4,
    vohMinVolts: 2.4,
  ),
  LogicLevelStandard(
    id: 'cmos_5v',
    label: 'CMOS 5 V',
    family: 'CMOS',
    supplyVolts: 5.0,
    vilMaxVolts: 1.5,
    vihMinVolts: 3.5,
    volMaxVolts: 0.5,
    vohMinVolts: 4.44,
  ),
  LogicLevelStandard(
    id: 'lvttl_3v3',
    label: 'LVTTL 3.3 V',
    family: 'LVTTL',
    supplyVolts: 3.3,
    vilMaxVolts: 0.8,
    vihMinVolts: 2.0,
    volMaxVolts: 0.4,
    vohMinVolts: 2.4,
  ),
  LogicLevelStandard(
    id: 'cmos_2v5',
    label: 'CMOS 2.5 V',
    family: 'CMOS',
    supplyVolts: 2.5,
    vilMaxVolts: 0.7,
    vihMinVolts: 1.7,
    volMaxVolts: 0.2,
    vohMinVolts: 2.3,
  ),
  LogicLevelStandard(
    id: 'cmos_1v8',
    label: 'CMOS 1.8 V',
    family: 'CMOS',
    supplyVolts: 1.8,
    vilMaxVolts: 0.7,
    vihMinVolts: 1.17,
    volMaxVolts: 0.45,
    vohMinVolts: 1.2,
  ),
  LogicLevelStandard(
    id: 'ecl',
    label: 'ECL',
    family: 'ECL',
    vilMaxVolts: -1.4,
    vihMinVolts: -1.2,
    volNotStated: true,
    vohNotStated: true,
    notes:
        'Output levels (VOL/VOH) are not stated in the source table. Use the '
        'device datasheet for output levels.',
  ),
  LogicLevelStandard(
    id: 'rs232',
    label: 'RS-232',
    family: 'RS-232',
    vilRangeVolts: [-15.0, -3.0],
    vihRangeVolts: [3.0, 15.0],
    volRangeVolts: [-15.0, -5.0],
    vohRangeVolts: [5.0, 15.0],
    negativeLogic: true,
    notes:
        'Values are ranges from the source table. Negative logic: low=1, '
        'high=0.',
  ),
  LogicLevelStandard(
    id: 'htl_10_30v',
    label: 'HTL 10…30 V',
    family: 'HTL',
    supplyRangeVolts: [10.0, 30.0],
    vilMaxFactorOfSupply: 0.2,
    vihMinFactorOfSupply: 0.6,
    vohTypicalFactorOfSupply: 1.0,
    volNotStated: true,
    notes:
        'Supply-dependent: VIL ≤ 0.2 × UB, VIH ≥ 0.6 × UB, VOH ≈ UB. Output '
        'low is not stated in the source table.',
  ),
];

/// Source label for the edge-time values. These values were supplied by the
/// user and are not part of the Wikipedia logic-level table.
const String logicEdgeTimeSource = 'User-provided reference values';

/// One supply-dependent maximum edge time.
class LogicEdgeTimePoint {
  const LogicEdgeTimePoint({
    required this.supplyVolts,
    required this.maxEdgeTimeNs,
  });

  final double supplyVolts;
  final double maxEdgeTimeNs;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'supplyVolts': supplyVolts,
    'maxEdgeTimeNs': maxEdgeTimeNs,
  };
}

/// Maximum edge time of a logic family or series.
///
/// [points] contains absolute limits at specific supply voltages (4000 and
/// 74HC series). Families with a slope limit use
/// [maxEdgeTimeNsPerVoltMin]/[maxEdgeTimeNsPerVoltMax]; the actual limit is
/// `ns/V × voltage swing`.
class LogicEdgeTimeReference {
  const LogicEdgeTimeReference({
    required this.id,
    required this.family,
    required this.exampleSeries,
    this.points = const [],
    this.supplyRangeVolts,
    this.maxEdgeTimeNsPerVoltMin,
    this.maxEdgeTimeNsPerVoltMax,
    this.exampleSupplyVolts,
    this.exampleMaxEdgeTimeNs,
    this.notes = '',
  });

  final String id;
  final String family;
  final String exampleSeries;
  final List<LogicEdgeTimePoint> points;
  final List<double>? supplyRangeVolts;
  final double? maxEdgeTimeNsPerVoltMin;
  final double? maxEdgeTimeNsPerVoltMax;
  final double? exampleSupplyVolts;
  final double? exampleMaxEdgeTimeNs;
  final String notes;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'family': family,
    'exampleSeries': exampleSeries,
    if (points.isNotEmpty)
      'points': [for (final point in points) point.toMap()],
    'supplyRangeVolts': ?supplyRangeVolts,
    'maxEdgeTimeNsPerVoltMin': ?maxEdgeTimeNsPerVoltMin,
    'maxEdgeTimeNsPerVoltMax': ?maxEdgeTimeNsPerVoltMax,
    'exampleSupplyVolts': ?exampleSupplyVolts,
    'exampleMaxEdgeTimeNs': ?exampleMaxEdgeTimeNs,
    'notes': notes,
    'source': logicEdgeTimeSource,
  };
}

/// Edge-time reference values supplied by the user.
const List<LogicEdgeTimeReference> logicEdgeTimeReferences = [
  LogicEdgeTimeReference(
    id: 'standard_cmos_4000',
    family: 'Standard CMOS (4000 series)',
    exampleSeries: 'CD4000B, TC40xxB',
    points: [
      LogicEdgeTimePoint(supplyVolts: 5.0, maxEdgeTimeNs: 5000.0),
      LogicEdgeTimePoint(supplyVolts: 10.0, maxEdgeTimeNs: 1000.0),
      LogicEdgeTimePoint(supplyVolts: 15.0, maxEdgeTimeNs: 500.0),
    ],
    notes:
        'Absolute maximum edge time at the given supply voltage (5 µs at '
        '5 V, 1 µs at 10 V, 500 ns at 15 V).',
  ),
  LogicEdgeTimeReference(
    id: 'high_speed_cmos_74hc',
    family: 'High-Speed CMOS',
    exampleSeries: '74HC / 74HCT',
    points: [
      LogicEdgeTimePoint(supplyVolts: 2.0, maxEdgeTimeNs: 1000.0),
      LogicEdgeTimePoint(supplyVolts: 4.5, maxEdgeTimeNs: 500.0),
      LogicEdgeTimePoint(supplyVolts: 6.0, maxEdgeTimeNs: 400.0),
    ],
    notes:
        'Absolute maximum edge time at the given supply voltage (1 µs at '
        '2.0 V, 500 ns at 4.5 V, 400 ns at 6.0 V).',
  ),
  LogicEdgeTimeReference(
    id: 'advanced_cmos_74ac',
    family: 'Advanced CMOS',
    exampleSeries: '74AC / 74ACT',
    supplyRangeVolts: [3.0, 5.5],
    maxEdgeTimeNsPerVoltMin: 20.0,
    maxEdgeTimeNsPerVoltMax: 20.0,
    exampleSupplyVolts: 5.0,
    exampleMaxEdgeTimeNs: 100.0,
    notes:
        '20 ns/V; for example the maximum is 100 ns at 5 V. Multiply the '
        'slope by the actual voltage swing.',
  ),
  LogicEdgeTimeReference(
    id: 'very_high_speed_cmos_74vhc',
    family: 'Very High-Speed CMOS',
    exampleSeries: '74VHC / 74VHCT',
    supplyRangeVolts: [3.3, 5.0],
    maxEdgeTimeNsPerVoltMin: 20.0,
    maxEdgeTimeNsPerVoltMax: 100.0,
    notes:
        '20 to 100 ns/V, depending on the family. Multiply the selected '
        'slope by the actual voltage swing.',
  ),
  LogicEdgeTimeReference(
    id: 'low_voltage_cmos_74lvc',
    family: 'Low-Voltage CMOS',
    exampleSeries: '74LVC / 74AUC',
    supplyRangeVolts: [1.8, 3.3],
    maxEdgeTimeNsPerVoltMin: 5.0,
    maxEdgeTimeNsPerVoltMax: 10.0,
    notes:
        '5 to 10 ns/V. Multiply the selected slope by the actual voltage '
        'swing.',
  ),
];

/// Source label for the ESP32 values. These values were supplied by the user
/// and are not part of the Wikipedia logic-level table.
const String esp32LogicSource = 'User-provided reference values';

/// Logic, drive and edge reference for one ESP32 variant.
class Esp32LogicReference {
  const Esp32LogicReference({
    required this.id,
    required this.label,
    required this.supplyRangeVolts,
    required this.vilMinVolts,
    required this.vilFactorOfSupply,
    required this.vilAbsoluteMaxVolts,
    required this.vihFactorOfSupply,
    required this.vihAbsoluteMinVolts,
    required this.vihMaxAboveSupplyVolts,
    required this.volFactorOfSupply,
    required this.volAbsoluteMaxVolts,
    required this.volTestCurrentMilliamps,
    required this.vohFactorOfSupply,
    required this.vohAbsoluteMinVolts,
    required this.vohTestCurrentMilliamps,
    required this.maxOutputCurrentMilliamps,
    required this.recommendedContinuousCurrentMilliamps,
    required this.riseTimeNsMin,
    required this.riseTimeNsMax,
    required this.fallTimeNsMin,
    required this.fallTimeNsMax,
    required this.pullUpKiloOhms,
    required this.pullDownKiloOhms,
    required this.absoluteMaxInputMinVolts,
    required this.absoluteMaxInputAboveSupplyVolts,
    this.notes = '',
  });

  final String id;
  final String label;
  final List<double> supplyRangeVolts;
  final double vilMinVolts;
  final double vilFactorOfSupply;
  final double vilAbsoluteMaxVolts;
  final double vihFactorOfSupply;
  final double vihAbsoluteMinVolts;
  final double vihMaxAboveSupplyVolts;
  final double volFactorOfSupply;
  final double volAbsoluteMaxVolts;
  final double volTestCurrentMilliamps;
  final double vohFactorOfSupply;
  final double vohAbsoluteMinVolts;
  final double vohTestCurrentMilliamps;
  final double maxOutputCurrentMilliamps;
  final double recommendedContinuousCurrentMilliamps;
  final double riseTimeNsMin;
  final double riseTimeNsMax;
  final double fallTimeNsMin;
  final double fallTimeNsMax;
  final double pullUpKiloOhms;
  final double pullDownKiloOhms;
  final double absoluteMaxInputMinVolts;
  final double absoluteMaxInputAboveSupplyVolts;
  final String notes;

  static Esp32LogicReference? parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final reference in esp32LogicReferences) {
      if (reference.id == normalized ||
          reference.label.toLowerCase() == normalized) {
        return reference;
      }
    }
    return null;
  }

  /// JSON-safe representation. With [supplyVolts], the absolute thresholds
  /// are computed from the formulas; without it, only the formulas and
  /// absolute caps are returned.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final supply = supplyVolts;
    final vilMax = supply == null
        ? null
        : math.min(vilFactorOfSupply * supply, vilAbsoluteMaxVolts);
    final vihMin = supply == null
        ? null
        : math.max(vihFactorOfSupply * supply, vihAbsoluteMinVolts);
    final volMax = supply == null
        ? null
        : math.min(volFactorOfSupply * supply, volAbsoluteMaxVolts);
    final vohMin = supply == null
        ? null
        : math.max(vohFactorOfSupply * supply, vohAbsoluteMinVolts);
    return <String, dynamic>{
      'id': id,
      'label': label,
      'supplyRangeVolts': supplyRangeVolts,
      'supplyVolts': ?supply,
      'input': <String, dynamic>{
        'vilMinVolts': vilMinVolts,
        'vilMaxVolts': ?vilMax,
        'vilMaxFormula': 'min(0.25 × VDD, 0.825 V)',
        'vilAbsoluteMaxVolts': vilAbsoluteMaxVolts,
        'vihMinVolts': ?vihMin,
        'vihMinFormula': 'max(0.75 × VDD, 2.475 V)',
        'vihAbsoluteMinVolts': vihAbsoluteMinVolts,
        'vihMaxFormula': 'VDD + 0.3 V',
        'vihMaxVolts': supply == null ? null : supply + vihMaxAboveSupplyVolts,
      },
      'output': <String, dynamic>{
        'volMaxVolts': ?volMax,
        'volMaxFormula': 'min(0.1 × VDD, 0.33 V)',
        'volAbsoluteMaxVolts': volAbsoluteMaxVolts,
        'volTestCurrentMilliamps': volTestCurrentMilliamps,
        'vohMinVolts': ?vohMin,
        'vohMinFormula': 'max(0.8 × VDD, 2.64 V)',
        'vohAbsoluteMinVolts': vohAbsoluteMinVolts,
        'vohTestCurrentMilliamps': vohTestCurrentMilliamps,
      },
      'drive': <String, dynamic>{
        'maxOutputCurrentMilliamps': maxOutputCurrentMilliamps,
        'recommendedContinuousCurrentMilliamps':
            recommendedContinuousCurrentMilliamps,
      },
      'edges': <String, dynamic>{
        'riseTimeNsMin': riseTimeNsMin,
        'riseTimeNsMax': riseTimeNsMax,
        'fallTimeNsMin': fallTimeNsMin,
        'fallTimeNsMax': fallTimeNsMax,
      },
      'pullResistorsKiloOhms': <String, dynamic>{
        'pullUp': pullUpKiloOhms,
        'pullDown': pullDownKiloOhms,
      },
      'absoluteMaxInput': <String, dynamic>{
        'minVolts': absoluteMaxInputMinVolts,
        'maxFormula': 'VDD + 0.3 V',
        'maxAboveSupplyVolts': absoluteMaxInputAboveSupplyVolts,
        if (supply != null)
          'maxVolts': supply + absoluteMaxInputAboveSupplyVolts,
      },
      'notes': notes,
      'source': esp32LogicSource,
    };
  }
}

/// ESP32-family values supplied by the user.
const List<Esp32LogicReference> esp32LogicReferences = [
  Esp32LogicReference(
    id: 'esp32',
    label: 'ESP32',
    supplyRangeVolts: [2.3, 3.6],
    vilMinVolts: 0.0,
    vilFactorOfSupply: 0.25,
    vilAbsoluteMaxVolts: 0.825,
    vihFactorOfSupply: 0.75,
    vihAbsoluteMinVolts: 2.475,
    vihMaxAboveSupplyVolts: 0.3,
    volFactorOfSupply: 0.1,
    volAbsoluteMaxVolts: 0.33,
    volTestCurrentMilliamps: 5,
    vohFactorOfSupply: 0.8,
    vohAbsoluteMinVolts: 2.64,
    vohTestCurrentMilliamps: 5,
    maxOutputCurrentMilliamps: 40,
    recommendedContinuousCurrentMilliamps: 20,
    riseTimeNsMin: 2.5,
    riseTimeNsMax: 6.0,
    fallTimeNsMin: 2.5,
    fallTimeNsMax: 6.0,
    pullUpKiloOhms: 45,
    pullDownKiloOhms: 45,
    absoluteMaxInputMinVolts: -0.3,
    absoluteMaxInputAboveSupplyVolts: 0.3,
    notes: 'VIL lower bound is 0 V for the ESP32.',
  ),
  Esp32LogicReference(
    id: 'esp32_s2',
    label: 'ESP32-S2',
    supplyRangeVolts: [3.0, 3.6],
    vilMinVolts: -0.3,
    vilFactorOfSupply: 0.25,
    vilAbsoluteMaxVolts: 0.825,
    vihFactorOfSupply: 0.75,
    vihAbsoluteMinVolts: 2.475,
    vihMaxAboveSupplyVolts: 0.3,
    volFactorOfSupply: 0.1,
    volAbsoluteMaxVolts: 0.33,
    volTestCurrentMilliamps: 5,
    vohFactorOfSupply: 0.8,
    vohAbsoluteMinVolts: 2.64,
    vohTestCurrentMilliamps: 5,
    maxOutputCurrentMilliamps: 28,
    recommendedContinuousCurrentMilliamps: 20,
    riseTimeNsMin: 2.0,
    riseTimeNsMax: 5.5,
    fallTimeNsMin: 2.0,
    fallTimeNsMax: 5.5,
    pullUpKiloOhms: 45,
    pullDownKiloOhms: 45,
    absoluteMaxInputMinVolts: -0.3,
    absoluteMaxInputAboveSupplyVolts: 0.3,
    notes:
        'VIL lower bound is -0.3 V. Maximum output current is 28 mA for the '
        'S2.',
  ),
  Esp32LogicReference(
    id: 'esp32_s3',
    label: 'ESP32-S3',
    supplyRangeVolts: [3.0, 3.6],
    vilMinVolts: -0.3,
    vilFactorOfSupply: 0.25,
    vilAbsoluteMaxVolts: 0.825,
    vihFactorOfSupply: 0.75,
    vihAbsoluteMinVolts: 2.475,
    vihMaxAboveSupplyVolts: 0.3,
    volFactorOfSupply: 0.1,
    volAbsoluteMaxVolts: 0.33,
    volTestCurrentMilliamps: 5,
    vohFactorOfSupply: 0.8,
    vohAbsoluteMinVolts: 2.64,
    vohTestCurrentMilliamps: 5,
    maxOutputCurrentMilliamps: 40,
    recommendedContinuousCurrentMilliamps: 20,
    riseTimeNsMin: 2.0,
    riseTimeNsMax: 5.5,
    fallTimeNsMin: 2.0,
    fallTimeNsMax: 5.5,
    pullUpKiloOhms: 45,
    pullDownKiloOhms: 45,
    absoluteMaxInputMinVolts: -0.3,
    absoluteMaxInputAboveSupplyVolts: 0.3,
    notes:
        'VIL lower bound is -0.3 V. Maximum output current is 40 mA for the '
        'S3.',
  ),
  Esp32LogicReference(
    id: 'esp32_c3_c6',
    label: 'ESP32-C3 / ESP32-C6',
    supplyRangeVolts: [3.0, 3.6],
    vilMinVolts: -0.3,
    vilFactorOfSupply: 0.25,
    vilAbsoluteMaxVolts: 0.825,
    vihFactorOfSupply: 0.75,
    vihAbsoluteMinVolts: 2.475,
    vihMaxAboveSupplyVolts: 0.3,
    volFactorOfSupply: 0.1,
    volAbsoluteMaxVolts: 0.33,
    volTestCurrentMilliamps: 5,
    vohFactorOfSupply: 0.8,
    vohAbsoluteMinVolts: 2.64,
    vohTestCurrentMilliamps: 5,
    maxOutputCurrentMilliamps: 28,
    recommendedContinuousCurrentMilliamps: 20,
    riseTimeNsMin: 2.0,
    riseTimeNsMax: 5.0,
    fallTimeNsMin: 2.0,
    fallTimeNsMax: 5.0,
    pullUpKiloOhms: 45,
    pullDownKiloOhms: 45,
    absoluteMaxInputMinVolts: -0.3,
    absoluteMaxInputAboveSupplyVolts: 0.3,
    notes:
        'VIL lower bound is -0.3 V. Maximum output current is 28 mA for the '
        'C3/C6.',
  ),
];
