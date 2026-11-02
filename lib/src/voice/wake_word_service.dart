import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/logger.dart';
import 'voice_command_capture.dart';
import 'wake_word_model_manager.dart';
import 'whisper_transcriber.dart';

/// Lifecycle of the voice control pipeline as presented by the toolbar button.
enum WakeWordPhase {
  /// Detection is off. This is the state after every application start.
  off,

  /// The model is being downloaded, loaded, or the microphone is starting.
  preparing,

  /// The microphone is open and the keyword spotter listens for the wakeword.
  listening,

  /// The wakeword was detected; the microphone audio is captured for whisper.
  commandListening,

  /// A captured utterance is being transcribed or executed by the app agent.
  transcribing,
}

/// Immutable snapshot of the voice control state.
@immutable
class WakeWordStatus {
  const WakeWordStatus({
    this.phase = WakeWordPhase.off,
    this.downloadProgress,
    this.message = '',
    this.errorMessage,
    this.errorCount = 0,
    this.detectionCount = 0,
  });

  final WakeWordPhase phase;

  /// Download progress between 0 and 1 while the wakeword model is fetched.
  final double? downloadProgress;

  /// Human-readable progress text, also used for the button tooltip.
  final String message;

  /// Last fatal error, shown once by the UI when [errorCount] changes.
  final String? errorMessage;

  /// Increments for every fatal error.
  final int errorCount;

  /// Increments on every wakeword detection.
  final int detectionCount;

  bool get isOff => phase == WakeWordPhase.off;
  bool get isPreparing => phase == WakeWordPhase.preparing;
  bool get isListening => phase == WakeWordPhase.listening;
  bool get isCommandMode => phase == WakeWordPhase.commandListening;
  bool get isTranscribing => phase == WakeWordPhase.transcribing;

  /// Whether the microphone is currently used for wakeword or command input.
  bool get isActive => phase != WakeWordPhase.off;
}

/// Called with the whisper transcript of a spoken command.
typedef VoiceCommandHandler = Future<void> Function(String transcript);

/// Owns the microphone, the sherpa-onnx keyword spotter, the command capture,
/// and the whisper transcriber.
///
/// Detection deliberately starts in [WakeWordPhase.off] on every application
/// start. After the wakeword, the service records the following utterance,
/// transcribes it with whisper.cpp, and hands the text to [onCommand]. Ten
/// seconds without speech end command mode and return to wakeword detection.
class WakeWordService {
  WakeWordService({
    WakeWordModelManager? modelManager,
    AudioRecorder? recorder,
    WhisperTranscriber? whisperTranscriber,
    this.onCommand,
    AppLogger? logger,
  }) : _modelManager = modelManager ?? WakeWordModelManager(),
       _ownsModelManager = modelManager == null,
       _recorder = recorder ?? AudioRecorder(),
       _whisper = whisperTranscriber ?? WhisperTranscriber(),
       _ownsWhisper = whisperTranscriber == null,
       _logger =
           logger ?? AppLogger(agentName: 'WakeWord', toolName: 'service');

  /// Sample rate expected by the keyword spotter, the capture, and whisper.
  static const int sampleRate = 16000;

  /// Silence without speech that ends command mode.
  static const Duration commandInactivityTimeout = Duration(seconds: 10);

  final ValueNotifier<WakeWordStatus> status = ValueNotifier(
    const WakeWordStatus(),
  );

  /// Receives the whisper transcript of every spoken command.
  final VoiceCommandHandler? onCommand;

  final WakeWordModelManager _modelManager;
  final bool _ownsModelManager;
  final AudioRecorder _recorder;
  final WhisperTranscriber _whisper;
  final bool _ownsWhisper;
  final AppLogger _logger;

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSubscription;
  VoiceCommandCapture? _commandCapture;
  final _Pcm16ToFloat32Converter _pcmConverter = _Pcm16ToFloat32Converter();

  /// sherpa-onnx bindings only need to be initialized once per isolate.
  static Future<void>? _bindingsFuture;

  bool _disposed = false;
  bool _starting = false;
  bool _commandMode = false;
  bool _transcribing = false;

  /// Toggles detection on or off. Ignored while preparing or transcribing.
  Future<void> toggle() async {
    switch (status.value.phase) {
      case WakeWordPhase.off:
        await start();
      case WakeWordPhase.listening:
      case WakeWordPhase.commandListening:
        await stop();
      case WakeWordPhase.preparing:
      case WakeWordPhase.transcribing:
        break;
    }
  }

