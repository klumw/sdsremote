/// Standard logic-level reference table.
///
/// The table contains common standard logic levels: VIL/VIH are input
/// thresholds, VOL/VOH are output levels. Levels between VIL and VIH are
/// forbidden and have no defined logic value.
library;

import 'dart:math' as math;

const String logicLevelSource = 'Standard logic-level reference table';

/// Source label for values taken from the TI Logic Guide SDYU001AC.
const String tiLogicGuideSource =
    'TI Logic Guide SDYU001AC (Rev. AC, November 2025)';

/// Source label for the typical switching thresholds (Vt, Vt+, Vt-).
const String logicSwitchingThresholdSource =
    'TI Logic Guide SDYU001AC, Figures 2-2 and 2-3';

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
    this.vtTypicalVolts,
    this.vtPlusMaxVolts,
    this.vtMinusMinVolts,
    this.schmittTrigger = false,
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
    this.source = logicLevelSource,
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

  /// Typical switching threshold Vt.
  final double? vtTypicalVolts;

  /// Maximum positive-going threshold of a Schmitt-trigger input.
  final double? vtPlusMaxVolts;

  /// Minimum negative-going threshold of a Schmitt-trigger input.
  final double? vtMinusMinVolts;

  /// Whether the input has Schmitt-trigger hysteresis.
  final bool schmittTrigger;

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

  /// Source label for this row.
  final String source;

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
      if (vtTypicalVolts != null ||
          vtPlusMaxVolts != null ||
          vtMinusMinVolts != null)
        'vtSource': logicSwitchingThresholdSource,
      'input': <String, dynamic>{
        'vilMaxVolts': ?vilMax,
        'vihMinVolts': ?vihMin,
        'vilRangeVolts': ?vilRangeVolts,
        'vihRangeVolts': ?vihRangeVolts,
        'vtTypicalVolts': ?vtTypicalVolts,
        'vtPlusMaxVolts': ?vtPlusMaxVolts,
        'vtMinusMinVolts': ?vtMinusMinVolts,
        if (schmittTrigger) 'schmittTrigger': true,
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
      'source': source,
    };
  }
}

/// Source label for the edge-time values. These values were supplied by the
/// user and are not part of the logic-level reference table.
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

/// Source label for the ESP32 values. These values were supplied by the user
/// and are not part of the logic-level reference table.
const String esp32LogicSource = 'User-provided reference values';

/// Logic, drive and edge reference for one ESP32 variant.
class Esp32LogicReference {
  const Esp32LogicReference({
    required this.id,
    required this.label,
    this.aliases = const [],
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
    this.source = esp32LogicSource,
  });

  final String id;
  final String label;
  final List<String> aliases;
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

  /// Source label for this variant.
  final String source;

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
      'source': source,
    };
  }
}

/// Source label for the STM32 family values.
const String stm32LogicSource = 'STMicroelectronics STM32 datasheets (st.com)';

/// Logic, drive and pull reference for one STM32 series.
///
/// The input thresholds are supply-scaled CMOS levels. The output levels use
/// the datasheet's nominal CMOS-port specification; the relaxed limits are
/// included as separate values. Values apply to the general-purpose I/Os;
/// special I/O types are named in [notes].
class Stm32LogicReference {
  const Stm32LogicReference({
    required this.id,
    required this.label,
    required this.series,
    required this.supplyRangeVolts,
    required this.vilFactorOfSupply,
    required this.vihFactorOfSupply,
    required this.pullUpKiloOhmsMin,
    required this.pullUpKiloOhmsTyp,
    required this.pullUpKiloOhmsMax,
    required this.pullDownKiloOhmsMin,
    required this.pullDownKiloOhmsTyp,
    required this.pullDownKiloOhmsMax,
    required this.source,
    this.volMaxVolts = 0.4,
    this.vohDropFromSupplyVolts = 0.4,
    this.relaxedVolMaxVolts = 1.3,
    this.relaxedVohDropFromSupplyVolts = 1.3,
    this.nominalOutputCurrentMilliamps = 8,
    this.relaxedOutputCurrentMilliamps = 20,
    this.fiveVoltTolerantPins = true,
    this.absoluteMaxInputMinVolts = -0.3,
    this.absoluteMaxInputAboveSupplyVolts = 0.3,
    this.fiveVoltTolerantMaxVolts = 5.5,
    this.notes = '',
  });

