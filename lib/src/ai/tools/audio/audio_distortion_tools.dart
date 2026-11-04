/// Distortion tools for the audio analysis agent.
///
/// THD, THD+N and SINAD come from the same FFT metric engine as the Spectrum
/// tab. Harmonics and intermodulation products are measured at their exact
/// frequencies with the windowed DFT helper.
library;

import 'dart:math' as math;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../../spectrum/spectrum_models.dart';
import 'audio_analysis_context.dart';
import 'audio_spectrum.dart';
import 'audio_time_domain.dart';
import 'audio_tool_support.dart';

/// Creates the distortion tool group (B).
List<Tool<Map<String, dynamic>>> createAudioDistortionTools({
  AudioAnalysisContextProvider? context,
  String agentName = 'unknown',
}) {
  return [
    _measureThd(context, agentName),
    _measureThdn(context, agentName),
    _measureSinad(context, agentName),
    _analyzeHarmonics(context, agentName),
    _detectIntermodulation(context, agentName),
    _analyzeDistortion(context, agentName),
  ];
}

Tool<Map<String, dynamic>> _measureThd(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_thd',
    agentName: agentName,
    description:
        'Measures total harmonic distortion (THD) of one acquired channel '
        'from the FFT metrics. Returns THD in percent and dB, the '
        'fundamental frequency, the number of harmonics used and the FFT '
        'resolution. Harmonics above Nyquist are ignored.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
      'harmonicCount': audioIntegerProperty(
        'Maximum harmonic number analysed (2…Nyquist).',
        minimum: 2,
        maximum: 50,
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
        harmonicCount: audioIntOr(args, 'harmonicCount', 10),
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final metrics = spectrum.metrics;
      return {
        'channel': channel.label,
        'thdPercent': metrics.thdPercent,
        'thdDb': metrics.thdDb,
        'fundamentalHz': metrics.fundamentalHz,
        'fundamentalVpk': metrics.fundamentalVpk,
        'harmonicsUsed': metrics.harmonicsUsed,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_harmonic_power_ratio',
        'warnings': metrics.harmonicsUsed == 0
            ? const ['no harmonic fits below Nyquist']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureThdn(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_thdn',
    agentName: agentName,
    description:
        'Measures THD+N (total harmonic distortion plus noise) of one '
        'acquired channel. Returns the ratio in dB and percent, plus the '
        'fundamental level and the noise floor. This is an FFT-based '
        'measurement with the application\'s 8-bit acquisition limits.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
      'harmonicCount': audioIntegerProperty(
        'Maximum harmonic number analysed.',
        minimum: 2,
        maximum: 50,
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
        harmonicCount: audioIntOr(args, 'harmonicCount', 10),
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final db = spectrum.metrics.thdPlusNDb;
      return {
        'channel': channel.label,
        'thdPlusNoiseDb': db,
        'thdPlusNoisePercent': db.isFinite
            ? math.pow(10, db / 20).toDouble() * 100
            : null,
        'fundamentalHz': spectrum.metrics.fundamentalHz,
        'fundamentalDbfs': spectrum.metrics.fundamentalDbfs,
        'noiseFloorDbfs': spectrum.metrics.noiseFloorDbfs,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_distortion_plus_noise_over_fundamental',
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureSinad(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_sinad',
    agentName: agentName,
    description:
        'Measures SINAD (signal-to-noise-and-distortion ratio) of one '
        'acquired channel and derives ENOB from it. Also returns SNR, '
        'THD+N and the noise floor. Use it to judge the effective '
        'resolution of the acquired signal.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
      'harmonicCount': audioIntegerProperty(
        'Maximum harmonic number analysed.',
        minimum: 2,
        maximum: 50,
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
        harmonicCount: audioIntOr(args, 'harmonicCount', 10),
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final metrics = spectrum.metrics;
      return {
        'channel': channel.label,
        'sinadDb': metrics.sinadDb.isFinite ? metrics.sinadDb : null,
        'enobBits': metrics.enobBits.isFinite ? metrics.enobBits : null,
        'snrDb': metrics.snrDb.isFinite ? metrics.snrDb : null,
        'thdPlusNoiseDb': metrics.thdPlusNDb,
        'noiseFloorDbfs': metrics.noiseFloorDbfs,
        'fundamentalHz': metrics.fundamentalHz,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_sinad_enob',
      };
    },
  );
}

Tool<Map<String, dynamic>> _analyzeHarmonics(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'analyze_harmonics',
    agentName: agentName,
    description:
        'Measures the harmonic series of one acquired channel. Returns each '
        'harmonic number, frequency, amplitude, dBc and whether it is above '
        'the noise floor, together with THD. Pass fundamentalHz to analyse '
        'a known tone; otherwise the strongest FFT peak is used.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'fundamentalHz': audioNumberProperty(
        'Known fundamental frequency. Omit it to use the FFT peak.',
        minimum: 0.001,
      ),
      'harmonicCount': audioIntegerProperty(
        'Highest harmonic number to report.',
        minimum: 2,
        maximum: 50,
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
        harmonicCount: audioIntOr(args, 'harmonicCount', 10),
        peakCount: 20,
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final measured = spectrum.metrics.fundamentalHz;
      final fundamental =
          audioNumberArg(args, 'fundamentalHz') ??
          (measured.isFinite && measured > 0 ? measured : null);
      if (fundamental == null || fundamental <= 0) {
        return {
          'channel': channel.label,
          'error': 'No fundamental frequency is available.',
        };
      }
      final count = audioIntOr(args, 'harmonicCount', 10);
      return {
        'channel': channel.label,
        'fundamentalHz': fundamental,
        'fundamentalVpk': spectrum.metrics.fundamentalVpk,
        'harmonics': _harmonicRows(spectrum, fundamental, count),
        'thdPercent': spectrum.metrics.thdPercent,
        'thdDb': spectrum.metrics.thdDb,
        'harmonicCount': count,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_windowed_dft_at_harmonics',
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectIntermodulation(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_intermodulation',
    agentName: agentName,
    description:
        'Measures two-tone intermodulation products of one acquired '
        'channel. Pass lowerToneHz and upperToneHz for a known test signal; '
        'otherwise the two strongest non-harmonic FFT peaks are used. '
        'Returns f2−f1, 2f1−f2, 2f2−f1 and f1+f2 products in dBc. Needs a '
        'two-tone signal; a single tone cannot produce valid IMD data.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'lowerToneHz': audioNumberProperty(
        'Lower test tone frequency. Omit it to detect the tones.',
        minimum: 0.001,
      ),
      'upperToneHz': audioNumberProperty(
        'Upper test tone frequency. Omit it to detect the tones.',
        minimum: 0.001,
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
        peakCount: 20,
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      return _intermodulationResult(
        spectrum,
        lower: audioNumberArg(args, 'lowerToneHz'),
        upper: audioNumberArg(args, 'upperToneHz'),
      );
    },
  );
}

Tool<Map<String, dynamic>> _analyzeDistortion(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'analyze_distortion',
    agentName: agentName,
    description:
        'Combines the distortion picture of one acquired channel: THD, '
        'THD+N, SINAD, SNR, SFDR, the strongest harmonics, clipping and, '
        'when a two-tone signal is present, intermodulation products. The '
        'verdict is a descriptive THD category, not a standards-compliant '
        'audio measurement.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'fftSize': audioIntegerProperty(
        'Requested FFT size (0 = automatic largest power of two).',
        minimum: 0,
      ),
      'harmonicCount': audioIntegerProperty(
        'Maximum harmonic number analysed.',
        minimum: 2,
        maximum: 50,
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
        harmonicCount: audioIntOr(args, 'harmonicCount', 10),
        peakCount: 20,
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final metrics = spectrum.metrics;
      final fundamental = metrics.fundamentalHz;
      final harmonics = fundamental.isFinite && fundamental > 0
          ? _harmonicRows(spectrum, fundamental, 5)
          : const <Map<String, dynamic>>[];
      final clipping = fundamental.isFinite && fundamental > 0
          ? detectAudioClipping(channel, fundamentalHz: fundamental)
          : detectAudioClipping(channel);
      final intermodulation = _intermodulationResult(spectrum);
      final thd = metrics.thdPercent;
      final verdict = !thd.isFinite
          ? 'unknown'
          : thd < 0.1
          ? 'very_low'
          : thd < 1.0
          ? 'low'
          : thd < 3.0
          ? 'moderate'
          : 'high';
      return {
        'channel': channel.label,
        'thdPercent': thd,
        'thdDb': metrics.thdDb,
        'thdPlusNoiseDb': metrics.thdPlusNDb,
        'sinadDb': metrics.sinadDb.isFinite ? metrics.sinadDb : null,
        'snrDb': metrics.snrDb.isFinite ? metrics.snrDb : null,
        'sfdrDb': metrics.sfdrDb.isFinite ? metrics.sfdrDb : null,
        'fundamentalHz': fundamental,
        'fundamentalVpk': metrics.fundamentalVpk,
        'harmonics': harmonics,
        'clipping': {
          'detected': clipping.clippingDetected,
          'clippingRatio': clipping.clippingRatio,
          'adcClippingRatio': clipping.adcClippingRatio,
          'regionCount': clipping.regionCount,
        },
        'intermodulation': intermodulation,
        'verdict': verdict,
        'verdictBasis':
            'descriptive THD bands (<0.1 %, <1 %, <3 %, otherwise high); '
            'not a calibrated audio-analyzer limit',
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_distortion_summary',
      };
    },
  );
}

List<Map<String, dynamic>> _harmonicRows(
  AudioSpectrum spectrum,
  double fundamental,
  int count,
) {
  final noiseAmp = spectrum.metrics.noiseFloorDbfs.isFinite
      ? spectrum.fullScaleVolts *
            math.pow(10, spectrum.metrics.noiseFloorDbfs / 20).toDouble()
      : 0.0;
  final rows = <Map<String, dynamic>>[];
  for (var harmonic = 2; harmonic <= count; harmonic++) {
    final frequency = harmonic * fundamental;
    if (frequency >= spectrum.nyquistHz) break;
    final amplitude = amplitudeAtFrequency(spectrum, frequency);
    rows.add({
      'harmonic': harmonic,
      'frequencyHz': frequency,
      'amplitudeVpk': amplitude,
      'dbc': dbcRelativeToFundamental(spectrum, amplitude),
      'dbfs': dbfsFromAmplitude(amplitude, spectrum.fullScaleVolts),
      'aboveNoiseFloor': amplitude > noiseAmp,
    });
  }
  return rows;
}

Map<String, dynamic> _intermodulationResult(
  AudioSpectrum spectrum, {
  double? lower,
  double? upper,
}) {
  double? first = lower;
  double? second = upper;
  final warnings = <String>[];

  if ((first == null) != (second == null)) {
    return {
      'error':
          'Pass both lowerToneHz and upperToneHz, or neither to detect the '
          'tones automatically.',
    };
  }

  if (first == null || second == null) {
    final fundamental = spectrum.metrics.fundamentalHz;
    final candidates = <SpectrumPeak>[];
    for (final peak in spectrum.peaks.skip(1)) {
      final frequency = peak.frequencyHz;
      if (!frequency.isFinite || frequency <= 0) continue;
      if (fundamental.isFinite &&
          fundamental > 0 &&
          _isHarmonic(frequency, fundamental)) {
        continue;
      }
      candidates.add(peak);
    }
    candidates.sort((a, b) => b.amplitudeVpk.compareTo(a.amplitudeVpk));
    if (candidates.length < 2) {
      return {
        'error':
            'Fewer than two non-harmonic tones were found. Provide '
            'lowerToneHz and upperToneHz for a two-tone test.',
      };
    }
    first = candidates[0].frequencyHz;
    second = candidates[1].frequencyHz;
    warnings.add('tone frequencies were detected automatically');
  }

  final lowerTone = first;
  final upperTone = second;
  if (!(lowerTone > 0) || !(upperTone > 0) || lowerTone == upperTone) {
    return {'error': 'The two tone frequencies must be positive and distinct.'};
  }
  var firstTone = lowerTone;
  var secondTone = upperTone;
  if (firstTone > secondTone) {
    final swap = firstTone;
    firstTone = secondTone;
    secondTone = swap;
  }
  if (secondTone >= spectrum.nyquistHz) {
    return {'error': 'The upper tone is at or above Nyquist.'};
  }

  final lowerAmplitude = amplitudeAtFrequency(spectrum, firstTone);
  final upperAmplitude = amplitudeAtFrequency(spectrum, secondTone);
  if (lowerAmplitude <= 0 || upperAmplitude <= 0) {
    return {
      'error':
          'At least one tone has no measurable amplitude. Check the tone '
          'frequencies.',
    };
  }
  if (_isHarmonic(secondTone, firstTone)) {
    warnings.add(
      'the second tone is a harmonic of the first; the result is a harmonic '
      'test rather than a two-tone IMD test',
    );
  }

  final products = <Map<String, dynamic>>[];
  final productFrequencies = <(String, double)>[
    ('f2_minus_f1', secondTone - firstTone),
    ('2f1_minus_f2', 2 * firstTone - secondTone),
    ('2f2_minus_f1', 2 * secondTone - firstTone),
    ('f1_plus_f2', firstTone + secondTone),
  ];
  double? worstDb;
  for (final (label, frequency) in productFrequencies) {
    if (frequency <= 0 || frequency >= spectrum.nyquistHz) continue;
    final amplitude = amplitudeAtFrequency(spectrum, frequency);
    final relativeLower = dbRatio(amplitude / lowerAmplitude);
    final relativeUpper = dbRatio(amplitude / upperAmplitude);
    if (relativeLower != null && (worstDb == null || relativeLower > worstDb)) {
      worstDb = relativeLower;
    }
    products.add({
      'product': label,
      'frequencyHz': frequency,
      'amplitudeVpk': amplitude,
      'relativeToLowerToneDbc': relativeLower,
      'relativeToUpperToneDbc': relativeUpper,
    });
  }

  if ((secondTone - firstTone) < spectrum.resolutionHz * 2) {
    warnings.add(
      'the tone separation is close to the FFT resolution; the f2−f1 product '
      'is not resolved',
    );
  }

  return {
    'lowerToneHz': firstTone,
    'upperToneHz': secondTone,
    'toneSeparationHz': secondTone - firstTone,
    'lowerToneAmplitudeVpk': lowerAmplitude,
    'upperToneAmplitudeVpk': upperAmplitude,
    'products': products,
    'worstImdDbc': worstDb,
    'fftSize': spectrum.fftSize,
    'resolutionHz': spectrum.resolutionHz,
    'method': 'fft_two_tone_im_products',
    'warnings': warnings,
  };
}

bool _isHarmonic(double frequency, double fundamental) {
  final ratio = frequency / fundamental;
  final nearest = ratio.round();
  if (nearest < 2) return false;
  return (ratio - nearest).abs() <= 0.02 * nearest;
}
