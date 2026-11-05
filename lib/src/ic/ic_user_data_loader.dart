/// Loads user-provided IC component references from the application data
/// directory.
///
/// The bundled reference documents under `assets/ic/data` are read-only. The
/// SpecAnalyst stores extracted components under `<app data>/ic/data`; this
/// loader scans that directory and returns the parsed components. A malformed
/// local file is skipped with a warning so it never prevents the bundled data
/// from loading.
library;

import 'dart:convert';
import 'dart:io';

import '../waveform/analysis/logic_level_reference.dart';
import 'ic_reference_parser.dart';

/// Result of scanning the local IC data directory.
class IcUserDataLoadResult {
  const IcUserDataLoadResult({
    required this.components,
    required this.warnings,
    required this.directoryPath,
  });

  final List<ComponentReference> components;

  /// Non-fatal problems found while scanning the directory.
  final List<String> warnings;

  final String directoryPath;
}

/// Loads all `*.json` component documents from [directory].
///
/// A missing directory yields an empty result. Files that cannot be read, are
/// not valid JSON, or do not use `kind: "component"` are skipped and reported
/// through [IcUserDataLoadResult.warnings].
Future<IcUserDataLoadResult> loadUserIcData(Directory directory) async {
  final warnings = <String>[];
  final components = <ComponentReference>[];
  if (!await directory.exists()) {
    return IcUserDataLoadResult(
      components: const [],
      warnings: const [],
      directoryPath: directory.path,
    );
  }

  List<FileSystemEntity> entries;
  try {
    entries = await directory.list().toList();
  } on Object catch (error) {
    warnings.add('Could not list "${directory.path}": $error');
    return IcUserDataLoadResult(
      components: const [],
      warnings: warnings,
      directoryPath: directory.path,
    );
  }
  entries.sort((a, b) => a.path.compareTo(b.path));

  for (final entry in entries) {
    if (entry is! File || !entry.path.toLowerCase().endsWith('.json')) {
      continue;
    }
    try {
      final text = await entry.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        warnings.add(
          'Skipped "${entry.path}": the document root must be an object.',
        );
        continue;
      }
      final document = IcDataDocument.fromJson(decoded, path: entry.path);
      if (document.kind != 'component') {
        warnings.add(
          'Skipped "${entry.path}": local IC data must use kind "component", '
          'found "${document.kind}".',
        );
        continue;
      }
      for (final item in document.items) {
        components.add(
          parseComponentItem(
            item,
            fallbackSource: document.source,
            path: entry.path,
          ),
        );
      }
    } on IcReferenceParseException catch (error) {
      warnings.add('Skipped "${entry.path}": $error');
    } on FormatException catch (error) {
      warnings.add('Skipped "${entry.path}": invalid JSON (${error.message}).');
    } on Object catch (error) {
      warnings.add('Skipped "${entry.path}": $error');
    }
  }

  return IcUserDataLoadResult(
    components: components,
    warnings: warnings,
    directoryPath: directory.path,
  );
}
