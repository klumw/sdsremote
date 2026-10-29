import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_settings.dart';
import 'help_ai_service.dart';

/// Owns the help window's AI conversation.
///
/// The controller is created by the help window and lives as long as it is
/// open: closing and reopening the chat panel keeps the transcript, the open
/// state and the agent — and therefore the complete multi-turn history —
/// intact. Leaving the help page disposes the controller, which discards the
/// transcript.
class HelpChatController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [serviceFactory] is primarily useful for tests; production code uses the
  /// default [HelpAiService] constructor.
  HelpChatController({HelpAiService Function()? serviceFactory})
    : _serviceFactory = serviceFactory ?? HelpAiService.new;

  final HelpAiService Function() _serviceFactory;

  final List<Map<String, String>> _messages = <Map<String, String>>[];

  HelpAiService? _service;
  AiSettings? _settings;
  String _manual = '';

  bool _isOpen = false;
  bool _isChatting = false;
  bool _disposed = false;

  StreamSubscription<String>? _subscription;
  Completer<void>? _sendCompleter;
  bool _cancelRequested = false;

  /// Invalidates chunks from a request that belonged to an older agent (for
  /// example after the AI settings changed mid-response).
  int _generation = 0;

  /// Whether the chat panel is open.
  bool get isOpen => _isOpen;

  /// Whether a response is currently being streamed.
  bool get isChatting => _isChatting;

  /// Whether the underlying agent is ready to receive messages.
  bool get isInitialized => _service?.isInitialized ?? false;

  /// Whether the chat can be opened: valid AI settings are configured.
  ///
  /// The agent itself is created once the manual has loaded; until then the
  /// panel can already open, with its input disabled.
  bool get isAvailable => _settings?.isConfigured == true;

  /// The complete chat transcript. The list is owned by the controller and is
  /// only read by the chat window.
  List<Map<String, String>> get messages => _messages;

  /// Cancels an in-flight response without changing the transcript.
  void _cancelActiveRequest() {
    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Creates or updates the agent for [settings] and [manual].
  ///
  /// When settings and manual are unchanged, the existing agent is kept,
  /// including its conversation history. Passing null or an unconfigured
  /// value closes the chat and disposes the agent; the transcript is retained
  /// so it is still there when the AI is configured again.
  void configure(AiSettings? settings, {required String manual}) {
    if (_disposed) return;
    final configured = settings != null && settings.isConfigured;

    if (!configured) {
      final changed = _service != null || _isOpen || _settings != null;
      _cancelActiveRequest();
      _settings = null;
      _manual = '';
      _generation++;
      _isChatting = false;
      _isOpen = false;
      _service?.dispose();
      _service = null;
      if (changed) notifyListeners();
      return;
    }

    if (_settings == settings && _manual == manual && _service != null) {
      return;
    }

    _cancelActiveRequest();
    _settings = settings;
    _manual = manual;
    _generation++;
    _isChatting = false;
    _service?.dispose();

    final service = _serviceFactory();
    service.configure(
      apiKey: settings.apiKeyName,
      apiToken: settings.apiToken,
      model: settings.model,
      manual: manual,
    );
    _service = service;
    notifyListeners();
  }

  /// Opens or closes the chat panel.
  void toggleOpen() {
    if (!isAvailable) return;
    _isOpen = !_isOpen;
    notifyListeners();
  }

  /// Closes the chat panel, for example when a section link was clicked.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  /// Sends [text] to the agent and streams the answer into [messages].
  ///
  /// The stream is owned by the controller rather than the chat panel, so a
  /// response that is still being generated when the panel is closed is
  /// completed in the transcript and visible on reopen.
  Future<void> send(String text) async {
    final service = _service;
    final trimmed = text.trim();
    if (_disposed || service == null || !service.isInitialized) return;
    if (trimmed.isEmpty || _isChatting) return;

    final generation = _generation;
    final aiMessage = <String, String>{'role': 'ai', 'content': ''};
    _messages.add(<String, String>{'role': 'user', 'content': trimmed});
    _messages.add(aiMessage);
    _isChatting = true;
    _cancelRequested = false;
    final completer = Completer<void>();
    _sendCompleter = completer;

    var hasReceivedChunk = false;
    var hasError = false;
    final subscription = service
        .sendMessageStream(text: trimmed)
        .listen(
          (chunk) {
            if (_disposed || generation != _generation || _cancelRequested) {
              return;
            }
            hasReceivedChunk = true;
            aiMessage['content'] = (aiMessage['content'] ?? '') + chunk;
            notifyListeners();
          },
          onError: (Object e) {
            if (_disposed || generation != _generation || _cancelRequested) {
              if (!completer.isCompleted) completer.complete();
              return;
            }
            hasError = true;
            aiMessage['content'] = 'Error: Failed to connect to AI server ($e)';
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    _subscription = subscription;
    notifyListeners();

    await completer.future;

    if (_subscription == subscription) _subscription = null;
    if (_sendCompleter == completer) _sendCompleter = null;

    if (_disposed || generation != _generation || _cancelRequested) return;

    if (!hasReceivedChunk && !hasError) {
      aiMessage['content'] = 'No response from AI-Server';
    }
    _isChatting = false;
    notifyListeners();
  }

  /// Stops the active response immediately and reports the termination in the
  /// transcript.
  Future<void> cancel() async {
    if (_disposed || !_isChatting) return;

    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;

    final aiMessage = _messages.isNotEmpty && _messages.last['role'] == 'ai'
        ? _messages.last
        : null;
    aiMessage?['content'] = 'terminated by user';

    _isChatting = false;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();

    await subscription?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelActiveRequest();
    _service?.dispose();
    _service = null;
    super.dispose();
  }
}
