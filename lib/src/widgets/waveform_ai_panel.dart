import 'package:flutter/material.dart';

import '../ai/waveform_chat_controller.dart';
import '../app/app_theme.dart';
import 'osci_chat_window.dart';

/// Sliding AI side panel of the Acquire Waveform view.
///
/// It reuses [ChatWindow] so the transcript, Markdown rendering, streaming
/// indicator and send/stop controls match the other assistants in the app.
class WaveformAiPanel extends StatefulWidget {
  const WaveformAiPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final WaveformChatController controller;
  final VoidCallback onClose;

  @override
  State<WaveformAiPanel> createState() => _WaveformAiPanelState();
}

class _WaveformAiPanelState extends State<WaveformAiPanel> {
  final TextEditingController _input = TextEditingController();

  WaveformChatController get _chat => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(-8, 0),
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
                    hintText: 'Ask about the waveform or spectrum...',
                    emptyStateText:
                        'Ask about the current acquisition\n\n'
                        'Which channel has the lowest THD?\n\n'
                        'Explain the spectrum peaks and harmonics.\n\n'
                        'Convert the CH1 fundamental level to dBV.',
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
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF172A45),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 18,
            color: Colors.lightBlueAccent,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Waveform AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            _chat.statusLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Clear chat',
            onPressed: _chat.messages.isEmpty || _chat.isChatting
                ? null
                : _chat.clearChat,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            color: Colors.white70,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 18),
            color: Colors.white70,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF3A2A10),
      child: const Text(
        'AI is not configured. Set the provider, token and model in '
        'SDS-Remote Settings to use the waveform assistant.',
        style: TextStyle(color: Colors.amberAccent, fontSize: 11),
      ),
    );
  }
}
