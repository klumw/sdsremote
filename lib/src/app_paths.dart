import 'dart:io';

/// Provides OS-specific default directory paths for SDS Remote data files.
///
/// - Linux:   ~/.local/share/sdsremote/
/// - Windows: %LocalAppData%\sdsremote\
/// - Other:   Directory.current (fallback)
///
/// File-type-specific subdirectories within the working directory:
///   screenshots/        Screen dump images
///   profiles/           Instrument profile (.lss) files
///   waveform/images/    Waveform chart PNG images
///   waveform/csv/       Waveform data CSV files (save & reference load)
///   logger/reports/     Data logger PDF reports
///   logger/csv/         Data logger CSV data files
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

  // ---------------------------------------------------------------------------
  // Type-specific subdirectories
  // ---------------------------------------------------------------------------

  static final String _sep = Platform.pathSeparator;

  /// `  <app working dir>/screenshots  `
  static Directory get screenshotsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}screenshots');

  /// `  <app working dir>/profiles  `
  static Directory get profilesDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}profiles');

  /// `  <app working dir>/waveform/images  `
  static Directory get waveformImagesDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}waveform${_sep}images');

  /// `  <app working dir>/waveform/csv  `
  static Directory get waveformCsvDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}waveform${_sep}csv');

  /// `  <app working dir>/logger/reports  `
  static Directory get loggerReportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}logger${_sep}reports');

  /// `  <app working dir>/logger/csv  `
  static Directory get loggerCsvDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}logger${_sep}csv');

  /// `  <app working dir>/preferences  `
  static Directory get preferencesDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}preferences');

  // ---------------------------------------------------------------------------
  // Convenience: ensure-and-get
  // ---------------------------------------------------------------------------

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

  static Future<Directory> getOrCreateScreenshotsDir() =>
      ensureDirectoryExists(screenshotsDirectory);

  static Future<Directory> getOrCreateProfilesDir() =>
      ensureDirectoryExists(profilesDirectory);

  static Future<Directory> getOrCreateWaveformImagesDir() =>
      ensureDirectoryExists(waveformImagesDirectory);

  static Future<Directory> getOrCreateWaveformCsvDir() =>
      ensureDirectoryExists(waveformCsvDirectory);

  static Future<Directory> getOrCreateLoggerReportsDir() =>
      ensureDirectoryExists(loggerReportsDirectory);

  static Future<Directory> getOrCreateLoggerCsvDir() =>
      ensureDirectoryExists(loggerCsvDirectory);

  static Future<Directory> getOrCreatePreferencesDir() =>
      ensureDirectoryExists(preferencesDirectory);

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
