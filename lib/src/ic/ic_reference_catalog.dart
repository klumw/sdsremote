/// Loads and indexes the IC reference JSON data.
///
/// The catalog is immutable after loading. Lookups are synchronous so the AI
/// tool can build its input schemas and resolve arguments without awaiting.
library;

import 'dart:convert';

import '../waveform/analysis/logic_level_reference.dart';
import 'ic_data_asset_source.dart';
import 'ic_reference_parser.dart';

const String _indexPath = 'assets/ic/data/index.json';

/// Reference data loaded from `assets/ic/data`.
class IcReferenceCatalog {
  IcReferenceCatalog({
    required List<LogicLevelStandard> standards,
    required List<LogicEdgeTimeReference> edgeTimes,
    required List<Esp32LogicReference> esp32Variants,
    required List<Stm32LogicReference> stm32Series,
    required List<RaspberryPiLogicReference> raspberryPiMcus,
    required List<GowinFpgaReference> gowinFpgas,
    required List<XilinxFpgaReference> xilinxFpgas,
    required List<LatticeFpgaReference> latticeFpgas,
    List<ComponentReference> components = const [],
    required this.logicSource,
    required this.edgeTimeSource,
    required this.esp32Source,
    required this.stm32Source,
    required this.raspberryPiSource,
    required this.gowinSource,
    required this.xilinxSource,
    required this.latticeSource,
    this.componentSource = componentReferenceSource,
  }) : standards = List.unmodifiable(standards),
       edgeTimes = List.unmodifiable(edgeTimes),
       esp32Variants = List.unmodifiable(esp32Variants),
       stm32Series = List.unmodifiable(stm32Series),
       raspberryPiMcus = List.unmodifiable(raspberryPiMcus),
       gowinFpgas = List.unmodifiable(gowinFpgas),
       xilinxFpgas = List.unmodifiable(xilinxFpgas),
       latticeFpgas = List.unmodifiable(latticeFpgas),
       components = List.unmodifiable(components),
       _standardLookup = _buildLookup(
         standards,
         (item) => [item.id, item.label],
       ),
       _esp32Lookup = _buildLookup(
         esp32Variants,
         (item) => [item.id, item.label, ...item.aliases],
       ),
       _stm32Lookup = _buildLookup(
         stm32Series,
         (item) => [item.id, item.label, item.series],
       ),
       _raspberryPiLookup = _buildLookup(
         raspberryPiMcus,
         (item) => [item.id, item.label, item.series],
       ),
       _gowinLookup = _buildLookup(
         gowinFpgas,
         (item) => [item.id, item.label, item.series],
       ),
       _xilinxLookup = _buildLookup(
         xilinxFpgas,
         (item) => [item.id, item.label, item.series],
       ),
       _latticeLookup = _buildLookup(
         latticeFpgas,
         (item) => [item.id, item.label, item.series],
       ),
       _componentLookup = _buildLookup(
         components,
         (item) => [item.id, item.label, ...item.aliases],
       );

  final List<LogicLevelStandard> standards;
  final List<LogicEdgeTimeReference> edgeTimes;
  final List<Esp32LogicReference> esp32Variants;
  final List<Stm32LogicReference> stm32Series;
  final List<RaspberryPiLogicReference> raspberryPiMcus;
  final List<GowinFpgaReference> gowinFpgas;
  final List<XilinxFpgaReference> xilinxFpgas;
  final List<LatticeFpgaReference> latticeFpgas;

  /// User-provided component and family references.
  final List<ComponentReference> components;

  /// Section source labels from the family documents.
  final String logicSource;
  final String edgeTimeSource;
  final String esp32Source;
  final String stm32Source;
  final String raspberryPiSource;
  final String gowinSource;
  final String xilinxSource;
  final String latticeSource;

  /// Source label for the user-provided component references.
  final String componentSource;

  final Map<String, LogicLevelStandard> _standardLookup;
  final Map<String, Esp32LogicReference> _esp32Lookup;
  final Map<String, Stm32LogicReference> _stm32Lookup;
  final Map<String, RaspberryPiLogicReference> _raspberryPiLookup;
  final Map<String, GowinFpgaReference> _gowinLookup;
  final Map<String, XilinxFpgaReference> _xilinxLookup;
  final Map<String, LatticeFpgaReference> _latticeLookup;
  final Map<String, ComponentReference> _componentLookup;

