import 'package:flutter/material.dart';

/// A simple multi-line text editor for editing macro file content.
///
/// Displays a header with "Macro Editor" title and a Close button.
/// The editable text area shows the macro commands and supports
/// full editing via keyboard, with line numbers on the left side.
class MacroEditorPanel extends StatefulWidget {
  /// The initial content to populate the text editor with.
  final String initialContent;

  /// Called whenever the user modifies the text content.
  final ValueChanged<String> onContentChanged;

  /// Called when the Close button is pressed.
  final VoidCallback onClose;

  const MacroEditorPanel({
    super.key,
    this.initialContent = '',
    required this.onContentChanged,
    required this.onClose,
  });

  @override
  State<MacroEditorPanel> createState() => _MacroEditorPanelState();
}

class _MacroEditorPanelState extends State<MacroEditorPanel> {
  late final TextEditingController _controller;
  final ScrollController _gutterScrollController = ScrollController();
  final ScrollController _editorScrollController = ScrollController();
  bool _isSyncing = false;
  int _lineCount = 1;

  static const double _lineHeight = 13.0 * 1.5; // fontSize * height

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(_onTextChanged);
    _updateLineCount();

    // Sync the gutter scroll to follow the editor scroll.
    _editorScrollController.addListener(_onEditorScroll);

    // Sync the editor scroll to follow the gutter scroll.
    _gutterScrollController.addListener(_onGutterScroll);
  }

  void _onEditorScroll() {
    if (!_isSyncing && _gutterScrollController.hasClients) {
      _isSyncing = true;
      final offset = _editorScrollController.offset;
      _gutterScrollController.jumpTo(offset.clamp(
        0.0,
        _gutterScrollController.position.maxScrollExtent,
      ));
      _isSyncing = false;
    }
  }

  void _onGutterScroll() {
    if (!_isSyncing && _editorScrollController.hasClients) {
      _isSyncing = true;
      final offset = _gutterScrollController.offset;
      _editorScrollController.jumpTo(offset.clamp(
        0.0,
        _editorScrollController.position.maxScrollExtent,
      ));
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

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _gutterScrollController.removeListener(_onGutterScroll);
    _editorScrollController.removeListener(_onEditorScroll);
    _gutterScrollController.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _updateLineCount();
    widget.onContentChanged(_controller.text);
  }

  void _updateLineCount() {
    final lines = _controller.text.split('\n').length;
    if (lines != _lineCount) {
      setState(() {
        _lineCount = lines;
      });
    }
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
                const Row(
                  children: [
                    Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Macro Editor",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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

          // Editable text area with line numbers
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2A4A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF475569)),
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
                    Container(
                      width: 1,
                      color: const Color(0xFF2A3A5A),
                    ),
                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        scrollController: _editorScrollController,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter macro commands...',
                          hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(
                            left: 8, top: 12, right: 12, bottom: 12,
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
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18),
                label: const Text("Close"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
