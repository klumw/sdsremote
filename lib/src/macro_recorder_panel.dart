import 'package:flutter/material.dart';

import 'macro_recorder_models.dart';
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

  /// The file name of the currently loaded macro, if any.
  /// Shown in the header; cleared when recording a new macro.
  final String? loadedFileName;

  /// Whether the loaded macro has been modified since last save.
  /// When true, a `*` is shown after the file name.
  final bool isModified;

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
    this.loadedFileName,
    this.isModified = false,
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
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  List<MacroInfo> get _sortedFiles {
    final list = List<MacroInfo>.from(widget.macroFiles);
    if (_sortType == MacroSortType.name) {
      list.sort((a, b) {
        final cmp =
            a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
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

  @override
  Widget build(BuildContext context) {
    final sortedList = _sortedFiles;

    return Container(
      width: 680,
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
                    // Recording indicator: blinking red dot
                    if (widget.isRecording)
                      AnimatedBuilder(
                        animation: _blinkAnimation,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _blinkAnimation.value,
                            child: Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      )
                    else
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
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // ==================================================================
          // Action Buttons Row
          // ==================================================================
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Record button
                Expanded(
                  child: _buildActionButton(
                    label: widget.isRecording ? "Recording..." : "Record",
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
                        : const Icon(Icons.fiber_manual_record, size: 18),
                    onPressed: (widget.isRecording || widget.isPlaying) ? null : widget.onRecord,
                    color: widget.isRecording ? Colors.grey[800]! : Colors.red[800]!,
                    disabled: widget.isRecording || widget.isPlaying,
                  ),
                ),
                const SizedBox(width: 8),
                // Stop button (also active during playback to cancel it)
                Expanded(
                  child: _buildActionButton(
                    label: widget.isPlaying ? "Stop Playback" : "Stop",
                    icon: const Icon(Icons.stop, size: 18),
                    onPressed: (widget.isRecording || widget.isPlaying) ? widget.onStop : null,
                    color: widget.isPlaying ? Colors.red[800]! : Colors.orange[800]!,
                    disabled: !widget.isRecording && !widget.isPlaying,
                  ),
                ),
                const SizedBox(width: 8),
                // Play button
                Expanded(
                  child: _buildActionButton(
                    label: "Play",
                    icon: const Icon(Icons.play_arrow, size: 18),
                    onPressed: widget.isPlaying ? null : widget.onPlay,
                    color: Colors.green[800]!,
                    disabled: widget.isRecording || widget.isPlaying,
                  ),
                ),
                const SizedBox(width: 8),
                // Edit button
                Expanded(
                  child: _buildActionButton(
                    label: "Edit",
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: widget.isPlaying ? null : widget.onEdit,
                    color: Colors.blue[800]!,
                    disabled: widget.isPlaying,
                  ),
                ),
                const SizedBox(width: 8),
                // Save button
                Expanded(
                  child: _buildActionButton(
                    label: "Save",
                    icon: const Icon(Icons.save, size: 18),
                    onPressed: (widget.isPlaying || !widget.isSaveEnabled) ? null : widget.onSave,
                    color: Colors.cyan[800]!,
                    disabled: widget.isPlaying || !widget.isSaveEnabled,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // ==================================================================
          // Sort Controls
          // ==================================================================
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  "Sort by:",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(width: 8),
                _buildSortButton("Name", MacroSortType.name),
                const SizedBox(width: 8),
                _buildSortButton("Date", MacroSortType.date),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.cyanAccent,
                    size: 16,
                  ),
                  tooltip: _isAscending ? 'Ascending' : 'Descending',
                  onPressed: () => setState(() => _isAscending = !_isAscending),
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
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: sortedList.length,
                    itemBuilder: (context, index) {
                      final macro = sortedList[index];
                      final displayName = _displayName(macro.fileName);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF172A45).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF475569).withValues(alpha: 0.5),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  ? () => widget.onLoad(macro.fileName)
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
                              onPressed: () => widget.onDelete(macro.fileName),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
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
        foregroundColor:
            disabled ? Colors.white38 : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
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
          color:
              isActive ? Colors.cyan[800]?.withValues(alpha: 0.3) : Colors.transparent,
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
