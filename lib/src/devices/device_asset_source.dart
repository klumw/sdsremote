/// Abstraction over bundled Flutter assets and filesystem files.
///
/// The core device-profile layer depends only on [DeviceAssetSource], so tests
/// can use [InMemoryDeviceAssetSource] or [FileDeviceAssetSource] without a
/// Flutter binding. The application uses `FlutterDeviceAssetSource`, which is
/// kept in a separate file to keep this library free of Flutter imports.
library;

import 'dart:io';

/// Thrown when an asset path does not exist.
class DeviceAssetNotFoundException implements Exception {
  const DeviceAssetNotFoundException(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() =>
      'Device asset "$path" was not found'
      '${cause == null ? '' : ' ($cause)'}.';
}

/// Loads a device asset by its bundle-relative path.
abstract class DeviceAssetSource {
  Future<String> loadString(String path);
}

/// Reads device assets from the filesystem.
///
/// Relative paths are resolved against [rootPath]. Tests and command-line
/// tools use this source; the application uses the Flutter bundle source.
class FileDeviceAssetSource implements DeviceAssetSource {
  FileDeviceAssetSource({String? rootPath})
    : _rootPath = rootPath ?? Directory.current.path;

  final String _rootPath;

  @override
  Future<String> loadString(String path) async {
    final normalized = path.replaceAll('/', Platform.pathSeparator);
    final file = File(
      normalized.startsWith(Platform.pathSeparator)
          ? normalized
          : '$_rootPath${Platform.pathSeparator}$normalized',
    );
    if (!await file.exists()) {
      throw DeviceAssetNotFoundException(path);
    }
    try {
      return await file.readAsString();
    } catch (error) {
      throw DeviceAssetNotFoundException(path, error);
    }
  }
}

/// In-memory asset source for unit tests.
class InMemoryDeviceAssetSource implements DeviceAssetSource {
  InMemoryDeviceAssetSource([Map<String, String>? files])
    : _files = Map<String, String>.from(files ?? const {});

  final Map<String, String> _files;

  @override
  Future<String> loadString(String path) async {
    final value = _files[path];
    if (value == null) {
      throw DeviceAssetNotFoundException(path);
    }
    return value;
  }
}