  /// Loads the index and all referenced family documents.
  static Future<IcReferenceCatalog> load(IcDataAssetSource source) async {
    final index = await _loadJson(source, _indexPath);
    final version = index['schema_version'];
    if (version is! String || !supportedIcSchemaVersions.contains(version)) {
      throw IcReferenceParseException(
        'Unsupported schema_version "$version". Supported versions: '
        '${supportedIcSchemaVersions.join(', ')}.',
        path: _indexPath,
      );
    }
    final filesValue = index['files'];
    if (filesValue is! List || filesValue.isEmpty) {
      throw IcReferenceParseException(
        'Field "files" must be a non-empty array.',
        path: _indexPath,
      );
    }
    final files = <String>[];
    for (final value in filesValue) {
      if (value is! String || value.trim().isEmpty) {
        throw IcReferenceParseException(
          'Field "files" must contain non-empty paths.',
          path: _indexPath,
        );
      }
      files.add(value);
    }
    final documents = await Future.wait(
      files.map((path) async {
        final json = await _loadJson(source, path);
        return IcDataDocument.fromJson(json, path: path);
      }),
    );
    return _fromDocuments(documents);
  }

  /// Finds a standard logic family by id or label, then by family name.
  ///
  /// Several standards share a family name (for example the CMOS families),
  /// so the family fallback returns the first match in table order.
  LogicLevelStandard? findStandard(String? value) {
    final direct = _findReference(_standardLookup, value);
    if (direct != null) {
      return direct;
    }
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final standard in standards) {
      if (standard.family.toLowerCase() == normalized) {
        return standard;
      }
    }
    return null;
  }

  /// Finds an ESP32 variant by id, label, alias or series name.
  Esp32LogicReference? findEsp32Variant(String? value) =>
      _findReference(_esp32Lookup, value);

  /// Finds an STM32 series by id, label or series name.
  Stm32LogicReference? findStm32Series(String? value) =>
      _findReference(_stm32Lookup, value);

  /// Finds a Raspberry Pi MCU by id, label or series name.
  RaspberryPiLogicReference? findRaspberryPiMcu(String? value) =>
      _findReference(_raspberryPiLookup, value);

  /// Finds a Gowin FPGA family by id, label or series name.
  GowinFpgaReference? findGowinFpga(String? value) =>
      _findReference(_gowinLookup, value);

  /// Finds an AMD/Xilinx FPGA bank type by id, label or series name.
  XilinxFpgaReference? findXilinxFpga(String? value) =>
      _findReference(_xilinxLookup, value);

  /// Finds a Lattice FPGA family by id, label or series name.
  LatticeFpgaReference? findLatticeFpga(String? value) =>
      _findReference(_latticeLookup, value);

  /// Finds a user-provided component by id, label or alias.
  ComponentReference? findComponent(String? value) =>
      _findReference(_componentLookup, value);

  /// Returns a copy with [additional] user components appended.
  ///
  /// Components whose id, label or alias is already defined are skipped and
  /// reported through [warnings] when the list is provided.
  IcReferenceCatalog withComponents(
    List<ComponentReference> additional, {
    List<String>? warnings,
  }) {
    if (additional.isEmpty) return this;
    final knownKeys = <String>{};
    for (final component in components) {
      knownKeys.addAll(_componentKeys(component));
    }
    final added = <ComponentReference>[];
    for (final component in additional) {
      final keys = _componentKeys(component);
      String? conflict;
      for (final key in keys) {
        if (knownKeys.contains(key)) {
          conflict = key;
          break;
        }
      }
      if (conflict != null) {
        warnings?.add(
          'Component "${component.label}" was skipped because the key '
          '"$conflict" is already defined.',
        );
        continue;
      }
      knownKeys.addAll(keys);
      added.add(component);
    }
    if (added.isEmpty) return this;
    return IcReferenceCatalog(
      standards: standards,
      edgeTimes: edgeTimes,
      esp32Variants: esp32Variants,
      stm32Series: stm32Series,
      raspberryPiMcus: raspberryPiMcus,
      gowinFpgas: gowinFpgas,
      xilinxFpgas: xilinxFpgas,
      latticeFpgas: latticeFpgas,
      components: [...components, ...added],
      logicSource: logicSource,
      edgeTimeSource: edgeTimeSource,
      esp32Source: esp32Source,
      stm32Source: stm32Source,
      raspberryPiSource: raspberryPiSource,
      gowinSource: gowinSource,
      xilinxSource: xilinxSource,
      latticeSource: latticeSource,
      componentSource: componentSource,
    );
  }

  static Set<String> _componentKeys(ComponentReference component) {
    final keys = <String>{};
    for (final key in [component.id, component.label, ...component.aliases]) {
      final normalized = key.trim().toLowerCase();
      if (normalized.isNotEmpty) keys.add(normalized);
    }
    return keys;
  }

  static IcReferenceCatalog _fromDocuments(List<IcDataDocument> documents) {
    final standards = <LogicLevelStandard>[];
    final edgeTimes = <LogicEdgeTimeReference>[];
    final esp32 = <Esp32LogicReference>[];
    final stm32 = <Stm32LogicReference>[];
    final raspberryPi = <RaspberryPiLogicReference>[];
    final gowin = <GowinFpgaReference>[];
    final xilinx = <XilinxFpgaReference>[];
    final lattice = <LatticeFpgaReference>[];
    final components = <ComponentReference>[];
    String? logicSource;
    String? edgeTimeSource;
    String? esp32Source;
    String? stm32Source;
    String? raspberryPiSource;
    String? gowinSource;
    String? xilinxSource;
    String? latticeSource;
    String? componentSource;

    for (final document in documents) {
      if (document.kind == 'standard_logic') {
        logicSource ??= document.source;
        for (final item in document.items) {
          standards.add(
            parseLogicLevelItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'edge_times') {
        edgeTimeSource ??= document.source;
        for (final item in document.items) {
          edgeTimes.add(parseEdgeTimeItem(item, path: document.path));
        }
      } else if (document.kind == 'esp32') {
        esp32Source ??= document.source;
        for (final item in document.items) {
          esp32.add(
            parseEsp32Item(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'stm32') {
        stm32Source ??= document.source;
        for (final item in document.items) {
          stm32.add(
            parseStm32Item(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'raspberry_pi') {
        raspberryPiSource ??= document.source;
        for (final item in document.items) {
          raspberryPi.add(
            parseRaspberryPiItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'gowin_fpga') {
        gowinSource ??= document.source;
        for (final item in document.items) {
          gowin.add(
            parseGowinItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'xilinx_fpga') {
        xilinxSource ??= document.source;
        for (final item in document.items) {
          xilinx.add(
            parseXilinxItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'lattice_fpga') {
        latticeSource ??= document.source;
        for (final item in document.items) {
          lattice.add(
            parseLatticeItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else if (document.kind == 'component') {
        componentSource ??= document.source;
        for (final item in document.items) {
          components.add(
            parseComponentItem(
              item,
              fallbackSource: document.source,
              path: document.path,
            ),
          );
        }
      } else {
        throw IcReferenceParseException(
          'Unsupported kind "${document.kind}".',
          path: document.path,
        );
      }
    }

    if (standards.isEmpty ||
        edgeTimes.isEmpty ||
        esp32.isEmpty ||
        stm32.isEmpty ||
        raspberryPi.isEmpty ||
        gowin.isEmpty ||
        xilinx.isEmpty ||
        lattice.isEmpty) {
      throw const IcReferenceParseException(
        'The IC reference index must contain standard_logic, edge_times, '
        'esp32, stm32, raspberry_pi, gowin_fpga, xilinx_fpga and '
        'lattice_fpga documents.',
      );
    }

    return IcReferenceCatalog(
      standards: standards,
      edgeTimes: edgeTimes,
      esp32Variants: esp32,
      stm32Series: stm32,
      raspberryPiMcus: raspberryPi,
      gowinFpgas: gowin,
      xilinxFpgas: xilinx,
      latticeFpgas: lattice,
      components: components,
      logicSource: logicSource ?? logicLevelSource,
      edgeTimeSource: edgeTimeSource ?? logicEdgeTimeSource,
      esp32Source: esp32Source ?? esp32LogicSource,
      stm32Source: stm32Source ?? stm32LogicSource,
      raspberryPiSource: raspberryPiSource ?? raspberryPiLogicSource,
      gowinSource: gowinSource ?? gowinFpgaLogicSource,
      xilinxSource: xilinxSource ?? xilinxLogicSource,
      latticeSource: latticeSource ?? latticeLogicSource,
      componentSource: componentSource ?? componentReferenceSource,
    );
  }

  static Future<Map<String, dynamic>> _loadJson(
    IcDataAssetSource source,
    String path,
  ) async {
    final text = await source.loadString(path);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw IcReferenceParseException(
        'The document root must be an object.',
        path: path,
      );
    } on FormatException catch (error) {
      throw IcReferenceParseException(
        'Invalid JSON: ${error.message}',
        path: path,
      );
    }
  }

  static T? _findReference<T>(Map<String, T> lookup, String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return lookup[normalized];
  }

  static Map<String, T> _buildLookup<T>(
    List<T> items,
    Iterable<String> Function(T item) keysOf,
  ) {
    final lookup = <String, T>{};
    for (final item in items) {
      final itemKeys = <String>{};
      for (final key in keysOf(item)) {
        final normalized = key.trim().toLowerCase();
        if (normalized.isEmpty || !itemKeys.add(normalized)) {
          continue;
        }
        if (lookup.containsKey(normalized)) {
          throw IcReferenceParseException('Duplicate IC reference key "$key".');
        }
        lookup[normalized] = item;
      }
    }
    return lookup;
  }
}
