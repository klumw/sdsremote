/// Process-wide holder for the loaded IC reference catalog.
///
/// The application loads the catalog once during startup. After that, the AI
/// tools read it synchronously; if loading failed, [catalogOrNull] is null and
/// the tool reports an error instead of inventing values.
library;

import 'ic_data_asset_source.dart';
import 'ic_reference_catalog.dart';

class IcReferenceRepository {
  IcReferenceRepository._();

  static final IcReferenceRepository instance = IcReferenceRepository._();

  IcReferenceCatalog? _catalog;
  Future<IcReferenceCatalog>? _pending;
  Object? _lastError;

  /// The loaded catalog, or null when loading has not succeeded.
  IcReferenceCatalog? get catalogOrNull => _catalog;

  /// The error from the last failed load, if any.
  Object? get lastError => _lastError;

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
  Future<IcReferenceCatalog> load(IcDataAssetSource source) {
    final existing = _catalog;
    if (existing != null) {
      return Future<IcReferenceCatalog>.value(existing);
    }
    return _pending ??= _load(source);
  }

  Future<IcReferenceCatalog> _load(IcDataAssetSource source) async {
    try {
      final catalog = await IcReferenceCatalog.load(source);
      _catalog = catalog;
      _lastError = null;
      return catalog;
    } catch (error) {
      _lastError = error;
      _pending = null;
      rethrow;
    }
  }
}
