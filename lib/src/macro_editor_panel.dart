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

  const MacroEditorPanel({
    super.key,
    this.initialContent = '',
    this.loadedFileName,
    this.isModified = false,
    this.errorMessage,
    required this.onContentChanged,
    required this.onClose,
  });

  @override
  State<MacroEditorPanel> createState() => _MacroEditorPanelState();
}

class _MacroEditorPanelState extends State<MacroEditorPanel> {
  late final MacroLintController _controller;
  final ScrollController _gutterScrollController = ScrollController();
  final ScrollController _editorScrollController = ScrollController();
  bool _isSyncing = false;
  int _lineCount = 1;
  Timer? _lintDebounce;

  static const double _lineHeight = 13.0 * 1.5; // fontSize * height
  static const Duration _lintDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _controller = MacroLintController(text: widget.initialContent);
    _controller.addListener(_onTextChanged);
    _controller.addListener(_onLintRequired);
    _updateLineCount();

    // Run an initial lint pass on the starting content.
    _scheduleLint();

    // Sync the gutter scroll to follow the editor scroll.
    _editorScrollController.addListener(_onEditorScroll);

    // Sync the editor scroll to follow the gutter scroll.
    _gutterScrollController.addListener(_onGutterScroll);

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
    _gutterScrollController.removeListener(_onGutterScroll);
    _editorScrollController.removeListener(_onEditorScroll);
    _gutterScrollController.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    if (event is KeyDownEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        (event.logicalKey == LogicalKeyboardKey.keyD ||
            event.logicalKey == LogicalKeyboardKey.keyX)) {
      _deleteCurrentLine();
      return true; // handled
    }
    return false; // not handled
  }

  void _onEditorScroll() {
    if (!_isSyncing && _gutterScrollController.hasClients) {
      _isSyncing = true;
      final offset = _editorScrollController.offset;
      _gutterScrollController.jumpTo(
        offset.clamp(0.0, _gutterScrollController.position.maxScrollExtent),
      );
      _isSyncing = false;
    }
  }

  void _onGutterScroll() {
    if (!_isSyncing && _editorScrollController.hasClients) {
      _isSyncing = true;
      final offset = _gutterScrollController.offset;
      _editorScrollController.jumpTo(
        offset.clamp(0.0, _editorScrollController.position.maxScrollExtent),
      );
      _isSyncing = false;
    }
  }

  @override
  void didUpdateWidget(MacroEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller text if the initial content changed externally
    // (e.g. after loading a different macro file).
    if (widget.initialContent != oldWidget.initialContent &&
        widget.initialContent != _controller.text) {
      _controller.text = widget.initialContent;
      _updateLineCount();
    }
  }

  void _onTextChanged() {
    _updateLineCount();
    widget.onContentChanged(_controller.text);
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
  }

  void _updateLineCount() {
    final lines = _controller.text.split('\n').length;
    if (lines != _lineCount) {
      setState(() {
        _lineCount = lines;
      });
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _insertTextAtCursor('  ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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

    _controller.value = TextEditingValue(
      text: text.replaceRange(removeStart, removeEnd, ''),
      selection: TextSelection.collapsed(offset: newCursor),
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
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate gutter width based on digit count (min 32, add 8 per extra digit beyond 2)
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
                color: const Color(0xFF1A2A4A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent, width: 1.0),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line number gutter
                    Container(
                      width: gutterWidth,
                      color: const Color(0xFF152238),
                      padding: const EdgeInsets.only(top: 12, right: 8),
                      child: ListView.builder(
                        controller: _gutterScrollController,
                        itemCount: _lineCount,
                        itemExtent: _lineHeight,
                        itemBuilder: (context, index) {
                          return Text(
                            '${index + 1}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          );
                        },
                      ),
                    ),
                    // Vertical divider
                    Container(width: 1, color: const Color(0xFF2A3A5A)),
                    // Text field
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKeyEvent,
                        child: TextField(
                          controller: _controller,
                          scrollController: _editorScrollController,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Enter macro commands...',
                            hintStyle: TextStyle(
                              color: Colors.white24,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.only(
                              left: 8,
                              top: 12,
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
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
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
