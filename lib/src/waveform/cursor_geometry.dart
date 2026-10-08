import 'dart:ui';

import '../waveform_models.dart';

/// Panel geometry constants for the cursor info overlay.
const double cursorPanelWidth = 200.0;
const double cursorPanelPadding = 12.0;
const double cursorRowHeight = 20.0;
const double cursorHeaderHeight = 24.0;
const double cursorSectionGap = 8.0;
const double cursorPanelMargin = 12.0;

/// Computes the height of the cursor info panel based on which cursor
/// types are enabled.
///
/// X cursors contribute 2 rows, Y cursors contribute 3 rows.
double computeCursorPanelHeight(CursorState cursorState) {
  final yRows = cursorState.cursorsYEnabled ? 3 : 0;
  final xRows = cursorState.cursorsXEnabled ? 2 : 0;
  final sectionsGap = (yRows > 0 && xRows > 0) ? cursorSectionGap : 0;
  return cursorHeaderHeight +
      (yRows + xRows) * cursorRowHeight +
      sectionsGap +
      cursorPanelPadding * 2;
}

/// Returns the bounding rectangle of the cursor info panel in local widget
/// coordinates, or null if no cursors are enabled.
///
/// The panel is positioned at the top-right of the waveform display area
/// with a 12-pixel margin.
Rect? getCursorInfoPanelRect(Size size, CursorState cursorState) {
  if (!cursorState.cursorsXEnabled && !cursorState.cursorsYEnabled) {
    return null;
  }
  final panelHeight = computeCursorPanelHeight(cursorState);
  final panelX =
      size.width - cursorPanelWidth - cursorPanelMargin + cursorState.cursorInfoOffset.dx;
  final panelY = cursorPanelMargin + cursorState.cursorInfoOffset.dy;
  return Rect.fromLTWH(panelX, panelY, cursorPanelWidth, panelHeight);
}

/// Clamps the cursor info panel offset so the panel stays fully visible
/// within the waveform display area.
///
/// The panel position is computed in waveform_painter.dart as:
///   panelX = size.width - panelWidth - 12 + offset.dx
///   panelY = 12 + offset.dy
Offset clampCursorInfoOffset(
  Offset proposedOffset,
  Size size,
  CursorState cursorState,
) {
  final panelHeight = computeCursorPanelHeight(cursorState);

  // Constrain panelX within [margin, size.width - panelWidth - margin]
  final minDx = cursorPanelMargin -
      (size.width - cursorPanelWidth - cursorPanelMargin);
  final maxDx = cursorPanelMargin - cursorPanelMargin;
  final clampedDx = proposedOffset.dx.clamp(minDx, maxDx);

  // Constrain panelY within [margin, size.height - panelHeight - margin]
  final minDy = cursorPanelMargin - cursorPanelMargin;
  final maxDy = size.height - panelHeight - cursorPanelMargin - cursorPanelMargin;
  final clampedDy = proposedOffset.dy.clamp(minDy, maxDy);

  return Offset(clampedDx, clampedDy);
}
