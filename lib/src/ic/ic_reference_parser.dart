/// Parses IC reference JSON documents into the model classes.
///
/// The parser is pure Dart so tests and command-line tools can load the same
/// files as the Flutter application.
library;

import '../waveform/analysis/logic_level_reference.dart';

/// Supported schema versions of the IC reference documents.
const Set<String> supportedIcSchemaVersions = {'1.0'};

/// Thrown when an IC reference document is malformed.
class IcReferenceParseException implements Exception {
  const IcReferenceParseException(this.message, {this.path, this.itemId});

  final String message;
  final String? path;
  final String? itemId;

  @override
  String toString() {
    final context = <String>[?path, if (itemId != null) 'item "$itemId"'];
    return context.isEmpty ? message : '${context.join(', ')}: $message';
  }
}

/// One decoded family document with its unparsed items.
class IcDataDocument {
  const IcDataDocument({
    required this.path,
    required this.kind,
    required this.source,
    required this.items,
  });

  factory IcDataDocument.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final version = _requiredString(json, 'schema_version', path: path);
    if (!supportedIcSchemaVersions.contains(version)) {
      throw IcReferenceParseException(
        'Unsupported schema_version "$version". Supported versions: '
        '${supportedIcSchemaVersions.join(', ')}.',
        path: path,
      );
    }
    final kind = _requiredString(json, 'kind', path: path);
    final sourceMap = _requiredMap(json, 'source', path: path);
    final source = _requiredString(sourceMap, 'label', path: path);
    final itemsValue = json['items'];
    if (itemsValue is! List || itemsValue.isEmpty) {
      throw IcReferenceParseException(
        'Field "items" must be a non-empty array.',
        path: path,
      );
    }
    final items = <Map<String, dynamic>>[];
    for (var index = 0; index < itemsValue.length; index++) {
      final item = itemsValue[index];
      if (item is! Map<String, dynamic>) {
        throw IcReferenceParseException(
          'items[$index] must be an object.',
          path: path,
        );
      }
      items.add(item);
    }
    return IcDataDocument(path: path, kind: kind, source: source, items: items);
  }

  final String path;
  final String kind;
  final String source;
  final List<Map<String, dynamic>> items;
}

