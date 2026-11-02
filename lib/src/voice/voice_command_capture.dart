import 'dart:math' as math;
import 'dart:typed_data';

/// Splits a continuous 16 kHz mono PCM16 stream into spoken utterances.
///
/// The detector uses short-term RMS energy with an adaptive noise floor. It
/// keeps a short pre-roll so the first syllable is not clipped, ends an
/// utterance after [speechEndSilence], and reports inactivity after
/// [inactivityTimeout] without speech.
class VoiceCommandCapture {
  VoiceCommandCapture({
    required this.onUtterance,
    this.onInactivityTimeout,
    this.sampleRate = 16000,
    this.speechOnset = const Duration(milliseconds: 60),
    this.speechEndSilence = const Duration(milliseconds: 1000),
    this.inactivityTimeout = const Duration(seconds: 10),
    this.maxUtterance = const Duration(seconds: 15),
    this.preRoll = const Duration(milliseconds: 350),
  }) {
    _frameSamples = sampleRate * _frameDurationMs ~/ 1000;
    _frameBytes = _frameSamples * 2;
    _onsetFramesRequired = _framesFor(speechOnset);
    _silenceFramesToEnd = _framesFor(speechEndSilence);
    _preRollFramesMax = _framesFor(preRoll);
    _inactivitySamples = _samplesFor(inactivityTimeout);
    _maxUtteranceSamples = _samplesFor(maxUtterance);
    _minimumVoicedSamples = sampleRate * _minimumVoicedMs ~/ 1000;
  }

  /// Called once for every completed utterance.
  final void Function(Uint8List pcm16) onUtterance;

  /// Called when no speech was detected for [inactivityTimeout].
  ///
  /// When null, silence never ends the capture; the owner stops it explicitly.
  final void Function()? onInactivityTimeout;

  /// Sample rate of the PCM stream. The app always uses 16 kHz.
  final int sampleRate;

  /// Minimum voiced duration that starts an utterance.
  final Duration speechOnset;

  /// Silence after speech that completes an utterance.
  final Duration speechEndSilence;

  /// Silence without any speech that ends command mode.
  final Duration inactivityTimeout;

  /// Upper bound for one utterance.
  final Duration maxUtterance;

  /// Audio kept before the detected speech onset.
  final Duration preRoll;

  static const int _frameDurationMs = 20;
  static const double _initialNoiseFloor = 0.002;
  static const double _minimumSpeechRms = 0.015;
  static const double _voiceToNoiseRatio = 1.4;
  static const int _noiseWindowFrames = 50;
  static const int _minimumVoicedMs = 250;

  late final int _frameSamples;
  late final int _frameBytes;
  late final int _onsetFramesRequired;
  late final int _silenceFramesToEnd;
  late final int _preRollFramesMax;
  late final int _inactivitySamples;
  late final int _maxUtteranceSamples;
  late final int _minimumVoicedSamples;

  final List<Uint8List> _preRollFrames = [];
  final List<double> _noiseWindow = [];
  BytesBuilder _utterance = BytesBuilder(copy: false);
  Uint8List _carry = Uint8List(0);

  bool _speechActive = false;
  bool _paused = false;
  bool _closed = false;
  int _onsetFrames = 0;
  int _silenceFrames = 0;
  int _utteranceSamples = 0;
  int _voicedSamples = 0;
  int _samplesSinceSpeech = 0;

  bool get isSpeechActive => _speechActive;
  bool get isPaused => _paused;

  /// Feeds raw PCM16 bytes from the microphone stream.
  void feed(Uint8List bytes) {
    if (_closed || _paused || bytes.isEmpty) return;

    final input = Uint8List(_carry.length + bytes.length);
    input.setRange(0, _carry.length, _carry);
    input.setRange(_carry.length, input.length, bytes);

    var offset = 0;
    while (offset + _frameBytes <= input.length) {
      if (_paused || _closed) return;
      final frame = Uint8List.sublistView(input, offset, offset + _frameBytes);
      _processFrame(frame);
      offset += _frameBytes;
      if (_closed) return;
    }
    _carry = offset < input.length
        ? Uint8List.fromList(input.sublist(offset))
        : Uint8List(0);
  }

  /// Stops processing while an utterance is transcribed.
  void pause() {
    _paused = true;
    _resetSpeechState(clearPreRoll: true);
    _samplesSinceSpeech = 0;
    _carry = Uint8List(0);
  }

  /// Resumes processing and restarts the inactivity timeout.
  void resume() {
    if (_closed) return;
    _paused = false;
    _resetSpeechState(clearPreRoll: true);
    _samplesSinceSpeech = 0;
    _carry = Uint8List(0);
  }

