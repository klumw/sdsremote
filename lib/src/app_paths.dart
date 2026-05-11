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
}
