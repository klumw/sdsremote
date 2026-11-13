part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeCursorsZoom on _OsciHomePageState {
  /// Checks if the mouse position is near any cursor line.
  /// Returns the index of the nearest cursor, or null if none is close enough.
  int? _findNearestCursor(double relX, double relY) {
    double minDist = double.infinity;
    int? closestIndex;

    if (_cursorState.cursorsXEnabled) {
      final d1 = (relX - _cursorState.cursorX1).abs();
      final d2 = (relX - _cursorState.cursorX2).abs();
      if (d1 < minDist) {
        minDist = d1;
        closestIndex = 0;
      }
      if (d2 < minDist) {
        minDist = d2;
        closestIndex = 1;
      }
    }

    if (_cursorState.cursorsYEnabled) {
      final d1 = (relY - _cursorState.cursorY1).abs();
      final d2 = (relY - _cursorState.cursorY2).abs();
      if (d1 < minDist) {
        minDist = d1;
        closestIndex = 2;
      }
      if (d2 < minDist) {
        minDist = d2;
        closestIndex = 3;
      }
    }

    // Only return a cursor if it's within the hit threshold
    if (closestIndex != null &&
        minDist <= _OsciHomePageState._cursorHitThreshold) {
      return closestIndex;
    }
    return null;
  }

  void _onZoomFactorChanged(double factor) {
    _setState(() {
      // When zooming out completely to 1.0x, reset pan to center
      // so the waveform returns to its original centered position.
      _zoomState = _zoomState.copyWith(
        zoomFactor: factor,
        panX: factor == 1.0 ? 0.5 : null,
        panY: factor == 1.0 ? 0.5 : null,
      );
    });
  }

  void _onPanXChanged(double panX) {
    _setState(() {
      _zoomState = _zoomState.copyWith(panX: panX);
    });
  }

  void _onPanYChanged(double panY) {
    _setState(() {
      _zoomState = _zoomState.copyWith(panY: panY);
    });
  }

  Widget _buildHorizontalPanSlider() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SliderTheme(
        data: const SliderThemeData(
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: Colors.cyanAccent,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.cyanAccent,
        ),
        child: Slider(value: _zoomState.panX, onChanged: _onPanXChanged),
      ),
    );
  }

  Widget _buildVerticalPanSlider() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground.withValues(alpha: 0.8),
        border: const Border(left: BorderSide(color: AppColors.border)),
      ),
      child: RotatedBox(
        quarterTurns: 1,
        child: SliderTheme(
          data: const SliderThemeData(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.orangeAccent,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.orangeAccent,
          ),
          child: Slider(value: _zoomState.panY, onChanged: _onPanYChanged),
        ),
      ),
    );
  }

  void _onDeviceParamChannelToggle(String channel) {
    _setState(() {
      switch (channel) {
        case 'CH1':
          _ch1Enabled = !_ch1Enabled;
        case 'CH2':
          _ch2Enabled = !_ch2Enabled;
        case 'CH3':
          _ch3Enabled = !_ch3Enabled;
        case 'CH4':
          _ch4Enabled = !_ch4Enabled;
      }
    });
  }

  void _onCursorXToggled(bool enabled) {
    _setState(() {
      _cursorState = _cursorState.copyWith(cursorsXEnabled: enabled);
    });
  }

  void _onCursorYToggled(bool enabled) {
    _setState(() {
      _cursorState = _cursorState.copyWith(cursorsYEnabled: enabled);
    });
  }

  /// Returns the size of the waveform widget, or null if not available.
  Size? _getWaveformSize() {
    final renderBox =
        _waveformKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size;
  }

  Rect? _getCursorInfoPanelRect(Size size) =>
      getCursorInfoPanelRect(size, _cursorState);

  void _onCursorHover(PointerHoverEvent event) {
    // While the reference is being moved the cursor drag is suspended, so no
    // cursor highlight is computed either.
    if (_refMoving) {
      if (_hoveredCursorType != null) {
        _setState(() => _hoveredCursorType = null);
      }
      return;
    }

    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = event.localPosition;
    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    // Check if hovering over cursor info panel
    final panelRect = _getCursorInfoPanelRect(size);
    final bool overPanel = panelRect != null && panelRect.contains(localPos);

    if (overPanel) {
      if (_hoveredCursorType != 'info') {
        _setState(() => _hoveredCursorType = 'info');
      }
      return;
    }

    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) {
      if (_hoveredCursorType != null) {
        _setState(() => _hoveredCursorType = null);
      }
      return;
    }

    final nearest = _findNearestCursor(relX, relY);
    final newType = switch (nearest) {
      null => null,
      0 || 1 => 'x',
      _ => 'y',
    };

    if (newType != _hoveredCursorType) {
      _setState(() => _hoveredCursorType = newType);
    }
  }

  void _onCursorDragStart(DragStartDetails details) {
    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = details.localPosition;

    // Check if starting drag on cursor info panel
    final panelRect = _getCursorInfoPanelRect(size);
    if (panelRect != null && panelRect.contains(localPos)) {
      _draggingCursorInfo = true;
      return;
    }

    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) return;

    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    // Only start drag if directly over a cursor line
    final nearest = _findNearestCursor(relX, relY);
    if (nearest != null) {
      _draggingCursorIndex = nearest;
    }
  }

  Offset _clampCursorInfoOffset(Offset proposedOffset, Size size) =>
      clampCursorInfoOffset(proposedOffset, size, _cursorState);

  void _onCursorDragUpdate(DragUpdateDetails details) {
    if (_draggingCursorInfo) {
      final size = _getWaveformSize();
      if (size == null || size.width == 0 || size.height == 0) return;

      final newOffset = _cursorState.cursorInfoOffset + details.delta;
      final clampedOffset = _clampCursorInfoOffset(newOffset, size);
      _setState(() {
        _cursorState = _cursorState.copyWith(cursorInfoOffset: clampedOffset);
      });
      return;
    }

    if (_draggingCursorIndex == null) return;

    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = details.localPosition;
    final relX = (localPos.dx / size.width).clamp(0.0, 1.0);
    final relY = (localPos.dy / size.height).clamp(0.0, 1.0);

    _setState(() {
      switch (_draggingCursorIndex) {
        case 0:
          _cursorState = _cursorState.copyWith(cursorX1: relX);
          break;
        case 1:
          _cursorState = _cursorState.copyWith(cursorX2: relX);
          break;
        case 2:
          _cursorState = _cursorState.copyWith(cursorY1: relY);
          break;
        case 3:
          _cursorState = _cursorState.copyWith(cursorY2: relY);
          break;
      }
    });
  }

  void _onCursorDragEnd(DragEndDetails details) {
    _draggingCursorIndex = null;
    _draggingCursorInfo = false;
  }
}
