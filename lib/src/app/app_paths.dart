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
///   waveform/csv/       Waveform data CSV files (save & reference load)
///   waveform/reports/   Waveform PDF measurement reports
///   waveform/exports/   Waveform export files (PWL, WAV, VCD)
///   logger/reports/     Data logger PDF reports
///   logger/csv/         Data logger CSV data files
///   timelapse/          Timelapse run folders with PNG frames
///   bode/reports/       Bode plot PDF reports
///   bode/csv/           Bode plot CSV data files
///   automation/macros/  Macro (.m) files
///   automation/reports/ Macro PDF reports
///   ic/data/            User-provided IC reference components
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

  /// `  <app working dir>/waveform/csv  `
  static Directory get waveformCsvDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}waveform${_sep}csv');

  /// `  <app working dir>/waveform/reports  `
  static Directory get waveformReportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}waveform${_sep}reports');

  /// `  <app working dir>/waveform/exports  `
  static Directory get waveformExportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}waveform${_sep}exports');

  /// `  <app working dir>/logger/reports  `
  static Directory get loggerReportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}logger${_sep}reports');

  /// `  <app working dir>/logger/csv  `
  static Directory get loggerCsvDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}logger${_sep}csv');

  /// `  <app working dir>/timelapse  `
  static Directory get timelapseDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}timelapse');

  /// `  <app working dir>/bode/reports  `
  static Directory get bodeReportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}bode${_sep}reports');

  /// `  <app working dir>/bode/csv  `
  static Directory get bodeCsvDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}bode${_sep}csv');

  /// `  <app working dir>/automation/macros  `
  static Directory get macrosDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}automation${_sep}macros');

  /// `  <app working dir>/automation/reports  `
  static Directory get macroReportsDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}automation${_sep}reports');

  /// `  <app working dir>/preferences  `
  static Directory get preferencesDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}preferences');

  /// `  <app working dir>/calculator  `
  static Directory get calculatorDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}calculator');

  /// `  <app working dir>/ic/data  `
  ///
  /// Stores component and family reference documents that were extracted by
  /// the SpecAnalyst. The directory is separate from the bundled
  /// `assets/ic/data` documents and can be edited by the user.
  static Directory get icDataDirectory =>
      Directory('${defaultSaveDirectory.path}${_sep}ic${_sep}data');

  /// `  <app working dir>/calculator/workspace.json  `
  static File get calculatorWorkspaceFile => File(
    '${defaultSaveDirectory.path}${_sep}calculator${_sep}workspace.json',
  );

  /// `<app working dir>/preferences/fault_analysis_profile.json`
  ///
  /// Long-term store for user-supplied fault-analysis specifications. The
  /// file is organized per channel and contains reference values, tolerances
  /// and limits only; measured values and analysis results are not stored.
  static File get faultAnalysisProfileFile => File(
    '${defaultSaveDirectory.path}${_sep}preferences${_sep}fault_analysis_profile.json',
  );

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

  static Future<Directory> getOrCreateWaveformCsvDir() =>
      ensureDirectoryExists(waveformCsvDirectory);

  static Future<Directory> getOrCreateWaveformReportsDir() =>
      ensureDirectoryExists(waveformReportsDirectory);

  static Future<Directory> getOrCreateWaveformExportsDir() =>
      ensureDirectoryExists(waveformExportsDirectory);

  static Future<Directory> getOrCreateLoggerReportsDir() =>
      ensureDirectoryExists(loggerReportsDirectory);

  static Future<Directory> getOrCreateLoggerCsvDir() =>
      ensureDirectoryExists(loggerCsvDirectory);

  static Future<Directory> getOrCreateTimelapseDir() =>
      ensureDirectoryExists(timelapseDirectory);

  static Future<Directory> getOrCreateBodeReportsDir() =>
      ensureDirectoryExists(bodeReportsDirectory);

  static Future<Directory> getOrCreateBodeCsvDir() =>
      ensureDirectoryExists(bodeCsvDirectory);

  static Future<Directory> getOrCreateMacrosDir() =>
      ensureDirectoryExists(macrosDirectory);

  static Future<Directory> getOrCreateMacroReportsDir() =>
      ensureDirectoryExists(macroReportsDirectory);

  static Future<Directory> getOrCreatePreferencesDir() =>
      ensureDirectoryExists(preferencesDirectory);

  static Future<Directory> getOrCreateCalculatorDir() =>
      ensureDirectoryExists(calculatorDirectory);

  static Future<Directory> getOrCreateIcDataDir() =>
      ensureDirectoryExists(icDataDirectory);

  /// Returns a [File] with a unique filename in [directory].
  ///
  /// If `[baseName].[extension]` already exists, appends `(1)`, `(2)`, etc.
  /// before the extension until a free name is found.
  ///
  /// Example: `getUniqueFilePath(dir, 'screen_dump', 'png')`
  ///   -> `screen_dump.png` if free,
  ///   -> `screen_dump(1).png` if taken,
  ///   -> `screen_dump(2).png` if both taken, etc.
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
