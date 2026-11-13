part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeChat on _OsciHomePageState {
  Widget _buildHelpWindow() {
    return HelpWindow(aiSettings: _aiSettings, voiceInput: _voiceInputService);
  }

  Widget _buildChatWindow() {
    return Column(
      children: [
        _buildChatHeader(),
        Expanded(
          child: ChatWindow(
            chatMessages: _chatMessages,
            isChatting: _isChatting,
            isInitialized: _aiChatService.isInitialized,
            onSendMessage: _onChatSendMessage,
            onCancel: _cancelChat,
            voiceInput: _aiChatVoice,
            inputHistory: _chatInputHistory.entries,
            onHistorySelected: _onChatSendMessage,
          ),
        ),
      ],
    );
  }

  /// Header of the main AI chat, with the session-clear button.
  Widget _buildChatHeader() {
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
              'AI Chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear session',
            onPressed: _chatMessages.isEmpty || _isChatting
                ? null
                : _clearChatSession,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            color: Colors.white70,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _onChatSendMessage(String text) async {
    if (_isChatting) return;
    _chatInputHistory.record(text);
    _setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _isChatting = true;
      _chatCancelRequested = false;
      // Add a placeholder for the AI response
      _chatMessages.add({'role': 'ai', 'content': ''});
    });

    final aiMsgIndex = _chatMessages.length - 1;
    final completer = Completer<void>();
    _chatSendCompleter = completer;
    var hasReceivedChunk = false;
    var hasError = false;

    final subscription = _aiChatService
        .sendMessageStream(text: text)
        .listen(
          (chunk) {
            if (!mounted || _chatCancelRequested) return;
            hasReceivedChunk = true;
            _setState(() {
              _chatMessages[aiMsgIndex]['content'] =
                  (_chatMessages[aiMsgIndex]['content'] ?? '') + chunk;
            });
          },
          onError: (Object e) {
            if (!mounted || _chatCancelRequested) {
              if (!completer.isCompleted) completer.complete();
              return;
            }
            hasError = true;
            _setState(() {
              _chatMessages[aiMsgIndex]['content'] =
                  'Error: Failed to connect to AI server ($e)';
            });
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    _chatSubscription = subscription;

    await completer.future;

    if (_chatSubscription == subscription) _chatSubscription = null;
    if (_chatSendCompleter == completer) _chatSendCompleter = null;

    if (!mounted || _chatCancelRequested) return;

    if (!hasReceivedChunk && !hasError) {
      _setState(() {
        _chatMessages[aiMsgIndex]['content'] = 'No response from AI-Server';
      });
    }
    _setState(() {
      _isChatting = false;
    });
  }

  /// Stops the active main-chat response immediately.
  Future<void> _cancelChat() async {
    if (!_isChatting) return;

    _chatCancelRequested = true;
    final subscription = _chatSubscription;
    _chatSubscription = null;

    if (mounted &&
        _chatMessages.isNotEmpty &&
        _chatMessages.last['role'] == 'ai') {
      _setState(() {
        _chatMessages.last['content'] = 'terminated by user';
      });
    }

    final completer = _chatSendCompleter;
    _chatSendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (mounted) {
      _setState(() {
        _isChatting = false;
      });
    }

    await subscription?.cancel();
  }

  /// Clears the main chat transcript and the agent conversation history.
  ///
  /// The next request starts a fresh session without the previous turns.
  void _clearChatSession() {
    if (_isChatting) {
      unawaited(_cancelChat());
    }
    _setState(() {
      _chatMessages.clear();
    });
    _aiChatService.clearSession();
  }
}
