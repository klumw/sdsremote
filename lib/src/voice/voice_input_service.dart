import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../core/logger.dart';
import 'voice_command_capture.dart';
import 'whisper_transcriber.dart';

/// Lifecycle of the microphone that an AI assistant activates.
enum VoiceInputPhase {
  /// The microphone is off. This is the state whenever an assistant opens.
  off,

  /// The whisper model is being loaded or the microphone is starting.
  preparing,

  /// The microphone is open and waits for a spoken utterance.
  listening,

  /// A captured utterance is being transcribed by whisper.cpp.
  transcribing,

  /// The transcript was handed to the assistant, which is answering.
  responding,
}

/// Immutable snapshot of the assistant microphone state.
@immutable
class VoiceInputStatus {
  const VoiceInputStatus({
    this.phase = VoiceInputPhase.off,
    this.ownerId,
    this.downloadProgress,
    this.message = '',
    this.errorMessage,
    this.errorCount = 0,
  });

  final VoiceInputPhase phase;

  /// Assistant that currently owns the microphone, for example
  /// `control_panel_ai` or `waveform_ai`.
  final String? ownerId;

  /// Download progress between 0 and 1 while the whisper model is fetched.
  final double? downloadProgress;

  /// Human-readable progress text, also used for the microphone tooltip.
  final String message;

  /// Last fatal error, shown once by the UI when [errorCount] changes.
  final String? errorMessage;

  /// Increments for every fatal error.
  final int errorCount;

  bool get isOff => phase == VoiceInputPhase.off;
  bool get isPreparing => phase == VoiceInputPhase.preparing;
  bool get isListening => phase == VoiceInputPhase.listening;
  bool get isTranscribing => phase == VoiceInputPhase.transcribing;
  bool get isResponding => phase == VoiceInputPhase.responding;

  /// Whether the microphone is on in any state.
  bool get isActive => phase != VoiceInputPhase.off;

  /// Whether [owner] currently owns the microphone session.
  bool isActiveFor(String owner) => isActive && ownerId == owner;
}

/// Thrown when the assistant microphone cannot be started.
class VoiceInputException implements Exception {
  const VoiceInputException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns the microphone and the whisper transcriber for the AI assistants.
///
/// A session is always owned by exactly one assistant. [start] opens the
/// microphone and listens until [stop] is called; each detected utterance is
/// transcribed locally with whisper.cpp and handed to the session's
/// `onTranscript` callback. While the assistant produces its answer the
/// capture is paused, and listening resumes automatically afterwards.
class VoiceInputService {
  VoiceInputService({
    AudioRecorder? recorder,
    WhisperTranscriber? whisperTranscriber,
    AppLogger? logger,
  }) : _recorder = recorder ?? AudioRecorder(),
       _whisper = whisperTranscriber ?? WhisperTranscriber(),
       _ownsWhisper = whisperTranscriber == null,
       _logger =
           logger ?? AppLogger(agentName: 'VoiceInput', toolName: 'service');

  /// Sample rate expected by the capture and by whisper.
  static const int sampleRate = 16000;

  final ValueNotifier<VoiceInputStatus> status = ValueNotifier(
    const VoiceInputStatus(),
  );

  final AudioRecorder _recorder;
  final WhisperTranscriber _whisper;
  final bool _ownsWhisper;
  final AppLogger _logger;

  StreamSubscription<Uint8List>? _audioSubscription;
  VoiceCommandCapture? _capture;
  String? _ownerId;
  Future<void> Function(String transcript)? _onTranscript;

  bool _disposed = false;
  bool _starting = false;
  bool _transcribing = false;

  /// Set when the whisper model should be released after the running
  /// transcription finishes, because releasing it earlier would free native
  /// state that whisper.cpp is still using.
  bool _releaseWhenIdle = false;

  /// Invalidates callbacks from a previous start/stop cycle.
  int _session = 0;

  /// Starts the microphone for [ownerId] and sends every transcript to
  /// [onTranscript].
  ///
  /// Starting a session for another assistant stops the previous one first.
  Future<void> start({
    required String ownerId,
    required Future<void> Function(String transcript) onTranscript,
  }) async {
    if (_disposed || _starting) return;
    if (status.value.isActiveFor(ownerId)) return;
    if (status.value.isActive) {
      await stop();
    }
    if (_disposed) return;

    _starting = true;
    final session = ++_session;
    _ownerId = ownerId;
    _onTranscript = onTranscript;
    _emit(
      VoiceInputStatus(
        phase: VoiceInputPhase.preparing,
        ownerId: ownerId,
        message: 'Preparing speech recognition...',
      ),
    );

    try {
      await _whisper.ensureModel(
        onProgress: (progress) {
          if (_disposed || session != _session) return;
          _emit(
            VoiceInputStatus(
              phase: VoiceInputPhase.preparing,
              ownerId: ownerId,
              downloadProgress: progress,
              message:
                  'Downloading speech model... '
                  '${(progress * 100).round()}%',
            ),
          );
        },
      );
      if (_disposed || session != _session) return;

      _emit(
        VoiceInputStatus(
          phase: VoiceInputPhase.preparing,
          ownerId: ownerId,
          message: 'Starting microphone...',
        ),
      );
      await _startAudioCapture(session);
      if (_disposed || session != _session) {
        await _stopAudioCapture();
        return;
      }

      _capture = VoiceCommandCapture(
        onUtterance: _onUtterance,
        sampleRate: sampleRate,
      );
      _emit(
        VoiceInputStatus(
          phase: VoiceInputPhase.listening,
          ownerId: ownerId,
          message: 'Listening...',
        ),
      );
      await _logger.log('Assistant microphone enabled for $ownerId');
    } catch (error) {
      await _stopAudioCapture();
      _capture?.close();
      _capture = null;
      _ownerId = null;
      _onTranscript = null;
      final message = error is VoiceInputException
          ? error.message
          : 'Could not start the microphone: $error';
      await _logger.error(message);
      _emit(
        VoiceInputStatus(
          phase: VoiceInputPhase.off,
          errorMessage: message,
          errorCount: status.value.errorCount + 1,
        ),
      );
    } finally {
      _starting = false;
    }
  }