  final String id;
  final String label;
  final String series;
  final List<double> supplyRangeVolts;

  /// VIL max = factor × VDD.
  final double vilFactorOfSupply;

  /// VIH min = factor × VDD.
  final double vihFactorOfSupply;

  final double volMaxVolts;

  /// VOH min = VDD − this value at the nominal test current.
  final double vohDropFromSupplyVolts;

  final double relaxedVolMaxVolts;

  /// VOH min = VDD − this value at the relaxed test current.
  final double relaxedVohDropFromSupplyVolts;

  final double nominalOutputCurrentMilliamps;
  final double relaxedOutputCurrentMilliamps;

  final double pullUpKiloOhmsMin;
  final double pullUpKiloOhmsTyp;
  final double pullUpKiloOhmsMax;
  final double pullDownKiloOhmsMin;
  final double pullDownKiloOhmsTyp;
  final double pullDownKiloOhmsMax;

  final bool fiveVoltTolerantPins;
  final double absoluteMaxInputMinVolts;
  final double absoluteMaxInputAboveSupplyVolts;
  final double fiveVoltTolerantMaxVolts;
  final String notes;
  final String source;

  /// JSON-safe representation. With [supplyVolts], the absolute thresholds
  /// are computed from the formulas; without it, only the formulas and
  /// absolute limits are returned.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final supply = supplyVolts;
    final vilMax = supply == null ? null : vilFactorOfSupply * supply;
    final vihMin = supply == null ? null : vihFactorOfSupply * supply;
    final vohMin = supply == null ? null : supply - vohDropFromSupplyVolts;
    final relaxedVohMin = supply == null
        ? null
        : supply - relaxedVohDropFromSupplyVolts;
    return <String, dynamic>{
      'id': id,
      'label': label,
      'series': series,
      'supplyRangeVolts': supplyRangeVolts,
      'supplyVolts': ?supply,
      'input': <String, dynamic>{
        'vilMaxVolts': ?vilMax,
        'vilMaxFormula': '$vilFactorOfSupply × VDD',
        'vihMinVolts': ?vihMin,
        'vihMinFormula': '$vihFactorOfSupply × VDD',
      },
      'output': <String, dynamic>{
        'volMaxVolts': volMaxVolts,
        'vohMinVolts': ?vohMin,
        'vohDropFromSupplyVolts': vohDropFromSupplyVolts,
        'testCurrentMilliamps': nominalOutputCurrentMilliamps,
        'relaxedVolMaxVolts': relaxedVolMaxVolts,
        'relaxedVohMinVolts': ?relaxedVohMin,
        'relaxedVohDropFromSupplyVolts': relaxedVohDropFromSupplyVolts,
        'relaxedTestCurrentMilliamps': relaxedOutputCurrentMilliamps,
      },
      'drive': <String, dynamic>{
        'nominalOutputCurrentMilliamps': nominalOutputCurrentMilliamps,
        'relaxedOutputCurrentMilliamps': relaxedOutputCurrentMilliamps,
      },
      'pullResistorsKiloOhms': <String, dynamic>{
        'pullUpMin': pullUpKiloOhmsMin,
        'pullUpTyp': pullUpKiloOhmsTyp,
        'pullUpMax': pullUpKiloOhmsMax,
        'pullDownMin': pullDownKiloOhmsMin,
        'pullDownTyp': pullDownKiloOhmsTyp,
        'pullDownMax': pullDownKiloOhmsMax,
      },
      'absoluteMaxInput': <String, dynamic>{
        'minVolts': absoluteMaxInputMinVolts,
        'maxAboveSupplyVolts': absoluteMaxInputAboveSupplyVolts,
        if (supply != null)
          'maxVolts': supply + absoluteMaxInputAboveSupplyVolts,
        'fiveVoltTolerantPins': fiveVoltTolerantPins,
        if (fiveVoltTolerantPins)
          'fiveVoltTolerantMaxVolts': fiveVoltTolerantMaxVolts,
      },
      'notes': notes,
      'source': source,
    };
  }
}

