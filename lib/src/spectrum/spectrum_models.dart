import 'dart:typed_data';

import 'windows.dart';

/// Unit used for the displayed spectrum levels.
enum SpectrumUnit { dbfs, dbv, dbm50 }

/// Configuration for one spectrum computation.
class SpectrumSettings {
  /// Window function applied before the FFT.
  final SpectrumWindow window;

  /// Requested FFT size. `0` selects the largest power of two that fits the
  /// available samples (bounded by [maxFftSize]).
  final int fftSize;

  /// Upper bound for the automatic FFT size (default 1,048,576).
  final int maxFftSize;

  /// Unit used for [SpectrumTrace.levelsDb] and peak levels.
  final SpectrumUnit unit;

  /// Subtract the mean of the analysed block before windowing.
  final bool removeDc;

  /// Number of automatic peak markers.
  final int peakCount;

  /// Highest harmonic analysed for THD/SINAD (limited by Nyquist).
  final int harmonicCount;

  /// Samples skipped at the start of the acquisition to avoid the known
  /// leading transient. Ignored when it would leave fewer than 8 samples.
  final int leadingSamplesToSkip;

  const SpectrumSettings({
    this.window = SpectrumWindow.hann,
    this.fftSize = 0,
    this.maxFftSize = 1 << 20,
    this.unit = SpectrumUnit.dbfs,
    this.removeDc = true,
    this.peakCount = 5,
    this.harmonicCount = 10,
    this.leadingSamplesToSkip = 8,
  });

  SpectrumSettings copyWith({
    SpectrumWindow? window,
    int? fftSize,
    int? maxFftSize,
    SpectrumUnit? unit,
    bool? removeDc,
    int? peakCount,
    int? harmonicCount,
    int? leadingSamplesToSkip,
  }) {
    return SpectrumSettings(
      window: window ?? this.window,
      fftSize: fftSize ?? this.fftSize,
      maxFftSize: maxFftSize ?? this.maxFftSize,
      unit: unit ?? this.unit,
      removeDc: removeDc ?? this.removeDc,
      peakCount: peakCount ?? this.peakCount,
      harmonicCount: harmonicCount ?? this.harmonicCount,
      leadingSamplesToSkip: leadingSamplesToSkip ?? this.leadingSamplesToSkip,
    );
  }
}

/// Raw samples and vertical settings of one channel.
class SpectrumChannelInput {
  /// Channel label, e.g. `'ch1'`.
  final String label;

  /// Raw 8-bit samples as returned by the acquisition.
  final Uint8List raw;

  /// Volts per division used to convert the raw codes.
  final double vdiv;

  /// Vertical offset in volts used to convert the raw codes.
  final double voffset;

  const SpectrumChannelInput({
    required this.label,
    required this.raw,
    required this.vdiv,
    required this.voffset,
  });
}

/// Input of one spectrum computation. Multiple channels are computed
/// independently and returned as overlays in [SpectrumResult.traces].
class SpectrumRequest {
  final List<SpectrumChannelInput> channels;
  final double sampleRate;
  final SpectrumSettings settings;

  const SpectrumRequest({
    required this.channels,
    required this.sampleRate,
    required this.settings,
  });
}

/// One automatic peak marker.
class SpectrumPeak {
  /// 1-based marker number, 1 is the fundamental.
  final int marker;

  final double frequencyHz;

  /// Peak amplitude in volts (peak, not RMS), interpolated between bins.
  final double amplitudeVpk;

  /// Level in the unit selected in [SpectrumSettings.unit].
  final double levelDb;

  /// Level relative to full scale in dBFS.
  final double dbfs;

  /// Level relative to the fundamental in dBc (0 for the fundamental).
  final double relativeToFundamentalDb;

  final bool isFundamental;

  const SpectrumPeak({
    required this.marker,
    required this.frequencyHz,
    required this.amplitudeVpk,
    required this.levelDb,
    required this.dbfs,
    required this.relativeToFundamentalDb,
    required this.isFundamental,
  });
}

/// Distortion and noise metrics of one spectrum.
class SpectrumMetrics {
  final double fundamentalHz;
  final double fundamentalVpk;
  final double fundamentalDbfs;

  /// Total harmonic distortion in percent and dB.
  final double thdPercent;
  final double thdDb;

  /// THD + noise in dB.
  final double thdPlusNDb;

  /// Signal-to-noise ratio in dB (harmonics excluded from the noise).
  final double snrDb;

  /// Signal-to-noise-and-distortion ratio in dB.
  final double sinadDb;

  /// Effective number of bits derived from [sinadDb].
  final double enobBits;

  /// Spurious-free dynamic range in dBc.
  final double sfdrDb;

  /// Mean noise power per noise bin in dBFS.
  final double noiseFloorDbfs;

  /// Number of harmonics that fit below Nyquist.
  final int harmonicsUsed;

  final double nyquistHz;
  final double resolutionHz;

  const SpectrumMetrics({
    required this.fundamentalHz,
    required this.fundamentalVpk,
    required this.fundamentalDbfs,
    required this.thdPercent,
    required this.thdDb,
    required this.thdPlusNDb,
    required this.snrDb,
    required this.sinadDb,
    required this.enobBits,
    required this.sfdrDb,
    required this.noiseFloorDbfs,
    required this.harmonicsUsed,
    required this.nyquistHz,
    required this.resolutionHz,
  });
}

/// Spectrum of one channel.
class SpectrumTrace {
  final String channel;
  final int fftSize;
  final double sampleRate;
  final double fullScaleVolts;
  final double resolutionHz;

  final Float64List frequenciesHz;

  /// Level per bin in [SpectrumSettings.unit].
  final Float64List levelsDb;

  /// Level per bin in dBFS.
  final Float64List dbfs;

  /// Peak amplitude per bin in volts (peak).
  final Float64List amplitudesVpk;

  final List<SpectrumPeak> peaks;
  final SpectrumMetrics metrics;

  const SpectrumTrace({
    required this.channel,
    required this.fftSize,
    required this.sampleRate,
    required this.fullScaleVolts,
    required this.resolutionHz,
    required this.frequenciesHz,
    required this.levelsDb,
    required this.dbfs,
    required this.amplitudesVpk,
    required this.peaks,
    required this.metrics,
  });
}

/// Result of one computation; one trace per input channel.
class SpectrumResult {
  final List<SpectrumTrace> traces;
  final SpectrumSettings settings;

  const SpectrumResult({required this.traces, required this.settings});

  SpectrumTrace? traceFor(String channel) {
    for (final trace in traces) {
      if (trace.channel == channel) return trace;
    }
    return null;
  }
}
