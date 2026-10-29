import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_settings.dart';
import '../ai/macro_chat_controller.dart';
import '../macro/macro_debug.dart';
import '../macro/macro_lint_controller.dart';
import '../macro/macro_linter.dart';
import '../macro/macro_print_controller.dart';
import 'osci_chat_window.dart';

/// A simple multi-line text editor for editing macro file content.
///
/// Displays a header with "Macro Editor" title and a Close button.
/// The editable text area shows the macro commands and supports
/// full editing via keyboard, with line numbers on the left side.
///
/// The AI assistant opens to the right of the editor.
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

  /// AI settings for the macro assistant.
  ///
  /// Null when no AI provider, token and model are configured; the AI button
  /// in the header is then disabled.
  final AiSettings? aiSettings;

  /// Optional controller that owns the AI conversation.
  ///
  /// The parent passes a long-lived controller so that closing and reopening
  /// the editor keeps the chat open and preserves its complete history. When
  /// null, the panel creates its own controller and disposes it with the
  /// panel.
  final MacroChatController? chatController;

  /// Whether the complete macro is currently being played.
  final bool isPlaying;

  /// Whether a step-by-step debug session is active.
  final bool hasDebugSession;

  /// Whether the debug session is paused before a statement.
  final bool isDebugPaused;

  /// Whether a step is currently executing (session active, not paused).
  final bool isDebugRunning;

  /// Status text shown in the debug bar (e.g. the statement about to run).
  final String? debugStatus;

  /// 1-based source line of the statement being executed or paused at.
  final int? debugCurrentLine;

  /// Variable values after the most recent step, shown in the watch panel.
  final Map<String, String> debugVariables;

  /// Output of `print()` statements from the current playback.
  ///
  /// The left sidebar shows the variables in its upper half and these messages
  /// in its lower half. When null, the lower half shows its empty state.
  final MacroPrintController? printController;

  /// Breakpoint lines (1-based) set in this editor.
  final Set<int> breakpoints;

  /// Breakpoints that are currently disabled.
  ///
  /// Disabled breakpoints remain visible in the gutter (drawn hollow) but do
  /// not pause the debugger.
  final Set<int> inactiveBreakpoints;

  /// Called when the user toggles a breakpoint in the gutter.
  final ValueChanged<Set<int>>? onBreakpointsChanged;

  /// Deletes the breakpoint on [line] (gutter context menu).
  final ValueChanged<int>? onDeleteBreakpoint;

  /// Enables or disables the breakpoint on [line] (gutter context menu).
  final void Function(int line, bool enabled)? onSetBreakpointEnabled;

  /// Enables or disables every breakpoint (gutter context menu).
  final ValueChanged<bool>? onSetAllBreakpointsEnabled;

  /// Deletes every breakpoint (gutter context menu).
  final VoidCallback? onDeleteAllBreakpoints;

  /// Starts a full playback of the current editor content.
  final VoidCallback? onPlay;

  /// Executes the next statement in the debug session.
  final VoidCallback? onStep;

  /// Continues the debug session until the next breakpoint (or the end).
  final VoidCallback? onContinue;

  /// Stops a running playback or debug session.
  final VoidCallback? onStop;

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
    this.aiSettings,
    this.chatController,
    this.isPlaying = false,
    this.hasDebugSession = false,
    this.isDebugPaused = false,
    this.isDebugRunning = false,
    this.debugStatus,
    this.debugCurrentLine,
    this.debugVariables = const <String, String>{},
    this.printController,
    this.breakpoints = const <int>{},
    this.inactiveBreakpoints = const <int>{},
    this.onBreakpointsChanged,
    this.onDeleteBreakpoint,
    this.onSetBreakpointEnabled,
    this.onSetAllBreakpointsEnabled,
    this.onDeleteAllBreakpoints,
    this.onPlay,
    this.onStep,
    this.onContinue,
    this.onStop,
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
  final ScrollController _printScrollController = ScrollController();
  bool _inProgrammaticEdit = false;
  String _lastNotifiedText = '';
  TextEditingValue _lastKnownValue = TextEditingValue.empty;
  int _lineCount = 1;
  Timer? _lintDebounce;
  Set<int> _errorLines = {};

  /// AI assistant state.
  ///
  /// A controller passed by the parent outlives the panel; without one the
  /// panel owns a controller for its own lifetime.
  MacroChatController? _ownedChatController;

  MacroChatController get _chat =>
      widget.chatController ?? _ownedChatController!;

  /// Focus node of the editor's text field.
  ///
  /// The global hardware-key handler must only act while this field has
  /// focus; otherwise shortcuts such as Ctrl+X would edit the macro while the
  /// user types in the AI chat.
  final FocusNode _editorFocusNode = FocusNode();

  static const Duration _lintDelay = Duration(milliseconds: 300);

  // Layout constants of the editor text area. They are used for the debug
  // line highlight, auto-scroll, and gutter hit testing; keep them in sync
  // with _editorTextStyle and the TextField content padding.
  static const double _editorLineHeight = 19.5;
  static const double _editorContentTop = 18.0;
  static const double _gutterTopPadding = 12.0;

  /// Minimum and maximum number of monospace characters the editor column is
  /// sized for.
  static const int _editorMinChars = 60;
  static const int _editorMaxChars = 120;

  /// Minimum widths of the side panels. The editor stays at its 60-character
  /// floor before either panel drops below these widths.
  static const double _minOutputSidebarWidth = 220;
  static const double _minChatWidth = 400;

  /// Width of one monospace character at [_editorTextStyle], measured on the
  /// first build and reused afterwards.
  double? _editorCharWidth;

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
    _gutterBaselineOffset = sample.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

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

    // Attach this editor to the (possibly shared) AI chat controller and
    // create the agent when the AI is already configured.
    _initMacroChat();
    _chat.addListener(_onMacroChatChanged);

    // Keep the lower half of the output sidebar in sync with print output.
    widget.printController?.addListener(_onPrintOutputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollPrintToBottom());
  }

  void _onPrintOutputChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollPrintToBottom();
  }

  /// Scrolls the print output to its newest message after the next frame.
  void _scrollPrintToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_printScrollController.hasClients) return;
      final extent = _printScrollController.position.maxScrollExtent;
      _printScrollController.animateTo(
        extent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  /// Creates the owned controller (if any), registers the editor callbacks
  /// and configures the agent for the current AI settings.
  void _initMacroChat() {
    if (widget.chatController == null) {
      _ownedChatController = MacroChatController();
    }
    _chat.attachEditor(
      readMacro: () => mounted ? _controller.text : '',
      writeMacro: _applyAiMacroEdit,
      macroFileName: () => widget.loadedFileName,
    );
    _chat.configure(widget.aiSettings);
  }

  void _onMacroChatChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lintDebounce?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    // Detach instead of disposing a controller owned by the parent: the
    // transcript and agent must survive until the editor is opened again.
    _chat.removeListener(_onMacroChatChanged);
    _chat.detachEditor();
    _ownedChatController?.dispose();
    _ownedChatController = null;
    widget.printController?.removeListener(_onPrintOutputChanged);
    _printScrollController.dispose();
    _editorFocusNode.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.removeListener(_onLintRequired);
    _controller.dispose();
    _editorScrollController.removeListener(_onUserScrolled);
    _editorScrollController.dispose();
    super.dispose();
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // The handler is global. Only act while the editor itself has focus so
    // that shortcuts typed in the AI chat (Ctrl+X, Ctrl+D, …) do not modify
    // the macro behind the chat.
    if (!_editorFocusNode.hasFocus) return false;

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

    // A different shared controller means this panel moved to a new owner.
    if (widget.chatController != oldWidget.chatController) {
      final oldChat = oldWidget.chatController ?? _ownedChatController;
      oldChat?.removeListener(_onMacroChatChanged);
      oldChat?.detachEditor();
      _ownedChatController?.dispose();
      _ownedChatController = null;
      _initMacroChat();
      _chat.addListener(_onMacroChatChanged);
    } else if (widget.aiSettings != oldWidget.aiSettings) {
      // Reconfigure the agent when the AI settings change while the editor is
      // open (e.g. after saving the settings dialog). The controller keeps
      // the agent and its history when the settings are unchanged.
      _chat.configure(widget.aiSettings);
    }

    if (widget.printController != oldWidget.printController) {
      oldWidget.printController?.removeListener(_onPrintOutputChanged);
      widget.printController?.addListener(_onPrintOutputChanged);
      _scrollPrintToBottom();
    }

    if (widget.debugCurrentLine != oldWidget.debugCurrentLine &&
        widget.debugCurrentLine != null) {
      _scrollToDebugLine(widget.debugCurrentLine!);
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

  /// Width of one character in the editor's monospace font.
  double _measureEditorCharWidth() {
    final cached = _editorCharWidth;
    if (cached != null) return cached;

    final tp = TextPainter(
      text: const TextSpan(text: '0000000000', style: _editorTextStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = tp.width / 10;
    _editorCharWidth = width;
    return width;
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

  // ── Debug bar ────────────────────────────────────────────────────────

  /// Maps a local y in the gutter to a 1-based source line.
  ///
  /// Uses the same line metrics and baseline offset as [_GutterPainter] so a
  /// click maps to exactly the line whose number is drawn at that position.
  int? _lineAtGutterOffset(double localY) {
    final metrics = _lineMetrics;
    if (metrics == null || metrics.isEmpty) return null;

    for (var i = 0; i < metrics.length; i++) {
      final top =
          _gutterTopPadding +
          metrics[i].baseline -
          _scrollOffset -
          _gutterBaselineOffset;
      if (localY >= top && localY < top + metrics[i].height) {
        return i + 1;
      }
    }
    return null;
  }

  /// Toggles a breakpoint on the gutter line at [localY].
  void _toggleBreakpointAt(double localY) {
    final onChanged = widget.onBreakpointsChanged;
    if (onChanged == null) return;

    final line = _lineAtGutterOffset(localY);
    if (line == null || line < 1 || line > _lineCount) return;

    // Breakpoints only make sense on lines that contain a statement.
    final sourceLines = _controller.text.split('\n');
    final source = line <= sourceLines.length
        ? sourceLines[line - 1].trim()
        : '';
    if (source.isEmpty || source.startsWith('#')) return;

    final next = Set<int>.of(widget.breakpoints);
    if (!next.add(line)) next.remove(line);
    onChanged(next);
  }

  /// Shows the breakpoint context menu at a secondary (right) click.
  ///
  /// The menu is only opened when the click lands on an existing breakpoint.
  Future<void> _showBreakpointMenu(TapDownDetails details) async {
    final line = _lineAtGutterOffset(details.localPosition.dy);
    if (line == null || !widget.breakpoints.contains(line)) return;

    final isEnabled = !widget.inactiveBreakpoints.contains(line);
    final hasActive = hasActiveMacroBreakpoint(
      breakpoints: widget.breakpoints,
      inactiveBreakpoints: widget.inactiveBreakpoints,
    );
    final hasInactive = hasInactiveMacroBreakpoint(
      breakpoints: widget.breakpoints,
      inactiveBreakpoints: widget.inactiveBreakpoints,
    );

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<_BreakpointMenuAction>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 340),
      items: [
        PopupMenuItem<_BreakpointMenuAction>(
          value: _BreakpointMenuAction.deleteOne,
          enabled: widget.onDeleteBreakpoint != null,
          child: _breakpointMenuItem(Icons.delete_outline, 'Delete Breakpoint'),
        ),
        PopupMenuItem<_BreakpointMenuAction>(
          value: _BreakpointMenuAction.toggleOne,
          enabled: widget.onSetBreakpointEnabled != null,
          child: _breakpointMenuItem(
            isEnabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
            isEnabled ? 'Deactivate Breakpoint' : 'Activate Breakpoint',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_BreakpointMenuAction>(
          value: _BreakpointMenuAction.activateAll,
          enabled: hasInactive && widget.onSetAllBreakpointsEnabled != null,
          child: _breakpointMenuItem(
            Icons.play_circle_outline,
            'Activate All Breakpoints',
          ),
        ),
        PopupMenuItem<_BreakpointMenuAction>(
          value: _BreakpointMenuAction.deactivateAll,
          enabled: hasActive && widget.onSetAllBreakpointsEnabled != null,
          child: _breakpointMenuItem(
            Icons.pause_circle_outline,
            'Deactivate All Breakpoints',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_BreakpointMenuAction>(
          value: _BreakpointMenuAction.deleteAll,
          enabled: widget.onDeleteAllBreakpoints != null,
          child: _breakpointMenuItem(
            Icons.delete_sweep,
            'Delete All Breakpoints',
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _BreakpointMenuAction.deleteOne:
        widget.onDeleteBreakpoint?.call(line);
      case _BreakpointMenuAction.toggleOne:
        widget.onSetBreakpointEnabled?.call(line, !isEnabled);
      case _BreakpointMenuAction.activateAll:
        widget.onSetAllBreakpointsEnabled?.call(true);
      case _BreakpointMenuAction.deactivateAll:
        widget.onSetAllBreakpointsEnabled?.call(false);
      case _BreakpointMenuAction.deleteAll:
        widget.onDeleteAllBreakpoints?.call();
    }
  }

  Widget _breakpointMenuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  /// Scrolls the editor so the current debug line is visible.
  void _scrollToDebugLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editorScrollController.hasClients) return;
      final position = _editorScrollController.position;
      final lineTop = _editorContentTop + (line - 1) * _editorLineHeight;
      final lineBottom = lineTop + _editorLineHeight;
      final viewTop = position.pixels;
      final viewBottom = viewTop + position.viewportDimension;
      if (lineTop < viewTop || lineBottom > viewBottom) {
        final target = (lineTop - position.viewportDimension / 2).clamp(
          0.0,
          position.maxScrollExtent,
        );
        position.jumpTo(target);
      }
    });
  }

  /// Top offset of [line] inside the editor's scroll view.
  double _debugLineTop(int line) =>
      _editorContentTop + (line - 1) * _editorLineHeight - _scrollOffset;

  /// Left sidebar shown while the debugger has variables or print output
  /// exists. It is split into two equally sized halves: variables on top and
  /// print output below.
  Widget _buildOutputSidebar(Map<String, String> variables) {
    return Padding(
      // The sidebar fills the space from the left window edge to the editor
      // column.
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      child: Container(
        key: const ValueKey('macro-output-sidebar'),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D0D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF475569)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildVariablesSection(variables)),
              const Divider(height: 1, thickness: 1, color: Color(0xFF2A3A5A)),
              Expanded(child: _buildPrintOutputSection()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariablesSection(Map<String, String> variables) {
    final entries = variables.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      key: const ValueKey('macro-variables-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebarHeader(
          icon: Icons.data_object,
          title: 'Variables (${entries.length})',
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'No variables yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: SelectableText(
                            '${entry.key} = ${entry.value}',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPrintOutputSection() {
    final controller = widget.printController;
    final messages = controller?.messages ?? const <String>[];

    return Column(
      key: const ValueKey('macro-print-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebarHeader(
          icon: Icons.terminal,
          title: 'Print Output',
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_sweep,
              color: Colors.white54,
              size: 15,
            ),
            tooltip: 'Clear print output',
            onPressed: controller != null && controller.hasMessages
                ? controller.clear
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'No print output yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _printScrollController,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        messages[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSidebarHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF172A45),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildDebugBar() {
    final hasContent = _controller.text.trim().isNotEmpty;
    final canPlay =
        widget.onPlay != null &&
        !widget.isPlaying &&
        !widget.isDebugRunning &&
        hasContent;
    final canStep =
        widget.onStep != null &&
        !widget.isPlaying &&
        hasContent &&
        (!widget.hasDebugSession || widget.isDebugPaused);
    final canContinue =
        widget.onContinue != null &&
        !widget.isPlaying &&
        hasContent &&
        widget.hasDebugSession &&
        widget.isDebugPaused;
    final canStop =
        widget.onStop != null && (widget.isPlaying || widget.hasDebugSession);

    final status = widget.isPlaying
        ? 'Running full macro…'
        : widget.debugStatus ?? 'Idle';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            _buildDebugButton(
              label: 'Play',
              icon: Icons.play_arrow,
              color: Colors.green[800]!,
              onPressed: canPlay ? widget.onPlay : null,
            ),
            const SizedBox(width: 8),
            _buildDebugButton(
              label: 'Step',
              icon: Icons.skip_next,
              color: Colors.blue[800]!,
              onPressed: canStep ? widget.onStep : null,
            ),
            const SizedBox(width: 8),
            _buildDebugButton(
              label: 'Continue',
              icon: Icons.fast_forward,
              color: Colors.teal[800]!,
              onPressed: canContinue ? widget.onContinue : null,
            ),
            const SizedBox(width: 8),
            _buildDebugButton(
              label: 'Stop',
              icon: Icons.stop,
              color: Colors.orange[800]!,
              onPressed: canStop ? widget.onStop : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed == null ? Colors.grey[800]! : color,
        foregroundColor: onPressed == null ? Colors.white38 : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  // ── AI assistant ─────────────────────────────────────────────────────

  /// Whether the AI assistant is configured and its agent was created.
  bool get _isAiAvailable =>
      widget.aiSettings?.isConfigured == true && _chat.isAvailable;

  /// Applies a complete macro written by the AI assistant.
  ///
  /// Uses the programmatic-edit path so Ctrl+Z restores the previous version
  /// and the parent is notified about the modification.
  bool _applyAiMacroEdit(String content) {
    if (!mounted) return false;
    _applyProgrammaticEdit(
      TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      ),
    );
    return true;
  }

  /// Opens or closes the AI chat panel next to the editor.
  void _toggleMacroChat() {
    if (!_isAiAvailable) return;
    _chat.toggleOpen();

    if (!_chat.isOpen) {
      // Give the focus back to the editor so its keyboard shortcuts work
      // immediately after closing the chat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocusNode.requestFocus();
      });
    }
  }

  /// Sends a message to the macro agent and streams its answer into the chat.
  ///
  /// The controller owns the request, so it also completes normally while the
  /// editor is closed.
  Future<void> _onMacroChatSend(String text) => _chat.send(text);

  Widget _buildMacroChatWindow() {
    return ChatWindow(
      chatMessages: _chat.messages,
      isChatting: _chat.isChatting,
      isInitialized: _chat.isInitialized,
      onSendMessage: _onMacroChatSend,
      onCancel: _chat.cancel,
      hintText: 'Ask the macro assistant...',
      emptyStateText:
          'Ask me to create or change the macro.\n'
          'I can read and edit the macro in this editor.',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate gutter width based on digit count (min 32, add 8 per extra
    // digit beyond 2).
    final gutterWidth = 32.0 + (_lineCount.toString().length - 1) * 8.0;
    final showChat = _chat.isOpen && _isAiAvailable;
    final showOutputSidebar =
        widget.debugVariables.isNotEmpty ||
        (widget.printController?.hasMessages ?? false);

    final charWidth = _measureEditorCharWidth();
    // The editor column is sized for 60 to 120 monospace characters: the
    // text area plus the text-field padding (8 + 12), the gutter, the divider
    // and the editor box border.
    final minEditorWidth = _editorMinChars * charWidth + gutterWidth + 55;
    final maxEditorWidth = _editorMaxChars * charWidth + gutterWidth + 55;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Usable width inside the panel border.
        final maxInnerWidth = (constraints.maxWidth - 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        final panelMinWidth =
            (showOutputSidebar ? _minOutputSidebarWidth : 0.0) +
            (showChat ? _minChatWidth : 0.0);
        // The side panels keep their minimum widths; the editor takes the
        // remaining space, so it grows with the window until it reaches 120
        // characters. Only when the window is too narrow does it drop below
        // 60 characters, instead of overflowing.
        final editorWidth = (maxInnerWidth - panelMinWidth)
            .clamp(minEditorWidth, maxEditorWidth)
            .clamp(0.0, maxInnerWidth)
            .toDouble();
        final showSidePanels = showChat || showOutputSidebar;
        final panelWidth = showSidePanels ? double.infinity : editorWidth + 2;
        final rowWidth = showSidePanels ? maxInnerWidth : editorWidth;
        final sideSpace = (rowWidth - editorWidth)
            .clamp(0.0, double.infinity)
            .toDouble();

        // The sidebar fills the left side region and the chat the right one.
        // While the editor is below its maximum width, its growth consumes
        // the extra space; afterwards the side panels grow.
        double sidebarWidth = 0;
        double chatWidth = 0;
        if (showOutputSidebar && showChat) {
          final minSum = _minOutputSidebarWidth + _minChatWidth;
          if (sideSpace >= minSum) {
            final extra = (sideSpace - minSum) / 2;
            sidebarWidth = _minOutputSidebarWidth + extra;
            chatWidth = _minChatWidth + extra;
          } else {
            // Very narrow window: scale both minimum widths down instead of
            // overflowing.
            final scale = sideSpace / minSum;
            sidebarWidth = _minOutputSidebarWidth * scale;
            chatWidth = _minChatWidth * scale;
          }
        } else if (showOutputSidebar) {
          sidebarWidth = sideSpace;
        } else if (showChat) {
          chatWidth = sideSpace;
        }

        return Container(
          // With an open side panel the panel fills the window so that the
          // sidebar reaches the left edge and the chat reaches the right edge.
          // Without side panels it is only as wide as the editor column.
          width: panelWidth,
          decoration: BoxDecoration(
            color: const Color(0xFF0A192F),
            border: Border.all(color: const Color(0xFF475569)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF172A45),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
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
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // AI Macro Assistant toggle. Disabled until the AI
                        // provider, token and model are configured.
                        IconButton(
                          icon: Icon(
                            Icons.auto_awesome,
                            color: _isAiAvailable
                                ? (_chat.isOpen
                                      ? Colors.cyanAccent
                                      : Colors.white70)
                                : Colors.white24,
                            size: 20,
                          ),
                          tooltip: _isAiAvailable
                              ? (_chat.isOpen
                                    ? 'Close AI Macro Assistant'
                                    : 'AI Macro Assistant')
                              : 'Configure AI settings first',
                          onPressed: _isAiAvailable ? _toggleMacroChat : null,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
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
                  ],
                ),
              ),
              // Error banner — full width, below the filename line
              if (widget.errorMessage != null)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF3D0000),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    widget.errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFFF8888),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),

              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The output sidebar fills the space from the left window
                    // edge to the editor column.
                    SizedBox(
                      width: sidebarWidth,
                      child: showOutputSidebar
                          ? _buildOutputSidebar(widget.debugVariables)
                          : null,
                    ),
                    SizedBox(
                      width: editorWidth,
                      child: Column(
                        children: [
                          _buildDebugBar(),
                          // Editable text area with line numbers
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D0D0D),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.cyanAccent,
                                  width: 1.0,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Line number gutter ──────────────
                                    // Rendered via CustomPaint that uses the SAME
                                    // scroll offset and line-height formula as
                                    // the TextField, guaranteeing pixel-perfect
                                    // alignment at any depth.
                                    GestureDetector(
                                      key: const ValueKey(
                                        'macro-editor-gutter',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (details) =>
                                          _toggleBreakpointAt(
                                            details.localPosition.dy,
                                          ),
                                      onSecondaryTapDown: _showBreakpointMenu,
                                      child: Container(
                                        width: gutterWidth,
                                        color: const Color(0xFF080808),
                                        child: ClipRect(
                                          child: CustomPaint(
                                            painter: _GutterPainter(
                                              lineCount: _lineCount,
                                              errorLines: _errorLines,
                                              lineMetrics: _lineMetrics,
                                              gutterBaselineOffset:
                                                  _gutterBaselineOffset,
                                              topPadding: _gutterTopPadding,
                                              scrollOffset: _scrollOffset,
                                              normalStyle: _gutterNormalStyle,
                                              errorStyle: _gutterErrorStyle,
                                              gutterWidth: gutterWidth,
                                              rightPadding: 8.0,
                                              breakpoints: widget.breakpoints,
                                              inactiveBreakpoints:
                                                  widget.inactiveBreakpoints,
                                              currentLine:
                                                  widget.debugCurrentLine,
                                            ),
                                            size: Size.infinite,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Vertical divider
                                    Container(
                                      width: 1,
                                      color: const Color(0xFF2A3A5A),
                                    ),
                                    // ── Text field ──────────────────────
                                    Expanded(
                                      child: ClipRect(
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (widget.debugCurrentLine != null)
                                              Positioned(
                                                key: const ValueKey(
                                                  'macro-debug-line-highlight',
                                                ),
                                                left: 0,
                                                right: 0,
                                                top: _debugLineTop(
                                                  widget.debugCurrentLine!,
                                                ),
                                                height: _editorLineHeight,
                                                child: IgnorePointer(
                                                  child: Container(
                                                    color: Colors.cyanAccent
                                                        .withValues(
                                                          alpha: 0.10,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            Focus(
                                              onKeyEvent: _onKeyEvent,
                                              child: TextField(
                                                controller: _controller,
                                                focusNode: _editorFocusNode,
                                                scrollController:
                                                    _editorScrollController,
                                                maxLines: null,
                                                minLines: null,
                                                textAlignVertical:
                                                    TextAlignVertical.top,
                                                style: _editorTextStyle,
                                                decoration: const InputDecoration(
                                                  hintText:
                                                      'Enter macro commands...',
                                                  hintStyle: TextStyle(
                                                    color: Colors.white24,
                                                    fontSize: 13,
                                                  ),
                                                  border: InputBorder.none,
                                                  contentPadding:
                                                      EdgeInsets.only(
                                                        left: 8,
                                                        top: 18,
                                                        right: 12,
                                                        bottom: 12,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
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
                                border: Border.all(
                                  color: Colors.cyanAccent,
                                  width: 1.0,
                                ),
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
                    ),
                    // The chat fills the space from the editor column to the
                    // right window edge.
                    SizedBox(
                      width: chatWidth,
                      child: showChat
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
                              child: _buildMacroChatWindow(),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Gutter painter
// ============================================================================

/// Actions offered by the breakpoint context menu.
enum _BreakpointMenuAction {
  deleteOne,
  toggleOne,
  activateAll,
  deactivateAll,
  deleteAll,
}

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
  final Set<int> breakpoints;
  final Set<int> inactiveBreakpoints;
  final int? currentLine;

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
    required this.breakpoints,
    required this.inactiveBreakpoints,
    required this.currentLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount == 0) return;
    final metrics = lineMetrics;
    // An empty document has one logical line but no measured line metrics.
    if (metrics == null || metrics.isEmpty) return;

    // Cull: determine which lines intersect the visible viewport.
    const double approxLineHeight = 19.5;
    final double visibleTop = scrollOffset - topPadding;
    final double visibleBottom = visibleTop + size.height;
    final int firstVisible = (visibleTop / approxLineHeight).floor().clamp(
      0,
      lineCount - 1,
    );
    final int lastVisible = (visibleBottom / approxLineHeight).ceil().clamp(
      0,
      lineCount - 1,
    );
    final int lastMetric = metrics.length - 1;

    final double textAreaWidth = gutterWidth - rightPadding;
    final currentLinePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.12);
    final breakpointPaint = Paint()..color = Colors.redAccent;
    final inactiveBreakpointPaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = firstVisible; i <= lastVisible; i++) {
      final int metricIdx = i.clamp(0, lastMetric);

      // Align the gutter text's alphabetic baseline with the editor's
      // text baseline.  [LineMetrics.baseline] is the baseline position
      // relative to the paragraph top (content-padding top in the editor).
      final double y =
          topPadding +
          metrics[metricIdx].baseline -
          scrollOffset -
          gutterBaselineOffset;

      // Quick cull: skip lines clearly outside the viewport.
      if (y + gutterBaselineOffset < 0 || y > size.height) continue;

      // [y] is the top of the number's text box (the baseline alignment
      // above makes the number's baseline match the editor text).
      final double lineHeight = metrics[metricIdx].height;
      if (currentLine == i + 1) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, gutterWidth, lineHeight),
          currentLinePaint,
        );
      }
      if (breakpoints.contains(i + 1)) {
        final center = Offset(6, y + lineHeight / 2);
        canvas.drawCircle(
          center,
          4,
          inactiveBreakpoints.contains(i + 1)
              ? inactiveBreakpointPaint
              : breakpointPaint,
        );
      }

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
        gutterWidth != oldDelegate.gutterWidth ||
        breakpoints != oldDelegate.breakpoints ||
        inactiveBreakpoints != oldDelegate.inactiveBreakpoints ||
        currentLine != oldDelegate.currentLine;
  }
}
