import 'dart:io';

/// Provides OS-specific default directory paths for SDS Remote data files.
///
/// - Linux:   ~/.local/share/sdsremote/
/// - Windows: %LocalAppData%\sdsremote\
/// - Other:   Directory.current (fallback)
class AppPaths {
  AppPaths._();

  /// Returns the platform-specific default save directory.
  static Directory get defaultSaveDirectory {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      return Directory('$home/.local/share/sdsremote');
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '.';
      return Directory('$localAppData\\sdsremote');
    }
    // Fallback for unsupported platforms
    return Directory.current;
  }

  /// Ensures the directory exists, creating it (and parents) if needed.
  static Future<Directory> ensureDirectoryExists(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Shortcut: returns the default save directory and ensures it exists.
  static Future<Directory> getOrCreateDefaultDirectory() =>
      ensureDirectoryExists(defaultSaveDirectory);

  /// Returns a [File] with a unique filename in [directory].
  ///
  /// If `[baseName].[extension]` already exists, appends `(1)`, `(2)`, etc.
  /// before the extension until a free name is found.
  ///
  /// Example: `getUniqueFilePath(dir, 'screen_dump', 'png')`
  ///   → `screen_dump.png` if free,
  ///   → `screen_dump(1).png` if taken,
  ///   → `screen_dump(2).png` if both taken, etc.
  static Future<File> getUniqueFilePath(
    Directory directory,
    String baseName,
    String extension,
  ) async {
    String candidate = '$baseName.$extension';
    if (!await File('${directory.path}/$candidate').exists()) {
      return File('${directory.path}/$candidate');
    }
    int n = 1;
    while (true) {
      candidate = '$baseName($n).$extension';
      if (!await File('${directory.path}/$candidate').exists()) {
        return File('${directory.path}/$candidate');
      }
      n++;
    }
  }
}
