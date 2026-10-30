import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                    chatMessages: _chat.messages,
                    isChatting: _chat.isChatting,
                    isInitialized: _chat.isAvailable,
                    onSendMessage: _chat.send,
                    onCancel: _chat.cancel,
                    autofocus: _chat.isOpen,
                    inputController: _input,
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
    final results = _chat.resultsFor(index);
    final code = _extractLastCodeBlock(content);
    if (content.isEmpty && results.isEmpty) return null;

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
          for (final result in results) _buildResultCard(result),
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

  Widget _buildResultCard(CalculatorChatResult result) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E35),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.result,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 17,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          if (result.formulaName != null)
            Text(
              result.formulaName!,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
            ),
          if (result.assumptions.isNotEmpty)
            Text(
              result.assumptions.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            children: [
              _smallAction(
                icon: Icons.input,
                label: 'Insert result',
                onPressed: () => widget.onInsertExpression(result.value),
              ),
              _smallAction(
                icon: Icons.save,
                label: 'Store as variable',
                onPressed: () => widget.onStoreResult(result.value),
              ),
              _smallAction(
                icon: Icons.copy,
                label: 'Copy',
                onPressed: () => _copy(result.result, 'Result copied.'),
              ),
            ],
          ),
        ],
      ),
    );
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
