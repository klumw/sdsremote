import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../ai/calculator_chat_controller.dart';
import '../app/app_theme.dart';
import '../calculator/calculator_controller.dart';
import 'calculator_dialogs.dart';
import 'osci_chat_window.dart';

/// Sliding AI side panel of the Engineering Calculator.
///
/// It reuses [ChatWindow] so the transcript, markdown rendering, streaming
/// indicator and send/stop controls match the other assistants in the app.
class CalculatorChatPanel extends StatefulWidget {
  const CalculatorChatPanel({
    super.key,
    required this.controller,
    required this.calculatorController,
    required this.onClose,
    required this.onReloadSettings,
    required this.onInsertExpression,
    required this.onStoreResult,
    required this.onApplyProgram,
  });

  final CalculatorChatController controller;
  final CalculatorController calculatorController;
  final VoidCallback onClose;
  final VoidCallback onReloadSettings;
  final ValueChanged<String> onInsertExpression;
  final ValueChanged<String> onStoreResult;
  final ValueChanged<String> onApplyProgram;

  @override
  State<CalculatorChatPanel> createState() => _CalculatorChatPanelState();
}

class _CalculatorChatPanelState extends State<CalculatorChatPanel> {
  final TextEditingController _input = TextEditingController();

  CalculatorChatController get _chat => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: _chat,
        builder: (context, _) {
          return Column(
            children: [
              _buildHeader(),
              if (!_chat.isAvailable) _buildConfigurationBanner(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                  child: ChatWindow(
                    chatMessages: _displayMessages(),
                    isChatting: _chat.isChatting,
                    isInitialized: _chat.isAvailable,
                    onSendMessage: _chat.send,
                    onCancel: _chat.cancel,
                    inputHistory: _chat.inputHistory,
                    onHistorySelected: _chat.send,
                    autofocus: _chat.isOpen,
                    inputController: _input,
                    markdownBuilders: {
                      'code': _CalculatorFootnoteBuilder(
                        summaryFor: _footnoteSummary,
                        onSecondaryTap: _showFootnoteMenu,
                      ),
                    },
                    useSelectionArea: false,
                    messageFooterBuilder: _buildMessageFooter,
                    hintText: 'Ask the calculator assistant...',
                    emptyStateText:
                        'Describe a calculation\n\n'
                        'What is the cutoff frequency of a 10 kΩ '
                        'and 100 nF RC filter?\n\nConvert 20 dBm to mW\n\n'
                        'What is the record time at 1 GSa/s and 10 MSa?"',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Links `[n]` citations in an answer to the corresponding structured
  /// result. Code blocks and inline code are left untouched.
  List<Map<String, String>> _displayMessages() {
    final messages = _chat.messages;
    final display = <Map<String, String>>[];
    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      final resultCount = _chat.resultsFor(index).length;
      if (message['role'] != 'ai' || resultCount == 0) {
        display.add(message);
        continue;
      }
      display.add({
        ...message,
        'content': _linkFootnotes(message['content'] ?? '', index, resultCount),
      });
    }
    return display;
  }

  String _linkFootnotes(String content, int messageIndex, int resultCount) {
    final code = RegExp(r'```[\s\S]*?```|`[^`\n]*`');
    final counts = <int, int>{};
    String replace(String text) {
      return text.replaceAllMapped(RegExp(r'\[(\d+)\](?!\()'), (match) {
        final footnote = int.tryParse(match.group(1)!);
        if (footnote == null || footnote < 1 || footnote > resultCount) {
          return match.group(0)!;
        }
        final occurrence = counts[footnote] ?? 0;
        counts[footnote] = occurrence + 1;
        return '`calc-fn:$messageIndex:$footnote:$occurrence`';
      });
    }

    final output = StringBuffer();
    var last = 0;
    for (final match in code.allMatches(content)) {
      output.write(replace(content.substring(last, match.start)));
      output.write(match.group(0));
      last = match.end;
    }
    output.write(replace(content.substring(last)));
    return output.toString();
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF10233D),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _chat.statusLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          IconButton(
            tooltip: 'Insert calculator variable',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.memory, size: 18, color: Colors.white70),
            onPressed: _insertVariable,
          ),
          IconButton(
            tooltip: 'Reload AI settings',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
            onPressed: widget.onReloadSettings,
          ),
          IconButton(
            tooltip: 'Close calculator assistant',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: Colors.white70),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2A1F0B),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amberAccent, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'AI is not configured. Set the provider, token and model in '
              'SDS-Remote Settings. The calculator remains fully usable.',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: widget.onReloadSettings,
            child: const Text('Reload'),
          ),
        ],
      ),
    );
  }

  Future<void> _insertVariable() async {
    final name = await showRecallDialog(context, widget.calculatorController);
    if (name == null) return;
    final selection = _input.selection;
    final start = selection.isValid ? selection.start : _input.text.length;
    final end = selection.isValid ? selection.end : _input.text.length;
    final next = _input.text.replaceRange(start, end, name);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + name.length),
    );
  }

  Widget? _buildMessageFooter(BuildContext context, int index) {
    if (index < 0 || index >= _chat.messages.length) return null;
    final message = _chat.messages[index];
    final content = message['content'] ?? '';
    final code = _extractLastCodeBlock(content);
    if (content.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              if (content.isNotEmpty)
                _smallAction(
                  icon: Icons.copy,
                  label: 'Copy',
                  onPressed: () => _copy(content, 'Answer copied.'),
                ),
              if (code != null)
                _smallAction(
                  icon: Icons.code,
                  label: 'Use in program',
                  onPressed: () => widget.onApplyProgram(code),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 28),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  String _footnoteSummary(int messageIndex, int footnote) {
    final results = _chat.resultsFor(messageIndex);
    if (footnote < 1 || footnote > results.length) return 'Result [$footnote]';
    final result = results[footnote - 1];
    return '${result.result}\nCalculation: ${_calculationLabel(result)}';
  }

  Future<void> _showFootnoteMenu(
    BuildContext anchorContext,
    int messageIndex,
    int footnote,
    Offset globalPosition,
  ) async {
    final results = _chat.resultsFor(messageIndex);
    if (footnote < 1 || footnote > results.length) return;
    final result = results[footnote - 1];
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final local = overlay.globalToLocal(globalPosition);
    final action = await showMenu<_FootnoteAction>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        _footnoteMenuItem(
          _FootnoteAction.copy,
          'footnote-action-copy',
          Icons.copy,
          'Copy',
        ),
        _footnoteMenuItem(
          _FootnoteAction.insertResult,
          'footnote-action-insert-result',
          Icons.input,
          'Insert result',
        ),
        _footnoteMenuItem(
          _FootnoteAction.useInProgram,
          'footnote-action-use-in-program',
          Icons.code,
          'Use in program',
        ),
        _footnoteMenuItem(
          _FootnoteAction.useAsVariable,
          'footnote-action-use-as-variable',
          Icons.save,
          'Use as variable',
        ),
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _FootnoteAction.copy:
        await _copy(result.result, 'Result copied.');
      case _FootnoteAction.insertResult:
        widget.onInsertExpression(result.value);
      case _FootnoteAction.useInProgram:
        final content = _chat.messages[messageIndex]['content'] ?? '';
        final code =
            _extractLastCodeBlock(content) ?? _calculationLabel(result);
        widget.onApplyProgram(code);
      case _FootnoteAction.useAsVariable:
        widget.onStoreResult(result.value);
    }
  }

  PopupMenuItem<_FootnoteAction> _footnoteMenuItem(
    _FootnoteAction action,
    String key,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_FootnoteAction>(
      key: ValueKey(key),
      value: action,
      child: Row(
        children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  String _calculationLabel(CalculatorChatResult result) {
    final source = result.expression.trim().isNotEmpty
        ? result.expression.trim()
        : result.normalized.trim();
    if (result.formulaInputs.isEmpty) return source;
    final inputs = result.formulaInputs.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    return '$source  ($inputs)';
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static String? _extractLastCodeBlock(String text) {
    final matches = RegExp(
      r'```[^\n]*\n([\s\S]*?)```',
    ).allMatches(text).toList();
    if (matches.isEmpty) return null;
    final code = matches.last.group(1)?.trim();
    return code == null || code.isEmpty ? null : code;
  }
}

enum _FootnoteAction { copy, insertResult, useInProgram, useAsVariable }

/// Renders the inline `calc-fn:…` code markers produced by
/// [_CalculatorChatPanelState._linkFootnotes] as right-clickable footnote
/// badges.
class _CalculatorFootnoteBuilder extends MarkdownElementBuilder {
  _CalculatorFootnoteBuilder({
    required this.summaryFor,
    required this.onSecondaryTap,
  });

  final String Function(int messageIndex, int footnote) summaryFor;
  final void Function(
    BuildContext context,
    int messageIndex,
    int footnote,
    Offset globalPosition,
  )
  onSecondaryTap;

  static final RegExp _pattern = RegExp(r'^calc-fn:(\d+):(\d+):(\d+)$');

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final match = _pattern.firstMatch(element.textContent);
    if (match == null) return null;
    final messageIndex = int.parse(match.group(1)!);
    final footnote = int.parse(match.group(2)!);

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Tooltip(
              message: summaryFor(messageIndex, footnote),
              mouseCursor: SystemMouseCursors.click,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onSecondaryTapUp: (details) => onSecondaryTap(
                    context,
                    messageIndex,
                    footnote,
                    details.globalPosition,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      '[$footnote]',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
