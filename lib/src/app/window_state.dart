import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/logger.dart';
import 'app_preferences.dart';

/// Persists and restores the size and position of the main window.
///
/// Geometry is stored in the normal preferences file, so it survives restarts
/// without a separate configuration format. A saved position is only restored
/// when a meaningful part of the window would still be visible on one of the
/// connected displays; otherwise the window is centered so it can never open
/// completely off-screen after a monitor change.
class WindowStateStore {
  WindowStateStore._();

  static const String _widthKey = 'window.width';
  static const String _heightKey = 'window.height';
  static const String _xKey = 'window.x';
  static const String _yKey = 'window.y';

  /// Loads the last saved geometry, falling back to the default size and a
  /// centered window when nothing usable is stored.
  static Future<WindowGeometry> load() async {
    final width = await AppPreferences.getInt(_widthKey);
    final height = await AppPreferences.getInt(_heightKey);
    final x = await AppPreferences.getInt(_xKey);
    final y = await AppPreferences.getInt(_yKey);

    return WindowGeometry.fromSavedValues(
      width: width,
      height: height,
      x: x,
      y: y,
      displayBounds: await _displayBounds(),
    );
  }

  /// Saves the current size and position.
  ///
  /// Errors are logged but never propagated: a geometry write must not block
  /// or break application shutdown.
  static Future<void> save() async {
    try {
      final bounds = await windowManager.getBounds();
      await AppPreferences.setAll(<String, int>{
        _widthKey: bounds.width.round(),
        _heightKey: bounds.height.round(),
        _xKey: bounds.left.round(),
        _yKey: bounds.top.round(),
      });
    } catch (error) {
      AppLogger(
        agentName: 'WindowState',
        toolName: 'save',
      ).log('Could not save window geometry: $error');
    }
  }

  /// Returns the usable rectangles of all displays, in logical pixels.
  ///
  /// An empty list disables position validation.
  static Future<List<Rect>> _displayBounds() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      return [
        for (final display in displays)
          Rect.fromLTWH(
            (display.visiblePosition ?? Offset.zero).dx,
            (display.visiblePosition ?? Offset.zero).dy,
            (display.visibleSize ?? display.size).width,
            (display.visibleSize ?? display.size).height,
          ),
      ];
    } catch (error) {
      AppLogger(
        agentName: 'WindowState',
        toolName: 'load',
      ).log('Could not read display bounds, centering the window: $error');
      return const <Rect>[];
    }
  }
}

/// Size and optional position of the main window.
class WindowGeometry {
  /// Size used on the very first start (and when no size is stored).
  static const Size defaultSize = Size(1400, 900);

  /// Smallest size the window may have.
  static const Size minimumSize = Size(1400, 900);

  /// Minimum overlap with a display for a saved position to be accepted.
  static const double _minVisibleWidth = 200;
  static const double _minVisibleHeight = 40;

  final Size size;

  /// `null` means "no usable saved position; center the window".
  final Offset? position;

  const WindowGeometry({required this.size, this.position});

  /// Creates a geometry from the persisted integers.
  ///
  /// Exposed for tests so the validation can be exercised without platform
  /// channels. [displayBounds] are the usable areas of the connected displays.
  @visibleForTesting
  static WindowGeometry fromSavedValues({
    required int? width,
    required int? height,
    required int? x,
    required int? y,
    required List<Rect> displayBounds,
  }) {
    final size = Size(
      math.max((width ?? defaultSize.width).toDouble(), minimumSize.width),
      math.max((height ?? defaultSize.height).toDouble(), minimumSize.height),
    );

    if (x == null || y == null || displayBounds.isEmpty) {
      return WindowGeometry(size: size);
    }

    final position = Offset(x.toDouble(), y.toDouble());
    if (!_isVisible(position, size, displayBounds)) {
      return WindowGeometry(size: size);
    }
    return WindowGeometry(size: size, position: position);
  }

  static bool _isVisible(Offset position, Size size, List<Rect> displayBounds) {
    final window = Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );
    for (final display in displayBounds) {
      final overlap = window.intersect(display);
      if (overlap.width >= _minVisibleWidth &&
          overlap.height >= _minVisibleHeight) {
        return true;
      }
    }
    return false;
  }
}
