/// Abstraction over bundled Flutter assets and filesystem files for IC data.
///
/// The core IC reference layer depends only on [IcDataAssetSource], so tests
/// can use [InMemoryIcDataAssetSource] or [FileIcDataAssetSource] without a
/// Flutter binding. The application uses `FlutterIcDataAssetSource`.
library;

import 'dart:io';

/// Thrown when an IC data asset path does not exist or cannot be read.
class IcDataAssetNotFoundException implements Exception {
  const IcDataAssetNotFoundException(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() =>
      'IC data asset "$path" was not found'
      '${cause == null ? '' : ' ($cause)'}.';
}

/// Loads an IC data asset by its bundle-relative path.
abstract class IcDataAssetSource {
  Future<String> loadString(String path);
}

/// Reads IC data assets from the filesystem.
///
/// Relative paths are resolved against [rootPath]. Tests and command-line
/// tools use this source; the application uses the Flutter bundle source.
class FileIcDataAssetSource implements IcDataAssetSource {
  FileIcDataAssetSource({String? rootPath})
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
      throw IcDataAssetNotFoundException(path);
    }
    try {
      return await file.readAsString();
    } catch (error) {
      throw IcDataAssetNotFoundException(path, error);
    }
  }
}

/// In-memory asset source for unit tests.
class InMemoryIcDataAssetSource implements IcDataAssetSource {
  InMemoryIcDataAssetSource([Map<String, String>? files])
    : _files = Map<String, String>.from(files ?? const {});

  final Map<String, String> _files;

  @override
  Future<String> loadString(String path) async {
    final value = _files[path];
    if (value == null) {
      throw IcDataAssetNotFoundException(path);
    }
    return value;
  }
}
