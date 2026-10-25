import 'package:flutter/material.dart';

import '../macro/macro_recorder_models.dart';
import '../macro/macro_print_controller.dart';
import 'macro_editor_panel.dart';

/// Sort options for the macro file list.
enum MacroSortType { name, date }

/// The main Macro Recorder panel widget.
///
/// Displays:
/// - A header with title and Close button
/// - Action buttons: Start, Stop, Edit, Save
/// - A sortable file list of macro (.m) files with Load and Delete per entry
/// - When `isRecording` is true, the Start button shows a blinking red dot
///
/// Clicking the Edit button switches the content area to the
/// [MacroEditorPanel] sub-view. Closing the editor returns to the file list.
class MacroRecorderPanel extends StatefulWidget {
  /// The list of available macro files.
  final List<MacroInfo> macroFiles;

  /// Whether the device is currently online (enables Load buttons).
  final bool isOnline;

  /// Whether a macro recording is currently in progress.
  final bool isRecording;

  /// Whether a macro playback is currently in progress.
  final bool isPlaying;

  /// Whether the Save button should be enabled.
  final bool isSaveEnabled;

  /// Whether there is macro content available to play or edit.
  /// When false, the Play and Edit buttons are disabled.
  final bool hasContent;

  /// The file name of the currently loaded macro, if any.
  /// Shown in the header; cleared when recording a new macro.
  final String? loadedFileName;

  /// Whether the loaded macro has been modified since last save.
  /// When true, a `*` is shown after the file name.
  final bool isModified;

  /// Status of the last macro playback: null = none, 0 = error, 1 = success,
  /// 2 = cancelled. Displayed as an icon in the header.
  final int? macroStatus;

  /// Error message of the last failed macro playback, shown under the
  /// status icon when [macroStatus] is 0 (error).
  final String? macroStatusMessage;

  /// Output of `print()` statements from the current or last playback.
  ///
  /// When it contains messages, a print panel is shown on the left of the
  /// recorder panel, next to the macro file list. It appears with the first
  /// message and disappears when the output is cleared.
  final MacroPrintController? printController;

  final VoidCallback onRecord;
  final VoidCallback onStop;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final Function(String) onLoad;
  final Function(String) onDelete;
  final VoidCallback onClose;

  const MacroRecorderPanel({
    super.key,
    required this.macroFiles,
    required this.isOnline,
    required this.isRecording,
    this.isPlaying = false,
    this.isSaveEnabled = false,
    this.hasContent = false,
    this.loadedFileName,
    this.isModified = false,
    this.macroStatus,
    this.macroStatusMessage,
    this.printController,
    required this.onRecord,
    required this.onStop,
    required this.onPlay,
    required this.onEdit,
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<MacroRecorderPanel> createState() => _MacroRecorderPanelState();
}

class _MacroRecorderPanelState extends State<MacroRecorderPanel>
    with SingleTickerProviderStateMixin {
  MacroSortType _sortType = MacroSortType.name;
  bool _isAscending = true;

  // Blinking dot animation
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  /// Scroll controller of the print output panel.
  final ScrollController _printScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Animation controller for the blinking red dot in the panel header.
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blinkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    widget.printController?.addListener(_onPrintOutputChanged);
    // Output from a playback that finished while the editor was open should
    // be scrolled to the newest line when the recorder panel appears again.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollPrintToBottom(jump: true),
    );
  }

  @override
  void didUpdateWidget(MacroRecorderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _blinkController.stop();
      _blinkController.reset();
    }

