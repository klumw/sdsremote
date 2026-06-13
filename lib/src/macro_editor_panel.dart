import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'macro_lint_controller.dart';
import 'macro_linter.dart';

/// A simple multi-line text editor for editing macro file content.
///
/// Displays a header with "Macro Editor" title and a Close button.
/// The editable text area shows the macro commands and supports
/// full editing via keyboard, with line numbers on the left side.
class MacroEditorPanel extends StatefulWidget {
  /// The initial content to populate the text editor with.
  final String initialContent;

  /// The file name of the currently loaded macro, if any.
  /// Shown in the header; cleared when recording a new macro.
  final String? loadedFileName;

  /// Whether the loaded macro has been modified since last save.
  /// When true, a `*` is shown after the file name.
  final bool isModified;

  /// If non-null, displayed as an error banner below the filename in the
  /// header, spanning the full panel width.
  final String? errorMessage;

  /// Called whenever the user modifies the text content.
  final ValueChanged<String> onContentChanged;

  /// Called when the Close button is pressed.
  final VoidCallback onClose;

  /// Called when Ctrl+S is pressed while the editor has focus.
  /// If null, Ctrl+S is ignored.
  final VoidCallback? onSave;

  const MacroEditorPanel({
    super.key,
    this.initialContent = '',
    this.loadedFileName,
    this.isModified = false,
    this.errorMessage,
    required this.onContentChanged,
    required this.onClose,
    this.onSave,
  });

  @override
  State<MacroEditorPanel> createState() => _MacroEditorPanelState();
}

class _MacroEditorPanelState extends State<MacroEditorPanel> {
  late final MacroLintController _controller;
  final ScrollController _editorScrollController = ScrollController();
  bool _inProgrammaticEdit = false;
  String _lastNotifiedText = '';
  TextEditingValue _lastKnownValue = TextEditingValue.empty;
  int _lineCount = 1;
  Timer? _lintDebounce;
  Set<int> _errorLines = {};

  static const double _lineHeight = 13.0 * 1.5; // fontSize * height
  static const Duration _lintDelay = Duration(milliseconds: 300);

  /// Pre-computed line metrics measured by running the editor's text
  /// through the same [TextPainter] configuration that [RenderEditable]
  /// uses internally.  The gutter painter uses these for pixel-perfect
  /// alignment instead of guessing with a simple formula.
  List<LineMetrics>? _lineMetrics;

  /// The distance from the top of a single-line gutter [TextPainter] to
  /// its alphabetic baseline, measured once and cached.
  double _gutterBaselineOffset = 0;

