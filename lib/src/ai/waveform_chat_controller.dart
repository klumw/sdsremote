import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_settings.dart';
import 'tools/spectrum_summary_tool.dart';
import 'tools/waveform_summary_tool.dart';
import 'waveform_ai_service.dart';

/// Owns the Waveform AI transcript, agent lifecycle and open state.
///
/// The controller only manages the conversation; the waveform and spectrum
/// data stay in the owning page and are read through the providers.
class WaveformChatController extends ChangeNotifier {
  WaveformChatController({WaveformAiService Function()? serviceFactory})
    : _serviceFactory = serviceFactory ?? WaveformAiService.new;

  final WaveformAiService Function() _serviceFactory;
  final List<Map<String, String>> _messages = [];

  WaveformAiService? _service;
  AiSettings? _settings;

  bool _isOpen = false;
  bool _isChatting = false;
  bool _disposed = false;
  int _generation = 0;

  StreamSubscription<String>? _subscription;
  Completer<void>? _sendCompleter;
  bool _cancelRequested = false;

  bool get isOpen => _isOpen;
  bool get isChatting => _isChatting;
  bool get isInitialized => _service?.isInitialized ?? false;
  bool get isAvailable => _settings?.isConfigured == true && isInitialized;
  List<Map<String, String>> get messages => _messages;

  String get statusLabel {
    if (!isAvailable) return 'AI not configured';
    if (_isChatting) return 'Working…';
    return 'Ready';
  }

  void configure(
    AiSettings? settings, {
    required WaveformSummaryProvider readWaveformSummary,
    required SpectrumSummaryProvider readSpectrumSummary,
  }) {
    if (_disposed) return;
    final configured = settings != null && settings.isConfigured;
    if (!configured) {
      _cancelActiveRequest();
      _settings = null;
      _generation++;
      _isChatting = false;
      _service?.dispose();
      _service = null;
      notifyListeners();
      return;
    }
    if (_settings == settings && _service != null) return;

    _cancelActiveRequest();
    _settings = settings;
    _generation++;
    _isChatting = false;
    _service?.dispose();

    final service = _serviceFactory();
    service.configure(
      apiKey: settings.apiKeyName,
      apiToken: settings.apiToken,
      model: settings.model,
      readWaveformSummary: readWaveformSummary,
      readSpectrumSummary: readSpectrumSummary,
    );
    _service = service;
    notifyListeners();
  }

  void setOpen(bool open) {
    if (_disposed || _isOpen == open) return;
    _isOpen = open;
    notifyListeners();
  }

  void toggleOpen() => setOpen(!_isOpen);

  void close() => setOpen(false);

  Future<void> send(String text) async {
    final service = _service;
    final trimmed = text.trim();
    if (_disposed ||
        service == null ||
        !service.isInitialized ||
        trimmed.isEmpty ||
        _isChatting) {
      return;
    }

    final generation = _generation;
    final aiMessage = <String, String>{'role': 'ai', 'content': ''};
    _messages.add({'role': 'user', 'content': trimmed});
    _messages.add(aiMessage);
    _isChatting = true;
    _cancelRequested = false;
    final completer = Completer<void>();
    _sendCompleter = completer;

    var receivedChunk = false;
    var hadError = false;
    final subscription = service
        .sendMessageStream(text: trimmed)
        .listen(
          (chunk) {
            if (_disposed || generation != _generation || _cancelRequested) {
              return;
            }
            receivedChunk = true;
            aiMessage['content'] = (aiMessage['content'] ?? '') + chunk;
            notifyListeners();
          },
          onError: (Object error) {
            hadError = true;
            if (!_disposed && generation == _generation && !_cancelRequested) {
              aiMessage['content'] = 'Error: $error';
              notifyListeners();
            }
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
    if (!receivedChunk && !hadError) {
      aiMessage['content'] = 'No response from the AI provider.';
    }
    _isChatting = false;
    notifyListeners();
  }

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

  void clearChat() {
    if (_isChatting) return;
    _messages.clear();
    notifyListeners();
  }

  void _cancelActiveRequest() {
    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (subscription != null) unawaited(subscription.cancel());
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
