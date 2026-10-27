import 'package:flutter/foundation.dart';

import 'ai_settings.dart';
import 'macro_ai_service.dart';
import 'tools/macro_tools.dart';

/// Owns the Macro Editor's AI conversation.
///
/// The controller is created by the parent (the home page) and passed to the
/// [MacroEditorPanel]. Because it outlives the panel, closing and reopening
/// the editor keeps the chat transcript, its open state and the agent — and
/// therefore the complete multi-turn history — intact.
///
/// The agent's tools access the editor through mutable callbacks that are
/// registered with [attachEditor]. Only the callbacks are replaced when the
/// editor is reopened; the agent itself is reused as long as the AI settings
/// do not change.
class MacroChatController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [serviceFactory] is primarily useful for tests; production code uses the
  /// default [MacroAiService] constructor.
  MacroChatController({MacroAiService Function()? serviceFactory})
    : _serviceFactory = serviceFactory ?? MacroAiService.new;

  final MacroAiService Function() _serviceFactory;

  final List<Map<String, String>> _messages = <Map<String, String>>[];

  MacroAiService? _service;
  AiSettings? _settings;

  MacroReader? _readMacro;
  MacroWriter? _writeMacro;
  String? Function()? _macroFileName;
  MacroSiggenStatusReader? _readSiggenStatus;

  bool _isOpen = false;
  bool _isChatting = false;
  bool _disposed = false;

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

  /// Registers the currently mounted editor.
  ///
  /// Called from the panel's `initState`; [detachEditor] is called when it is
  /// disposed. The callbacks are read dynamically by the agent tools, so the
  /// same agent can work on the newly opened editor after a reopen.
  void attachEditor({
    required MacroReader readMacro,
    required MacroWriter writeMacro,
    String? Function()? macroFileName,
  }) {
    _readMacro = readMacro;
    _writeMacro = writeMacro;
    _macroFileName = macroFileName;
  }

  /// Unregisters the editor. A request that is still streaming keeps updating
  /// the transcript, but tool calls that need the editor fail until the next
  /// [attachEditor].
  void detachEditor() {
    _readMacro = null;
    _writeMacro = null;
    _macroFileName = null;
  }

  /// Registers the live signal-generator settings/status source used by the
  /// agent's `read_siggen_status` tool.
  ///
  /// The callback is read dynamically, so it may be registered before or after
  /// [configure]. Without it the tool falls back to the persisted generator
  /// selection in [readStoredSiggenStatus].
  void attachSignalGeneratorStatus(MacroSiggenStatusReader readStatus) {
    _readSiggenStatus = readStatus;
  }

  /// Creates or updates the agent for [settings].
  ///
  /// When the settings are unchanged, the existing agent is kept, including
  /// its conversation history. Passing null or an unconfigured value closes
  /// the chat and disposes the agent; the transcript is retained so it is
  /// still there when the AI is configured again.
  void configure(AiSettings? settings) {
    if (_disposed) return;
    final configured = settings != null && settings.isConfigured;

    if (!configured) {
      final changed = _service != null || _isOpen || _settings != null;
      _settings = null;
      _generation++;
      _isChatting = false;
      _isOpen = false;
      _service?.dispose();
      _service = null;
      if (changed) notifyListeners();
      return;
    }

    if (_settings == settings && _service != null) {
      return;
    }

    _settings = settings;
    _generation++;
    _isChatting = false;
    _service?.dispose();

    final service = _serviceFactory();
    service.configure(
      apiKey: settings.apiKeyName,
      apiToken: settings.apiToken,
      model: settings.model,
      readMacro: () => _readMacro?.call() ?? '',
      writeMacro: (content) => _writeMacro?.call(content) ?? false,
      macroFileName: () => _macroFileName?.call(),
      readSiggenStatus: () async {
        final reader = _readSiggenStatus;
        return reader != null ? reader() : readStoredSiggenStatus();
      },
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

  /// Sends [text] to the agent and streams the answer into [messages].
  ///
  /// The stream is owned by the controller rather than the editor panel, so a
  /// response that is still being generated when the editor is closed is
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
    notifyListeners();

    var hasReceivedChunk = false;
    try {
      await for (final chunk in service.sendMessageStream(text: trimmed)) {
        if (_disposed || generation != _generation) return;
        hasReceivedChunk = true;
        aiMessage['content'] = (aiMessage['content'] ?? '') + chunk;
        notifyListeners();
      }

      if (!_disposed && generation == _generation && !hasReceivedChunk) {
        aiMessage['content'] = 'No response from AI-Server';
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        aiMessage['content'] = 'Error: Failed to connect to AI server ($e)';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _isChatting = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _service?.dispose();
    _service = null;
    super.dispose();
  }
}