/// Source label for the Raspberry Pi MCU values.
const String raspberryPiLogicSource =
    'Raspberry Pi RP2040/RP2350 datasheets (raspberrypi.com)';

/// One supply-specific I/O point of a Raspberry Pi MCU.
class RaspberryPiLogicPoint {
  const RaspberryPiLogicPoint({
    required this.supplyVolts,
    required this.vilMinVolts,
    required this.vilMaxVolts,
    required this.vihMinVolts,
    required this.vihMaxVolts,
    required this.volMaxVolts,
    required this.vohMinVolts,
    required this.vhysVolts,
    this.pullUpKiloOhmsMin,
    this.pullUpKiloOhmsMax,
    this.pullDownKiloOhmsMin,
    this.pullDownKiloOhmsMax,
    this.fiveVoltTolerantMaxVolts,
  });

  final double supplyVolts;
  final double vilMinVolts;
  final double vilMaxVolts;
  final double vihMinVolts;
  final double vihMaxVolts;
  final double volMaxVolts;
  final double vohMinVolts;
  final double vhysVolts;
  final double? pullUpKiloOhmsMin;
  final double? pullUpKiloOhmsMax;
  final double? pullDownKiloOhmsMin;
  final double? pullDownKiloOhmsMax;
  final double? fiveVoltTolerantMaxVolts;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'supplyVolts': supplyVolts,
    'vilMinVolts': vilMinVolts,
    'vilMaxVolts': vilMaxVolts,
    'vihMinVolts': vihMinVolts,
    'vihMaxVolts': vihMaxVolts,
    'volMaxVolts': volMaxVolts,
    'vohMinVolts': vohMinVolts,
    'vhysVolts': vhysVolts,
    'pullUpKiloOhmsMin': ?pullUpKiloOhmsMin,
    'pullUpKiloOhmsMax': ?pullUpKiloOhmsMax,
    'pullDownKiloOhmsMin': ?pullDownKiloOhmsMin,
    'pullDownKiloOhmsMax': ?pullDownKiloOhmsMax,
    'fiveVoltTolerantMaxVolts': ?fiveVoltTolerantMaxVolts,
  };
}

/// Logic, drive and pull reference for one Raspberry Pi MCU.
///
/// The input and output levels are specified at discrete IOVDD points. An
/// intermediate supply uses the next lower specified point.
class RaspberryPiLogicReference {
  const RaspberryPiLogicReference({
    required this.id,
    required this.label,
    required this.series,
    required this.supplyRangeVolts,
    required this.points,
    required this.driveStrengthsMilliamps,
    required this.totalOutputCurrentMilliamps,
    required this.fiveVoltTolerantPins,
    required this.absoluteMaxInputMinVolts,
    required this.absoluteMaxInputAboveSupplyVolts,
    required this.source,
    this.qspiTotalOutputCurrentMilliamps,
    this.notes = '',
  });

  final String id;
  final String label;
  final String series;
  final List<double> supplyRangeVolts;
  final List<RaspberryPiLogicPoint> points;
  final List<double> driveStrengthsMilliamps;
  final double totalOutputCurrentMilliamps;
  final double? qspiTotalOutputCurrentMilliamps;
  final bool fiveVoltTolerantPins;
  final double absoluteMaxInputMinVolts;
  final double absoluteMaxInputAboveSupplyVolts;
  final String notes;
  final String source;

  /// The highest specified point at or below [supply].
  RaspberryPiLogicPoint? pointForSupply(double supply) {
    RaspberryPiLogicPoint? selected;
    for (final point in points) {
      if (point.supplyVolts <= supply &&
          (selected == null || point.supplyVolts > selected.supplyVolts)) {
        selected = point;
      }
    }
    return selected;
  }

