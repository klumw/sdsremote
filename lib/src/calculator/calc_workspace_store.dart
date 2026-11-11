/// File-backed named workspaces for the engineering calculator.
///
/// The default workspace (`workspace.json`) is managed by `CalcSession` and is
/// deliberately excluded here. Named workspaces are explicit snapshots written
/// by the user through the export dialog.
library;

import 'dart:io';

import '../app/app_paths.dart';

/// One named workspace file on disk.
class CalcWorkspaceFile {
  const CalcWorkspaceFile({
    required this.name,
    required this.file,
    required this.modified,
  });

  /// User-visible name without the `.json` extension.
  final String name;

  final File file;

  final DateTime modified;
}

/// Reads, writes, lists and deletes named calculator workspaces.
class CalcWorkspaceStore {
  CalcWorkspaceStore({Directory? directory}) : _directoryOverride = directory;

  /// File extension of a named workspace.
  static const String extension = 'json';

  /// Base name of the automatically saved default workspace.
  static const String defaultBaseName = 'workspace';

  final Directory? _directoryOverride;

  /// Directory that holds the named workspace files.
  Directory get directory => _directoryOverride ?? AppPaths.calculatorDirectory;

  /// The automatically saved workspace file managed by `CalcSession`.
  File get defaultFile {
    final override = _directoryOverride;
    if (override == null) return AppPaths.calculatorWorkspaceFile;
    return File(
      '${override.path}${Platform.pathSeparator}'
      '$defaultBaseName.$extension',
    );
  }

  /// Normalizes [raw] and validates it as a workspace name.
  ///
  /// A trailing `.json` is accepted and stripped. Throws [FormatException]
  /// with a user-facing message when the name is not usable.
  static String normalizeName(String raw) {
    var name = raw.trim();
    if (name.toLowerCase().endsWith('.$extension')) {
      name = name.substring(0, name.length - extension.length - 1).trim();
    }
    if (name.isEmpty) {
      throw const FormatException('Enter a workspace name.');
    }
    if (name.toLowerCase() == defaultBaseName) {
      throw const FormatException(
        'The name "workspace" is reserved for the default workspace.',
      );
    }
    if (name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      throw const FormatException('The name must not contain path separators.');
    }
    if (RegExp(r'[\x00-\x1F<>:"|?*]').hasMatch(name)) {
      throw const FormatException(
        'The name contains characters that are not allowed in file names.',
      );
    }
    if (name.endsWith('.') || name.endsWith(' ')) {
      throw const FormatException(
        'The name must not end with a dot or a space.',
      );
    }
    return name;
  }

  /// The file that holds the named workspace [name].
  Future<File> fileFor(String name) async {
    final normalized = normalizeName(name);
    await directory.create(recursive: true);
    return File(
      '${directory.path}${Platform.pathSeparator}$normalized.$extension',
    );
  }

  /// Whether a named workspace [name] already exists.
  Future<bool> exists(String name) async => (await fileFor(name)).exists();

  /// Lists all named workspace files, sorted by name.
  ///
  /// The default `workspace.json` and temporary files are excluded.
  Future<List<CalcWorkspaceFile>> list() async {
    if (!await directory.exists()) return const [];
    final entries = <CalcWorkspaceFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final baseName = entity.uri.pathSegments.last;
      if (!baseName.toLowerCase().endsWith('.$extension')) continue;
      final name = baseName.substring(
        0,
        baseName.length - extension.length - 1,
      );
      if (name.isEmpty || name.toLowerCase() == defaultBaseName) continue;
      DateTime modified;
      try {
        modified = await entity.lastModified();
      } on FileSystemException {
        modified = DateTime.fromMillisecondsSinceEpoch(0);
      }
      entries.add(
        CalcWorkspaceFile(name: name, file: entity, modified: modified),
      );
    }
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return entries;
  }

  /// Writes [jsonText] to the named workspace [name] and returns the file.
  Future<File> write(String name, String jsonText) async {
    final file = await fileFor(name);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonText, flush: true);
    await temporary.rename(file.path);
    return file;
  }

  /// Reads a workspace file.
  Future<String> read(File file) => file.readAsString();

  /// Reads the automatically saved default workspace, or null when it has not
  /// been created yet.
  Future<String?> readDefault() async {
    final file = defaultFile;
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Modification time of the default workspace, or null when it does not
  /// exist.
  Future<DateTime?> defaultModified() async {
    final file = defaultFile;
    if (!await file.exists()) return null;
    try {
      return await file.lastModified();
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// Deletes a named workspace file.
  Future<void> delete(CalcWorkspaceFile workspace) => workspace.file.delete();
}