/// Parses one ESP32-family item.
Esp32LogicReference parseEsp32Item(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final input = _requiredMap(json, 'input', path: path, itemId: id);
  final output = _requiredMap(json, 'output', path: path, itemId: id);
  final drive = _requiredMap(json, 'drive', path: path, itemId: id);
  final edges = _requiredMap(json, 'edges', path: path, itemId: id);
  final rise = _requiredMap(edges, 'riseTimeNs', path: path, itemId: id);
  final fall = _requiredMap(edges, 'fallTimeNs', path: path, itemId: id);
  final pull = _requiredMap(
    json,
    'pullResistorsKiloOhms',
    path: path,
    itemId: id,
  );
  final absolute = _requiredMap(
    json,
    'absoluteMaxInput',
    path: path,
    itemId: id,
  );
  final vilMin = _requiredMap(input, 'vilMin', path: path, itemId: id);
  final vilMax = _requiredMap(input, 'vilMax', path: path, itemId: id);
  final vihMin = _requiredMap(input, 'vihMin', path: path, itemId: id);
  final vihMax = _requiredMap(input, 'vihMax', path: path, itemId: id);
  final volMax = _requiredMap(output, 'volMax', path: path, itemId: id);
  final vohMin = _requiredMap(output, 'vohMin', path: path, itemId: id);
  return Esp32LogicReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    aliases: _optionalStringList(json, 'aliases', path: path, itemId: id),
    supplyRangeVolts: _requiredDoubleList(
      json,
      'supplyRangeVolts',
      path: path,
      itemId: id,
    ),
    vilMinVolts: _requiredDouble(vilMin, 'volts', path: path, itemId: id),
    vilFactorOfSupply: _requiredDouble(
      vilMax,
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    vilAbsoluteMaxVolts: _requiredDouble(
      vilMax,
      'capVolts',
      path: path,
      itemId: id,
    ),
    vihFactorOfSupply: _requiredDouble(
      vihMin,
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    vihAbsoluteMinVolts: _requiredDouble(
      vihMin,
      'floorVolts',
      path: path,
      itemId: id,
    ),
    vihMaxAboveSupplyVolts: _requiredDouble(
      vihMax,
      'aboveSupplyVolts',
      path: path,
      itemId: id,
    ),
    volFactorOfSupply: _requiredDouble(
      volMax,
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    volAbsoluteMaxVolts: _requiredDouble(
      volMax,
      'capVolts',
      path: path,
      itemId: id,
    ),
    volTestCurrentMilliamps: _requiredDouble(
      volMax,
      'testCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    vohFactorOfSupply: _requiredDouble(
      vohMin,
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    vohAbsoluteMinVolts: _requiredDouble(
      vohMin,
      'floorVolts',
      path: path,
      itemId: id,
    ),
    vohTestCurrentMilliamps: _requiredDouble(
      vohMin,
      'testCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    maxOutputCurrentMilliamps: _requiredDouble(
      drive,
      'maxOutputCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    recommendedContinuousCurrentMilliamps: _requiredDouble(
      drive,
      'recommendedContinuousCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    riseTimeNsMin: _requiredDouble(rise, 'min', path: path, itemId: id),
    riseTimeNsMax: _requiredDouble(rise, 'max', path: path, itemId: id),
    fallTimeNsMin: _requiredDouble(fall, 'min', path: path, itemId: id),
    fallTimeNsMax: _requiredDouble(fall, 'max', path: path, itemId: id),
    pullUpKiloOhms: _requiredDouble(pull, 'pullUp', path: path, itemId: id),
    pullDownKiloOhms: _requiredDouble(pull, 'pullDown', path: path, itemId: id),
    absoluteMaxInputMinVolts: _requiredDouble(
      absolute,
      'minVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputAboveSupplyVolts: _requiredDouble(
      absolute,
      'maxAboveSupplyVolts',
      path: path,
      itemId: id,
    ),
    notes: _optionalString(json, 'notes') ?? '',
    source: _optionalString(json, 'source') ?? fallbackSource,
  );
}

/// Parses one STM32-series item.
Stm32LogicReference parseStm32Item(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final input = _requiredMap(json, 'input', path: path, itemId: id);
  final output = _requiredMap(json, 'output', path: path, itemId: id);
  final volMax = _requiredMap(output, 'volMax', path: path, itemId: id);
  final vohMin = _requiredMap(output, 'vohMin', path: path, itemId: id);
  final relaxed = _requiredMap(output, 'relaxed', path: path, itemId: id);
  final pull = _requiredMap(
    json,
    'pullResistorsKiloOhms',
    path: path,
    itemId: id,
  );
  final pullUp = _requiredMap(pull, 'pullUp', path: path, itemId: id);
  final pullDown = _requiredMap(pull, 'pullDown', path: path, itemId: id);
  final absolute = _requiredMap(
    json,
    'absoluteMaxInput',
    path: path,
    itemId: id,
  );
  return Stm32LogicReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    series: _requiredString(json, 'series', path: path, itemId: id),
    supplyRangeVolts: _requiredDoubleList(
      json,
      'supplyRangeVolts',
      path: path,
      itemId: id,
    ),
    vilFactorOfSupply: _requiredDouble(
      _requiredMap(input, 'vilMax', path: path, itemId: id),
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    vihFactorOfSupply: _requiredDouble(
      _requiredMap(input, 'vihMin', path: path, itemId: id),
      'factorOfSupply',
      path: path,
      itemId: id,
    ),
    volMaxVolts: _requiredDouble(volMax, 'volts', path: path, itemId: id),
    vohDropFromSupplyVolts: _requiredDouble(
      vohMin,
      'dropFromSupplyVolts',
      path: path,
      itemId: id,
    ),
    relaxedVolMaxVolts: _requiredDouble(
      relaxed,
      'volMaxVolts',
      path: path,
      itemId: id,
    ),
    relaxedVohDropFromSupplyVolts: _requiredDouble(
      relaxed,
      'vohDropFromSupplyVolts',
      path: path,
      itemId: id,
    ),
    nominalOutputCurrentMilliamps: _requiredDouble(
      volMax,
      'testCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    relaxedOutputCurrentMilliamps: _requiredDouble(
      relaxed,
      'testCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    pullUpKiloOhmsMin: _requiredDouble(pullUp, 'min', path: path, itemId: id),
    pullUpKiloOhmsTyp: _requiredDouble(pullUp, 'typ', path: path, itemId: id),
    pullUpKiloOhmsMax: _requiredDouble(pullUp, 'max', path: path, itemId: id),
    pullDownKiloOhmsMin: _requiredDouble(
      pullDown,
      'min',
      path: path,
      itemId: id,
    ),
    pullDownKiloOhmsTyp: _requiredDouble(
      pullDown,
      'typ',
      path: path,
      itemId: id,
    ),
    pullDownKiloOhmsMax: _requiredDouble(
      pullDown,
      'max',
      path: path,
      itemId: id,
    ),
    fiveVoltTolerantPins: _requiredBool(
      absolute,
      'fiveVoltTolerantPins',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputMinVolts: _requiredDouble(
      absolute,
      'minVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputAboveSupplyVolts: _requiredDouble(
      absolute,
      'maxAboveSupplyVolts',
      path: path,
      itemId: id,
    ),
    fiveVoltTolerantMaxVolts: _requiredDouble(
      absolute,
      'fiveVoltTolerantMaxVolts',
      path: path,
      itemId: id,
    ),
    notes: _optionalString(json, 'notes') ?? '',
    source: _optionalString(json, 'source') ?? fallbackSource,
  );
}

/// Parses one Raspberry Pi MCU item.
RaspberryPiLogicReference parseRaspberryPiItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final pointsValue = json['points'];
  if (pointsValue is! List || pointsValue.isEmpty) {
    throw IcReferenceParseException(
      'Field "points" must be a non-empty array.',
      path: path,
      itemId: id,
    );
  }
  final points = <RaspberryPiLogicPoint>[];
  for (var index = 0; index < pointsValue.length; index++) {
    final point = pointsValue[index];
    if (point is! Map<String, dynamic>) {
      throw IcReferenceParseException(
        'points[$index] must be an object.',
        path: path,
        itemId: id,
      );
    }
    points.add(_parseRaspberryPiPoint(point, path: path, itemId: id));
  }
  final absolute = _requiredMap(
    json,
    'absoluteMaxInput',
    path: path,
    itemId: id,
  );
  return RaspberryPiLogicReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    series: _requiredString(json, 'series', path: path, itemId: id),
    supplyRangeVolts: _requiredDoubleList(
      json,
      'supplyRangeVolts',
      path: path,
      itemId: id,
    ),
    points: points,
    driveStrengthsMilliamps: _requiredDoubleList(
      json,
      'driveStrengthsMilliamps',
      path: path,
      itemId: id,
    ),
    totalOutputCurrentMilliamps: _requiredDouble(
      json,
      'totalOutputCurrentMilliamps',
      path: path,
      itemId: id,
    ),
    qspiTotalOutputCurrentMilliamps: _optionalDouble(
      json,
      'qspiTotalOutputCurrentMilliamps',
    ),
    fiveVoltTolerantPins: _requiredBool(
      absolute,
      'fiveVoltTolerantPins',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputMinVolts: _requiredDouble(
      absolute,
      'minVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputAboveSupplyVolts: _requiredDouble(
      absolute,
      'maxAboveSupplyVolts',
      path: path,
      itemId: id,
    ),
    notes: _optionalString(json, 'notes') ?? '',
    source: _optionalString(json, 'source') ?? fallbackSource,
  );
}

RaspberryPiLogicPoint _parseRaspberryPiPoint(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
}) {
  final input = _requiredMap(json, 'input', path: path, itemId: itemId);
  final output = _requiredMap(json, 'output', path: path, itemId: itemId);
  final pull = _requiredMap(
    json,
    'pullResistorsKiloOhms',
    path: path,
    itemId: itemId,
  );
  return RaspberryPiLogicPoint(
    supplyVolts: _requiredDouble(
      json,
      'supplyVolts',
      path: path,
      itemId: itemId,
    ),
    vilMinVolts: _requiredDouble(
      input,
      'vilMinVolts',
      path: path,
      itemId: itemId,
    ),
    vilMaxVolts: _requiredDouble(
      input,
      'vilMaxVolts',
      path: path,
      itemId: itemId,
    ),
    vihMinVolts: _requiredDouble(
      input,
      'vihMinVolts',
      path: path,
      itemId: itemId,
    ),
    vihMaxVolts: _requiredDouble(
      input,
      'vihMaxVolts',
      path: path,
      itemId: itemId,
    ),
    volMaxVolts: _requiredDouble(
      output,
      'volMaxVolts',
      path: path,
      itemId: itemId,
    ),
    vohMinVolts: _requiredDouble(
      output,
      'vohMinVolts',
      path: path,
      itemId: itemId,
    ),
    vhysVolts: _requiredDouble(input, 'vhysVolts', path: path, itemId: itemId),
    pullUpKiloOhmsMin: _optionalDouble(pull, 'pullUpMin'),
    pullUpKiloOhmsMax: _optionalDouble(pull, 'pullUpMax'),
    pullDownKiloOhmsMin: _optionalDouble(pull, 'pullDownMin'),
    pullDownKiloOhmsMax: _optionalDouble(pull, 'pullDownMax'),
    fiveVoltTolerantMaxVolts: _optionalDouble(json, 'fiveVoltTolerantMaxVolts'),
  );
}

/// Parses one standard-logic item.
LogicLevelStandard parseLogicLevelItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final input = _requiredMap(json, 'input', path: path, itemId: id);
  final output = _requiredMap(json, 'output', path: path, itemId: id);
  final vilMax = _optionalMap(input, 'vilMax');
  final vihMin = _optionalMap(input, 'vihMin');
  final volMax = _optionalMap(output, 'volMax');
  final vohMin = _optionalMap(output, 'vohMin');
  final vohTypical = _optionalMap(output, 'vohTypical');
  return LogicLevelStandard(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    family: _requiredString(json, 'family', path: path, itemId: id),
    supplyVolts: _optionalDouble(json, 'supplyVolts'),
    supplyRangeVolts: _optionalDoubleList(
      json,
      'supplyRangeVolts',
      path: path,
      itemId: id,
    ),
    vilMaxVolts: _optionalSpecDouble(vilMax, 'volts'),
    vihMinVolts: _optionalSpecDouble(vihMin, 'volts'),
    volMaxVolts: _optionalSpecDouble(volMax, 'volts'),
    vohMinVolts: _optionalSpecDouble(vohMin, 'volts'),
    vtTypicalVolts: _optionalSpecDouble(
      _optionalMap(input, 'vtTypical'),
      'volts',
    ),
    vtPlusMaxVolts: _optionalSpecDouble(
      _optionalMap(input, 'vtPlusMax'),
      'volts',
    ),
    vtMinusMinVolts: _optionalSpecDouble(
      _optionalMap(input, 'vtMinusMin'),
      'volts',
    ),
    schmittTrigger: _optionalBool(input, 'schmittTrigger') ?? false,
    vilRangeVolts: _optionalSpecDoubleList(vilMax, 'rangeVolts'),
    vihRangeVolts: _optionalSpecDoubleList(vihMin, 'rangeVolts'),
    volRangeVolts: _optionalSpecDoubleList(volMax, 'rangeVolts'),
    vohRangeVolts: _optionalSpecDoubleList(vohMin, 'rangeVolts'),
    vilMaxFactorOfSupply: _optionalSpecDouble(vilMax, 'factorOfSupply'),
    vihMinFactorOfSupply: _optionalSpecDouble(vihMin, 'factorOfSupply'),
    vohTypicalFactorOfSupply: _optionalSpecDouble(vohTypical, 'factorOfSupply'),
    negativeLogic: _optionalString(json, 'logic') == 'negative',
    volNotStated: _optionalBool(output, 'volNotStated') ?? false,
    vohNotStated: _optionalBool(output, 'vohNotStated') ?? false,
    notes: _optionalString(json, 'notes') ?? '',
    source: _optionalString(json, 'source') ?? fallbackSource,
  );
}

/// Parses one edge-time reference item.
LogicEdgeTimeReference parseEdgeTimeItem(
  Map<String, dynamic> json, {
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final points = <LogicEdgeTimePoint>[];
  final pointsValue = json['points'];
  if (pointsValue != null) {
    if (pointsValue is! List) {
      throw IcReferenceParseException(
        'Field "points" must be an array.',
        path: path,
        itemId: id,
      );
    }
    for (var index = 0; index < pointsValue.length; index++) {
      final point = pointsValue[index];
      if (point is! Map<String, dynamic>) {
        throw IcReferenceParseException(
          'points[$index] must be an object.',
          path: path,
          itemId: id,
        );
      }
      points.add(
        LogicEdgeTimePoint(
          supplyVolts: _requiredDouble(
            point,
            'supplyVolts',
            path: path,
            itemId: id,
          ),
          maxEdgeTimeNs: _requiredDouble(
            point,
            'maxEdgeTimeNs',
            path: path,
            itemId: id,
          ),
        ),
      );
    }
  }
  return LogicEdgeTimeReference(
    id: id,
    family: _requiredString(json, 'family', path: path, itemId: id),
    exampleSeries: _requiredString(
      json,
      'exampleSeries',
      path: path,
      itemId: id,
    ),
    points: points,
    supplyRangeVolts: _optionalDoubleList(
      json,
      'supplyRangeVolts',
      path: path,
      itemId: id,
    ),
    maxEdgeTimeNsPerVoltMin: _optionalDouble(json, 'maxEdgeTimeNsPerVoltMin'),
    maxEdgeTimeNsPerVoltMax: _optionalDouble(json, 'maxEdgeTimeNsPerVoltMax'),
    exampleSupplyVolts: _optionalDouble(json, 'exampleSupplyVolts'),
    exampleMaxEdgeTimeNs: _optionalDouble(json, 'exampleMaxEdgeTimeNs'),
    notes: _optionalString(json, 'notes') ?? '',
  );
}

/// Parses one Gowin FPGA item.
GowinFpgaReference parseGowinItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  return GowinFpgaReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    series: _requiredString(json, 'series', path: path, itemId: id),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputVolts: _requiredDouble(
      json,
      'absoluteMaxInputVolts',
      path: path,
      itemId: id,
    ),
    standards: _parseIoStandards(
      json,
      path: path,
      itemId: id,
      parse: (standard) => _parseGowinIo(standard, path: path, itemId: id),
    ),
    source: _optionalString(json, 'source') ?? fallbackSource,
    notes: _optionalString(json, 'notes') ?? '',
  );
}

/// Parses one AMD/Xilinx FPGA item.
XilinxFpgaReference parseXilinxItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  final absolute = _requiredMap(
    json,
    'absoluteMaxInput',
    path: path,
    itemId: id,
  );
  return XilinxFpgaReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    series: _requiredString(json, 'series', path: path, itemId: id),
    bankType: _requiredString(json, 'bankType', path: path, itemId: id),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputMinVolts: _requiredDouble(
      absolute,
      'minVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputAboveSupplyVolts: _requiredDouble(
      absolute,
      'maxAboveSupplyVolts',
      path: path,
      itemId: id,
    ),
    standards: _parseIoStandards(
      json,
      path: path,
      itemId: id,
      parse: (standard) => _parseXilinxIo(standard, path: path, itemId: id),
    ),
    source: _optionalString(json, 'source') ?? fallbackSource,
    notes: _optionalString(json, 'notes') ?? '',
  );
}