  /// Enables voice control, preparing the wakeword model first when necessary.
  Future<void> start() async {
    if (_disposed || _starting || status.value.phase != WakeWordPhase.off) {
      return;
    }
    _starting = true;
    _commandMode = false;
    _transcribing = false;
    _commandCapture?.close();
    _commandCapture = null;
    _emit(
      const WakeWordStatus(
        phase: WakeWordPhase.preparing,
        message: 'Checking wakeword model...',
      ),
    );

    try {
      final modelDirectory = await _modelManager.ensureModel(
        onProgress: (progress) {
          _emit(
            WakeWordStatus(
              phase: WakeWordPhase.preparing,
              downloadProgress: progress,
              message:
                  'Downloading wakeword model... '
                  '${(progress * 100).round()}%',
            ),
          );
        },
      );
      if (_disposed) return;

      _emit(
        const WakeWordStatus(
          phase: WakeWordPhase.preparing,
          message: 'Starting wakeword detector...',
        ),
      );
      await _ensureSpotter(modelDirectory);
      if (_disposed) {
        _stream?.free();
        _stream = null;
        _spotter?.free();
        _spotter = null;
        return;
      }

      await _startAudioCapture();
      if (_disposed) {
        await _stopAudioCapture();
        return;
      }

      _emit(
        const WakeWordStatus(
          phase: WakeWordPhase.listening,
          message: 'Listening for "Hey Assistant"...',
        ),
      );
      await _logger.log('Wakeword detection enabled');
      unawaited(_prepareWhisperModel());
    } catch (error) {
      await _stopAudioCapture();
      final message = error is WakeWordException
          ? error.message
          : 'Could not start wakeword detection: $error';
      await _logger.error(message);
      _emit(
        WakeWordStatus(
          phase: WakeWordPhase.off,
          errorMessage: message,
          errorCount: status.value.errorCount + 1,
        ),
      );
    } finally {
      _starting = false;
    }
  }

  /// Stops the microphone stream and disables voice control.
  Future<void> stop() async {
    await _endCommandMode(silent: true);
    await _stopAudioCapture();
    final spotter = _spotter;
    final stream = _stream;
    if (spotter != null && stream != null) {
      try {
        spotter.reset(stream);
      } catch (error) {
        await _logger.debug('Could not reset the wakeword stream: $error');
      }
    }
    unawaited(_whisper.releaseModel());
    _emit(
      const WakeWordStatus(
        phase: WakeWordPhase.off,
        message: 'Wakeword detection disabled',
      ),
    );
    await _logger.log('Wakeword detection disabled');
  }