  Map<String, dynamic> toMap({double? supplyVolts}) {
    final point = supplyVolts == null ? null : pointForSupply(supplyVolts);
    final vilMin = point?.vilMinVolts;
    final vilMax = point?.vilMaxVolts;
    final vihMin = point?.vihMinVolts;
    final vihMax = point?.vihMaxVolts;
    final volMax = point?.volMaxVolts;
    final vohMin = point?.vohMinVolts;
    final vhys = point?.vhysVolts;
    final pullUpMin = point?.pullUpKiloOhmsMin;
    final pullUpMax = point?.pullUpKiloOhmsMax;
    final pullDownMin = point?.pullDownKiloOhmsMin;
    final pullDownMax = point?.pullDownKiloOhmsMax;
    final ftMax = point?.fiveVoltTolerantMaxVolts;
    return <String, dynamic>{
      'id': id,
      'label': label,
      'series': series,
      'supplyRangeVolts': supplyRangeVolts,
      'supplyVolts': ?supplyVolts,
      if (point != null) 'selectedPointSupplyVolts': point.supplyVolts,
      'points': [for (final entry in points) entry.toMap()],
      'input': <String, dynamic>{
        'vilMinVolts': ?vilMin,
        'vilMaxVolts': ?vilMax,
        'vihMinVolts': ?vihMin,
        'vihMaxVolts': ?vihMax,
        'vhysVolts': ?vhys,
      },
      'output': <String, dynamic>{
        'volMaxVolts': ?volMax,
        'vohMinVolts': ?vohMin,
        'driveStrengthsMilliamps': driveStrengthsMilliamps,
      },
      'drive': <String, dynamic>{
        'totalOutputCurrentMilliamps': totalOutputCurrentMilliamps,
        'qspiTotalOutputCurrentMilliamps': ?qspiTotalOutputCurrentMilliamps,
      },
      'pullResistorsKiloOhms': <String, dynamic>{
        'pullUpMin': ?pullUpMin,
        'pullUpMax': ?pullUpMax,
        'pullDownMin': ?pullDownMin,
        'pullDownMax': ?pullDownMax,
      },
      'absoluteMaxInput': <String, dynamic>{
        'minVolts': absoluteMaxInputMinVolts,
        'maxAboveSupplyVolts': absoluteMaxInputAboveSupplyVolts,
        if (supplyVolts != null)
          'maxVolts': supplyVolts + absoluteMaxInputAboveSupplyVolts,
        'fiveVoltTolerantPins': fiveVoltTolerantPins,
        'fiveVoltTolerantMaxVolts': ?ftMax,
      },
      'notes': notes,
      'source': source,
    };
  }
}

/// Source label for the Gowin FPGA values.
const String gowinFpgaLogicSource =
    'Gowin Semiconductor GW1N/GW2A/GW5A datasheets (gowinsemi.com)';

/// One single-ended I/O standard of a Gowin FPGA family.
class GowinIoStandard {
  const GowinIoStandard({
    required this.name,
    required this.vccioNominalVolts,
    required this.vccioRangeVolts,
    required this.volMaxVolts,
    required this.vohDropFromSupplyVolts,
    required this.driveStrengthsMilliamps,
    this.vilMaxVolts,
    this.vihMinVolts,
    this.vilMaxFactorOfSupply,
    this.vihMinFactorOfSupply,
    this.vihMaxVolts,
    this.vihMaxAboveSupplyVolts,
    this.lowDriveCurrentMilliamps = 0.1,
    this.lowDriveVolMaxVolts = 0.2,
    this.lowDriveVohDropFromSupplyVolts = 0.2,
  });

  final String name;
  final double vccioNominalVolts;
  final List<double> vccioRangeVolts;

  /// Fixed VIL max; when null, [vilMaxFactorOfSupply] is used.
  final double? vilMaxVolts;

  /// Fixed VIH min; when null, [vihMinFactorOfSupply] is used.
  final double? vihMinVolts;

  final double? vilMaxFactorOfSupply;
  final double? vihMinFactorOfSupply;

  /// Fixed VIH max; when null, [vihMaxAboveSupplyVolts] is used.
  final double? vihMaxVolts;
  final double? vihMaxAboveSupplyVolts;

  final double volMaxVolts;
  final double vohDropFromSupplyVolts;
  final List<double> driveStrengthsMilliamps;

