/// Shared data model for the audio analysis tools.
///
/// The tools are deterministic: the caller supplies an immutable snapshot of
/// the current acquisition and the tools compute from it. No file or device
/// I/O happens in this folder.
library;

import 'dart:typed_data';

import '../../cancellation.dart';

/// One acquired channel, already converted to volts.
///
/// [samples] contain the complete usable record in volts. The caller removes
/// the known leading acquisition artifact before constructing the channel;
/// [leadingSamplesRemoved] documents how many samples were dropped.
class AudioChannelData {
  const AudioChannelData({
    required this.label,
    required this.samples,
    required this.sampleRateHz,
    required this.fullScaleVolts,
    this.verticalScaleVoltsPerDiv,
    this.verticalOffsetVolts,
    this.leadingSamplesRemoved = 0,
  });

  /// Channel label, e.g. `ch1`.
  final String label;

  /// Uniformly sampled voltage values.
  final Float64List samples;

  /// Effective sample rate of [samples] in samples per second.
  final double sampleRateHz;

  /// Peak full scale of the acquisition in volts.
  ///
  /// This is the reference for dBFS values. It is derived from the vertical
  /// scale by the provider, not guessed by the tools.
  final double fullScaleVolts;

  /// Vertical scale in volts per division, when known.
  final double? verticalScaleVoltsPerDiv;

  /// Vertical offset in volts, when known.
  final double? verticalOffsetVolts;

  /// Number of leading acquisition samples removed by the provider.
  final int leadingSamplesRemoved;

  int get sampleCount => samples.length;

  double get durationSeconds =>
      sampleRateHz > 0 ? samples.length / sampleRateHz : 0;

  double get sampleIntervalSeconds => sampleRateHz > 0 ? 1 / sampleRateHz : 0;

  bool get isUsable =>
      samples.length >= 16 && sampleRateHz > 0 && fullScaleVolts > 0;
}