  /// Releases the internal buffers. Further [feed] calls are ignored.
  void close() {
    _closed = true;
    _paused = false;
    _resetSpeechState(clearPreRoll: true);
    _carry = Uint8List(0);
  }

  void _processFrame(Uint8List frame) {
    final rms = _computeRms(frame);
    if (!_speechActive) {
      _updateNoiseWindow(rms);
    }
    final threshold = math.max(
      _minimumSpeechRms,
      _currentNoiseFloor() * _voiceToNoiseRatio,
    );
    final voiced = rms > threshold;

    if (!_speechActive) {
      if (voiced) {
        _samplesSinceSpeech = 0;
        _onsetFrames++;
        _appendPreRoll(frame);
        if (_onsetFrames >= _onsetFramesRequired) {
          _startSpeech();
        }
      } else {
        _onsetFrames = 0;
        _samplesSinceSpeech += _frameSamples;
        _appendPreRoll(frame);
      }

      if (onInactivityTimeout != null &&
          !_speechActive &&
          _samplesSinceSpeech >= _inactivitySamples) {
        _resetSpeechState(clearPreRoll: true);
        _samplesSinceSpeech = 0;
        onInactivityTimeout!();
      }
      return;
    }

    _utterance.add(frame);
    _utteranceSamples += _frameSamples;
    if (voiced) {
      _voicedSamples += _frameSamples;
      _silenceFrames = 0;
      _samplesSinceSpeech = 0;
    } else {
      _silenceFrames++;
      _samplesSinceSpeech += _frameSamples;
      if (_silenceFrames >= _silenceFramesToEnd) {
        _finishUtterance();
        return;
      }
    }

    if (_utteranceSamples >= _maxUtteranceSamples) {
      _finishUtterance();
    }
  }

  void _startSpeech() {
    _speechActive = true;
    _onsetFrames = 0;
    _silenceFrames = 0;
    _samplesSinceSpeech = 0;
    _utterance = BytesBuilder(copy: false);
    for (final frame in _preRollFrames) {
      _utterance.add(frame);
    }
    _utteranceSamples = _preRollFrames.length * _frameSamples;
    _voicedSamples = _onsetFramesRequired * _frameSamples;
    _preRollFrames.clear();
  }

  void _finishUtterance() {
    final hasEnoughSpeech = _voicedSamples >= _minimumVoicedSamples;
    final utterance = _utterance.takeBytes();
    _resetSpeechState(clearPreRoll: true);
    _samplesSinceSpeech = 0;
    if (hasEnoughSpeech && utterance.isNotEmpty) {
      onUtterance(utterance);
    }
  }

  void _appendPreRoll(Uint8List frame) {
    _preRollFrames.add(Uint8List.fromList(frame));
    while (_preRollFrames.length > _preRollFramesMax) {
      _preRollFrames.removeAt(0);
    }
  }

  void _resetSpeechState({required bool clearPreRoll}) {
    _speechActive = false;
    _onsetFrames = 0;
    _silenceFrames = 0;
    _utterance = BytesBuilder(copy: false);
    _utteranceSamples = 0;
    _voicedSamples = 0;
    if (clearPreRoll) {
      _preRollFrames.clear();
    }
  }

  /// Tracks the ambient level over the last second. Frames are only added
  /// while no utterance is active, so a speaker cannot raise the threshold
  /// against themselves.
  void _updateNoiseWindow(double rms) {
    _noiseWindow.add(rms);
    if (_noiseWindow.length > _noiseWindowFrames) {
      _noiseWindow.removeAt(0);
    }
  }

  /// 20th percentile of the recent non-speech frames.
  double _currentNoiseFloor() {
    if (_noiseWindow.isEmpty) return _initialNoiseFloor;
    final sorted = List<double>.from(_noiseWindow)..sort();
    final index = ((sorted.length - 1) * 0.2).round();
    return sorted[index];
  }

  double _computeRms(Uint8List frame) {
    final count = frame.length ~/ 2;
    if (count == 0) return 0;
    var sum = 0.0;
    for (var index = 0; index < count; index++) {
      var value = frame[index * 2] | (frame[index * 2 + 1] << 8);
      if (value >= 0x8000) value -= 0x10000;
      final normalized = value / 32768.0;
      sum += normalized * normalized;
    }
    return math.sqrt(sum / count);
  }

  int _framesFor(Duration duration) =>
      (duration.inMilliseconds / _frameDurationMs).ceil();

  int _samplesFor(Duration duration) =>
      sampleRate * duration.inMilliseconds ~/ 1000;
}