  final double lowDriveCurrentMilliamps;
  final double lowDriveVolMaxVolts;
  final double lowDriveVohDropFromSupplyVolts;

  Map<String, dynamic> toMap({double? supplyVolts}) {
    final supply = supplyVolts ?? vccioNominalVolts;
    final vilMax =
        vilMaxVolts ??
        (vilMaxFactorOfSupply == null ? null : vilMaxFactorOfSupply! * supply);
    final vihMin =
        vihMinVolts ??
        (vihMinFactorOfSupply == null ? null : vihMinFactorOfSupply! * supply);
    final vihMax =
        vihMaxVolts ??
        (vihMaxAboveSupplyVolts == null
            ? null
            : supply + vihMaxAboveSupplyVolts!);
    return <String, dynamic>{
      'name': name,
      'vccioNominalVolts': vccioNominalVolts,
      'vccioRangeVolts': vccioRangeVolts,
      'vilMaxVolts': ?vilMax,
      'vihMinVolts': ?vihMin,
      'vihMaxVolts': ?vihMax,
      'volMaxVolts': volMaxVolts,
      'vohMinVolts': supply - vohDropFromSupplyVolts,
      'driveStrengthsMilliamps': driveStrengthsMilliamps,
      'lowDriveCurrentMilliamps': lowDriveCurrentMilliamps,
      'lowDriveVolMaxVolts': lowDriveVolMaxVolts,
      'lowDriveVohMinVolts': supply - lowDriveVohDropFromSupplyVolts,
    };
  }
}

/// Logic and I/O reference for one Gowin FPGA family.
class GowinFpgaReference {
  const GowinFpgaReference({
    required this.id,
    required this.label,
    required this.series,
    required this.vccioRangeVolts,
    required this.absoluteMaxInputVolts,
    required this.standards,
    required this.source,
    this.notes = '',
  });

  final String id;
  final String label;
  final String series;
  final List<double> vccioRangeVolts;
  final double absoluteMaxInputVolts;
  final List<GowinIoStandard> standards;
  final String notes;
  final String source;

  /// Maps the standards. With [supplyVolts], only standards whose VCCIO range
  /// contains the supply are returned and their thresholds use that supply.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final selected = supplyVolts == null
        ? standards
        : standards
              .where(
                (standard) =>
                    supplyVolts >= standard.vccioRangeVolts.first &&
                    supplyVolts <= standard.vccioRangeVolts.last,
              )
              .toList();
    return <String, dynamic>{
      'id': id,
      'label': label,
      'series': series,
      'vccioRangeVolts': vccioRangeVolts,
      'absoluteMaxInputVolts': absoluteMaxInputVolts,
      'supplyVolts': ?supplyVolts,
      'standards': [
        for (final standard in selected)
          standard.toMap(supplyVolts: supplyVolts),
      ],
      'notes': notes,
      'source': source,
    };
  }
}

/// Source label for the AMD/Xilinx FPGA values.
const String xilinxLogicSource =
    'AMD/Xilinx 7 Series and UltraScale+ datasheets (docs.amd.com)';

/// One single-ended I/O standard of an AMD/Xilinx FPGA bank.
class XilinxIoStandard {
  const XilinxIoStandard({
    required this.name,
    required this.vccioNominalVolts,
    required this.vccioRangeVolts,
    required this.driveStrengthsMilliamps,
    this.vilMinVolts = -0.3,
    this.vilMaxVolts,
    this.vilMaxFactorOfSupply,
    this.vihMinVolts,
    this.vihMinFactorOfSupply,
    this.vihMaxVolts,
    this.vihMaxAboveSupplyVolts,
    this.volMaxVolts,
    this.volFactorOfSupply,
    this.vohMinVolts,
    this.vohDropFromSupplyVolts,
    this.vohFactorOfSupply,
  });

  final String name;
  final double vccioNominalVolts;
  final List<double> vccioRangeVolts;
  final List<double> driveStrengthsMilliamps;

  final double vilMinVolts;
  final double? vilMaxVolts;
  final double? vilMaxFactorOfSupply;

  final double? vihMinVolts;
  final double? vihMinFactorOfSupply;