/// One point of a Bode/frequency sweep.
class AudioSweepPoint {
  const AudioSweepPoint({
    required this.frequencyHz,
    this.gainDb,
    this.phaseDeg,
    this.vinRms,
    this.voutRms,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;
  final double? gainDb;
  final double? phaseDeg;
  final double? vinRms;
  final double? voutRms;
  final bool valid;
  final String? note;
}

/// Result of a Bode/frequency sweep.
class AudioSweepData {
  const AudioSweepData({
    required this.points,
    this.source = 'bode_sweep',
    this.configSummary,
  });

  final List<AudioSweepPoint> points;
  final String source;
  final String? configSummary;
}

/// Parameters for requesting a new sweep from the host application.
class AudioSweepRequest {
  const AudioSweepRequest({
    required this.startFrequencyHz,
    required this.stopFrequencyHz,
    required this.pointCount,
    this.measurePhase = false,
    this.useCurrentGeneratorSettings = false,
    this.waveform = 'sine',
    this.amplitudeVpp,
    this.offsetV,
    this.generatorChannel = 1,
    this.cancelToken,
  });

  final double startFrequencyHz;
  final double stopFrequencyHz;
  final int pointCount;
  final bool measurePhase;

  /// Whether the current generator waveform, amplitude and offset stay.
  final bool useCurrentGeneratorSettings;

  /// Generator waveform when the current settings are not kept.
  final String waveform;

  /// Generator amplitude when the current settings are not kept.
  final double? amplitudeVpp;

  /// Generator offset when the current settings are not kept.
  final double? offsetV;

  final int generatorChannel;

  /// Cancels a running sweep immediately when the chat request is cancelled.
  final CancellationToken? cancelToken;
}

/// Reports why a Bode/frequency sweep could not run or complete.
///
/// The host provider throws this exception instead of returning null so the
/// audio tools can pass the concrete cause, such as a disabled output channel
/// or a disconnected generator, to the agent and the user.
class AudioSweepException implements Exception {
  const AudioSweepException(
    this.message, {
    this.code = 'SWEEP_FAILED',
    this.hint,
  });

  /// User-facing explanation of the failure.
  final String message;

  /// Stable machine-readable error code.
  final String code;

  /// Optional next step that resolves the failure.
  final String? hint;

  @override
  String toString() => message;
}

/// Snapshot of the current acquisition for the audio tools.
class AudioAnalysisContext {
  const AudioAnalysisContext({
    required this.channels,
    this.deviceName,
    this.capturedAt,
    this.adcBits = 8,
  });

  /// Channels keyed by `ch1` … `ch4`.
  final Map<String, AudioChannelData> channels;

  final String? deviceName;
  final DateTime? capturedAt;
  final int adcBits;

  List<String> get availableChannels => [
    for (final id in const ['ch1', 'ch2', 'ch3', 'ch4'])
      if (channels[id]?.isUsable == true) id,
  ];

  /// Returns [id], or the first usable channel when [id] is null/empty.
  AudioChannelData? channel(String? id) {
    final requested = id?.trim().toLowerCase();
    if (requested == null || requested.isEmpty) {
      for (final candidate in const ['ch1', 'ch2', 'ch3', 'ch4']) {
        final data = channels[candidate];
        if (data != null && data.isUsable) return data;
      }
      return null;
    }
    final data = channels[requested];
    return data != null && data.isUsable ? data : null;
  }
}

/// Supplies the current acquisition to the audio tools.
typedef AudioAnalysisContextProvider = AudioAnalysisContext? Function();

/// Runs a Bode/frequency sweep and returns its points.
///
/// The host application implements this with the existing Bode service. The
/// provider is optional; sweep-only tools return a structured error when it is
/// not registered. When a sweep cannot start or does not complete, the
/// provider throws an [AudioSweepException] with the concrete cause.
typedef AudioSweepProvider =
    Future<AudioSweepData?> Function(AudioSweepRequest request);

/// One level measurement of a host-managed frequency series.
class AudioFrequencySeriesPoint {
  const AudioFrequencySeriesPoint({
    required this.frequencyHz,
    this.value,
    this.unit = 'Vpp',
    this.valid = true,
    this.note,
  });

  final double frequencyHz;
  final double? value;
  final String unit;
  final bool valid;
  final String? note;
}

/// Result of a host-managed frequency series.
class AudioFrequencySeriesData {
  const AudioFrequencySeriesData({
    required this.points,
    this.quantity = 'vpp',
    this.source = 'frequency_series',
    this.configSummary,
  });

  final List<AudioFrequencySeriesPoint> points;
  final String quantity;
  final String source;
  final String? configSummary;
}

/// Parameters for a host-managed level measurement at explicit frequencies.
class AudioFrequencySeriesRequest {
  const AudioFrequencySeriesRequest({
    required this.frequenciesHz,
    required this.channel,
    required this.quantity,
    this.amplitudeVpp,
    this.waveform = 'sine',
    this.useCurrentSettings = false,
    this.generatorChannel = 1,
    this.settlingMs = 1000,
    this.cancelToken,
  });

  final List<double> frequenciesHz;

  /// Scope channel label, for example `ch1`.
  final String channel;

  /// `vpp` or `vrms`.
  final String quantity;

  /// Generator amplitude when [useCurrentSettings] is false.
  final double? amplitudeVpp;

  /// Generator waveform when [useCurrentSettings] is false.
  final String waveform;

  /// Whether the current generator waveform, amplitude and offset stay.
  final bool useCurrentSettings;

  final int generatorChannel;
  final int settlingMs;
  final CancellationToken? cancelToken;
}

/// Reports why a host-managed frequency series could not run.
class AudioFrequencySeriesException implements Exception {
  const AudioFrequencySeriesException(
    this.message, {
    this.code = 'SERIES_FAILED',
    this.hint,
  });

  final String message;
  final String code;
  final String? hint;

  @override
  String toString() => message;
}

/// Runs a host-managed frequency series and returns the measured levels.
typedef AudioFrequencySeriesProvider =
    Future<AudioFrequencySeriesData?> Function(
      AudioFrequencySeriesRequest request,
    );
