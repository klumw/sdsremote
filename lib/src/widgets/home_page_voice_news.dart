part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeVoiceNews on _OsciHomePageState {
  /// Stops an assistant microphone when its chat panel is no longer visible.
  ///
  /// Most top-bar switches already stop the microphone directly, but the
  /// Control Panel and Acquire Waveform toolbar buttons replace the main view
  /// without going through `_togglePanel`. This check runs on every build and
  /// closes a session whose owning chat disappeared, regardless of the route
  /// that left the panel.
  void _scheduleVoiceInputVisibilityCheck() {
    final status = _voiceInputService.status.value;
    final owner = status.ownerId;
    if (!status.isActive || owner == null) return;
    if (_isVoiceOwnerVisible(owner)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _voiceInputService.status.value;
      if (!current.isActiveFor(owner)) return;
      if (_isVoiceOwnerVisible(owner)) return;
      unawaited(_voiceInputService.stop(ownerId: owner));
    });
  }

  /// Whether the chat that owns the microphone is still on screen.
  bool _isVoiceOwnerVisible(String owner) {
    return switch (owner) {
      'ai_chat' => _activePanel == ActivePanel.chat,
      'control_panel_ai' =>
        _activePanel == ActivePanel.none &&
            !_waveformAcquired &&
            _screenDump != null &&
            _controlPanelChatController.isOpen,
      'waveform_ai' =>
        _activePanel == ActivePanel.none &&
            _waveformAcquired &&
            _showWaveformAi &&
            _waveformChatController.isOpen,
      'macro_ai' =>
        _activePanel == ActivePanel.macroRecorder &&
            _showMacroEditor &&
            _macroChatController.isOpen,
      'help_ai' => _activePanel == ActivePanel.help,
      _ => true,
    };
  }

  Future<void> _checkNewsNotification() async {
    final service = NewsNotificationService();
    final news = await service.fetchNotification();
    if (news == null) return;

    final lastReadId = await service.getLastReadId();
    _setState(() {
      _latestNews = news;
      _hasUnreadUpdate = lastReadId == null || news.id > lastReadId;
    });

    if (news.forceShow) {
      _showNewsDialog();
    }
  }

  Future<void> _showNewsDialog() async {
    if (_latestNews == null) {
      await _checkNewsNotification();
    }

    if (_latestNews == null) {
      _showInfoSnackBar(
        'News service is currently unavailable. Please check your connection.',
        backgroundColor: const Color(0xFF1E293B),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => NewsNotificationDialog(
        notification: _latestNews!,
        onDismiss: () async {
          await NewsNotificationService().markAsRead(_latestNews!.id);
          _setState(() {
            _hasUnreadUpdate = false;
          });
        },
      ),
    );
  }
}