  final double? vihMaxVolts;
  final double? vihMaxAboveSupplyVolts;

  final double? volMaxVolts;
  final double? volFactorOfSupply;

  final double? vohMinVolts;
  final double? vohDropFromSupplyVolts;
  final double? vohFactorOfSupply;

  Map<String, dynamic> toMap({double? supplyVolts}) {
    final supply = supplyVolts ?? vccioNominalVolts;
    final vilMax =
        vilMaxVolts ??
        (vilMaxFactorOfSupply == null ? null : vilMaxFactorOfSupply! * supply);
    final vihMin =
        vihMinVolts ??
        (vihMinFactorOfSupply == null ? null : vihMinFactorOfSupply! * supply);
    final vihMax =
        vihMaxVolts ??
        (vihMaxAboveSupplyVolts == null
            ? null
            : supply + vihMaxAboveSupplyVolts!);
    final volMax =
        volMaxVolts ??
        (volFactorOfSupply == null ? null : volFactorOfSupply! * supply);
    final vohMin =
        vohMinVolts ??
        (vohDropFromSupplyVolts != null
            ? supply - vohDropFromSupplyVolts!
            : (vohFactorOfSupply == null ? null : vohFactorOfSupply! * supply));
    return <String, dynamic>{
      'name': name,
      'vccioNominalVolts': vccioNominalVolts,
      'vccioRangeVolts': vccioRangeVolts,
      'vilMinVolts': vilMinVolts,
      'vilMaxVolts': ?vilMax,
      'vihMinVolts': ?vihMin,
      'vihMaxVolts': ?vihMax,
      'volMaxVolts': ?volMax,
      'vohMinVolts': ?vohMin,
      'driveStrengthsMilliamps': driveStrengthsMilliamps,
    };
  }
}

/// Logic and I/O reference for one AMD/Xilinx FPGA bank type.
class XilinxFpgaReference {
  const XilinxFpgaReference({
    required this.id,
    required this.label,
    required this.series,
    required this.bankType,
    required this.vccioRangeVolts,
    required this.absoluteMaxInputMinVolts,
    required this.absoluteMaxInputAboveSupplyVolts,
    required this.standards,
    required this.source,
    this.notes = '',
  });

  final String id;
  final String label;
  final String series;
  final String bankType;
  final List<double> vccioRangeVolts;
  final double absoluteMaxInputMinVolts;
  final double absoluteMaxInputAboveSupplyVolts;
  final List<XilinxIoStandard> standards;
  final String notes;
  final String source;

  /// Maps the standards. With [supplyVolts], only standards whose VCCIO range
  /// contains the supply are returned and their thresholds use that supply.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final selected = supplyVolts == null
        ? standards
        : standards
              .where(
                (standard) =>
                    supplyVolts >= standard.vccioRangeVolts.first &&
                    supplyVolts <= standard.vccioRangeVolts.last,
              )
              .toList();
    return <String, dynamic>{
      'id': id,
      'label': label,
      'series': series,
      'bankType': bankType,
      'vccioRangeVolts': vccioRangeVolts,
      'absoluteMaxInput': <String, dynamic>{
        'minVolts': absoluteMaxInputMinVolts,
        'maxAboveSupplyVolts': absoluteMaxInputAboveSupplyVolts,
        if (supplyVolts != null)
          'maxVolts': supplyVolts + absoluteMaxInputAboveSupplyVolts,
      },
      'supplyVolts': ?supplyVolts,
      'standards': [
        for (final standard in selected)
          standard.toMap(supplyVolts: supplyVolts),
      ],
      'notes': notes,
      'source': source,
    };
  }
}

/// Source label for the Lattice FPGA values.
const String latticeLogicSource =
    'Lattice Semiconductor iCE40/MachXO2/MachXO3/ECP5 datasheets '
    '(latticesemi.com)';

