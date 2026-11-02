import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:whisper_ggml/whisper_ggml.dart';

import '../core/logger.dart';

/// Thrown when the whisper.cpp model cannot be downloaded or prepared.
class WhisperException implements Exception {
  const WhisperException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads and runs the whisper.cpp model used for assistant voice input.
///
/// The model is downloaded on first use from the official whisper.cpp model
/// repository into the package's application-support directory. One whisper
/// model is kept resident between utterances (`keepModelLoaded`); the caller
/// releases it when the microphone is switched off.
class WhisperTranscriber {
  WhisperTranscriber({
    http.Client? httpClient,
    WhisperController? controller,
    this.model = WhisperModel.base,
    this.initialPrompt = defaultInitialPrompt,
    AppLogger? logger,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _controller = controller ?? WhisperController(),
       _logger = logger ?? AppLogger(agentName: 'Whisper', toolName: 'model');

  /// Multilingual model used for German and English commands.
  static const WhisperModel defaultModel = WhisperModel.base;

  /// Vocabulary hint for whisper. Instrument and assistant terms are unusual
  /// words for the generic model, so biasing the decoder towards them improves
  /// recognition.
  static const String defaultInitialPrompt =
      'SDS-Remote voice input. Control Panel, Acquire Waveform, AI, Profiles, '
      'Data Logger, Bode, Macro Recorder, Help, Settings, Save, Export Data. '
      'Channel, Trigger, Timebase, Volts per division, Autoset, Measure, '
      'Cursor. Menübefehle: Control Panel, Acquire Waveform, Profile, '
      'Datenlogger, Bode, Makro Recorder, Hilfe, Einstellungen, Speichern, '
      'Daten exportieren.';

  final WhisperModel model;
  final String initialPrompt;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final WhisperController _controller;
  final AppLogger _logger;

  Future<void>? _ensureFuture;
  bool _disposed = false;

  /// Absolute path of the downloaded ggml model file.
  Future<String> get modelPath => _controller.getPath(model);

  /// Ensures the model file exists, downloading it if necessary.
  ///
  /// [onProgress] receives values between 0 and 1 while the download runs.
  /// Concurrent calls share the same download; only the first callback is
  /// used.
  Future<void> ensureModel({void Function(double progress)? onProgress}) {
    if (_disposed) {
      throw const WhisperException('The whisper transcriber is disposed.');
    }
    return _ensureFuture ??= _ensureModel(
      onProgress: onProgress,
    ).whenComplete(() => _ensureFuture = null);
  }

  Future<void> _ensureModel({
    void Function(double progress)? onProgress,
  }) async {
    final path = await _controller.getPath(model);
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      onProgress?.call(1.0);
      return;
    }

    await file.parent.create(recursive: true);
    final temporaryFile = File('${file.path}.download');
    try {
      await _download(model.modelUri, temporaryFile, onProgress: onProgress);
      if (await file.exists()) {
        await file.delete();
      }
      await temporaryFile.rename(file.path);
      await _logger.log('Whisper model ready at ${file.path}');
    } finally {
      if (await temporaryFile.exists()) {
        try {
          await temporaryFile.delete();
        } catch (error) {
          await _logger.debug('Could not remove ${temporaryFile.path}: $error');
        }
      }
    }
  }

  /// Transcribes a 16 kHz mono WAV file and returns the trimmed text.
  ///
  /// Returns null when whisper produced no text.
  Future<String?> transcribe(
    String wavPath, {
    void Function(int percent)? onProgress,
  }) async {
    await ensureModel();
    final result = await _controller.transcribe(
      model: model,
      audioPath: wavPath,
      lang: 'auto',
      initialPrompt: initialPrompt,
      noContext: true,
      suppressNonSpeechTokens: true,
      keepModelLoaded: true,
      onProgress: onProgress,
    );
    final text = result?.transcription.text.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Releases the model parked in native memory by [transcribe].
  Future<void> releaseModel() async {
    try {
      await _controller.releaseModel();
    } catch (error) {
      await _logger.debug('Could not release the whisper model: $error');
    }
  }

  /// Releases native resources and closes the HTTP client when owned.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    unawaited(releaseModel());
  }

  Future<void> _download(
    Uri uri,
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw WhisperException(
        'Whisper model download failed (HTTP ${response.statusCode}).',
      );
    }

    final totalBytes = response.contentLength;
    final sink = destination.openWrite();
    var receivedBytes = 0;
    var lastReportedPercent = -1;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes != null && totalBytes > 0 && onProgress != null) {
          final percent = receivedBytes * 100 ~/ totalBytes;
          if (percent != lastReportedPercent) {
            lastReportedPercent = percent;
            onProgress(receivedBytes / totalBytes);
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (totalBytes != null && totalBytes > 0 && receivedBytes != totalBytes) {
      throw const WhisperException(
        'Whisper model download was interrupted. Please try again.',
      );
    }
  }
}
