/// Writes SpecAnalyst extractions as IC reference component documents.
///
/// The writer normalizes the user-supplied name, converts the extracted rows
/// to the canonical parameter units, validates the generated document with the
/// runtime parser, and writes it atomically to `<app data>/ic/data`.
library;

import 'dart:convert';
import 'dart:io';

import '../app/app_paths.dart';
import '../waveform/analysis/specification_models.dart';
import 'ic_reference_parser.dart';

/// Result of a component-save operation.
class IcReferenceSaveResult {
  const IcReferenceSaveResult({
    this.saved = false,
    this.fileExists = false,
    this.filePath,
    this.error,
    this.warnings = const [],
  });

  final bool saved;

  /// True when the target file already exists and no overwrite was allowed.
  final bool fileExists;

  final String? filePath;
  final String? error;

  /// Non-fatal problems such as rows whose unit could not be converted.
  final List<String> warnings;

  Map<String, dynamic> toMap() => <String, dynamic>{
    if (saved) 'saved': true,
    if (fileExists) 'fileExists': true,
    if (filePath != null) 'savedFile': filePath,
    if (error != null) 'saveError': error,
    if (warnings.isNotEmpty) 'saveWarnings': warnings,
  };
}

/// Normalizes a component name to an IC reference id and file name.
///
/// The schema requires ids to start with a lowercase letter. A name that
/// starts with a digit or symbol therefore receives the `ic_` prefix.
String normalizeIcReferenceId(String name) {
  var normalized = name.trim().toLowerCase();
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  if (normalized.isEmpty) return '';
  if (!RegExp(r'^[a-z]').hasMatch(normalized)) {
    normalized = 'ic_$normalized';
  }
  return normalized;
}

/// Target file for the component [id].
File icReferenceFile(String id) =>
    File('${AppPaths.icDataDirectory.path}${Platform.pathSeparator}$id.json');

/// Whether a component file with [id] already exists.
Future<bool> icReferenceFileExists(String id) async {
  if (id.isEmpty) return false;
  return icReferenceFile(id).exists();
}

/// Saves the extracted [rows] as one component document.
///
/// [id] is normalized again for safety. When the target exists and
/// [overwrite] is false, the result reports [IcReferenceSaveResult.fileExists]
/// and nothing is written. Rows whose unit cannot be converted are stored as
/// a note with their original values instead of numeric fields.
Future<IcReferenceSaveResult> saveComponentReference({
  required String label,
  required String id,
  required bool overwrite,
  required List<SpecParameterRow> rows,
  String? sourceName,
  String? summary,
  List<String> warnings = const [],
}) async {
  final cleanedLabel = label.trim();
  if (cleanedLabel.isEmpty) {
    return const IcReferenceSaveResult(error: 'The component name is empty.');
  }
  final normalizedId = normalizeIcReferenceId(id);
  if (normalizedId.isEmpty) {
    return const IcReferenceSaveResult(
      error: 'The component name does not contain any usable characters.',
    );
  }

  final target = icReferenceFile(normalizedId);
  if (await target.exists() && !overwrite) {
    return IcReferenceSaveResult(
      fileExists: true,
      filePath: target.path,
      error: 'A reference file for "$cleanedLabel" already exists.',
    );
  }

  final parameters = <Map<String, dynamic>>[];
  final saveWarnings = <String>[];
  for (final row in rows) {
    final map = _componentParameterMap(row, saveWarnings);
    if (map != null) parameters.add(map);
  }
  if (parameters.isEmpty) {
    return IcReferenceSaveResult(
      error:
          'The analysis contained no electrical values or notes that can be '
          'stored.',
      warnings: saveWarnings,
    );
  }

  final notes = _buildNotes(summary, warnings);
  final document = <String, dynamic>{
    'schema_version': '1.0',
    'kind': 'component',
    'source': <String, dynamic>{
      'label': (sourceName == null || sourceName.trim().isEmpty)
          ? 'SpecAnalyst extraction'
          : sourceName.trim(),
      'retrieved': _todayUtc(),
    },
    if (notes.isNotEmpty) 'notes': notes,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': normalizedId,
        'label': cleanedLabel,
        'parameters': parameters,
      },
    ],
  };

  // Validate with the same parser the application uses at startup. This
  // guarantees that a saved file can be loaded again on the next start.
  try {
    final decoded = IcDataDocument.fromJson(document, path: target.path);
    for (final item in decoded.items) {
      parseComponentItem(
        item,
        fallbackSource: decoded.source,
        path: target.path,
      );
    }
  } on IcReferenceParseException catch (error) {
    return IcReferenceSaveResult(
      error: 'The generated IC reference is invalid: $error',
      warnings: saveWarnings,
    );
  }

  try {
    final directory = await AppPaths.getOrCreateIcDataDir();
    final file = File(
      '${directory.path}${Platform.pathSeparator}$normalizedId.json',
    );
    await _writeAtomic(file, document);
    return IcReferenceSaveResult(
      saved: true,
      filePath: file.path,
      warnings: saveWarnings,
    );
  } on Object catch (error) {
    return IcReferenceSaveResult(
      error: 'Could not save the IC reference: $error',
      warnings: saveWarnings,
    );
  }
}

Map<String, dynamic>? _componentParameterMap(
  SpecParameterRow row,
  List<String> warnings,
) {
  final unitError = row.unitError;
  if (unitError != null) {
    final original = <String>[
      if (row.min != null) 'min=${row.min} ${row.unit}'.trim(),
      if (row.typ != null) 'typ=${row.typ} ${row.unit}'.trim(),
      if (row.max != null) 'max=${row.max} ${row.unit}'.trim(),
    ].join(', ');
    warnings.add('${row.reference} ${row.parameter.id}: $unitError');
    return <String, dynamic>{
      'reference': row.reference,
      'parameter': row.parameter.id,
      if (row.symbol != null) 'symbol': row.symbol,
      if (row.description != null) 'description': row.description,
      'note': original.isEmpty
          ? unitError
          : '$unitError Original values: $original.',
      if (row.conditions != null) 'conditions': row.conditions,
      if (row.source != null) 'source': row.source,
    };
  }

  final min = row.minCanonical;
  final typ = row.typCanonical;
  final max = row.maxCanonical;
  final hasValues = min != null || typ != null || max != null;
  if (!hasValues && row.note == null) return null;

  return <String, dynamic>{
    'reference': row.reference,
    'parameter': row.parameter.id,
    if (row.symbol != null) 'symbol': row.symbol,
    if (row.description != null) 'description': row.description,
    'min': ?min,
    'typ': ?typ,
    'max': ?max,
    if (hasValues) 'unit': row.parameter.unit,
    if (row.conditions != null) 'conditions': row.conditions,
    if (row.source != null) 'source': row.source,
    if (row.note != null) 'note': row.note,
  };
}

String _buildNotes(String? summary, List<String> warnings) {
  final parts = <String>[
    if (summary != null && summary.trim().isNotEmpty) summary.trim(),
    for (final warning in warnings)
      if (warning.trim().isNotEmpty) warning.trim(),
  ];
  return parts.join('\n');
}

String _todayUtc() {
  final now = DateTime.now().toUtc();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

Future<void> _writeAtomic(File target, Map<String, dynamic> document) async {
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(document),
    flush: true,
  );
  try {
    await temporary.rename(target.path);
  } on FileSystemException {
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}
