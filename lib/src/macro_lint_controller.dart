import 'package:flutter/material.dart';

import 'macro_lint_error.dart';

/// A [TextEditingController] that highlights [MacroLintError] regions in the
/// text with a wavy red underline and a faint red background.
///
/// Call [updateErrors] with the latest set of lint errors to refresh the
/// visual highlights. Errors are automatically bounds-checked against the
/// current text to prevent [RangeError] during rapid editing.
class MacroLintController extends TextEditingController {
  List<MacroLintError> _errors = [];

  MacroLintController({super.text});

  /// Replaces the current error list and triggers a repaint.
  void updateErrors(List<MacroLintError> errors) {
    _errors = errors;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Fast path: no errors — use the default rendering.
    if (_errors.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final textLen = value.text.length;
    if (textLen == 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // Keep only errors whose start is within bounds, then sort by start.
    final sorted = _errors.where((e) => e.start < textLen).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (sorted.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    // Style for error-highlighted spans.
    final effectiveStyle = style ?? const TextStyle();
    final errorStyle = effectiveStyle.merge(
      const TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: Colors.red,
        decorationStyle: TextDecorationStyle.wavy,
        backgroundColor: Color(0x33FF0000),
      ),
    );

    final children = <TextSpan>[];
    var current = 0;

    for (final error in sorted) {
      final end = error.end > textLen ? textLen : error.end;

      // Non-error segment before this error.
      if (current < error.start) {
        children.add(
          TextSpan(
            text: value.text.substring(current, error.start),
            style: effectiveStyle,
          ),
        );
      }

      // Error segment.
      if (error.start < end) {
        children.add(
          TextSpan(
            text: value.text.substring(error.start, end),
            style: errorStyle,
          ),
        );
      }

      current = end;
    }

    // Trailing non-error segment.
    if (current < textLen) {
      children.add(
        TextSpan(
          text: value.text.substring(current, textLen),
          style: effectiveStyle,
        ),
      );
    }

    return TextSpan(style: effectiveStyle, children: children);
  }
}