/// Parses one Lattice FPGA item.
LatticeFpgaReference parseLatticeItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  return LatticeFpgaReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    series: _requiredString(json, 'series', path: path, itemId: id),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: id,
    ),
    absoluteMaxInputVolts: _requiredDouble(
      json,
      'absoluteMaxInputVolts',
      path: path,
      itemId: id,
    ),
    standards: _parseIoStandards(
      json,
      path: path,
      itemId: id,
      parse: (standard) => _parseLatticeIo(standard, path: path, itemId: id),
    ),
    source: _optionalString(json, 'source') ?? fallbackSource,
    notes: _optionalString(json, 'notes') ?? '',
  );
}

/// Canonical units accepted in component parameter rows.
const Set<String> _componentUnits = {
  'V',
  'A',
  's',
  'Hz',
  'F',
  'Ω',
  '%',
  'dB',
  'dBc',
  'V/s',
};

/// Parses one user-provided component or component-family item.
ComponentReference parseComponentItem(
  Map<String, dynamic> json, {
  required String fallbackSource,
  required String path,
}) {
  final id = _requiredString(json, 'id', path: path);
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
    throw IcReferenceParseException(
      'Field "id" must match ^[a-z][a-z0-9_]*\$.',
      path: path,
      itemId: id,
    );
  }
  final parametersValue = json['parameters'];
  if (parametersValue is! List || parametersValue.isEmpty) {
    throw IcReferenceParseException(
      'Field "parameters" must be a non-empty array.',
      path: path,
      itemId: id,
    );
  }
  final parameters = <ComponentParameter>[];
  for (var index = 0; index < parametersValue.length; index++) {
    final value = parametersValue[index];
    if (value is! Map<String, dynamic>) {
      throw IcReferenceParseException(
        'parameters[$index] must be an object.',
        path: path,
        itemId: id,
      );
    }
    parameters.add(_parseComponentParameter(value, path: path, itemId: id));
  }
  return ComponentReference(
    id: id,
    label: _requiredString(json, 'label', path: path, itemId: id),
    aliases: _optionalStringList(json, 'aliases', path: path, itemId: id),
    vendor: _optionalString(json, 'vendor'),
    partNumber: _optionalString(json, 'partNumber'),
    notes: _optionalString(json, 'notes') ?? '',
    source: _optionalString(json, 'source') ?? fallbackSource,
    parameters: parameters,
  );
}

