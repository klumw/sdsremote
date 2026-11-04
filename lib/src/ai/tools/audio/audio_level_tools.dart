/// Level and amplitude tools for the audio analysis agent.
///
/// The tools are deterministic wrappers around [computeAudioTimeStats],
/// [computeAudioSpectrum] and the clipping detector. They do not change the
/// instrument or the acquisition.
library;

import 'dart:math' as math;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'audio_analysis_context.dart';
import 'audio_spectrum.dart';
import 'audio_time_domain.dart';
import 'audio_tool_support.dart';

/// Creates the level/amplitude tool group (A).
List<Tool<Map<String, dynamic>>> createAudioLevelTools({
  AudioAnalysisContextProvider? context,
  String agentName = 'unknown',
}) {
  return [
    _measureAudioLevel(context, agentName),
    _detectClipping(context, agentName),
    _measureDcOffset(context, agentName),
    _measureFrequency(context, agentName),
    _measureNoiseFloor(context, agentName),
    _measureSnr(context, agentName),
    _measureCrestFactor(context, agentName),
    _measureChannelBalance(context, agentName),
  ];
}

Tool<Map<String, dynamic>> _measureAudioLevel(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_audio_level',
    agentName: agentName,
    description:
        'Measures the audio level of one acquired channel from the complete '
        'record: RMS, AC RMS, peak, peak-to-peak, mean/DC offset, crest '
        'factor and levels in dBFS, dBV and dBu. dBFS uses the peak full '
        'scale, so a full-scale sine reads about -3.01 dBFS RMS. Use it for '
        'level, gain-staging and headroom questions.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final stats = computeAudioTimeStats(channel);
      final fullScale = channel.fullScaleVolts;
      return {
        'channel': channel.label,
        'sampleCount': stats.sampleCount,
        'durationSeconds': stats.durationSeconds,
        'sampleRateHz': stats.sampleRateHz,
        'fullScaleVolts': fullScale,
        'rmsVolts': stats.rmsVolts,
        'acRmsVolts': stats.acRmsVolts,
        'peakVolts': stats.peakVolts,
        'peakToPeakVolts': stats.peakToPeakVolts,
        'meanVolts': stats.meanVolts,
        'dcOffsetVolts': stats.dcOffsetVolts,
        'crestFactor': stats.crestFactor,
        'crestFactorDb': stats.crestFactorDb,
        'dbfsPeak': dbfsFromAmplitude(stats.peakVolts, fullScale),
        'dbfsRms': dbfsFromAmplitude(stats.rmsVolts, fullScale),
        'dbvRms': dbRatio(stats.rmsVolts),
        'dbuRms': dbRatio(stats.rmsVolts / 0.775),
        'dbfsReference': 'peak full scale; a full-scale sine is -3.01 dBFS RMS',
        'method': 'time_domain_full_record',
        'warnings': stats.rmsVolts <= 0
            ? ['the record has zero RMS']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectClipping(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_clipping',
    agentName: agentName,
    description:
        'Detects clipping in one acquired channel. It reports flat-top '
        'clipping at the signal maximum/minimum using the application\'s '
        'feature-extractor heuristic, and separately counts ADC rail '
        'clipping near full scale. Returns the clipping ratio, upper/lower '
        'ratios, region count and event times. The flat-top result is a '
        'heuristic and is only conclusive when the actual clipping level is '
        'known; pass fundamentalHz when it is available.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to inspect. Omit it to use the first acquired channel.',
      ),
      'adcThresholdRatio': audioNumberProperty(
        'Fraction of full scale at which an ADC sample counts as clipped.',
        minimum: 0.5,
        maximum: 1.0,
      ),
      'fundamentalHz': audioNumberProperty(
        'Known or measured fundamental frequency; improves the flat-top '
        'heuristic.',
        minimum: 0.001,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final spectrum = computeAudioSpectrum(channel);
      final measuredFundamental = spectrum?.metrics.fundamentalHz;
      final fundamental =
          audioNumberArg(args, 'fundamentalHz') ??
          (measuredFundamental != null && measuredFundamental.isFinite
              ? measuredFundamental
              : null);
      final threshold = (audioDoubleOr(
        args,
        'adcThresholdRatio',
        0.99,
      )).clamp(0.5, 1.0).toDouble();
      final result = detectAudioClipping(
        channel,
        fundamentalHz: fundamental,
        adcThresholdRatio: threshold,
      );
      return {
        'channel': channel.label,
        'clippingDetected': result.clippingDetected,
        'clippingRatio': result.clippingRatio,
        'upperClippingRatio': result.upperClippingRatio,
        'lowerClippingRatio': result.lowerClippingRatio,
        'regionCount': result.regionCount,
        'adcClippingRatio': result.adcClippingRatio,
        'adcRegionCount': result.adcRegionCount,
        'regions': [
          for (final region in result.regions)
            {
              'type': region.type,
              'startSeconds': region.startSeconds,
              'endSeconds': region.endSeconds,
              'levelVolts': region.levelVolts,
              'sampleCount': region.sampleCount,
            },
        ],
        'fundamentalHz': fundamental,
        'adcThresholdRatio': threshold,
        'method': result.method,
        'warnings': result.warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureDcOffset(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_dc_offset',
    agentName: agentName,
    description:
        'Measures the DC offset (mean value) of one acquired channel, '
        'including the offset as a percentage of full scale and in dBFS. '
        'Also returns minimum, maximum and RMS for context. Use it before '
        'AC coupling or when a waveform looks vertically shifted.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final stats = computeAudioTimeStats(channel);
      final fullScale = channel.fullScaleVolts;
      return {
        'channel': channel.label,
        'dcOffsetVolts': stats.meanVolts,
        'dcOffsetPercentOfFullScale': fullScale > 0
            ? stats.meanVolts / fullScale * 100
            : null,
        'dcOffsetDbfs': dbfsFromAmplitude(stats.meanVolts.abs(), fullScale),
        'minVolts': stats.minVolts,
        'maxVolts': stats.maxVolts,
        'rmsVolts': stats.rmsVolts,
        'sampleCount': stats.sampleCount,
        'method': 'time_domain_full_record',
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureFrequency(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_frequency',
    agentName: agentName,
    description:
        'Measures the fundamental frequency of one acquired channel from '
        'the FFT peak and cross-checks it with a normalized autocorrelation. '
        'Returns the period, FFT resolution, fundamental amplitude/level and '
        'a warning when the two methods disagree by more than 2 %. Use it '
        'for tone, pitch or period questions.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final spectrum = computeAudioSpectrum(
        channel,
        requestedFftSize: audioIntOr(args, 'fftSize', 0),
      );
      final fftFrequency = spectrum?.metrics.fundamentalHz;
      final fftHz = fftFrequency != null && fftFrequency.isFinite
          ? fftFrequency
          : null;
      final autocorrelation = autocorrelationFundamentalHz(channel);
      final frequency = fftHz ?? autocorrelation;
      if (frequency == null || frequency <= 0) {
        return {
          'channel': channel.label,
          'error':
              'No periodic fundamental was detected. The signal may be '
              'noise, a transient or a non-periodic waveform.',
        };
      }
      final warnings = <String>[];
      if (fftHz != null &&
          autocorrelation != null &&
          (fftHz - autocorrelation).abs() / fftHz > 0.02) {
        warnings.add(
          'FFT and autocorrelation frequencies differ by more than 2 %; the '
          'signal may contain multiple tones or a strong subharmonic.',
        );
      }
      return {
        'channel': channel.label,
        'frequencyHz': frequency,
        'periodSeconds': 1 / frequency,
        'method': fftHz != null ? 'fft_peak' : 'autocorrelation',
        'autocorrelationHz': autocorrelation,
        'fftResolutionHz': spectrum?.resolutionHz,
        'fundamentalVpk': spectrum?.metrics.fundamentalVpk,
        'fundamentalDbfs': spectrum?.metrics.fundamentalDbfs,
        'fftSize': spectrum?.fftSize,
        'sampleRateHz': channel.sampleRateHz,
        'warnings': warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureNoiseFloor(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_noise_floor',
    agentName: agentName,
    description:
        'Measures the FFT noise floor of one acquired channel. Returns the '
        'mean noise power per bin in dBFS, the equivalent noise amplitude '
        'per bin and per root-hertz, the FFT size, resolution and full '
        'scale. The value is a per-bin FFT noise floor, not an integrated '
        'noise measurement; say so when quoting it.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final spectrum = computeAudioSpectrum(
        channel,
        requestedFftSize: audioIntOr(args, 'fftSize', 0),
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final noiseDbfs = spectrum.metrics.noiseFloorDbfs;
      final amplitudePerBin = noiseDbfs.isFinite
          ? spectrum.fullScaleVolts * math.pow(10, noiseDbfs / 20).toDouble()
          : null;
      return {
        'channel': channel.label,
        'noiseFloorDbfs': noiseDbfs.isFinite ? noiseDbfs : null,
        'noiseFloorVoltsPerBin': amplitudePerBin,
        'noiseFloorVoltsPerSqrtHz': amplitudePerBin != null
            ? amplitudePerBin / math.sqrt(spectrum.resolutionHz)
            : null,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'fullScaleVolts': spectrum.fullScaleVolts,
        'method': 'fft_mean_noise_power_per_bin',
        'warnings': noiseDbfs <= audioMinDb
            ? ['no noise power above the numeric floor']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureSnr(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_snr',
    agentName: agentName,
    description:
        'Measures the signal-to-noise ratio of one acquired channel from '
        'the FFT metrics. Returns SNR in dB, the fundamental RMS, the '
        'derived noise RMS, the fundamental level and the noise floor. '
        'Harmonics are excluded from the noise term, matching the '
        'application\'s SNR definition.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final spectrum = computeAudioSpectrum(
        channel,
        requestedFftSize: audioIntOr(args, 'fftSize', 0),
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final snr = spectrum.metrics.snrDb;
      final signalRms = rmsFromPeak(spectrum.metrics.fundamentalVpk);
      final noiseRms = snr.isFinite && signalRms > 0
          ? signalRms / math.pow(10, snr / 20).toDouble()
          : null;
      return {
        'channel': channel.label,
        'snrDb': snr.isFinite ? snr : null,
        'signalRmsVolts': signalRms,
        'noiseRmsVolts': noiseRms,
        'fundamentalVpk': spectrum.metrics.fundamentalVpk,
        'fundamentalDbfs': spectrum.metrics.fundamentalDbfs,
        'noiseFloorDbfs': spectrum.metrics.noiseFloorDbfs,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_signal_power_over_noise_power',
        'warnings': snr.isFinite
            ? const <String>[]
            : const ['SNR is not available because the noise power is zero'],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureCrestFactor(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_crest_factor',
    agentName: agentName,
    description:
        'Measures the crest factor of one acquired channel as peak divided '
        'by RMS, in linear form and in dB. The peak is the largest absolute '
        'deviation from the mean. Use it to distinguish a sine (about 1.41) '
        'from a pulse or a transient-heavy signal.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final stats = computeAudioTimeStats(channel);
      return {
        'channel': channel.label,
        'crestFactor': stats.crestFactor,
        'crestFactorDb': stats.crestFactorDb,
        'peakVolts': stats.peakVolts,
        'rmsVolts': stats.rmsVolts,
        'method': 'time_domain_peak_over_rms',
        'warnings': stats.rmsVolts <= 0
            ? ['crest factor is undefined for a zero-RMS record']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureChannelBalance(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_channel_balance',
    agentName: agentName,
    description:
        'Compares two acquired channels: RMS balance in dB (A relative to '
        'B), peak balance, individual RMS/peak values, normalized '
        'correlation and relative delay. Use it for stereo balance, '
        'left/right level differences or two-node level comparisons. The '
        'channels must have the same sample rate.',
    properties: {
      'channelA': audioChannelProperty('First channel (default ch1).'),
      'channelB': audioChannelProperty('Second channel (default ch2).'),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requestedA = audioStringArg(args, 'channelA') ?? 'ch1';
      final requestedB = audioStringArg(args, 'channelB') ?? 'ch2';
      final a = audioChannel(context, requestedA);
      final b = audioChannel(context, requestedB);
      if (a == null) return audioChannelError(requestedA);
      if (b == null) return audioChannelError(requestedB);
      if (a.sampleRateHz != b.sampleRateHz) {
        return {
          'error':
              'The channels have different sample rates and cannot be '
              'compared sample by sample.',
        };
      }

      final statsA = computeAudioTimeStats(a);
      final statsB = computeAudioTimeStats(b);
      if (statsA.rmsVolts <= 0 || statsB.rmsVolts <= 0) {
        return {
          'error': 'At least one channel has zero RMS; balance is undefined.',
          'channelA': a.label,
          'channelB': b.label,
        };
      }
      final correlation = audioChannelCorrelation(a, b);
      return {
        'channelA': a.label,
        'channelB': b.label,
        'balanceDb': dbRatio(statsA.rmsVolts / statsB.rmsVolts),
        'peakBalanceDb': dbRatio(statsA.peakVolts / statsB.peakVolts),
        'rmsAVolts': statsA.rmsVolts,
        'rmsBVolts': statsB.rmsVolts,
        'peakAVolts': statsA.peakVolts,
        'peakBVolts': statsB.peakVolts,
        'correlation': correlation?.coefficient,
        'delaySamples': correlation?.lagSamples,
        'delaySeconds': correlation == null
            ? null
            : correlation.lagSamples / a.sampleRateHz,
        'method': 'rms_ratio_and_cross_correlation',
      };
    },
  );
}
