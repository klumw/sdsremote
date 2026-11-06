/// Content-sized table column width for Markdown content.
///
/// Short columns stay as wide as their text; wide tables shrink to the
/// available width and wrap the remaining text. Shared by the Help window and
/// the AI chat window, which both render Markdown tables.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Sizes a table column to its content while letting the table shrink to the
/// available width.
///
/// The table first tries the maximum intrinsic width of every cell, so short
/// columns stay as wide as their text and explicit line breaks inside a cell
/// are respected. When the full content is wider than the available width, the
/// table layout shrinks the affected columns down to their minimum intrinsic
/// width (the longest word) and wraps the rest.
///
/// This is deliberately not an [IntrinsicColumnWidth]: flutter_markdown_plus
/// wraps those in a horizontal scroll view, which removes the width bound and
/// lets the table grow past the available edge.
class ContentColumnWidth extends TableColumnWidth {
  const ContentColumnWidth();

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var result = 0.0;
    for (final cell in cells) {
      result = math.max(result, cell.getMinIntrinsicWidth(double.infinity));
    }
    return result;
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    var result = 0.0;
    for (final cell in cells) {
      result = math.max(result, cell.getMaxIntrinsicWidth(double.infinity));
    }
    return result;
  }
}
