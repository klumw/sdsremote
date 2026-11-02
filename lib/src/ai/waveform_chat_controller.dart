import 'dart:async';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';

import 'ai_settings.dart';
import 'capture_command.dart';
import 'input_history.dart';
import 'specification_upload.dart';
import 'tools/signal_generator_tool.dart';
import 'tools/spectrum_summary_tool.dart';
import 'tools/vxi11_tool.dart';
import 'tools/waveform_analysis_tools.dart';
import 'tools/waveform_fault_profile_tool.dart';
import 'tools/waveform_fault_tool.dart';
import 'tools/waveform_history_tool.dart';
import 'tools/waveform_summary_tool.dart';
import 'waveform_ai_service.dart';

/// Runs one waveform acquisition for the Waveform Agent.
typedef WaveformAcquisitionCallback = Future<Map<String, dynamic>> Function();

/// Owns the Waveform AI transcript, agent lifecycle and open state.
///
/// The controller only manages the conversation; the waveform and spectrum
/// data stay in the owning page and are read through the providers.
class WaveformChatController extends ChangeNotifier {
  WaveformChatController({
    WaveformAiService Function()? serviceFactory,
    SpecificationFilePicker? filePicker,
    SpecificationTextExtractor? textExtractor,
  }) : _serviceFactory = serviceFactory ?? WaveformAiService.new,
       _filePicker = filePicker ?? pickSpecificationFile,
       _textExtractor = textExtractor ?? extractSpecificationText;

  final WaveformAiService Function() _serviceFactory;
  final SpecificationFilePicker _filePicker;
  final SpecificationTextExtractor _textExtractor;
  final List<Map<String, String>> _messages = [];
  final InputHistory _inputHistory = InputHistory();

  WaveformAiService? _service;
  AiSettings? _settings;
  String? _vxi11Host;
  WaveformAcquisitionCallback? _acquireWaveform;
  VoidCallback? _clearMeasurementHistory;
  SignalGeneratorStatusProvider? _readSignalGeneratorStatus;
  SignalGeneratorApplyProvider? _applySignalGenerator;
  SignalGeneratorActionProvider? _controlSignalGenerator;

  /// Whether the current user request contains the signal-generator keyword.
  bool _signalGeneratorIntent = false;

  bool _isOpen = false;
  bool _isChatting = false;
  bool _disposed = false;
  int _generation = 0;

  Completer<UploadedSpecification?>? _specUpload;
  bool _specUploadBusy = false;
  String? _specUploadError;

  StreamSubscription<String>? _subscription;
  Completer<void>? _sendCompleter;
  bool _cancelRequested = false;

  bool get isOpen => _isOpen;
  bool get isChatting => _isChatting;
  bool get isInitialized => _service?.isInitialized ?? false;
  bool get isAvailable => _settings?.isConfigured == true && isInitialized;
  List<Map<String, String>> get messages => _messages;

  /// Most recent user inputs, newest first.
  List<String> get inputHistory => _inputHistory.entries;

  /// Whether the Waveform Agent requested a specification file upload.
  bool get isSpecificationUploadVisible => _specUpload != null;

  /// Whether the selected specification file is being read.
  bool get isSpecificationUploadBusy => _specUploadBusy;

  /// User-facing error from the last specification file selection.
  String? get specificationUploadError => _specUploadError;

  String get statusLabel {
    if (!isAvailable) return 'AI not configured';
    if (_isChatting) return 'Working…';
    return 'Ready';
  }

