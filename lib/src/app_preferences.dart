import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

/// File-based preferences store backed by a JSON file in the
/// `<app working dir>/preferences/` subdirectory.
///
/// Replaces [SharedPreferences] so that all application settings are
/// kept inside the SDS Remote working directory.
class AppPreferences {
  AppPreferences._();

  static const String _fileName = 'preferences.json';
  static Map<String, dynamic>? _cache;

  /// Returns the full path to the preferences JSON file.
  static Future<File> get _file async {
    final dir = await AppPaths.getOrCreatePreferencesDir();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the JSON map from disk, or returns an empty map if the file
  /// does not exist yet.
  static Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    final file = await _file;
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        _cache = jsonDecode(content) as Map<String, dynamic>;
      } catch (_) {
        _cache = <String, dynamic>{};
      }
    } else {
      _cache = <String, dynamic>{};
    }
    return _cache!;
  }

  /// Writes the current in-memory map back to disk atomically.
  static Future<void> _save() async {
    if (_cache == null) return;
    final file = await _file;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_cache));
    await tmp.rename(file.path);
  }

  // ---------------------------------------------------------------------------
  // Public API – mirrors SharedPreferences
  // ---------------------------------------------------------------------------

  static Future<String?> getString(String key) async {
    final map = await _load();
    final v = map[key];
    return v is String ? v : null;
  }

  static Future<bool?> getBool(String key) async {
    final map = await _load();
    final v = map[key];
    return v is bool ? v : null;
  }

  static Future<int?> getInt(String key) async {
    final map = await _load();
    final v = map[key];
    return v is int ? v : null;
  }

  static Future<void> setString(String key, String value) async {
    final map = await _load();
    map[key] = value;
    await _save();
  }

  static Future<void> setBool(String key, bool value) async {
    final map = await _load();
    map[key] = value;
    await _save();
  }

  static Future<void> setInt(String key, int value) async {
    final map = await _load();
    map[key] = value;
    await _save();
  }

  /// Writes multiple key-value pairs in a single atomic operation.
  ///
  /// Accepts a map with mixed value types ([String], [bool], [int], etc.).
  /// This avoids the race condition that would occur when calling
  /// [setString] / [setBool] / [setInt] sequentially without `await`.
  static Future<void> setAll(Map<String, dynamic> values) async {
    final map = await _load();
    map.addAll(values);
    await _save();
  }

  /// Discards the in-memory cache so the next read reloads from disk.
  static void invalidateCache() {
    _cache = null;
  }
}