ComponentParameter _parseComponentParameter(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
}) {
  final reference = _requiredString(
    json,
    'reference',
    path: path,
    itemId: itemId,
  );
  final parameter = _requiredString(
    json,
    'parameter',
    path: path,
    itemId: itemId,
  );
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(parameter)) {
    throw IcReferenceParseException(
      'Field "parameter" must match ^[a-z][a-z0-9_]*\$.',
      path: path,
      itemId: itemId,
    );
  }
  final min = _optionalDouble(json, 'min');
  final typ = _optionalDouble(json, 'typ');
  final max = _optionalDouble(json, 'max');
  final unit = _optionalString(json, 'unit');
  final note = _optionalString(json, 'note');
  if (min == null && typ == null && max == null && note == null) {
    throw IcReferenceParseException(
      'Parameter "$reference/$parameter" requires a value or a note.',
      path: path,
      itemId: itemId,
    );
  }
  if ((min != null || typ != null || max != null) && unit == null) {
    throw IcReferenceParseException(
      'Parameter "$reference/$parameter" requires a unit for its values.',
      path: path,
      itemId: itemId,
    );
  }
  if (unit != null && !_componentUnits.contains(unit)) {
    throw IcReferenceParseException(
      'Parameter "$reference/$parameter" uses unsupported unit "$unit".',
      path: path,
      itemId: itemId,
    );
  }
  return ComponentParameter(
    reference: reference,
    parameter: parameter,
    symbol: _optionalString(json, 'symbol'),
    description: _optionalString(json, 'description'),
    min: min,
    typ: typ,
    max: max,
    unit: unit,
    conditions: _optionalString(json, 'conditions'),
    source: _optionalString(json, 'source'),
    note: note,
  );
}

