import 'dart:async';

import 'package:flutter/foundation.dart';

import '../macro/macro_oscope_status.dart';
import '../devices/device_agent_context.dart';
import 'ai_settings.dart';
import 'capture_command.dart';
import 'control_panel_ai_service.dart';
import 'input_history.dart';
import 'tools/macro_tools.dart';
import 'tools/vxi11_tool.dart';
import 'tools/waveform_summary_tool.dart';

/// Fetches a fresh Control Panel screen dump.
///
/// Returns a map with `success: true` or an `error` message.
typedef ScreenDumpRefreshCallback = Future<Map<String, dynamic>> Function();

/// Owns the Control Panel's AI conversation.
///
/// The controller is created by the home page and passed to the physical
/// control panel. It keeps the transcript, the open/closed state and the agent
/// alive across panel rebuilds, so collapsing and reopening the chat does not
/// lose the conversation.
///
/// The agent is configured from the same [AiSettings] as the other AI features
/// and is given the live oscilloscope status reader for its
/// `read_oscilloscope_status` tool.
class ControlPanelChatController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [serviceFactory] is primarily useful for tests; production code uses the
  /// default [ControlPanelAiService] constructor.
  ControlPanelChatController({ControlPanelAiService Function()? serviceFactory})
    : _serviceFactory = serviceFactory ?? ControlPanelAiService.new;

  final ControlPanelAiService Function() _serviceFactory;

  final List<Map<String, String>> _messages = <Map<String, String>>[];
  final InputHistory _inputHistory = InputHistory();

  ControlPanelAiService? _service;
  AiSettings? _settings;
  String? _vxi11Host;
  DeviceAgentContext? _instrumentDeviceContext;
  MacroOscilloscopeStatusReader? _readOscilloscopeStatus;
  ScpiCommandCallback? _onCommandSent;
  WaveformSummaryProvider? _readWaveformSummary;
  ScreenDumpRefreshCallback? _refreshScreenDump;

  /// Whether the agent has handled at least one request in the current
  /// session.
  ///
  /// During an ongoing dialog every user message must reach the model, even a
  /// short confirmation such as "bitte aufnehmen". Only a fresh session uses
  /// the local screen-dump shortcut; otherwise the reply would be swallowed
  /// and the dialog would end without the new screen content.
  bool _hasAgentConversation = false;

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

  /// Whether the chat can be opened: AI settings are configured and the agent
  /// was created successfully.
  bool get isAvailable => _settings?.isConfigured == true && isInitialized;

  /// The complete chat transcript. The list is owned by the controller and is
  /// only read by the chat window.
  List<Map<String, String>> get messages => _messages;

  /// Most recent user inputs, newest first.
  List<String> get inputHistory => _inputHistory.entries;

  /// Registers the live oscilloscope connection/model source used by the
  /// agent's `read_oscilloscope_status` tool.
  ///
  /// The callback is read dynamically, so it may be registered before or after
  /// [configure].
  void attachOscilloscopeStatus(MacroOscilloscopeStatusReader readStatus) {
    _readOscilloscopeStatus = readStatus;
  }

  /// Registers a listener that is called for every SCPI command the Control
  /// Panel agent sends to the instrument.
  ///
  /// The callback is read dynamically, so it may be registered before or after
  /// [configure]. The application uses it to refresh the Control Panel screen
  /// after the agent changed a setting.
  void attachCommandListener(ScpiCommandCallback onCommandSent) {
    _onCommandSent = onCommandSent;
  }

  /// Registers the source of the waveform summary used by the
  /// `read_waveform_summary` tool.
  ///
  /// The callback is read dynamically, so it may be registered before or after
  /// [configure]. It returns null when no waveform is displayed.
  void attachWaveformSummary(WaveformSummaryProvider readSummary) {
    _readWaveformSummary = readSummary;
  }

  /// Registers the source of a fresh screen dump for short capture commands
  /// such as "snapshot" or "Aufnahme".
  ///
  /// The callback is read dynamically, so it may be registered before or after
  /// [configure].
  void attachScreenDumpRefresh(ScreenDumpRefreshCallback refreshScreenDump) {
    _refreshScreenDump = refreshScreenDump;
  }

  /// Cancels an in-flight response without changing the transcript.
  ///
  /// Used when the agent is reconfigured or the controller is disposed. User
  /// initiated cancellation goes through [cancel], which also writes the
  /// termination notice into the transcript.
  void _cancelActiveRequest() {
    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (subscription != null) unawaited(subscription.cancel());
  }

  /// Creates or updates the agent for [settings] and the instrument address
  /// [vxi11Host].
  ///
  /// When neither the settings nor the address changed, the existing agent is
  /// kept, including its conversation history. Passing null or an unconfigured
  /// value closes the chat and disposes the agent; the transcript is retained
  /// so it is still there when the AI is configured again.
  void configure(
    AiSettings? settings, {
    String? vxi11Host,
    DeviceAgentContext? instrumentDeviceContext,
  }) {
    _instrumentDeviceContext = instrumentDeviceContext;
    if (_disposed) return;
    final configured = settings != null && settings.isConfigured;

    if (!configured) {
      final changed = _service != null || _isOpen || _settings != null;
      _cancelActiveRequest();
      _settings = null;
      _vxi11Host = null;
      _generation++;
      _isChatting = false;
      _isOpen = false;
      _service?.dispose();
      _service = null;
      if (changed) notifyListeners();
      return;
    }

    if (_settings == settings &&
        _vxi11Host == vxi11Host &&
        _instrumentDeviceContext == instrumentDeviceContext &&
        _service != null) {
      return;
    }

    _cancelActiveRequest();
    _settings = settings;
    _vxi11Host = vxi11Host;
    _generation++;
    _isChatting = false;
    _service?.dispose();

    final service = _serviceFactory();
    service.configure(
      apiKey: settings.apiKeyName,
      apiToken: settings.apiToken,
      model: settings.model,
      vxi11Host: vxi11Host,
      instrumentDeviceContext: _instrumentDeviceContext,
      readOscilloscopeStatus: () async {
        final reader = _readOscilloscopeStatus;
        return reader != null ? reader() : readUnavailableOscilloscopeStatus();
      },
      onCommandSent: (command, operation) {
        _onCommandSent?.call(command, operation);
      },
      readWaveformSummary: () => _readWaveformSummary?.call(),
    );
    _service = service;
    notifyListeners();
  }

  /// Opens or closes the chat overlay.
  void toggleOpen() {
    if (!isAvailable) return;
    _isOpen = !_isOpen;
    notifyListeners();
  }

  /// Sends [text] to the Control Panel agent and streams the answer into the
  /// transcript.
  Future<void> send(String text) async {
    final service = _service;
    final trimmed = text.trim();
    if (_disposed || service == null || !service.isInitialized) return;
    if (trimmed.isEmpty || _isChatting) return;

    _inputHistory.record(trimmed);

    // Short capture commands fetch a new screen dump without a model round
    // trip, so "Aufnahme", "record", "update" and "snapshot" always work in a
    // fresh session. During an ongoing dialog the same words can be the
    // user's answer to the agent's proposed next step. Intercepting that
    // reply locally would end the dialog and leave the agent without the new
    // screen content, so route it to the model instead.
    if (!_hasAgentConversation && isCaptureCommand(trimmed)) {
      await _runScreenDumpCommand(trimmed);
      return;
    }

    // From here on the session is a dialog: later user replies, including
    // short capture confirmations, belong to the model's context.
    _hasAgentConversation = true;

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

  /// Handles a short capture command without calling the AI model.
  ///
  /// The command fetches a new screen dump and reports the result in the
  /// transcript.
  Future<void> _runScreenDumpCommand(String trimmed) async {
    _messages.add(<String, String>{'role': 'user', 'content': trimmed});
    final aiMessage = <String, String>{'role': 'ai', 'content': ''};
    _messages.add(aiMessage);
    _isChatting = true;
    _cancelRequested = false;
    final generation = _generation;
    notifyListeners();

    final refresh = _refreshScreenDump;
    if (refresh == null) {
      aiMessage['content'] = 'The screen dump is not available.';
    } else {
      try {
        final result = await refresh();
        if (_disposed || generation != _generation || _cancelRequested) {
          return;
        }
        aiMessage['content'] = result['error'] != null
            ? '${result['error']}'
            : 'Screen dump updated.';
      } catch (error) {
        if (_disposed || generation != _generation || _cancelRequested) {
          return;
        }
        aiMessage['content'] = 'Failed to update the screen dump: $error';
      }
    }
    _isChatting = false;
    notifyListeners();
  }

  /// Stops the active response immediately and reports the termination in the
  /// transcript.
  ///
  /// The stream subscription is cancelled so no further chunks (and no further
  /// agent tool calls driven by the stream) are processed.
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

  /// Clears the transcript and the agent conversation history.
  ///
  /// The next request starts a fresh session without the previous turns.
  void clearSession() {
    if (_disposed) return;
    _hasAgentConversation = false;
    if (_isChatting) {
      _isChatting = false;
      _generation++;
      _cancelActiveRequest();
    }
    _messages.clear();
    _service?.clearSession();
    notifyListeners();
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
