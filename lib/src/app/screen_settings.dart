import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

/// Brightness and contrast applied to the Control Panel screenshot and the
/// live VNC stream.
///
/// The values only affect the rendered image. The captured screen dump bytes
/// used for reports stay untouched.
class ScreenSettings {
  /// Brightness offset in the range [minBrightness]..[maxBrightness].
  ///
  /// 0.0 leaves the image unchanged.
  final double brightness;

  /// Contrast factor in the range [minContrast]..[maxContrast].
  ///
  /// 1.0 leaves the image unchanged.
  final double contrast;

  static const double minBrightness = -1.0;
  static const double maxBrightness = 1.0;
  static const double minContrast = 0.5;
  static const double maxContrast = 2.0;

  /// Settings that render the image unchanged.
  static const ScreenSettings defaults = ScreenSettings(
    brightness: 0.0,
    contrast: 1.0,
  );

  const ScreenSettings({required this.brightness, required this.contrast});

  /// Whether the settings leave the image unchanged.
  bool get isNeutral => brightness == 0.0 && contrast == 1.0;

  /// Returns the 4x5 matrix for `ColorFilter.matrix`.
  ///
  /// Contrast scales the color channels around the 128 midpoint and
  /// brightness adds an offset of up to ±128. Alpha stays unchanged.
  List<double> toColorMatrix() {
    final offset = 128.0 * (1.0 - contrast) + brightness * 128.0;
    return <double>[
      contrast, 0, 0, 0, offset, //
      0, contrast, 0, 0, offset, //
      0, 0, contrast, 0, offset, //
      0, 0, 0, 1, 0,
    ];
  }

  /// Returns a copy with both values clamped to their allowed ranges.
  ScreenSettings clamped() => ScreenSettings(
    brightness: brightness.clamp(minBrightness, maxBrightness),
    contrast: contrast.clamp(minContrast, maxContrast),
  );

  @override
  bool operator ==(Object other) =>
      other is ScreenSettings &&
      other.brightness == brightness &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(brightness, contrast);
}

/// Loads and saves [ScreenSettings] in `<app working dir>/preferences/screen.json`.
class ScreenSettingsStore {
  ScreenSettingsStore._();

  static const String _fileName = 'screen.json';

  /// Loads the persisted settings.
  ///
  /// Falls back to [ScreenSettings.defaults] when the file is missing or
  /// malformed; out-of-range values are clamped.
  static Future<ScreenSettings> load() async {
    final file = AppPaths.screenSettingsFile;
    if (!await file.exists()) return ScreenSettings.defaults;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return ScreenSettings.defaults;
      }
      final brightness = decoded['brightness'];
      final contrast = decoded['contrast'];
      return ScreenSettings(
        brightness: brightness is num
            ? brightness.toDouble()
            : ScreenSettings.defaults.brightness,
        contrast: contrast is num
            ? contrast.toDouble()
            : ScreenSettings.defaults.contrast,
      ).clamped();
    } catch (_) {
      return ScreenSettings.defaults;
    }
  }

  /// Writes [settings] atomically to `screen.json`.
  static Future<void> save(ScreenSettings settings) async {
    final dir = await AppPaths.getOrCreatePreferencesDir();
    final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(<String, double>{
        'brightness': settings.brightness,
        'contrast': settings.contrast,
      }),
    );
    await tmp.rename(file.path);
  }
}