  // Text styles used by both the editor TextField and the gutter painter.
  // Must be kept identical so line metrics match exactly.
  static const _editorTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontFamily: 'monospace',
    height: 1.5,
  );
  static const _gutterNormalStyle = TextStyle(
    color: Colors.white38,
    fontSize: 13,
    fontFamily: 'monospace',
    height: 1.5,
  );
  static const _gutterErrorStyle = TextStyle(
    color: Colors.red,
    fontSize: 13,
    fontFamily: 'monospace',
    height: 1.5,
  );

  @override
  void initState() {
    super.initState();
    _lastNotifiedText = widget.initialContent;
    _controller = MacroLintController(text: widget.initialContent);
    _lastKnownValue = _controller.value;
    _controller.addListener(_onTextChanged);
    _controller.addListener(_onLintRequired);
    _updateLineCount();

    // Cache the baseline offset of the gutter text so we can align
    // its baseline with the editor's text baseline pixel-for-pixel.
    final sample = TextPainter(
      text: const TextSpan(text: '0', style: _gutterNormalStyle),
      textDirection: TextDirection.ltr,
    );
    sample.layout();
    _gutterBaselineOffset =
        sample.computeDistanceToActualBaseline(TextBaseline.alphabetic);

    // Defer the initial lint pass to after the first frame so that the
    // onContentChanged callback (which may call setState on a parent widget)
    // does not trigger during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleLint());

    // Repaint the gutter whenever the editor scrolls so line numbers
    // stay perfectly aligned with the text.
    _editorScrollController.addListener(_onUserScrolled);

    // Register a global hardware-key handler to intercept Ctrl+D
    // before EditableText's internal shortcut (DeleteForwardCharacterIntent
    // on Linux) consumes it.
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
  }

  @override
  void dispose() {
    _lintDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _controller.removeListener(_onTextChanged);
    _controller.removeListener(_onLintRequired);
    _controller.dispose();
    _editorScrollController.removeListener(_onUserScrolled);
    _editorScrollController.dispose();
    super.dispose();
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) return false;

    // Ctrl + D / Ctrl + X: delete current line
    if (event.logicalKey == LogicalKeyboardKey.keyD ||
        event.logicalKey == LogicalKeyboardKey.keyX) {
      _deleteCurrentLine();
      return true;
    }
    // Ctrl + /: toggle line comment
    //
    // On US keyboards the logical key is `slash`. On German (and many
    // other non-US) layouts `/` is Shift+7, so the logical key may be
    // `digit7` while Shift is held. We check both variants.
    if (event.logicalKey == LogicalKeyboardKey.slash ||
        (HardwareKeyboard.instance.isShiftPressed &&
            event.logicalKey == LogicalKeyboardKey.digit7)) {
      _toggleComment();
      return true;
    }
    // Ctrl + Backspace / Ctrl + Delete: delete word left / right of
    // cursor.  We match on physicalKey so the shortcut works regardless
    // of keyboard layout (e.g. German "Rücktaste" / "Entf").
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.physicalKey == PhysicalKeyboardKey.backspace) {
      _deleteWordLeft();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.physicalKey == PhysicalKeyboardKey.delete) {
      _deleteWordRight();
      return true;
    }
    // Ctrl + S: save macro file
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return true;
    }
    return false;
  }

  /// Called whenever the editor scrolls (user scroll, cursor movement,
  /// programmatic jump, etc.).  Triggers a repaint of the gutter so line
  /// numbers stay pixel-aligned with the corresponding text lines.
  void _onUserScrolled() {
    if (mounted) setState(() {});
  }

  /// Scrolls the editor to the top of the document.
  void _scrollToTop() {
    if (_editorScrollController.hasClients) {
      _editorScrollController.jumpTo(0);
    }
  }

  /// Scrolls the editor to the bottom of the document.
  void _scrollToBottom() {
    if (_editorScrollController.hasClients) {
      _editorScrollController.jumpTo(
        _editorScrollController.position.maxScrollExtent,
      );
    }
  }

  @override
  void didUpdateWidget(MacroEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller text if the initial content changed externally
    // (e.g. after loading a different macro file).
    if (widget.initialContent != oldWidget.initialContent &&
        widget.initialContent != _controller.text) {
      _lastNotifiedText = widget.initialContent;
      _controller.text = widget.initialContent;
      _updateLineCount();
    }
  }

  void _onTextChanged() {
    _updateLineCount();
    // Only notify the parent when the text actually changes, not for
    // selection-only changes (e.g. focus gain, cursor placement).
    final currentText = _controller.text;
    if (currentText != _lastNotifiedText) {
      // Push the previous state to the unified undo stack for regular
      // typing edits so that Ctrl+Z can restore both text and cursor
      // position.  Programmatic edits are pushed separately inside
      // _applyProgrammaticEdit.
      if (!_inProgrammaticEdit) {
        _programmaticUndoStack.add(_lastKnownValue);
      }
      _lastNotifiedText = currentText;
      widget.onContentChanged(currentText);
    }
    // Track the full controller value (text + selection) so that undo
    // can restore the exact cursor position that was active before the
    // most recent text change.
    _lastKnownValue = _controller.value;
  }

  /// Debounced handler: called on every text change, re-parses after
  /// [_lintDelay] of inactivity to avoid excessive re-parsing during
  /// fast typing.
  void _onLintRequired() {
    _lintDebounce?.cancel();
    _lintDebounce = Timer(_lintDelay, _scheduleLint);
  }

  /// Runs the macro parser on the current text and pushes the resulting
  /// lint errors back to the controller for visual highlighting.
  void _scheduleLint() {
    final errors = lintMacro(_controller.text);
    _controller.updateErrors(errors);
    _errorLines = errors.map((e) => e.line).toSet();
    _updateLineMetrics();
    if (!mounted) return;
    final savedOffset = _editorScrollController.hasClients
        ? _editorScrollController.offset
        : null;
    setState(() {});
    if (savedOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_editorScrollController.hasClients) {
          _editorScrollController.jumpTo(savedOffset);
        }
      });
    }
  }

  /// Measures exact line positions by running the editor text through
  /// a [TextPainter] configured identically to [RenderEditable].
  ///
  /// The [TextField] (via [RenderEditable]) does not set an explicit
  /// [TextHeightBehavior], which means both [applyHeightToFirstAscent]
  /// and [applyHeightToLastDescent] default to `false`.  We must
  /// replicate that here so the measured baselines match the editor.
  void _updateLineMetrics() {
    final tp = TextPainter(
      text: TextSpan(text: _controller.text, style: _editorTextStyle),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: double.infinity);
    _lineMetrics = tp.computeLineMetrics();
  }

  void _updateLineCount() {
    final lines = _controller.text.split('\n').length;
    if (lines != _lineCount) {
      // Defer setState to the post-frame phase so that the cursor position
      // is stable before a gutter-width change triggers a re-layout of the
      // TextField.  Without this, Ctrl+Z (undo) causes the cursor to jump
      // to the next line because setState runs synchronously inside the
      // controller listener callback and the resulting layout shift moves
      // the cursor's rendered position.
      final savedOffset = _editorScrollController.hasClients
          ? _editorScrollController.offset
          : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _lineCount = lines;
        });
        if (savedOffset != null && _editorScrollController.hasClients) {
          _editorScrollController.jumpTo(savedOffset);
        }
      });
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl + Home: jump to document start and scroll to top
    if (ctrl && event.logicalKey == LogicalKeyboardKey.home) {
      _controller.selection = TextSelection.collapsed(offset: 0);
      _scrollToTop();
      return KeyEventResult.handled;
    }
    // Ctrl + End: jump to document end and scroll to bottom
    if (ctrl && event.logicalKey == LogicalKeyboardKey.end) {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _scrollToBottom();
      return KeyEventResult.handled;
    }
    // Home / Shift+Home: smart home (first non-space, then column 0 on
    // second press). With Shift, extend the selection.
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _moveToStartOfLine(extend: shift);
      return KeyEventResult.handled;
    }
    // End / Shift+End: end of line. With Shift, extend the selection.
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _moveToEndOfLine(extend: shift);
      return KeyEventResult.handled;
    }
    // Tab / Shift+Tab: indent / outdent
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (shift) {
        _outdentLines();
      } else {
        _insertTextAtCursor('  ');
      }
      return KeyEventResult.handled;
    }
    // Ctrl + Backspace: delete word left of cursor.
    // We match on physicalKey so the shortcut works regardless of
    // keyboard layout (e.g. German "Rücktaste" / "Entf").
    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.physicalKey == PhysicalKeyboardKey.backspace)) {
      _deleteWordLeft();
      return KeyEventResult.handled;
    }
    // Ctrl + Delete: delete word right of cursor.
    if (ctrl &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.physicalKey == PhysicalKeyboardKey.delete)) {
      _deleteWordRight();
      return KeyEventResult.handled;
    }
    // Ctrl + Z: undo last edit (programmatic or regular typing).
    // We handle ALL undo ourselves so that the unified undo stack
    // always has correct cursor positions — Flutter's UndoHistory
    // becomes stale after programmatic edits bypass it.
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (_programmaticUndoStack.isNotEmpty) {
        _undoLastProgrammaticEdit();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves the cursor to the end of the current line.
  ///
  /// When [extend] is true (Shift is held), the selection is extended from
  /// the current [baseOffset] to the end-of-line position while keeping the
  /// anchor at the original cursor position.
  void _moveToEndOfLine({bool extend = false}) {
    final text = _controller.text;
    final sel = _controller.selection;
    final cursor = sel.baseOffset;
    final lineEndIndex = text.indexOf('\n', cursor);
    final target = lineEndIndex == -1 ? text.length : lineEndIndex;

    if (extend) {
      // Anchor stays at the original baseOffset (where the selection
      // started); the focus moves to the line end. If the selection is
      // already non-collapsed, keep the existing anchor.
      _controller.selection = TextSelection(
        baseOffset: sel.baseOffset,
        extentOffset: target,
      );
    } else {
      _controller.selection = TextSelection.collapsed(offset: target);
    }
  }

  /// Moves the cursor to the start of the current line (after leading
  /// whitespace when the cursor is already at column 0 of the line).
  ///
  /// When [extend] is true (Shift is held), the selection is extended from
  /// the current [baseOffset] to the target position while keeping the
  /// anchor at the original cursor position.
  void _moveToStartOfLine({bool extend = false}) {
    final text = _controller.text;
    final sel = _controller.selection;
    final cursor = sel.baseOffset;
    // Find the start of the current line.
    final lineStart = cursor > 0 ? text.lastIndexOf('\n', cursor - 1) + 1 : 0;
    // Find first non-whitespace character on this line.
    var firstNonSpace = lineStart;
    while (firstNonSpace < text.length &&
        (text[firstNonSpace] == ' ' || text[firstNonSpace] == '\t')) {
      firstNonSpace++;
    }
    // If cursor is already at the first non-space position, go to column 0.
    // Otherwise go to the first non-space position.
    final target = (cursor == firstNonSpace) ? lineStart : firstNonSpace;

    if (extend) {
      // Anchor stays at the original baseOffset (where the selection
      // started); the focus moves to the target. If the selection is
      // already non-collapsed, keep the existing anchor.
      _controller.selection = TextSelection(
        baseOffset: sel.baseOffset,
        extentOffset: target,
      );
    } else {
      _controller.selection = TextSelection.collapsed(offset: target);
    }
  }

  // ── Line-based operations ─────────────────────────────────────────────

  /// Toggles the `#` comment character on each line that intersects the
  /// current selection, or on the current cursor line when nothing is
  /// selected.
  void _toggleComment() {
    final text = _controller.text;
    final sel = _controller.selection;
    final lines = _lineRange(text, sel.start, sel.end);
    final buf = text.split('\n');

    for (var i = lines.$1; i <= lines.$2; i++) {
      final original = buf[i];
      final trimmed = original.trimLeft();
      if (trimmed.startsWith('#')) {
        // Uncomment: remove `# ` (hash + space) when present, otherwise
        // only the `#`.  Removing exactly two characters when a space
        // follows the hash guarantees idempotent toggling.
        final hashIdx = original.indexOf('#');
        if (trimmed.startsWith('# ')) {
          buf[i] =
              '${original.substring(0, hashIdx)}${original.substring(hashIdx + 2)}';
        } else {
          buf[i] =
              '${original.substring(0, hashIdx)}${original.substring(hashIdx + 1)}';
        }
      } else {
        // Comment: prepend `# ` (hash + one space).  Together with the
        // uncomment branch above this makes toggling idempotent — no
        // spaces accumulate across repeated comment / uncomment cycles.
        buf[i] = '# $original';
      }
    }

    final newText = buf.join('\n');

    // Recompute selection to span exactly the originally-affected lines
    // in the new text.  Simple delta arithmetic (sel.start + delta) can
    // undershoot when uncommenting (negative delta), bleeding the
    // selection into the previous line.
    final newBuf = newText.split('\n');
    var charOffset = 0;
    var newStart = newText.length;
    var newEnd = 0;
    for (var i = 0; i < newBuf.length; i++) {
      if (i == lines.$1) newStart = charOffset;
      if (i == lines.$2) newEnd = charOffset + newBuf[i].length;
      charOffset += newBuf[i].length + 1; // +1 for the '\n' separator
    }
    _replaceText(newText, newStart: newStart, newEnd: newEnd);
  }

  /// Removes up to 2 leading spaces from each line that intersects the
  /// current selection, or from the current cursor line when nothing is
  /// selected.
  void _outdentLines() {
    final text = _controller.text;
    final sel = _controller.selection;
    final lines = _lineRange(text, sel.start, sel.end);
    final buf = text.split('\n');

    var delta = 0;
    for (var i = lines.$1; i <= lines.$2; i++) {
      final original = buf[i];
      var removed = 0;
      if (original.startsWith('  ')) {
        buf[i] = original.substring(2);
        removed = 2;
      } else if (original.startsWith(' ')) {
        buf[i] = original.substring(1);
        removed = 1;
      }
      delta -= removed;
    }

    final newText = buf.join('\n');
    _replaceText(
      newText,
      newStart: (sel.start + delta).clamp(0, newText.length),
      newEnd: (sel.end + delta).clamp(0, newText.length),
    );
  }

  // ── Word-delete operations ────────────────────────────────────────────

  /// Deletes the word to the left of the cursor (or the current selection).
  void _deleteWordLeft() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isCollapsed) {
      _replaceText(
        text.replaceRange(sel.start, sel.end, ''),
        newStart: sel.start,
        newEnd: sel.start,
      );
      return;
    }
    final boundary = _prevWordBoundary(text, sel.start);
    _replaceText(
      text.replaceRange(boundary, sel.start, ''),
      newStart: boundary,
      newEnd: boundary,
    );
  }

  /// Deletes the word to the right of the cursor (or the current selection).
  void _deleteWordRight() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isCollapsed) {
      _replaceText(
        text.replaceRange(sel.start, sel.end, ''),
        newStart: sel.start,
        newEnd: sel.start,
      );
      return;
    }
    final boundary = _nextWordBoundary(text, sel.start);
    _replaceText(
      text.replaceRange(sel.start, boundary, ''),
      newStart: sel.start,
      newEnd: sel.start,
    );
  }

  /// Returns the start offset of the word before [pos] in [text].
  ///
  /// Never crosses a `\n` line boundary; stops at the beginning of the
  /// current line if the cursor is at the start of the line.
  static int _prevWordBoundary(String text, int pos) {
    // Clamp [pos] so we never look beyond the current line — if the
    // cursor sits on a `\n` or at column 0 we have nothing to delete.
    var i = pos;
    if (i > 0 && text[i - 1] == '\n') return i; // at start of a line
    // Find start of the current line (the `\n` before [pos], or 0).
    final lineStart = i > 0 ? text.lastIndexOf('\n', i - 1) + 1 : 0;
    // Skip trailing whitespace (spaces / tabs only, never `\n`).
    while (i > lineStart && (text[i - 1] == ' ' || text[i - 1] == '\t')) {
      i--;
    }
    // Skip word characters.
    while (i > lineStart && _isWordChar(text[i - 1])) {
      i--;
    }
    return i;
  }

  /// Returns the end offset of the word after [pos] in [text].
  ///
  /// Never crosses a `\n` line boundary; stops at the end of the
  /// current line if the cursor is at the end of the line.
  static int _nextWordBoundary(String text, int pos) {
    final len = text.length;
    // Find end of the current line (the next `\n`, or text length).
    final lineEnd = text.indexOf('\n', pos);
    final maxPos = lineEnd == -1 ? len : lineEnd;
    var i = pos;
    // Skip word characters (never cross `\n`).
    while (i < maxPos && _isWordChar(text[i])) {
      i++;
    }
    // Skip trailing whitespace (spaces / tabs only, never `\n`).
    while (i < maxPos && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    return i;
  }

  static bool _isWordChar(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        (code >= 48 && code <= 57) || // 0-9
        code == 95; // _
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Returns the inclusive line range (start, end) covered by character
  /// offsets [from] .. [to] in [text].
  static (int, int) _lineRange(String text, int from, int to) {
    int lineOf(int pos) {
      if (pos <= 0) return 0;
      final newlines = '\n'.allMatches(text.substring(0, pos));
      return newlines.length;
    }

    // When there is no selection, use the cursor line.
    if (from == to) return (lineOf(from), lineOf(from));

    final startLine = lineOf(from);
    final endLine = lineOf(to > 0 ? to - 1 : 0);
    return (startLine, endLine);
  }

  /// A lightweight undo stack for programmatic edits that bypass
  /// Flutter's [UndoHistory].  Each entry stores the controller value
  /// before a programmatic edit so that Ctrl+Z can restore it.
  final List<TextEditingValue> _programmaticUndoStack = <TextEditingValue>[];

  /// Applies [newValue] to the controller and records the previous state
  /// in [_programmaticUndoStack] for manual undo handling.
  ///
  /// Flutter's [UndoHistory] does not update its internal snapshot for
  /// selection-only changes, so programmatic text edits can push a stale
  /// selection onto the platform undo stack.  We work around this by
  /// maintaining our own undo history: before each edit we save the
  /// current value, and Ctrl+Z pops from our stack first.
  void _applyProgrammaticEdit(TextEditingValue newValue) {
    if (_controller.value == newValue) return;

    // Save the current state so Ctrl+Z can restore it with the correct
    // text *and* selection.
    _programmaticUndoStack.add(_controller.value);
    _inProgrammaticEdit = true;
    _controller.value = newValue;
    _inProgrammaticEdit = false;
  }

  /// Handles Ctrl+Z (undo) by checking our own undo stack before letting
  /// Flutter's native undo run.
  void _undoLastProgrammaticEdit() {
    if (_programmaticUndoStack.isEmpty) return;
    final previousValue = _programmaticUndoStack.removeLast();
    _inProgrammaticEdit = true;
    _controller.value = previousValue;
    _inProgrammaticEdit = false;
  }

  /// Replaces the entire text with [newText] and positions the selection
  /// at the given offsets.
  void _replaceText(
    String newText, {
    required int newStart,
    required int newEnd,
  }) {
    _applyProgrammaticEdit(
      TextEditingValue(
        text: newText,
        selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
      ),
    );
  }

  /// Deletes the line that currently contains the cursor.
  ///
  /// If the text is empty or there is only one line, the content is cleared.
  /// Otherwise the line is removed along with an adjacent newline so that
  /// lines below shift up. The cursor is placed at the beginning of the next
  /// logical line (or the end of the previous line when deleting the last
  /// line).
  void _deleteCurrentLine() {
    final text = _controller.text;
    if (text.isEmpty) return;

    final cursor = _controller.selection.baseOffset;

    // Find the start of the current line.
    // Search for the last '\n' strictly before the cursor so that if the
    // cursor sits directly on a '\n' we find the preceding one (or -1).
    final lineStart = cursor > 0 ? text.lastIndexOf('\n', cursor - 1) + 1 : 0;

    // Find the end of the current line (the '\n' that terminates it).
    final lineEndIndex = text.indexOf('\n', cursor);
    final lineEnd = lineEndIndex == -1 ? text.length : lineEndIndex;

    // Determine the range to remove and where to place the cursor.
    int removeStart;
    int removeEnd;
    int newCursor;

    if (lineStart == 0 && lineEnd == text.length) {
      // Only line in the file – clear everything.
      removeStart = 0;
      removeEnd = text.length;
      newCursor = 0;
    } else if (lineEnd == text.length) {
      // Last line – remove the preceding newline + this line.
      removeStart = lineStart - 1;
      removeEnd = text.length;
      newCursor = lineStart - 1;
    } else {
      // Middle or first line – remove this line + the trailing newline.
      removeStart = lineStart;
      removeEnd = lineEnd + 1;
      newCursor = lineStart;
    }

    _applyProgrammaticEdit(
      TextEditingValue(
        text: text.replaceRange(removeStart, removeEnd, ''),
        selection: TextSelection.collapsed(offset: newCursor),
      ),
    );
  }

  void _insertTextAtCursor(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final newText = value.text.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    _applyProgrammaticEdit(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      ),
    );
  }

  // ── Scroll-offset helper for the gutter painter ──────────────────────

  /// The current scroll offset of the editor, or 0 if not yet laid out.
  double get _scrollOffset {
    return _editorScrollController.hasClients
        ? _editorScrollController.offset
        : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate gutter width based on digit count (min 32, add 8 per extra
    // digit beyond 2).
    final gutterWidth = 32.0 + (_lineCount.toString().length - 1) * 8.0;

    return Container(
      width: 900,
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF172A45),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Macro Editor",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.loadedFileName != null)
                          Text(
                            '${widget.loadedFileName}${widget.isModified ? " *" : ""}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Error banner — full width, below the filename line
          if (widget.errorMessage != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF3D0000),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.errorMessage!,
                style: const TextStyle(
                  color: Color(0xFFFF8888),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          // Editable text area with line numbers
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent, width: 1.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Line number gutter ────────────────────────────
                    // Rendered via CustomPaint that uses the SAME scroll
                    // offset and line-height formula as the TextField,
                    // guaranteeing pixel-perfect alignment at any depth.
                    Container(
                      width: gutterWidth,
                      color: const Color(0xFF080808),
                      child: ClipRect(
                        child: CustomPaint(
                          painter: _GutterPainter(
                            lineCount: _lineCount,
                            errorLines: _errorLines,
                            lineMetrics: _lineMetrics,
                            gutterBaselineOffset: _gutterBaselineOffset,
                            topPadding: 12.0,
                            scrollOffset: _scrollOffset,
                            normalStyle: _gutterNormalStyle,
                            errorStyle: _gutterErrorStyle,
                            gutterWidth: gutterWidth,
                            rightPadding: 8.0,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                    // Vertical divider
                    Container(width: 1, color: const Color(0xFF2A3A5A)),
                    // ── Text field ────────────────────────────────────
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKeyEvent,
                        child: TextField(
                          controller: _controller,
                          scrollController: _editorScrollController,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: _editorTextStyle,
                          decoration: const InputDecoration(
                            hintText: 'Enter macro commands...',
                            hintStyle: TextStyle(
                              color: Colors.white24,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.only(
                              left: 8,
                              top: 18,
                              right: 12,
                              bottom: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Close button at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0A192F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent, width: 1.0),
              ),
              child: ElevatedButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18),
                label: const Text("Close"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 30,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Gutter painter
// ============================================================================

/// Paints line numbers in the editor gutter.
///
/// Uses [TextPainter] with the same [TextStyle] as the editor so that line
/// metrics (ascent, descent, line-height) match exactly.  Line positions are
/// computed from the editor's scroll offset using the identical formula that
/// the [TextField]'s [RenderEditable] uses internally:
///
///   y = topPadding + lineIndex * lineHeight - scrollOffset
///
/// Because both the editor and this painter share the same scroll controller,
/// layout constants, and text styles, alignment is guaranteed at any scroll
/// position regardless of document length.
class _GutterPainter extends CustomPainter {
  final int lineCount;
  final Set<int> errorLines;
  final List<LineMetrics>? lineMetrics;
  final double gutterBaselineOffset;
  final double topPadding;
  final double scrollOffset;
  final TextStyle normalStyle;
  final TextStyle errorStyle;
  final double gutterWidth;
  final double rightPadding;

  _GutterPainter({
    required this.lineCount,
    required this.errorLines,
    required this.lineMetrics,
    required this.gutterBaselineOffset,
    required this.topPadding,
    required this.scrollOffset,
    required this.normalStyle,
    required this.errorStyle,
    required this.gutterWidth,
    required this.rightPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount == 0) return;
    final metrics = lineMetrics;
    if (metrics == null) return;

    // Cull: determine which lines intersect the visible viewport.
    const double approxLineHeight = 19.5;
    final double visibleTop = scrollOffset - topPadding;
    final double visibleBottom = visibleTop + size.height;
    final int firstVisible =
        (visibleTop / approxLineHeight).floor().clamp(0, lineCount - 1);
    final int lastVisible =
        (visibleBottom / approxLineHeight).ceil().clamp(0, lineCount - 1);
    final int lastMetric = metrics.length - 1;

    final double textAreaWidth = gutterWidth - rightPadding;

    for (int i = firstVisible; i <= lastVisible; i++) {
      final int metricIdx = i.clamp(0, lastMetric);

      // Align the gutter text's alphabetic baseline with the editor's
      // text baseline.  [LineMetrics.baseline] is the baseline position
      // relative to the paragraph top (content-padding top in the editor).
      final double y = topPadding +
          metrics[metricIdx].baseline -
          scrollOffset -
          gutterBaselineOffset;

      // Quick cull: skip lines clearly outside the viewport.
      if (y + gutterBaselineOffset < 0 || y > size.height) continue;

      final bool isError = errorLines.contains(i + 1);
      final style = isError ? errorStyle : normalStyle;

      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: style),
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: textAreaWidth);

      // Right-align the number within the gutter.
      final double x = textAreaWidth - tp.width;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter oldDelegate) {
    return scrollOffset != oldDelegate.scrollOffset ||
        lineCount != oldDelegate.lineCount ||
        errorLines != oldDelegate.errorLines ||
        lineMetrics != oldDelegate.lineMetrics ||
        gutterWidth != oldDelegate.gutterWidth;
  }
}
