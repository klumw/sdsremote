/// Process-wide holder for the loaded IC reference catalog.
///
/// The application loads the catalog once during startup. After that, the AI
/// tools read it synchronously; if loading failed, [catalogOrNull] is null and
/// the tool reports an error instead of inventing values.
///
/// The repository also merges user-provided component documents from the
/// application data directory. [reload] refreshes the catalog after the
/// SpecAnalyst saved a new component.
library;

import 'dart:io';

import 'ic_data_asset_source.dart';
import 'ic_reference_catalog.dart';
import 'ic_user_data_loader.dart';

class IcReferenceRepository {
  IcReferenceRepository._();

  static final IcReferenceRepository instance = IcReferenceRepository._();

  IcReferenceCatalog? _catalog;
  Future<IcReferenceCatalog>? _pending;
  Object? _lastError;
  IcDataAssetSource? _source;
  Directory? _userDataDirectory;
  List<String> _warnings = const [];

  /// The loaded catalog, or null when loading has not succeeded.
  IcReferenceCatalog? get catalogOrNull => _catalog;

  /// The error from the last failed load, if any.
  Object? get lastError => _lastError;

  /// Non-fatal warnings from the last load (for example skipped local files).
  List<String> get warnings => _warnings;

  /// The loaded catalog.
  ///
  /// Throws a [StateError] when [load] has not completed successfully.
  IcReferenceCatalog get catalog {
    final value = _catalog;
    if (value == null) {
      throw StateError(
        'IC reference data is not loaded. Call load() before using the '
        'reference tables.',
      );
    }
    return value;
  }

  /// Loads the catalog once. Concurrent and repeated calls share the result.
  ///
  /// [userDataDirectory] is scanned for `*.json` component documents and
  /// merged into the bundled catalog.
  Future<IcReferenceCatalog> load(
    IcDataAssetSource source, {
    Directory? userDataDirectory,
  }) {
    final sameTarget =
        identical(_source, source) &&
        _userDataDirectory?.path == userDataDirectory?.path;
    final existing = _catalog;
    if (existing != null && sameTarget) {
      return Future<IcReferenceCatalog>.value(existing);
    }
    final pending = _pending;
    if (pending != null && sameTarget) return pending;
    _source = source;
    _userDataDirectory = userDataDirectory;
    _catalog = null;
    _pending = null;
    return _pending ??= _load(source, userDataDirectory);
  }

  /// Reloads the bundled catalog and the local component documents.
  Future<IcReferenceCatalog> reload() {
    final source = _source;
    if (source == null) {
      return Future<IcReferenceCatalog>.error(
        StateError('IC reference data has not been loaded yet.'),
      );
    }
    _catalog = null;
    _pending = null;
    return _pending ??= _load(source, _userDataDirectory);
  }

  Future<IcReferenceCatalog> _load(
    IcDataAssetSource source,
    Directory? userDataDirectory,
  ) async {
    try {
      final bundled = await IcReferenceCatalog.load(source);
      var catalog = bundled;
      var warnings = const <String>[];
      if (userDataDirectory != null) {
        final userData = await loadUserIcData(userDataDirectory);
        warnings = userData.warnings;
        if (userData.components.isNotEmpty) {
          final componentWarnings = <String>[];
          catalog = bundled.withComponents(
            userData.components,
            warnings: componentWarnings,
          );
          if (componentWarnings.isNotEmpty) {
            warnings = [...warnings, ...componentWarnings];
          }
        }
      }
      _catalog = catalog;
      _warnings = List.unmodifiable(warnings);
      _lastError = null;
      _source = source;
      _userDataDirectory = userDataDirectory;
      return catalog;
    } catch (error) {
      _lastError = error;
      _pending = null;
      rethrow;
    }
  }
}