  void configure(
    AiSettings? settings, {
    required WaveformSummaryProvider readWaveformSummary,
    required SpectrumSummaryProvider readSpectrumSummary,
    WaveformHistoryProvider? readWaveformHistory,
    WaveformClassificationProvider? classifyWaveform,
    WaveformReferenceComparisonProvider? compareWaveformToReferences,
    WaveformFeaturesProvider? readWaveformFeatures,
    WaveformPairComparisonProvider? compareWaveforms,
    ReferenceGenerationProvider? generateReferenceWaveform,
    WaveformFaultAnalysisProvider? analyzeWaveformFaults,
    WaveformFaultProfileProvider? manageFaultProfile,
    WaveformAcquisitionCallback? acquireWaveform,
    VoidCallback? clearMeasurementHistory,
    String? vxi11Host,
    ScpiCommandCallback? onCommandSent,
    SignalGeneratorStatusProvider? readSignalGeneratorStatus,
    SignalGeneratorApplyProvider? applySignalGenerator,
    SignalGeneratorActionProvider? controlSignalGenerator,
  }) {
    if (_disposed) return;
    _acquireWaveform = acquireWaveform;
    _clearMeasurementHistory = clearMeasurementHistory;
    _readSignalGeneratorStatus = readSignalGeneratorStatus;
    _applySignalGenerator = applySignalGenerator;
    _controlSignalGenerator = controlSignalGenerator;
    final configured = settings != null && settings.isConfigured;
    if (!configured) {
      _cancelActiveRequest();
      _settings = null;
      _vxi11Host = null;
      _generation++;
      _isChatting = false;
      _service?.dispose();
      _service = null;
      notifyListeners();
      return;
    }
    if (_settings == settings && _vxi11Host == vxi11Host && _service != null) {
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
      readWaveformSummary: readWaveformSummary,
      readSpectrumSummary: readSpectrumSummary,
      readWaveformHistory: readWaveformHistory,
      classifyWaveform: classifyWaveform,
      compareWaveformToReferences: compareWaveformToReferences,
      readWaveformFeatures: readWaveformFeatures,
      compareWaveforms: compareWaveforms,
      generateReferenceWaveform: generateReferenceWaveform,
      analyzeWaveformFaults: analyzeWaveformFaults,
      manageFaultProfile: manageFaultProfile,
      requestSpecUpload: requestSpecificationUpload,
      acquireWaveform: _acquireWaveformForAi,
      vxi11Host: vxi11Host,
      onCommandSent: onCommandSent,
      readSignalGeneratorStatus: _readSignalGeneratorStatus,
      applySignalGenerator: _applySignalGenerator,
      controlSignalGenerator: _controlSignalGenerator,
      isSignalGeneratorIntentEnabled: () => _signalGeneratorIntent,
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

    // Signal generator control is only allowed when the user explicitly
    // prefixes the request with the keyword "Signalgenerator". The flag is
    // read by the signal-generator tools during this request.
    _signalGeneratorIntent = hasSignalGeneratorKeyword(trimmed);

    // Short capture commands read a fresh waveform without a model round
    // trip, so "Aufnahme", "record", "update" and "snapshot" always work.
    if (isCaptureCommand(trimmed)) {
      await _runCaptureCommand(trimmed);
      return;
    }

    _recordInput(trimmed);
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
    if (_specUpload != null) _finishSpecificationUpload(null);
    if (!receivedChunk && !hadError) {
      aiMessage['content'] = 'No response from the AI provider.';
    }
    _isChatting = false;
    notifyListeners();
  }

  /// Handles a short capture command without calling the AI model.
  ///
  /// The command reads a new waveform from the oscilloscope and reports the
  /// result in the transcript.
  Future<void> _runCaptureCommand(String trimmed) async {
    _recordInput(trimmed);
    _messages.add(<String, String>{'role': 'user', 'content': trimmed});
    final aiMessage = <String, String>{'role': 'ai', 'content': ''};
    _messages.add(aiMessage);
    _isChatting = true;
    _cancelRequested = false;
    final generation = _generation;
    notifyListeners();

    final result = await _acquireWaveformForAi();
    if (_disposed || generation != _generation || _cancelRequested) return;

    if (result['cancelled'] == true) {
      aiMessage['content'] = 'The waveform acquisition was cancelled.';
    } else if (result['error'] != null) {
      aiMessage['content'] = '${result['error']}';
    } else {
      aiMessage['content'] = 'New waveform captured.';
    }
    _isChatting = false;
    notifyListeners();
  }

  Future<void> cancel() async {
    if (_disposed || !_isChatting) return;
    _cancelRequested = true;
    _generation++;
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

  /// Records a user input in the bounded history, newest first.
  void _recordInput(String text) => _inputHistory.record(text);

  /// Clears the transcript and the agent conversation history.
  ///
  /// The next request starts a fresh session without the previous turns.
  void clearSession() {
    if (_disposed) return;
    if (_isChatting) {
      _isChatting = false;
      _generation++;
      _cancelActiveRequest();
    }
    if (_specUpload != null) _finishSpecificationUpload(null);
    _messages.clear();
    _service?.clearSession();
    _clearMeasurementHistory?.call();
    notifyListeners();
  }

  /// Runs an acquisition for the `acquire_waveform` tool.
  ///
  /// The delay is awaited here so the response timeout can be suspended while
  /// the requested wait and the acquisition are running.
  Future<Map<String, dynamic>> _acquireWaveformForAi({
    int delaySeconds = 0,
  }) async {
    final acquire = _acquireWaveform;
    if (acquire == null) {
      return {
        'error': 'Waveform acquisition is not available in this context.',
      };
    }
    final generation = _generation;
    final waiting = delaySeconds > 0;
    if (waiting) _service?.suspendResponseTimeout();
    try {
      if (waiting) {
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      }
      if (_disposed || generation != _generation || _cancelRequested) {
        return {
          'cancelled': true,
          'error': 'The delayed acquisition was cancelled before it started.',
        };
      }
      return await acquire();
    } on Object catch (error) {
      return {'error': 'The waveform acquisition failed ($error).'};
    } finally {
      if (waiting) _service?.resumeResponseTimeout();
    }
  }

  /// Requests a DUT specification upload and waits for the user.
  ///
  /// Called by the `request_specification_upload` tool. While the returned
  /// future is pending, the chat panel shows the upload control.
  Future<UploadedSpecification?> requestSpecificationUpload() {
    if (_disposed) return Future<UploadedSpecification?>.value();
    final pending = _specUpload;
    if (pending != null) return pending.future;
    final request = Completer<UploadedSpecification?>();
    _specUpload = request;
    _specUploadBusy = false;
    _specUploadError = null;
    _service?.suspendResponseTimeout();
    notifyListeners();
    return request.future;
  }

  /// Opens the file dialog and attaches the selected specification.
  Future<void> pickSpecificationFileForUpload() async {
    final request = _specUpload;
    if (_disposed || request == null || _specUploadBusy) return;

    _specUploadError = null;
    _specUploadBusy = true;
    notifyListeners();

    XFile? file;
    try {
      file = await _filePicker();
    } on Object catch (error) {
      if (_disposed || !identical(_specUpload, request)) return;
      _specUploadBusy = false;
      _specUploadError = 'The file dialog could not be opened ($error).';
      notifyListeners();
      return;
    }
    if (_disposed || !identical(_specUpload, request)) return;
    if (file == null) {
      // The dialog was closed without a selection; keep the request open.
      _specUploadBusy = false;
      notifyListeners();
      return;
    }

    try {
      final uploaded = await _textExtractor(file);
      if (_disposed || !identical(_specUpload, request)) return;
      _completeSpecificationUpload(uploaded);
    } on SpecificationUploadException catch (error) {
      if (_disposed || !identical(_specUpload, request)) return;
      _specUploadBusy = false;
      _specUploadError = error.message;
      notifyListeners();
    } on Object catch (error) {
      if (_disposed || !identical(_specUpload, request)) return;
      _specUploadBusy = false;
      _specUploadError = 'The file could not be read ($error).';
      notifyListeners();
    }
  }

  /// Cancels the pending specification upload.
  void cancelSpecificationUpload() {
    if (_disposed || _specUpload == null || _specUploadBusy) return;
    _finishSpecificationUpload(null);
  }

  void _completeSpecificationUpload(UploadedSpecification uploaded) {
    final attachment = <String, String>{
      'role': 'user',
      'content':
          'Attached specification: ${uploaded.fileName} '
          '(${uploaded.characterCount} characters).',
    };
    // Keep the streaming AI placeholder last so the chat continues to show
    // its "Thinking..." indicator while the agent analyses the specification.
    final lastIndex = _messages.length - 1;
    final keepAiLast =
        lastIndex >= 0 &&
        _messages[lastIndex]['role'] != 'user' &&
        (_messages[lastIndex]['content'] ?? '').isEmpty;
    _messages.insert(keepAiLast ? lastIndex : _messages.length, attachment);
    _finishSpecificationUpload(uploaded);
  }

  void _finishSpecificationUpload(UploadedSpecification? uploaded) {
    final request = _specUpload;
    _specUpload = null;
    _specUploadBusy = false;
    _specUploadError = null;
    _service?.resumeResponseTimeout();
    if (!_disposed) notifyListeners();
    if (request != null && !request.isCompleted) request.complete(uploaded);
  }

  void _cancelActiveRequest() {
    if (_specUpload != null) _finishSpecificationUpload(null);
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