  /// Stops the microphone.
  ///
  /// When [ownerId] is given, the session is only stopped if that assistant
  /// still owns it, so a closing panel cannot stop a newer session.
  Future<void> stop({String? ownerId}) async {
    if (_disposed) return;
    if (ownerId != null && _ownerId != ownerId) return;
    if (!status.value.isActive) return;

    _session++;
    _ownerId = null;
    _onTranscript = null;
    _capture?.close();
    _capture = null;
    await _stopAudioCapture();
    _releaseWhisperWhenIdle();
    _emit(
      const VoiceInputStatus(
        phase: VoiceInputPhase.off,
        message: 'Microphone off',
      ),
    );
    await _logger.log('Assistant microphone disabled');
  }

  /// Releases the microphone and the whisper model.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _session++;
    _ownerId = null;
    _onTranscript = null;
    _capture?.close();
    _capture = null;
    await _stopAudioCapture();
    await _recorder.dispose();
    if (_ownsWhisper) {
      _whisper.dispose();
    }
    status.dispose();
  }

  Future<void> _startAudioCapture(int session) async {
    if (!await _recorder.hasPermission()) {
      throw const VoiceInputException(
        'Microphone access was denied. Allow audio input for SDS-Remote and '
        'try again.',
      );
    }
    if (_disposed || session != _session) return;

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
    _audioSubscription = audioStream.listen(
      (bytes) {
        if (_disposed || session != _session) return;
        _capture?.feed(bytes);
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail('Microphone stream failed: $error'));
      },
      onDone: () {
        unawaited(_fail('The microphone stream ended unexpectedly.'));
      },
      cancelOnError: false,
    );
    if (_disposed || session != _session) {
      await _stopAudioCapture();
    }
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

  void _onUtterance(Uint8List pcm16) {
    if (_disposed || status.value.phase != VoiceInputPhase.listening) return;
    unawaited(_handleUtterance(pcm16));
  }

  Future<void> _handleUtterance(Uint8List pcm16) async {
    final session = _session;
    final owner = _ownerId;
    _transcribing = true;
    _capture?.pause();
    _emit(
      VoiceInputStatus(
        phase: VoiceInputPhase.transcribing,
        ownerId: owner,
        message: 'Recognizing speech...',
      ),
    );

    File? wavFile;
    String? notice;
    try {
      wavFile = await _writeWavFile(pcm16);
      final text = await _whisper.transcribe(
        wavFile.path,
        onProgress: (percent) {
          if (_disposed || session != _session) return;
          _emit(
            VoiceInputStatus(
              phase: VoiceInputPhase.transcribing,
              ownerId: owner,
              message: 'Transcribing speech... $percent%',
            ),
          );
        },
      );
      if (_disposed || session != _session) return;

      final transcript = text?.trim() ?? '';
      if (transcript.isEmpty) {
        notice = 'No speech recognized.';
        await _logger.log('Assistant voice input: no speech recognized');
      } else {
        await _logger.log(
          'Assistant voice transcript for $owner: "$transcript"',
        );
        _emit(
          VoiceInputStatus(
            phase: VoiceInputPhase.responding,
            ownerId: owner,
            message: 'Assistant is answering...',
          ),
        );
        final handler = _onTranscript;
        if (handler != null) {
          await handler(transcript);
        }
      }
    } catch (error) {
      notice = 'Voice input failed: $error';
      await _logger.error('Voice input failed: $error');
    } finally {
      _transcribing = false;
      if (wavFile != null) {
        await _deleteWavFiles(wavFile);
      }
      if (_releaseWhenIdle) {
        _releaseWhenIdle = false;
        unawaited(_whisper.releaseModel());
      }
      if (!_disposed && session == _session && status.value.isActive) {
        _capture?.resume();
        _emit(
          VoiceInputStatus(
            phase: VoiceInputPhase.listening,
            ownerId: _ownerId,
            message: notice ?? 'Listening...',
          ),
        );
      }
    }
  }

  Future<void> _fail(String message) async {
    if (_disposed) return;
    _session++;
    _ownerId = null;
    _onTranscript = null;
    _capture?.close();
    _capture = null;
    await _stopAudioCapture();
    _releaseWhisperWhenIdle();
    await _logger.error(message);
    _emit(
      VoiceInputStatus(
        phase: VoiceInputPhase.off,
        message: 'Microphone off',
        errorMessage: message,
        errorCount: status.value.errorCount + 1,
      ),
    );
  }

  /// Releases the whisper model, or defers the release until the running
  /// transcription finished.
  void _releaseWhisperWhenIdle() {
    if (!_ownsWhisper) return;
    if (_transcribing) {
      _releaseWhenIdle = true;
      return;
    }
    unawaited(_whisper.releaseModel());
  }

  void _emit(VoiceInputStatus value) {
    if (_disposed) return;
    // The error counter is monotonic for the lifetime of the service, so the
    // UI can reliably react to increases even when a status transition (for
    // example listening -> off) omits it.
    final current = status.value;
    status.value = VoiceInputStatus(
      phase: value.phase,
      ownerId: value.ownerId,
      downloadProgress: value.downloadProgress,
      message: value.message,
      errorMessage: value.errorMessage,
      errorCount: value.errorCount > current.errorCount
          ? value.errorCount
          : current.errorCount,
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