List<T> _parseIoStandards<T>(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
  required T Function(Map<String, dynamic> standard) parse,
}) {
  final value = json['ioStandards'];
  if (value is! List || value.isEmpty) {
    throw IcReferenceParseException(
      'Field "ioStandards" must be a non-empty array.',
      path: path,
      itemId: itemId,
    );
  }
  final result = <T>[];
  for (var index = 0; index < value.length; index++) {
    final standard = value[index];
    if (standard is! Map<String, dynamic>) {
      throw IcReferenceParseException(
        'ioStandards[$index] must be an object.',
        path: path,
        itemId: itemId,
      );
    }
    result.add(parse(standard));
  }
  return result;
}

GowinIoStandard _parseGowinIo(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
}) {
  final input = _requiredMap(json, 'input', path: path, itemId: itemId);
  final output = _requiredMap(json, 'output', path: path, itemId: itemId);
  final lowDrive = _optionalMap(json, 'lowDrive');
  final vilMax = _optionalMap(input, 'vilMax');
  final vihMin = _optionalMap(input, 'vihMin');
  final vihMax = _optionalMap(input, 'vihMax');
  return GowinIoStandard(
    name: _requiredString(json, 'name', path: path, itemId: itemId),
    vccioNominalVolts: _requiredDouble(
      json,
      'vccioNominalVolts',
      path: path,
      itemId: itemId,
    ),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: itemId,
    ),
    vilMaxVolts: _optionalSpecDouble(vilMax, 'volts'),
    vihMinVolts: _optionalSpecDouble(vihMin, 'volts'),
    vilMaxFactorOfSupply: _optionalSpecDouble(vilMax, 'factorOfSupply'),
    vihMinFactorOfSupply: _optionalSpecDouble(vihMin, 'factorOfSupply'),
    vihMaxVolts: _optionalSpecDouble(vihMax, 'volts'),
    vihMaxAboveSupplyVolts: _optionalSpecDouble(vihMax, 'aboveSupplyVolts'),
    volMaxVolts: _requiredDouble(
      output,
      'volMaxVolts',
      path: path,
      itemId: itemId,
    ),
    vohDropFromSupplyVolts: _requiredDouble(
      output,
      'vohDropFromSupplyVolts',
      path: path,
      itemId: itemId,
    ),
    driveStrengthsMilliamps: _requiredDoubleList(
      output,
      'driveStrengthsMilliamps',
      path: path,
      itemId: itemId,
    ),
    lowDriveCurrentMilliamps:
        _optionalDouble(lowDrive, 'currentMilliamps') ?? 0.1,
    lowDriveVolMaxVolts: _optionalDouble(lowDrive, 'volMaxVolts') ?? 0.2,
    lowDriveVohDropFromSupplyVolts:
        _optionalDouble(lowDrive, 'vohDropFromSupplyVolts') ?? 0.2,
  );
}

