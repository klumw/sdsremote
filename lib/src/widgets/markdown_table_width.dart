/// Markdown rendering helpers.
///
/// [ContentColumnWidth] keeps table columns close to their content, and
/// [wrapMarkdownLines] inserts hard line breaks into long source lines before
/// the Markdown is rendered. Shared by the Help window and the AI chat window.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Maximum source line length used by [wrapMarkdownLines].
const int kMarkdownMaxLineLength = 200;

/// Inserts Markdown hard line breaks into lines longer than [maxLineLength].
///
/// Fenced code blocks, indented code, headings, table rows and HTML blocks are
/// left unchanged. Breaks are placed at spaces outside inline code spans and
/// links, so the Markdown structure stays intact. List items and blockquotes
/// keep their continuation indentation.
///
/// Render the result with `softLineBreak: true`; otherwise Markdown joins the
/// remaining source lines into paragraphs and the line limit is not kept.
String wrapMarkdownLines(String markdown, {int maxLineLength = 200}) {
  if (maxLineLength < 20) return markdown;
  final lines = markdown.split('\n');
  final result = StringBuffer();
  var fenceMarker = '';
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final fence = RegExp(
      r'^(`{3,}|~{3,})',
    ).firstMatch(_stripBlockquoteMarkers(line).trimLeft());
    if (fence != null) {
      final marker = fence.group(1)!;
      if (fenceMarker.isEmpty) {
        fenceMarker = marker;
      } else if (marker.startsWith(fenceMarker[0]) &&
          marker.length >= fenceMarker.length) {
        fenceMarker = '';
      }
      result.write(line);
    } else if (fenceMarker.isNotEmpty ||
        line.length <= maxLineLength ||
        _isProtectedMarkdownLine(line)) {
      result.write(line);
    } else {
      result.write(_wrapMarkdownLine(line, maxLineLength));
    }
    if (index < lines.length - 1) result.write('\n');
  }
  return result.toString();
}

bool _isProtectedMarkdownLine(String line) {
  final content = _stripBlockquoteMarkers(line);
  final trimmed = content.trimLeft();
  if (trimmed.isEmpty) return true;
  // ATX headings and setext underlines.
  if (RegExp(r'^#{1,6}(\s|$)').hasMatch(trimmed)) return true;
  if (RegExp(r'^(=+|-+)\s*$').hasMatch(trimmed)) return true;
  // Table rows.
  if (trimmed.startsWith('|')) return true;
  // Indented code blocks (but not indented list items).
  if (RegExp(r'^ {4,}\S').hasMatch(content) &&
      !RegExp(r'^ {4,}(?:[-*+]|\d+[.)])\s').hasMatch(content)) {
    return true;
  }
  // HTML blocks.
  if (RegExp(r'^<[A-Za-z!/]').hasMatch(trimmed)) return true;
  return false;
}

String _stripBlockquoteMarkers(String line) {
  var current = line;
  while (true) {
    final match = RegExp(r'^\s*>\s?').firstMatch(current);
    if (match == null) return current;
    current = current.substring(match.end);
  }
}

String _wrapMarkdownLine(String line, int maxLineLength) {
  final quoteMatch = RegExp(r'^(\s*(?:>\s*)+)').firstMatch(line);
  final quotePrefix = quoteMatch?.group(1) ?? '';
  final afterQuote = line.substring(quotePrefix.length);
  final listMatch = RegExp(
    r'^(\s*(?:[-*+]|\d+[.)])\s+)',
  ).firstMatch(afterQuote);
  final String firstPrefix;
  final String continuation;
  final String content;
  if (listMatch != null) {
    final listPrefix = listMatch.group(1)!;
    firstPrefix = quotePrefix + listPrefix;
    continuation = quotePrefix + ' ' * listPrefix.length;
    content = afterQuote.substring(listPrefix.length);
  } else {
    final leading = RegExp(r'^\s*').firstMatch(afterQuote)!.group(0)!;
    firstPrefix = quotePrefix + leading;
    continuation = quotePrefix + leading;
    content = afterQuote.substring(leading.length);
  }
  if (content.isEmpty) return line;

  final result = StringBuffer();
  var remaining = content;
  var prefix = firstPrefix;
  while (remaining.length + prefix.length > maxLineLength) {
    // Reserve the two trailing spaces of the Markdown hard break.
    final limit = maxLineLength - prefix.length - 2;
    if (limit <= 0) break;
    final cut = _lastBreakCandidate(remaining, limit);
    if (cut <= 0) break;
    final next = remaining.substring(cut).trimLeft();
    if (next.isEmpty) break;
    result
      ..write(prefix)
      ..write(remaining.substring(0, cut).trimRight())
      ..write('  \n');
    remaining = next;
    prefix = continuation;
  }
  result
    ..write(prefix)
    ..write(remaining);
  return result.toString();
}

/// Returns the last space before [limit] that is not inside inline code, a
/// link or a parenthesized span, or `-1` when there is no safe break.
int _lastBreakCandidate(String text, int limit) {
  var inCode = false;
  var codeTickLength = 0;
  var linkDepth = 0;
  var parenDepth = 0;
  var lastSpace = -1;
  final end = math.min(limit, text.length);
  for (var index = 0; index < end; index++) {
    final char = text[index];
    if (char == '`') {
      var run = 1;
      while (index + run < text.length && text[index + run] == '`') {
        run++;
      }
      if (!inCode) {
        inCode = true;
        codeTickLength = run;
      } else if (run == codeTickLength) {
        inCode = false;
      }
      index += run - 1;
      continue;
    }
    if (inCode) continue;
    if (char == '[') {
      linkDepth++;
    } else if (char == ']' && linkDepth > 0) {
      linkDepth--;
    } else if (char == '(') {
      parenDepth++;
    } else if (char == ')' && parenDepth > 0) {
      parenDepth--;
    } else if (char == ' ' && linkDepth == 0 && parenDepth == 0) {
      if (index == 0 || text[index - 1] != r'\') lastSpace = index;
    }
  }
  return lastSpace;
}

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