  /// Releases the microphone, the spotter, and the model resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _commandMode = false;
    _transcribing = false;
    _commandCapture?.close();
    _commandCapture = null;
    await _stopAudioCapture();
    _stream?.free();
    _stream = null;
    _spotter?.free();
    _spotter = null;
    await _recorder.dispose();
    if (_ownsWhisper) {
      _whisper.dispose();
    }
    if (_ownsModelManager) {
      _modelManager.dispose();
    }
    status.dispose();
  }

  Future<void> _prepareWhisperModel() async {
    try {
      await _whisper.ensureModel(
        onProgress: (progress) {
          if (_disposed || !status.value.isListening) return;
          _emit(
            WakeWordStatus(
              phase: WakeWordPhase.listening,
              message:
                  'Listening for "Hey Assistant"... '
                  '(Whisper model ${(progress * 100).round()}%)',
            ),
          );
        },
      );
      if (_disposed || !status.value.isListening) return;
      _emit(
        const WakeWordStatus(
          phase: WakeWordPhase.listening,
          message: 'Listening for "Hey Assistant"...',
        ),
      );
      await _logger.log('Whisper model ready for voice commands');
    } catch (error) {
      await _logger.warning('Whisper model download failed: $error');
      if (!_disposed && status.value.isListening) {
        _emit(
          const WakeWordStatus(
            phase: WakeWordPhase.listening,
            message: 'Listening for "Hey Assistant"...',
          ),
        );
      }
    }
  }

  void _onDetection(String keyword) {
    if (_commandMode || _disposed) return;
    _commandMode = true;
    _commandCapture?.close();
    _commandCapture = VoiceCommandCapture(
      onUtterance: _onUtterance,
      onInactivityTimeout: _onCommandInactivityTimeout,
      sampleRate: sampleRate,
      inactivityTimeout: commandInactivityTimeout,
    );

    final current = status.value;
    _emit(
      WakeWordStatus(
        phase: WakeWordPhase.commandListening,
        message: 'Listening for command...',
        detectionCount: current.detectionCount + 1,
      ),
    );

    final spotter = _spotter;
    final stream = _stream;
    if (spotter != null && stream != null) {
      try {
        spotter.reset(stream);
      } catch (error) {
        unawaited(_logger.debug('Could not reset the wakeword stream: $error'));
      }
    }
    unawaited(
      _logger.log('Wakeword detected: $keyword; listening for command'),
    );
  }

  void _onUtterance(Uint8List pcm16) {
    if (_disposed || !_commandMode || _transcribing) return;
    unawaited(_transcribeUtterance(pcm16));
  }

  Future<void> _transcribeUtterance(Uint8List pcm16) async {
    _transcribing = true;
    _commandCapture?.pause();
    _emit(
      const WakeWordStatus(
        phase: WakeWordPhase.transcribing,
        message: 'Recognizing command...',
      ),
    );

    File? wavFile;
    String? notice;
    try {
      wavFile = await _writeWavFile(pcm16);
      final text = await _whisper.transcribe(
        wavFile.path,
        onProgress: (percent) {
          if (_disposed || !_transcribing) return;
          _emit(
            WakeWordStatus(
              phase: WakeWordPhase.transcribing,
              message: 'Transcribing command... $percent%',
            ),
          );
        },
      );
      if (_disposed) return;

      final transcript = text?.trim() ?? '';
      if (transcript.isEmpty) {
        notice = 'No speech recognized.';
        await _logger.log('Voice command: no speech recognized');
      } else {
        await _logger.log('Voice command transcript: "$transcript"');
        _emit(
          WakeWordStatus(
            phase: WakeWordPhase.transcribing,
            message: 'Command: $transcript',
          ),
        );
        final handler = onCommand;
        if (handler != null) {
          await handler(transcript);
        }
      }
    } catch (error) {
      notice = 'Command failed: $error';
      await _logger.error('Voice command failed: $error');
    } finally {
      if (wavFile != null) {
        await _deleteWavFiles(wavFile);
      }
      _transcribing = false;
      if (!_disposed && _commandMode) {
        _commandCapture?.resume();
        _emit(
          WakeWordStatus(
            phase: WakeWordPhase.commandListening,
            message: notice ?? 'Listening for command...',
          ),
        );
      }
    }
  }

  void _onCommandInactivityTimeout() {
    if (_disposed || !_commandMode || _transcribing) return;
    unawaited(_endCommandMode());
  }

  Future<void> _endCommandMode({bool silent = false}) async {
    final wasCommandMode = _commandMode;
    _commandMode = false;
    _transcribing = false;
    final capture = _commandCapture;
    _commandCapture = null;
    capture?.close();
    if (!wasCommandMode) return;

    final spotter = _spotter;
    final stream = _stream;
    if (spotter != null && stream != null) {
      try {
        spotter.reset(stream);
      } catch (error) {
        await _logger.debug('Could not reset the wakeword stream: $error');
      }
    }
    if (silent) return;

    _emit(
      const WakeWordStatus(
        phase: WakeWordPhase.listening,
        message: 'Listening for "Hey Assistant"...',
      ),
    );
    await _logger.log(
      'Voice command mode ended after '
      '${commandInactivityTimeout.inSeconds} s of silence',
    );
  }

  Future<void> _ensureSpotter(Directory modelDirectory) async {
    if (_spotter != null) return;

    _bindingsFuture ??= sherpa.initBindingsAsync();
    try {
      await _bindingsFuture;
    } catch (_) {
      // Allow a later retry to initialize the native bindings again.
      _bindingsFuture = null;
      rethrow;
    }

    String pathOf(String name) =>
        '${modelDirectory.path}${Platform.pathSeparator}$name';

    final config = sherpa.KeywordSpotterConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: pathOf(WakeWordModelManager.encoderFileName),
          decoder: pathOf(WakeWordModelManager.decoderFileName),
          joiner: pathOf(WakeWordModelManager.joinerFileName),
        ),
        tokens: pathOf(WakeWordModelManager.tokensFileName),
        numThreads: 1,
        provider: 'cpu',
        debug: false,
      ),
      keywordsFile: pathOf(WakeWordModelManager.keywordsFileName),
    );

    _spotter = sherpa.KeywordSpotter(config);
    _stream = _spotter!.createStream();
    await _logger.log('Wakeword spotter initialized');
  }

  Future<void> _startAudioCapture() async {
    if (!await _recorder.hasPermission()) {
      throw const WakeWordException(
        'Microphone access was denied. Allow audio input for SDS-Remote and '
        'try again.',
      );
    }

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _pcmConverter.reset();
    _audioSubscription = audioStream.listen(
      _processAudio,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_failCapture('Microphone stream failed: $error'));
      },
      onDone: () {
        unawaited(_failCapture('The microphone stream ended unexpectedly.'));
      },
      cancelOnError: false,
    );
  }

  Future<void> _stopAudioCapture() async {
    final subscription = _audioSubscription;
    _audioSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (error) {
      await _logger.debug('Could not stop the microphone stream: $error');
    }
  }

  void _processAudio(Uint8List bytes) {
    if (_commandMode) {
      _commandCapture?.feed(bytes);
      return;
    }

    final spotter = _spotter;
    final stream = _stream;
    if (spotter == null || stream == null) return;

    try {
      final samples = _pcmConverter.convert(bytes);
      if (samples.isEmpty) return;

      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      while (spotter.isReady(stream)) {
        spotter.decode(stream);
        final result = spotter.getResult(stream);
        if (result.keyword.isNotEmpty) {
          // The rest of this chunk belongs to the wakeword utterance. Switch
          // to command capture and discard it so it is not transcribed.
          _onDetection(result.keyword);
          return;
        }
      }
    } catch (error) {
      unawaited(_failCapture('Wakeword processing failed: $error'));
    }
  }

  Future<void> _failCapture(String message) async {
    if (_disposed) return;
    _commandMode = false;
    _transcribing = false;
    _commandCapture?.close();
    _commandCapture = null;
    await _stopAudioCapture();
    if (_disposed) return;
    unawaited(_whisper.releaseModel());
    await _logger.error(message);
    _emit(
      WakeWordStatus(
        phase: WakeWordPhase.off,
        message: 'Wakeword detection disabled',
        errorMessage: message,
        errorCount: status.value.errorCount + 1,
      ),
    );
  }

  void _emit(WakeWordStatus value) {
    if (_disposed) return;
    // Error and detection counters are monotonic for the lifetime of the
    // service, so the UI can reliably react to increases even when a status
    // transition (for example off -> preparing) omits them.
    final current = status.value;
    status.value = WakeWordStatus(
      phase: value.phase,
      downloadProgress: value.downloadProgress,
      message: value.message,
      errorMessage: value.errorMessage,
      errorCount: value.errorCount > current.errorCount
          ? value.errorCount
          : current.errorCount,
      detectionCount: value.detectionCount > current.detectionCount
          ? value.detectionCount
          : current.detectionCount,
    );
  }

  Future<File> _writeWavFile(Uint8List pcm16) async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}sds'
      '${Platform.pathSeparator}voice',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'command_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final builder = BytesBuilder(copy: false)
      ..add(_wavHeader(pcm16.length))
      ..add(pcm16);
    await file.writeAsBytes(builder.takeBytes(), flush: true);
    return file;
  }

  Future<void> _deleteWavFiles(File file) async {
    for (final path in [file.path, '${file.path}.wav']) {
      try {
        final candidate = File(path);
        if (await candidate.exists()) {
          await candidate.delete();
        }
      } catch (error) {
        await _logger.debug('Could not remove $path: $error');
      }
    }
  }

  Uint8List _wavHeader(int dataLength) {
    final header = ByteData(44);
    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return header.buffer.asUint8List();
  }
}

/// Converts little-endian 16-bit PCM chunks to normalized float samples.
///
/// Microphone chunks can split a sample across two callbacks, so one trailing
/// byte is carried over to the next chunk.
class _Pcm16ToFloat32Converter {
  Uint8List _carry = Uint8List(0);

  void reset() {
    _carry = Uint8List(0);
  }

  Float32List convert(Uint8List bytes) {
    final input = Uint8List(_carry.length + bytes.length);
    input.setRange(0, _carry.length, _carry);
    input.setRange(_carry.length, input.length, bytes);

    final sampleCount = input.length ~/ 2;
    final samples = Float32List(sampleCount);
    for (var index = 0; index < sampleCount; index++) {
      var value = input[index * 2] | (input[index * 2 + 1] << 8);
      if (value >= 0x8000) value -= 0x10000;
      samples[index] = value / 32768.0;
    }

    _carry = input.length.isOdd
        ? Uint8List.fromList([input.last])
        : Uint8List(0);
    return samples;
  }
}