XilinxIoStandard _parseXilinxIo(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
}) {
  final input = _requiredMap(json, 'input', path: path, itemId: itemId);
  final output = _requiredMap(json, 'output', path: path, itemId: itemId);
  final vilMax = _optionalMap(input, 'vilMax');
  final vihMin = _optionalMap(input, 'vihMin');
  final vihMax = _optionalMap(input, 'vihMax');
  final volMax = _optionalMap(output, 'volMax');
  final vohMin = _optionalMap(output, 'vohMin');
  return XilinxIoStandard(
    name: _requiredString(json, 'name', path: path, itemId: itemId),
    vccioNominalVolts: _requiredDouble(
      json,
      'vccioNominalVolts',
      path: path,
      itemId: itemId,
    ),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: itemId,
    ),
    driveStrengthsMilliamps: _requiredDoubleList(
      output,
      'driveStrengthsMilliamps',
      path: path,
      itemId: itemId,
    ),
    vilMinVolts: _optionalDouble(input, 'vilMinVolts') ?? -0.3,
    vilMaxVolts: _optionalSpecDouble(vilMax, 'volts'),
    vilMaxFactorOfSupply: _optionalSpecDouble(vilMax, 'factorOfSupply'),
    vihMinVolts: _optionalSpecDouble(vihMin, 'volts'),
    vihMinFactorOfSupply: _optionalSpecDouble(vihMin, 'factorOfSupply'),
    vihMaxVolts: _optionalSpecDouble(vihMax, 'volts'),
    vihMaxAboveSupplyVolts: _optionalSpecDouble(vihMax, 'aboveSupplyVolts'),
    volMaxVolts: _optionalSpecDouble(volMax, 'volts'),
    volFactorOfSupply: _optionalSpecDouble(volMax, 'factorOfSupply'),
    vohMinVolts: _optionalSpecDouble(vohMin, 'volts'),
    vohDropFromSupplyVolts: _optionalSpecDouble(vohMin, 'dropFromSupplyVolts'),
    vohFactorOfSupply: _optionalSpecDouble(vohMin, 'factorOfSupply'),
  );
}