    if (widget.printController != oldWidget.printController) {
      oldWidget.printController?.removeListener(_onPrintOutputChanged);
      widget.printController?.addListener(_onPrintOutputChanged);
      _scrollPrintToBottom(jump: true);
    }
  }

  @override
  void dispose() {
    widget.printController?.removeListener(_onPrintOutputChanged);
    _printScrollController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  List<MacroInfo> get _sortedFiles {
    final list = List<MacroInfo>.from(widget.macroFiles);
    if (_sortType == MacroSortType.name) {
      list.sort((a, b) {
        final cmp = a.fileName.toLowerCase().compareTo(
          b.fileName.toLowerCase(),
        );
        return _isAscending ? cmp : -cmp;
      });
    } else {
      list.sort((a, b) {
        final cmp = a.lastModified.compareTo(b.lastModified);
        return _isAscending ? cmp : -cmp;
      });
    }
    return list;
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-"
        "${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:"
        "${dt.minute.toString().padLeft(2, '0')}";
  }

  String _displayName(String fileName) {
    return fileName.endsWith('.m')
        ? fileName.substring(0, fileName.length - 2)
        : fileName;
  }

  // ── Print output ─────────────────────────────────────────────────────

  /// Rebuilds the panel when a `print()` message arrives and keeps the view
  /// scrolled to the newest output. Playback happens while this panel is
  /// visible, so messages appear live.
  void _onPrintOutputChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollPrintToBottom();
  }

  /// Scrolls the print output to its last line after the next frame.
  ///
  /// [jump] is used for the initial position (no animation); new messages
  /// animate the scroll slightly.
  void _scrollPrintToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_printScrollController.hasClients) return;
      final extent = _printScrollController.position.maxScrollExtent;
      if (jump) {
        _printScrollController.jumpTo(extent);
      } else {
        _printScrollController.animateTo(
          extent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPrintOutputPanel(MacroPrintController controller) {
    final messages = controller.messages;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF475569)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF172A45),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.cyanAccent, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Print Output",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_sweep,
                    color: Colors.white54,
                    size: 16,
                  ),
                  tooltip: 'Clear print output',
                  onPressed: controller.clear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _printScrollController,
              padding: const EdgeInsets.all(10),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    messages[index],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedList = _sortedFiles;
    final printController = widget.printController;
    final showPrint = printController?.hasMessages ?? false;
    final activePrintController = showPrint ? printController : null;

    return Container(
      // The print panel sits to the left of the file list (300 px + 16 px
      // left padding + 12 px gap). The recorder content keeps its 680 px.
      width: showPrint ? 1008 : 680,
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ==================================================================
          // Header
          // ==================================================================
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
                    const Icon(Icons.movie, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Macro Recorder",
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Macro playback status icon (error text moved below header)
                    if (widget.macroStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Tooltip(
                          message: switch (widget.macroStatus!) {
                            0 => 'Macro failed with error',
                            1 => 'Macro completed successfully',
                            2 => 'Macro playback cancelled',
                            _ => '',
                          },
                          child: Icon(
                            switch (widget.macroStatus!) {
                              0 => Icons.error,
                              1 => Icons.check_circle,
                              2 => Icons.cancel,
                              _ => Icons.help,
                            },
                            color: switch (widget.macroStatus!) {
                              0 => Colors.redAccent,
                              1 => Colors.greenAccent,
                              2 => Colors.orangeAccent,
                              _ => Colors.white,
                            },
                            size: 40,
                          ),
                        ),
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
              ],
            ),
          ),
          // Error banner — full width, below the filename line
          if (widget.macroStatus == 0 && widget.macroStatusMessage != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF3D0000),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                widget.macroStatusMessage!,
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
                // Print output, to the left of the file list. Hidden until
                // the first print() statement produced output.
                if (activePrintController != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                    child: SizedBox(
                      width: 300,
                      child: _buildPrintOutputPanel(activePrintController),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    children: [
                      // ==================================================
                      // Action Buttons Row
                      // ==================================================
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E1E1E,
                            ).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.cyanAccent,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // New Record button
                              Expanded(
                                child: _buildActionButton(
                                  label: widget.isRecording
                                      ? "Recording..."
                                      : "New Record",
                                  icon: widget.isRecording
                                      ? AnimatedBuilder(
                                          animation: _blinkAnimation,
                                          builder: (context, child) {
                                            return Container(
                                              width: 14,
                                              height: 14,
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(
                                                  alpha: _blinkAnimation.value,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                            );
                                          },
                                        )
                                      : const Icon(
                                          Icons.fiber_manual_record,
                                          size: 18,
                                        ),
                                  onPressed:
                                      (widget.isRecording || widget.isPlaying)
                                      ? null
                                      : _onNewRecordPressed,
                                  color: widget.isRecording
                                      ? Colors.grey[800]!
                                      : Colors.red[800]!,
                                  disabled:
                                      widget.isRecording || widget.isPlaying,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Stop button (also active during playback to cancel it)
                              Expanded(
                                child: _buildActionButton(
                                  label: widget.isPlaying
                                      ? "Stop Playback"
                                      : "Stop",
                                  icon: const Icon(Icons.stop, size: 18),
                                  onPressed:
                                      (widget.isRecording || widget.isPlaying)
                                      ? widget.onStop
                                      : null,
                                  color: widget.isPlaying
                                      ? Colors.red[800]!
                                      : Colors.orange[800]!,
                                  disabled:
                                      !widget.isRecording && !widget.isPlaying,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Play button
                              Expanded(
                                child: _buildActionButton(
                                  label: "Play",
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  onPressed:
                                      (widget.isPlaying || !widget.hasContent)
                                      ? null
                                      : widget.onPlay,
                                  color: Colors.green[800]!,
                                  disabled:
                                      widget.isRecording ||
                                      widget.isPlaying ||
                                      !widget.hasContent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Edit button
                              Expanded(
                                child: _buildActionButton(
                                  label: "Edit",
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed:
                                      (widget.isRecording ||
                                          widget.isPlaying ||
                                          !widget.hasContent)
                                      ? null
                                      : widget.onEdit,
                                  color: Colors.blue[800]!,
                                  disabled:
                                      widget.isRecording ||
                                      widget.isPlaying ||
                                      !widget.hasContent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Save button
                              Expanded(
                                child: _buildActionButton(
                                  label: "Save",
                                  icon: const Icon(Icons.save, size: 18),
                                  onPressed:
                                      (widget.isRecording ||
                                          widget.isPlaying ||
                                          !widget.isSaveEnabled)
                                      ? null
                                      : widget.onSave,
                                  color: Colors.cyan[800]!,
                                  disabled:
                                      widget.isRecording ||
                                      widget.isPlaying ||
                                      !widget.isSaveEnabled,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Divider(color: Colors.white12, height: 1),

                      // ==================================================================
                      // Sort Controls
                      // ==================================================================
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              "Sort by:",
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildSortButton("Name", MacroSortType.name),
                            const SizedBox(width: 8),
                            _buildSortButton("Date", MacroSortType.date),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                _isAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: Colors.cyanAccent,
                                size: 16,
                              ),
                              tooltip: _isAscending
                                  ? 'Ascending'
                                  : 'Descending',
                              onPressed: () =>
                                  setState(() => _isAscending = !_isAscending),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),

                      // ==================================================================
                      // Macro File List
                      // ==================================================================
                      Expanded(
                        child: widget.macroFiles.isEmpty
                            ? const Center(
                                child: Text(
                                  "No macro files found",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: sortedList.length,
                                itemBuilder: (context, index) {
                                  final macro = sortedList[index];
                                  final displayName = _displayName(
                                    macro.fileName,
                                  );

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF172A45,
                                      ).withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF475569,
                                        ).withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.description,
                                          color: Colors.white38,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatDate(macro.lastModified),
                                                style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Load button
                                        IconButton(
                                          icon: Icon(
                                            Icons.file_upload,
                                            color: widget.isOnline
                                                ? Colors.greenAccent
                                                : Colors.white24,
                                            size: 20,
                                          ),
                                          tooltip: widget.isOnline
                                              ? 'Load Macro'
                                              : 'Device Offline',
                                          onPressed: widget.isOnline
                                              ? () => widget.onLoad(
                                                  macro.fileName,
                                                )
                                              : null,
                                        ),
                                        // Delete button
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                          tooltip: 'Delete Macro',
                                          onPressed: () =>
                                              widget.onDelete(macro.fileName),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Starts a new recording.
  ///
  /// If the editor already contains a macro, the recording would replace it,
  /// so the user is asked to confirm first. Cancel leaves the editor
  /// untouched; OK starts the recording.
  Future<void> _onNewRecordPressed() async {
    if (!widget.hasContent) {
      widget.onRecord();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Overwrite Macro?'),
        content: const Text(
          'The editor already contains a macro. Starting a new recording '
          'will overwrite it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      widget.onRecord();
    }
  }

  Widget _buildActionButton({
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
    required Color color,
    required bool disabled,
  }) {
    final effectiveColor = disabled ? Colors.grey[800]! : color;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColor,
        foregroundColor: disabled ? Colors.white38 : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
      ),
    );
  }

  Widget _buildSortButton(String label, MacroSortType type) {
    final isActive = _sortType == type;
    return InkWell(
      onTap: () => setState(() => _sortType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.cyan[800]?.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? Colors.cyanAccent.withValues(alpha: 0.5)
                : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.cyanAccent : Colors.white70,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
