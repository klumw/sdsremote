/// Flutter-bundled IC reference data.
library;

import 'package:flutter/services.dart';

import 'ic_data_asset_source.dart';

/// Loads IC reference data from the Flutter asset bundle.
///
/// The paths are declared in `pubspec.yaml` under `assets/ic/data/`.
class FlutterIcDataAssetSource implements IcDataAssetSource {
  const FlutterIcDataAssetSource();

  @override
  Future<String> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (error) {
      throw IcDataAssetNotFoundException(path, error);
    }
  }
}