LatticeIoStandard _parseLatticeIo(
  Map<String, dynamic> json, {
  required String path,
  required String itemId,
}) {
  final input = _requiredMap(json, 'input', path: path, itemId: itemId);
  final output = _requiredMap(json, 'output', path: path, itemId: itemId);
  final lowDrive = _optionalMap(json, 'lowDrive');
  final vilMax = _optionalMap(input, 'vilMax');
  final vihMin = _optionalMap(input, 'vihMin');
  final vihMax = _optionalMap(input, 'vihMax');
  return LatticeIoStandard(
    name: _requiredString(json, 'name', path: path, itemId: itemId),
    vccioNominalVolts: _requiredDouble(
      json,
      'vccioNominalVolts',
      path: path,
      itemId: itemId,
    ),
    vccioRangeVolts: _requiredDoubleList(
      json,
      'vccioRangeVolts',
      path: path,
      itemId: itemId,
    ),
    volMaxVolts: _requiredDouble(
      output,
      'volMaxVolts',
      path: path,
      itemId: itemId,
    ),
    vohDropFromSupplyVolts: _requiredDouble(
      output,
      'vohDropFromSupplyVolts',
      path: path,
      itemId: itemId,
    ),
    driveStrengthsMilliamps: _requiredDoubleList(
      output,
      'driveStrengthsMilliamps',
      path: path,
      itemId: itemId,
    ),
    vilMinVolts: _optionalDouble(input, 'vilMinVolts') ?? -0.3,
    vilMaxVolts: _optionalSpecDouble(vilMax, 'volts'),
    vilMaxFactorOfSupply: _optionalSpecDouble(vilMax, 'factorOfSupply'),
    vihMinVolts: _optionalSpecDouble(vihMin, 'volts'),
    vihMinFactorOfSupply: _optionalSpecDouble(vihMin, 'factorOfSupply'),
    vihMaxVolts: _optionalSpecDouble(vihMax, 'volts'),
    vihMaxAboveSupplyVolts: _optionalSpecDouble(vihMax, 'aboveSupplyVolts'),
    lowDriveCurrentMilliamps: _optionalDouble(lowDrive, 'currentMilliamps'),
    lowDriveVolMaxVolts: _optionalDouble(lowDrive, 'volMaxVolts') ?? 0.2,
    lowDriveVohDropFromSupplyVolts:
        _optionalDouble(lowDrive, 'vohDropFromSupplyVolts') ?? 0.2,
    notes: _optionalString(json, 'notes') ?? '',
  );
}

