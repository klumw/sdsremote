/// Frequency-domain tools for the audio analysis agent.
///
/// Peak, hum and interference analysis use the current FFT. Frequency
/// response and bandwidth use an injected Bode/frequency-sweep provider; the
/// bandwidth tool falls back to a spectrum-based occupied-bandwidth estimate
/// when no sweep is available.
library;

import 'dart:math' as math;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'audio_analysis_context.dart';
import 'audio_spectrum.dart';
import 'audio_sweep_analysis.dart';
import 'audio_tool_support.dart';

/// Creates the frequency-analysis tool group (C).
List<Tool<Map<String, dynamic>>> createAudioFrequencyTools({
  AudioAnalysisContextProvider? context,
  AudioSweepProvider? sweep,
  String agentName = 'unknown',
}) {
  return [
    _measureFrequencyResponse(sweep, agentName),
    _detectHum(context, agentName),
    _detectInterference(context, agentName),
    _analyzeSpectralPeaks(context, agentName),
    _measureBandwidth(context, sweep, agentName),
  ];
}

Tool<Map<String, dynamic>> _measureFrequencyResponse(
  AudioSweepProvider? sweepProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_frequency_response',
    agentName: agentName,
    description:
        'Runs a Bode/frequency sweep and returns the gain response. The host '
        'application performs the sweep through the connected signal '
        'generator and oscilloscope; this tool only interprets the measured '
        'points. Returns gain versus frequency plus peak gain, −3 dB '
        'crossings, bandwidth, Q factor and unity crossover. Requires the '
        'sweep provider and connected hardware.',
    properties: {
      'startFrequencyHz': audioNumberProperty(
        'Sweep start frequency.',
        minimum: 0.001,
      ),
      'stopFrequencyHz': audioNumberProperty(
        'Sweep stop frequency.',
        minimum: 0.002,
      ),
      'pointCount': audioIntegerProperty(
        'Number of sweep points.',
        minimum: 2,
        maximum: 200,
      ),
      'measurePhase': audioBooleanProperty(
        'Also measure phase during the sweep.',
      ),
    },
    handler: (args) async {
      if (sweepProvider == null) return audioSweepError();
      final start = audioDoubleOr(args, 'startFrequencyHz', 20);
      final stop = audioDoubleOr(args, 'stopFrequencyHz', 20000);
      final points = audioIntOr(args, 'pointCount', 20);
      final validation = _validateSweep(start, stop, points);
      if (validation != null) return {'error': validation};
      final data = await sweepProvider(
        AudioSweepRequest(
          startFrequencyHz: start,
          stopFrequencyHz: stop,
          pointCount: points,
          measurePhase: audioBoolArg(args, 'measurePhase'),
        ),
      );
      if (data == null) return audioSweepError();
      final summary = analyzeAudioSweepGain(data);
      return {
        'source': data.source,
        'configSummary': data.configSummary,
        'pointCount': data.points.length,
        'validPointCount': data.points.where((point) => point.valid).length,
        'points': [
          for (final point in data.points)
            {
              'frequencyHz': point.frequencyHz,
              'gainDb': point.gainDb,
              'vinRms': point.vinRms,
              'voutRms': point.voutRms,
              'valid': point.valid,
              'note': point.note,
            },
        ],
        'peakGainDb': summary.peakGainDb,
        'peakFrequencyHz': summary.peakFrequencyHz,
        'minus3DbFrequencyHz': summary.minus3DbFrequencyHz,
        'lowerMinus3DbFrequencyHz': summary.lowerMinus3DbFrequencyHz,
        'bandwidthHz': audioSweepBandwidth(data),
        'qFactor': summary.qFactor,
        'unityCrossoverHz': summary.unityCrossoverHz,
        'notes': summary.notes,
        'method': 'bode_sweep_gain',
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectHum(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_hum',
    agentName: agentName,
    description:
        'Detects mains hum in one acquired channel. It checks 50 Hz or '
        '60 Hz and their harmonics, reports each component in dBc relative '
        'to the fundamental and flags components above the supplied '
        'threshold. Omit mainsFrequencyHz to evaluate both 50 and 60 Hz. If '
        'the fundamental itself is a hum harmonic, that component is '
        'excluded and a warning is returned.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'mainsFrequencyHz': audioNumberProperty(
        'Mains base frequency (50 or 60). Omit it to evaluate both.',
        minimum: 1,
        maximum: 1000,
      ),
      'thresholdDbc': audioNumberProperty(
        'Component level above which hum is reported, in dBc.',
        minimum: -200,
        maximum: 0,
      ),
      'harmonicCount': audioIntegerProperty(
        'Highest mains harmonic to check.',
        minimum: 1,
        maximum: 30,
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
      final fundamental = spectrum.metrics.fundamentalHz;
      if (!fundamental.isFinite || fundamental <= 0) {
        return {
          'channel': channel.label,
          'error': 'No fundamental frequency is available for dBc reference.',
        };
      }
      final threshold = audioDoubleOr(args, 'thresholdDbc', -60);
      final count = audioIntOr(args, 'harmonicCount', 10);
      final requestedBase = audioNumberArg(args, 'mainsFrequencyHz');
      final bases = requestedBase != null && requestedBase > 0
          ? [requestedBase]
          : [50.0, 60.0];
      final tolerance = math.max(0.5, spectrum.resolutionHz * 2);
      final warnings = <String>[];
      var best = _HumCandidate.empty();

      for (final base in bases) {
        final components = <Map<String, dynamic>>[];
        double? worst;
        for (var harmonic = 1; harmonic <= count; harmonic++) {
          final target = harmonic * base;
          if (target >= spectrum.nyquistHz) break;
          if ((fundamental - target).abs() <= tolerance * 2) {
            warnings.add(
              'the fundamental lies on the $harmonic. mains harmonic at '
              '${target.toStringAsFixed(1)} Hz; that component was excluded',
            );
            continue;
          }
          final peak = peakNearFrequency(
            spectrum,
            target,
            toleranceHz: tolerance,
          );
          if (peak == null || peak.amplitudeVpk <= 0) continue;
          final dbc = dbcRelativeToFundamental(spectrum, peak.amplitudeVpk);
          if (dbc == null) continue;
          if (worst == null || dbc > worst) worst = dbc;
          components.add({
            'harmonic': harmonic,
            'frequencyHz': peak.frequencyHz,
            'targetHz': target,
            'amplitudeVpk': peak.amplitudeVpk,
            'dbc': dbc,
            'dbfs': dbfsFromAmplitude(
              peak.amplitudeVpk,
              spectrum.fullScaleVolts,
            ),
          });
        }
        if (worst != null && worst > best.worstDbc) {
          best = _HumCandidate(
            baseFrequencyHz: base,
            worstDbc: worst,
            components: components,
          );
        }
      }

      return {
        'channel': channel.label,
        'mainsFrequencyHz': best.baseFrequencyHz,
        'humDetected': best.worstDbc >= threshold,
        'thresholdDbc': threshold,
        'worstDbc': best.worstDbc == -double.infinity ? null : best.worstDbc,
        'components': best.components,
        'fundamentalHz': fundamental,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_mains_harmonic_search',
        'warnings': warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectInterference(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_interference',
    agentName: agentName,
    description:
        'Finds spectral peaks that are not harmonics of the fundamental and '
        'reports them in dBc. Each peak is marked as hum-related (near a '
        '50/60 Hz harmonic) or other interference. Use thresholdDbc to '
        'control which spurs are reported; the default is −60 dBc.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'thresholdDbc': audioNumberProperty(
        'Minimum level relative to the fundamental for a reported spur.',
        minimum: -200,
        maximum: 0,
      ),
      'maxPeaks': audioIntegerProperty(
        'Maximum number of interference peaks to report.',
        minimum: 1,
        maximum: 30,
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

      final maxPeaks = audioIntOr(args, 'maxPeaks', 10);
      final spectrum = computeAudioSpectrum(
        channel,
        requestedFftSize: audioIntOr(args, 'fftSize', 0),
        peakCount: maxPeaks + 1,
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final fundamental = spectrum.metrics.fundamentalHz;
      if (!fundamental.isFinite || fundamental <= 0) {
        return {
          'channel': channel.label,
          'error': 'No fundamental frequency is available for dBc reference.',
        };
      }
      final threshold = audioDoubleOr(args, 'thresholdDbc', -60);
      final peaks = <Map<String, dynamic>>[];
      for (final peak in spectrum.peaks.skip(1)) {
        if (_isHarmonic(peak.frequencyHz, fundamental)) continue;
        final dbc = dbcRelativeToFundamental(spectrum, peak.amplitudeVpk);
        if (dbc == null || dbc < threshold) continue;
        peaks.add({
          'frequencyHz': peak.frequencyHz,
          'amplitudeVpk': peak.amplitudeVpk,
          'dbfs': peak.dbfs,
          'dbc': dbc,
          'humRelated': _isHumRelated(peak.frequencyHz),
        });
      }
      peaks.sort((a, b) => (b['dbc'] as double).compareTo(a['dbc'] as double));
      return {
        'channel': channel.label,
        'interferenceDetected': peaks.isNotEmpty,
        'thresholdDbc': threshold,
        'fundamentalHz': fundamental,
        'peaks': peaks.take(maxPeaks).toList(),
        'noiseFloorDbfs': spectrum.metrics.noiseFloorDbfs,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_non_harmonic_peak_search',
        'warnings': peaks.isEmpty
            ? const ['no non-harmonic peak above the threshold']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _analyzeSpectralPeaks(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'analyze_spectral_peaks',
    agentName: agentName,
    description:
        'Returns the strongest spectral peaks of one acquired channel with '
        'frequency, amplitude, dBFS, dBc and their relation to the '
        'fundamental (fundamental, harmonic or non-harmonic). Use it as the '
        'deterministic basis for peak and spur interpretation.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'peakCount': audioIntegerProperty(
        'Number of peaks to return.',
        minimum: 1,
        maximum: 30,
      ),
      'thresholdDbc': audioNumberProperty(
        'Minimum level relative to the fundamental.',
        minimum: -200,
        maximum: 0,
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

      final peakCount = audioIntOr(args, 'peakCount', 10);
      final spectrum = computeAudioSpectrum(
        channel,
        requestedFftSize: audioIntOr(args, 'fftSize', 0),
        peakCount: peakCount,
      );
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final fundamental = spectrum.metrics.fundamentalHz;
      final threshold = audioDoubleOr(args, 'thresholdDbc', -120);
      final rows = <Map<String, dynamic>>[];
      for (final peak in spectrum.peaks) {
        final dbc = peak.isFundamental
            ? 0.0
            : dbcRelativeToFundamental(spectrum, peak.amplitudeVpk);
        if (dbc != null && dbc < threshold) continue;
        final harmonicNumber = peak.isFundamental || !fundamental.isFinite
            ? null
            : _harmonicNumber(peak.frequencyHz, fundamental);
        rows.add({
          'marker': peak.marker,
          'frequencyHz': peak.frequencyHz,
          'amplitudeVpk': peak.amplitudeVpk,
          'dbfs': peak.dbfs,
          'dbc': dbc,
          'relation': peak.isFundamental
              ? 'fundamental'
              : harmonicNumber != null
              ? 'harmonic'
              : 'non_harmonic',
          'harmonicNumber': harmonicNumber,
        });
      }
      return {
        'channel': channel.label,
        'fundamentalHz': fundamental.isFinite ? fundamental : null,
        'peaks': rows,
        'noiseFloorDbfs': spectrum.metrics.noiseFloorDbfs,
        'resolutionHz': spectrum.resolutionHz,
        'fftSize': spectrum.fftSize,
        'method': 'fft_peak_markers',
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureBandwidth(
  AudioAnalysisContextProvider? contextProvider,
  AudioSweepProvider? sweepProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_bandwidth',
    agentName: agentName,
    description:
        'Measures bandwidth. With a sweep provider it returns the −3 dB '
        'bandwidth from the Bode gain curve. Without one it falls back to a '
        'single-capture spectrum estimate: 99 % occupied bandwidth and the '
        'half-power width of the dominant peak. Always quote the method, '
        'because the two definitions are not interchangeable.',
    properties: {
      'channel': audioChannelProperty(
        'Channel for the spectrum fallback. Omit it to use the first '
        'acquired channel.',
      ),
      'method': audioEnumProperty(
        'Measurement method: auto, sweep or spectrum.',
        ['auto', 'sweep', 'spectrum'],
      ),
      'startFrequencyHz': audioNumberProperty(
        'Sweep start frequency.',
        minimum: 0.001,
      ),
      'stopFrequencyHz': audioNumberProperty(
        'Sweep stop frequency.',
        minimum: 0.002,
      ),
      'pointCount': audioIntegerProperty(
        'Number of sweep points.',
        minimum: 2,
        maximum: 200,
      ),
    },
    handler: (args) async {
      final method = audioStringOr(args, 'method', 'auto');
      final notes = <String>[];
      String? sweepError;
      String? sweepErrorCode;
      String? sweepHint;
      if (method != 'spectrum' && sweepProvider != null) {
        final start = audioDoubleOr(args, 'startFrequencyHz', 20);
        final stop = audioDoubleOr(args, 'stopFrequencyHz', 20000);
        final points = audioIntOr(args, 'pointCount', 20);
        final validation = _validateSweep(start, stop, points);
        if (validation != null) return {'error': validation};
        try {
          final data = await sweepProvider(
            AudioSweepRequest(
              startFrequencyHz: start,
              stopFrequencyHz: stop,
              pointCount: points,
            ),
          );
          if (data != null) {
            final summary = analyzeAudioSweepGain(data);
            if (summary.hasData) {
              return {
                'method': 'bode_sweep_minus_3db',
                'source': data.source,
                'bandwidthHz': audioSweepBandwidth(data),
                'minus3DbFrequencyHz': summary.minus3DbFrequencyHz,
                'lowerMinus3DbFrequencyHz': summary.lowerMinus3DbFrequencyHz,
                'peakGainDb': summary.peakGainDb,
                'peakFrequencyHz': summary.peakFrequencyHz,
                'qFactor': summary.qFactor,
                'unityCrossoverHz': summary.unityCrossoverHz,
                'notes': summary.notes,
              };
            }
            notes.add('the sweep returned no valid gain points');
          } else {
            notes.add('the sweep provider returned no data');
          }
        } on AudioSweepException catch (error) {
          sweepError = error.message;
          sweepErrorCode = error.code;
          sweepHint = error.hint;
          notes.add('the sweep failed: ${error.message}');
        } on Object catch (error) {
          sweepError = '$error';
          sweepErrorCode = 'SWEEP_FAILED';
          notes.add('the sweep failed: $error');
        }
      }
      if (method == 'sweep') {
        return {
          'error': sweepError == null
              ? 'The Bode sweep is not available or returned no data.'
              : 'The Bode sweep failed: $sweepError',
          'error_code': ?sweepErrorCode,
          'hint': ?sweepHint,
          'notes': notes,
        };
      }

      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);
      final spectrum = computeAudioSpectrum(channel, peakCount: 20);
      if (spectrum == null) {
        return {
          'channel': channel.label,
          'error': 'The channel has too few samples for a spectrum.',
        };
      }
      final occupied = _occupiedBandwidth(spectrum);
      final halfPower = _halfPowerWidth(spectrum);
      return {
        'channel': channel.label,
        'method': 'spectrum_occupied_bandwidth',
        'occupiedBandwidthHz': occupied?.bandwidthHz,
        'occupiedBandLowerHz': occupied?.lowerHz,
        'occupiedBandUpperHz': occupied?.upperHz,
        'peakHalfPowerBandwidthHz': halfPower?.bandwidthHz,
        'peakHalfPowerLowerHz': halfPower?.lowerHz,
        'peakHalfPowerUpperHz': halfPower?.upperHz,
        'fundamentalHz': spectrum.metrics.fundamentalHz,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'notes': [
          ...notes,
          'the spectrum fallback measures the acquired signal, not the '
              'transfer function of a device',
          if (occupied == null) '99 % occupied bandwidth is unavailable',
          if (halfPower == null) 'half-power width is unavailable',
        ],
      };
    },
  );
}

class _HumCandidate {
  const _HumCandidate({
    required this.baseFrequencyHz,
    required this.worstDbc,
    required this.components,
  });

  const _HumCandidate.empty()
    : baseFrequencyHz = null,
      worstDbc = -double.infinity,
      components = const [];

  final double? baseFrequencyHz;
  final double worstDbc;
  final List<Map<String, dynamic>> components;
}

class _BandwidthRange {
  const _BandwidthRange({
    required this.lowerHz,
    required this.upperHz,
    required this.bandwidthHz,
  });

  final double lowerHz;
  final double upperHz;
  final double bandwidthHz;
}

_BandwidthRange? _occupiedBandwidth(AudioSpectrum spectrum) {
  var total = 0.0;
  for (var k = 1; k < spectrum.binCount; k++) {
    total += spectrum.powers[k];
  }
  if (!(total > 0)) return null;
  final lowTarget = total * 0.005;
  final highTarget = total * 0.995;
  var cumulative = 0.0;
  double? lower;
  double? upper;
  for (var k = 1; k < spectrum.binCount; k++) {
    cumulative += spectrum.powers[k];
    if (lower == null && cumulative >= lowTarget) {
      lower = spectrum.frequenciesHz[k];
    }
    if (cumulative >= highTarget) {
      upper = spectrum.frequenciesHz[k];
      break;
    }
  }
  if (lower == null || upper == null || upper <= lower) return null;
  return _BandwidthRange(
    lowerHz: lower,
    upperHz: upper,
    bandwidthHz: upper - lower,
  );
}

_BandwidthRange? _halfPowerWidth(AudioSpectrum spectrum) {
  final fundamental = spectrum.metrics.fundamentalHz;
  if (!fundamental.isFinite || fundamental <= 0) return null;
  final center = (fundamental / spectrum.resolutionHz).round();
  if (center <= 0 || center >= spectrum.binCount - 1) return null;
  final halfPower = spectrum.powers[center] / 2;
  if (!(halfPower > 0)) return null;
  var lowerBin = center;
  while (lowerBin > 1 && spectrum.powers[lowerBin] > halfPower) {
    lowerBin--;
  }
  var upperBin = center;
  while (upperBin < spectrum.binCount - 2 &&
      spectrum.powers[upperBin] > halfPower) {
    upperBin++;
  }
  final lower = spectrum.frequenciesHz[lowerBin];
  final upper = spectrum.frequenciesHz[upperBin];
  if (upper <= lower) return null;
  return _BandwidthRange(
    lowerHz: lower,
    upperHz: upper,
    bandwidthHz: upper - lower,
  );
}

String? _validateSweep(double start, double stop, int points) {
  if (!start.isFinite || !stop.isFinite || start <= 0 || stop <= start) {
    return 'The sweep needs 0 < startFrequencyHz < stopFrequencyHz.';
  }
  if (points < 2 || points > 200) {
    return 'pointCount must be between 2 and 200.';
  }
  return null;
}

bool _isHarmonic(double frequency, double fundamental) =>
    _harmonicNumber(frequency, fundamental) != null;

int? _harmonicNumber(double frequency, double fundamental) {
  if (!frequency.isFinite || !fundamental.isFinite || fundamental <= 0) {
    return null;
  }
  final ratio = frequency / fundamental;
  final nearest = ratio.round();
  if (nearest < 2) return null;
  return (ratio - nearest).abs() <= 0.02 * nearest ? nearest : null;
}

bool _isHumRelated(double frequency) {
  for (final base in const [50.0, 60.0]) {
    for (var harmonic = 1; harmonic <= 10; harmonic++) {
      final target = base * harmonic;
      if ((frequency - target).abs() <= math.max(0.5, target * 0.01)) {
        return true;
      }
    }
  }
  return false;
}
