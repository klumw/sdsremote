/// Flutter-bundled device assets.
library;

import 'package:flutter/services.dart';

import 'device_asset_source.dart';

/// Loads device command and knowledge files from the Flutter asset bundle.
///
/// The paths are declared in `pubspec.yaml`:
/// `assets/devices/commands/` and `assets/devices/knowledge/`.
class FlutterDeviceAssetSource implements DeviceAssetSource {
  const FlutterDeviceAssetSource();

  @override
  Future<String> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (error) {
      throw DeviceAssetNotFoundException(path, error);
    }
  }
}