/// One single-ended I/O standard of a Lattice FPGA family.
class LatticeIoStandard {
  const LatticeIoStandard({
    required this.name,
    required this.vccioNominalVolts,
    required this.vccioRangeVolts,
    required this.volMaxVolts,
    required this.vohDropFromSupplyVolts,
    required this.driveStrengthsMilliamps,
    this.vilMinVolts = -0.3,
    this.vilMaxVolts,
    this.vilMaxFactorOfSupply,
    this.vihMinVolts,
    this.vihMinFactorOfSupply,
    this.vihMaxVolts,
    this.vihMaxAboveSupplyVolts,
    this.lowDriveCurrentMilliamps,
    this.lowDriveVolMaxVolts = 0.2,
    this.lowDriveVohDropFromSupplyVolts = 0.2,
    this.notes = '',
  });

  final String name;
  final double vccioNominalVolts;
  final List<double> vccioRangeVolts;

  final double vilMinVolts;
  final double? vilMaxVolts;
  final double? vilMaxFactorOfSupply;

  final double? vihMinVolts;
  final double? vihMinFactorOfSupply;

  final double? vihMaxVolts;
  final double? vihMaxAboveSupplyVolts;

  final double volMaxVolts;
  final double vohDropFromSupplyVolts;
  final List<double> driveStrengthsMilliamps;

  final double? lowDriveCurrentMilliamps;
  final double lowDriveVolMaxVolts;
  final double lowDriveVohDropFromSupplyVolts;
  final String notes;

  Map<String, dynamic> toMap({double? supplyVolts}) {
    final supply = supplyVolts ?? vccioNominalVolts;
    final vilMax =
        vilMaxVolts ??
        (vilMaxFactorOfSupply == null ? null : vilMaxFactorOfSupply! * supply);
    final vihMin =
        vihMinVolts ??
        (vihMinFactorOfSupply == null ? null : vihMinFactorOfSupply! * supply);
    final vihMax =
        vihMaxVolts ??
        (vihMaxAboveSupplyVolts == null
            ? null
            : supply + vihMaxAboveSupplyVolts!);
    return <String, dynamic>{
      'name': name,
      'vccioNominalVolts': vccioNominalVolts,
      'vccioRangeVolts': vccioRangeVolts,
      'vilMinVolts': vilMinVolts,
      'vilMaxVolts': ?vilMax,
      'vihMinVolts': ?vihMin,
      'vihMaxVolts': ?vihMax,
      'volMaxVolts': volMaxVolts,
      'vohMinVolts': supply - vohDropFromSupplyVolts,
      'driveStrengthsMilliamps': driveStrengthsMilliamps,
      if (lowDriveCurrentMilliamps != null) ...<String, dynamic>{
        'lowDriveCurrentMilliamps': lowDriveCurrentMilliamps,
        'lowDriveVolMaxVolts': lowDriveVolMaxVolts,
        'lowDriveVohMinVolts': supply - lowDriveVohDropFromSupplyVolts,
      },
      'notes': notes,
    };
  }
}

/// Logic and I/O reference for one Lattice FPGA family.
class LatticeFpgaReference {
  const LatticeFpgaReference({
    required this.id,
    required this.label,
    required this.series,
    required this.vccioRangeVolts,
    required this.absoluteMaxInputVolts,
    required this.standards,
    required this.source,
    this.notes = '',
  });

  final String id;
  final String label;
  final String series;
  final List<double> vccioRangeVolts;
  final double absoluteMaxInputVolts;
  final List<LatticeIoStandard> standards;
  final String notes;
  final String source;

  /// Maps the standards. With [supplyVolts], only standards whose VCCIO range
  /// contains the supply are returned and their thresholds use that supply.
  Map<String, dynamic> toMap({double? supplyVolts}) {
    final selected = supplyVolts == null
        ? standards
        : standards
              .where(
                (standard) =>
                    supplyVolts >= standard.vccioRangeVolts.first &&
                    supplyVolts <= standard.vccioRangeVolts.last,
              )
              .toList();
    return <String, dynamic>{
      'id': id,
      'label': label,
      'series': series,
      'vccioRangeVolts': vccioRangeVolts,
      'absoluteMaxInputVolts': absoluteMaxInputVolts,
      'supplyVolts': ?supplyVolts,
      'standards': [
        for (final standard in selected)
          standard.toMap(supplyVolts: supplyVolts),
      ],
      'notes': notes,
      'source': source,
    };
  }
}