Map<String, dynamic>? _optionalMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is Map<String, dynamic> ? value : null;
}

double? _optionalSpecDouble(Map<String, dynamic>? map, String key) {
  if (map == null) {
    return null;
  }
  return _optionalDouble(map, key);
}

List<double>? _optionalSpecDoubleList(Map<String, dynamic>? map, String key) {
  if (map == null) {
    return null;
  }
  final value = map[key];
  if (value is List &&
      value.every((element) => element is num && element.isFinite)) {
    return [for (final element in value) (element as num).toDouble()];
  }
  return null;
}

bool? _optionalBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is bool ? value : null;
}

String _requiredString(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw IcReferenceParseException(
    'Field "$key" must be a non-empty string.',
    path: path,
    itemId: itemId,
  );
}

String? _optionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}

double _requiredDouble(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  throw IcReferenceParseException(
    'Field "$key" must be a finite number.',
    path: path,
    itemId: itemId,
  );
}

double? _optionalDouble(Map<String, dynamic>? map, String key) {
  if (map == null) {
    return null;
  }
  final value = map[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}

List<double>? _optionalDoubleList(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is List &&
      value.every((element) => element is num && element.isFinite)) {
    return [for (final element in value) (element as num).toDouble()];
  }
  throw IcReferenceParseException(
    'Field "$key" must be an array of finite numbers.',
    path: path,
    itemId: itemId,
  );
}

bool _requiredBool(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  throw IcReferenceParseException(
    'Field "$key" must be a boolean.',
    path: path,
    itemId: itemId,
  );
}

List<double> _requiredDoubleList(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value is List &&
      value.isNotEmpty &&
      value.every((element) => element is num && element.isFinite)) {
    return [for (final element in value) (element as num).toDouble()];
  }
  throw IcReferenceParseException(
    'Field "$key" must be a non-empty array of finite numbers.',
    path: path,
    itemId: itemId,
  );
}

List<String> _optionalStringList(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value == null) {
    return const [];
  }
  if (value is List &&
      value.every(
        (element) => element is String && element.trim().isNotEmpty,
      )) {
    return [for (final element in value) element as String];
  }
  throw IcReferenceParseException(
    'Field "$key" must be an array of non-empty strings.',
    path: path,
    itemId: itemId,
  );
}

Map<String, dynamic> _requiredMap(
  Map<String, dynamic> map,
  String key, {
  required String path,
  String? itemId,
}) {
  final value = map[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw IcReferenceParseException(
    'Field "$key" must be an object.',
    path: path,
    itemId: itemId,
  );
}
