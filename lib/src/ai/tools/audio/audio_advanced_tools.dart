/// Advanced audio tools for the audio analysis agent.
///
/// Crosstalk, gain, dynamic range and coherence use the current acquisition.
/// Phase response, group delay and the complete sweep summary use an injected
/// Bode/frequency-sweep provider.
library;

import 'dart:math' as math;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'audio_analysis_context.dart';
import 'audio_spectrum.dart';
import 'audio_sweep_analysis.dart';
import 'audio_time_domain.dart';
import 'audio_tool_support.dart';

/// Creates the advanced audio tool group (E).
List<Tool<Map<String, dynamic>>> createAudioAdvancedTools({
  AudioAnalysisContextProvider? context,
  AudioSweepProvider? sweep,
  String agentName = 'unknown',
}) {
  return [
    _measureCrosstalk(context, agentName),
    _measureDynamicRange(context, agentName),
    _measureGain(context, agentName),
    _measurePhaseResponse(sweep, agentName),
    _measureGroupDelay(sweep, agentName),
    _analyzeFrequencySweep(sweep, agentName),
    _measureCoherence(context, agentName),
  ];
}

Tool<Map<String, dynamic>> _measureCrosstalk(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_crosstalk',
    agentName: agentName,
    description:
        'Measures crosstalk from an aggressor channel into a victim channel. '
        'It compares the victim and aggressor amplitudes at the aggressor\'s '
        'fundamental and harmonics and reports dBc, percent and the worst '
        'component. The channels must be acquired together and share a '
        'sample rate. If the victim carries its own signal at the same '
        'frequency, the result is not an isolated crosstalk measurement and '
        'a warning is returned.',
    properties: {
      'aggressorChannel': audioChannelProperty(
        'Channel carrying the aggressor signal (default ch1).',
      ),
      'victimChannel': audioChannelProperty(
        'Channel receiving the crosstalk (default ch2).',
      ),
      'harmonicCount': audioIntegerProperty(
        'Highest aggressor harmonic to check.',
        minimum: 1,
        maximum: 20,
      ),
      'thresholdDbc': audioNumberProperty(
        'Worst crosstalk level above which crosstalk is reported.',
        minimum: -200,
        maximum: 0,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final aggressorId = audioStringArg(args, 'aggressorChannel') ?? 'ch1';
      final victimId = audioStringArg(args, 'victimChannel') ?? 'ch2';
      final aggressor = audioChannel(context, aggressorId);
      final victim = audioChannel(context, victimId);
      if (aggressor == null) return audioChannelError(aggressorId);
      if (victim == null) return audioChannelError(victimId);
      if (aggressor.sampleRateHz != victim.sampleRateHz) {
        return {
          'error': 'The channels have different sample rates.',
          'aggressorChannel': aggressor.label,
          'victimChannel': victim.label,
        };
      }

      final aggressorSpectrum = computeAudioSpectrum(aggressor);
      final victimSpectrum = computeAudioSpectrum(victim);
      if (aggressorSpectrum == null || victimSpectrum == null) {
        return {'error': 'At least one channel has too few samples.'};
      }
      final fundamental = aggressorSpectrum.metrics.fundamentalHz;
      if (!fundamental.isFinite || fundamental <= 0) {
        return {'error': 'No aggressor fundamental frequency is available.'};
      }
      final count = audioIntOr(args, 'harmonicCount', 5);
      final threshold = audioDoubleOr(args, 'thresholdDbc', -60);
      final warnings = <String>[];
      final victimFundamental = victimSpectrum.metrics.fundamentalHz;
      if (victimFundamental.isFinite &&
          (victimFundamental - fundamental).abs() / fundamental < 0.02) {
        warnings.add(
          'the victim has its own signal at the aggressor frequency; the '
          'result may not isolate crosstalk',
        );
      }

      final aggressorNoiseAmplitude =
          aggressorSpectrum.metrics.noiseFloorDbfs.isFinite
          ? aggressorSpectrum.fullScaleVolts *
                math
                    .pow(10, aggressorSpectrum.metrics.noiseFloorDbfs / 20)
                    .toDouble()
          : 0.0;
      final components = <Map<String, dynamic>>[];
      var skippedBelowAggressorNoise = 0;
      double? worst;
      for (var harmonic = 1; harmonic <= count; harmonic++) {
        final frequency = harmonic * fundamental;
        if (frequency >= aggressorSpectrum.nyquistHz) break;
        final aggressorAmplitude = amplitudeAtFrequency(
          aggressorSpectrum,
          frequency,
        );
        final victimAmplitude = amplitudeAtFrequency(victimSpectrum, frequency);
        if (aggressorAmplitude <= aggressorNoiseAmplitude * 1.5) {
          skippedBelowAggressorNoise++;
          continue;
        }
        if (aggressorAmplitude <= 0 || victimAmplitude <= 0) continue;
        final dbc = dbRatio(victimAmplitude / aggressorAmplitude);
        if (dbc == null) continue;
        if (worst == null || dbc > worst) worst = dbc;
        components.add({
          'harmonic': harmonic,
          'frequencyHz': frequency,
          'aggressorAmplitudeVpk': aggressorAmplitude,
          'victimAmplitudeVpk': victimAmplitude,
          'crosstalkDbc': dbc,
        });
      }
      if (skippedBelowAggressorNoise > 0) {
        warnings.add(
          '$skippedBelowAggressorNoise aggressor component(s) were below the '
          'aggressor noise floor and were skipped',
        );
      }
      if (components.isEmpty) {
        return {
          'aggressorChannel': aggressor.label,
          'victimChannel': victim.label,
          'aggressorFundamentalHz': fundamental,
          'crosstalkDetected': false,
          'worstCrosstalkDbc': null,
          'components': components,
          'skippedBelowAggressorNoise': skippedBelowAggressorNoise,
          'thresholdDbc': threshold,
          'warnings': [
            ...warnings,
            'no measurable victim component at the aggressor frequencies',
          ],
        };
      }
      return {
        'aggressorChannel': aggressor.label,
        'victimChannel': victim.label,
        'aggressorFundamentalHz': fundamental,
        'crosstalkDetected': worst != null && worst >= threshold,
        'worstCrosstalkDbc': worst,
        'worstCrosstalkPercent': worst == null
            ? null
            : math.pow(10, worst / 20).toDouble() * 100,
        'thresholdDbc': threshold,
        'components': components,
        'skippedBelowAggressorNoise': skippedBelowAggressorNoise,
        'method': 'dft_component_ratio_victim_over_aggressor',
        'warnings': warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureDynamicRange(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_dynamic_range',
    agentName: agentName,
    description:
        'Estimates the dynamic range of one acquired channel from the FFT '
        'noise floor and SNR. Returns the full-scale-to-noise ratio derived '
        'from SNR, the per-bin noise-floor dynamic range, SNR, SFDR, ENOB and '
        'the noise floor. This is an FFT/8-bit acquisition estimate, not a '
        'standards-compliant audio dynamic-range measurement.',
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
      final metrics = spectrum.metrics;
      final signalRms = rmsFromPeak(metrics.fundamentalVpk);
      final fullScaleRms = channel.fullScaleVolts / math.sqrt(2);
      final noiseRms = metrics.snrDb.isFinite && signalRms > 0
          ? signalRms / math.pow(10, metrics.snrDb / 20).toDouble()
          : null;
      final dynamicRange = noiseRms != null && noiseRms > 0
          ? dbRatio(fullScaleRms / noiseRms)
          : null;
      return {
        'channel': channel.label,
        'dynamicRangeDb': dynamicRange,
        'dynamicRangeFromNoiseFloorDb': metrics.noiseFloorDbfs.isFinite
            ? -metrics.noiseFloorDbfs
            : null,
        'snrDb': metrics.snrDb.isFinite ? metrics.snrDb : null,
        'sfdrDb': metrics.sfdrDb.isFinite ? metrics.sfdrDb : null,
        'enobBits': metrics.enobBits.isFinite ? metrics.enobBits : null,
        'noiseFloorDbfs': metrics.noiseFloorDbfs,
        'fullScaleRmsVolts': fullScaleRms,
        'fftSize': spectrum.fftSize,
        'resolutionHz': spectrum.resolutionHz,
        'method': 'fft_noise_floor_and_snr_estimate',
        'warnings': const [
          'FFT/8-bit estimate; not a substitute for a calibrated audio '
              'dynamic-range measurement',
        ],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureGain(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_gain',
    agentName: agentName,
    description:
        'Measures the gain from an input channel to an output channel: RMS '
        'gain, peak gain, gain and phase at the fundamental, and individual '
        'levels. Use it for amplifier, attenuator or channel-gain questions. '
        'The channels must share a sample rate and represent the same '
        'signal path.',
    properties: {
      'inputChannel': audioChannelProperty(
        'Input/reference channel (default ch1).',
      ),
      'outputChannel': audioChannelProperty(
        'Output/measured channel (default ch2).',
      ),
      'frequencyHz': audioNumberProperty(
        'Frequency for the gain/phase measurement. Omit it to use the input '
        'fundamental.',
        minimum: 0.001,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final inputId = audioStringArg(args, 'inputChannel') ?? 'ch1';
      final outputId = audioStringArg(args, 'outputChannel') ?? 'ch2';
      final input = audioChannel(context, inputId);
      final output = audioChannel(context, outputId);
      if (input == null) return audioChannelError(inputId);
      if (output == null) return audioChannelError(outputId);
      if (input.sampleRateHz != output.sampleRateHz) {
        return {
          'error': 'The channels have different sample rates.',
          'inputChannel': input.label,
          'outputChannel': output.label,
        };
      }

      final inputStats = computeAudioTimeStats(input);
      final outputStats = computeAudioTimeStats(output);
      if (inputStats.rmsVolts <= 0) {
        return {'error': 'The input channel has zero RMS.'};
      }
      final inputSpectrum = computeAudioSpectrum(input);
      final frequency =
          audioNumberArg(args, 'frequencyHz') ??
          (inputSpectrum?.metrics.fundamentalHz.isFinite == true
              ? inputSpectrum!.metrics.fundamentalHz
              : null);
      final inputComponent = frequency == null
          ? null
          : componentAtFrequency(input, frequency);
      final outputComponent = frequency == null
          ? null
          : componentAtFrequency(output, frequency);
      final warnings = <String>[];
      final outputFundamental = computeAudioSpectrum(
        output,
      )?.metrics.fundamentalHz;
      if (frequency != null &&
          outputFundamental != null &&
          outputFundamental.isFinite &&
          (outputFundamental - frequency).abs() / frequency > 0.02) {
        warnings.add(
          'the output fundamental differs from the input fundamental; the '
          'gain at the input frequency may not represent the output signal',
        );
      }
      return {
        'inputChannel': input.label,
        'outputChannel': output.label,
        'frequencyHz': frequency,
        'rmsGainDb': dbRatio(outputStats.rmsVolts / inputStats.rmsVolts),
        'rmsGainLinear': outputStats.rmsVolts / inputStats.rmsVolts,
        'peakGainDb': dbRatio(outputStats.peakVolts / inputStats.peakVolts),
        'gainAtFundamentalDb':
            inputComponent != null &&
                outputComponent != null &&
                inputComponent.amplitudeVpk > 0
            ? dbRatio(
                outputComponent.amplitudeVpk / inputComponent.amplitudeVpk,
              )
            : null,
        'phaseDifferenceDeg': frequency == null
            ? null
            : phaseDifferenceAtFrequency(input, output, frequency),
        'inputRmsVolts': inputStats.rmsVolts,
        'outputRmsVolts': outputStats.rmsVolts,
        'inputPeakVolts': inputStats.peakVolts,
        'outputPeakVolts': outputStats.peakVolts,
        'method': 'rms_ratio_and_fundamental_dft',
        'warnings': warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measurePhaseResponse(
  AudioSweepProvider? sweepProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_phase_response',
    agentName: agentName,
    description:
        'Runs a Bode/frequency sweep with phase measurement and returns the '
        'unwrapped phase response: start/stop phase, phase range and each '
        'measured point. Pass frequencyHz to interpolate the phase at one '
        'frequency. Requires the sweep provider and connected hardware.',
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
      'frequencyHz': audioNumberProperty(
        'Optional frequency at which to report the phase.',
        minimum: 0.001,
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
          measurePhase: true,
        ),
      );
      if (data == null) return audioSweepError();
      final analysis = analyzeAudioSweep(data);
      final phase = analysis.phase;
      final target = audioNumberArg(args, 'frequencyHz');
      final atFrequency = target == null
          ? null
          : _interpolate([
              for (final point in phase.points)
                (point.frequencyHz, point.unwrappedPhaseDeg),
            ], target);
      return {
        'source': data.source,
        'configSummary': data.configSummary,
        'startPhaseDeg': phase.startPhaseDeg,
        'stopPhaseDeg': phase.stopPhaseDeg,
        'phaseRangeDeg': phase.phaseRangeDeg,
        'phaseAtFrequencyDeg': atFrequency,
        'targetFrequencyHz': target,
        'points': [
          for (final point in phase.points)
            {
              'frequencyHz': point.frequencyHz,
              'phaseDeg': point.phaseDeg,
              'unwrappedPhaseDeg': point.unwrappedPhaseDeg,
              'gainDb': point.gainDb,
            },
        ],
        'notes': analysis.notes,
        'method': 'bode_sweep_phase',
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureGroupDelay(
  AudioSweepProvider? sweepProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_group_delay',
    agentName: agentName,
    description:
        'Runs a Bode/frequency sweep with phase measurement and derives group '
        'delay from the unwrapped phase: τ = −dφ/dω. Returns the per-point '
        'delay and mean/min/max values. Pass frequencyHz to interpolate the '
        'delay at one frequency. No smoothing is applied; a noisy phase '
        'measurement produces a noisy delay.',
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
      'frequencyHz': audioNumberProperty(
        'Optional frequency at which to report the group delay.',
        minimum: 0.001,
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
          measurePhase: true,
        ),
      );
      if (data == null) return audioSweepError();
      final analysis = analyzeAudioSweep(data);
      final groupDelay = analysis.groupDelay;
      final target = audioNumberArg(args, 'frequencyHz');
      final atFrequency = target == null
          ? null
          : _interpolate([
              for (final point in groupDelay.points)
                (point.frequencyHz, point.delaySeconds),
            ], target);
      return {
        'source': data.source,
        'configSummary': data.configSummary,
        'meanGroupDelaySeconds': groupDelay.meanDelaySeconds,
        'minGroupDelaySeconds': groupDelay.minDelaySeconds,
        'maxGroupDelaySeconds': groupDelay.maxDelaySeconds,
        'groupDelayAtFrequencySeconds': atFrequency,
        'targetFrequencyHz': target,
        'points': [
          for (final point in groupDelay.points)
            {
              'frequencyHz': point.frequencyHz,
              'delaySeconds': point.delaySeconds,
              'phaseDeg': point.phaseDeg,
              'gainDb': point.gainDb,
            },
        ],
        'notes': analysis.notes,
        'method': 'bode_sweep_group_delay',
      };
    },
  );
}

Tool<Map<String, dynamic>> _analyzeFrequencySweep(
  AudioSweepProvider? sweepProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'analyze_frequency_sweep',
    agentName: agentName,
    description:
        'Runs one Bode/frequency sweep and returns the complete analysis: '
        'gain peak, −3 dB crossings, bandwidth, Q factor, unity crossover, '
        'phase range, group-delay statistics and the measured points. Use it '
        'when the user asks for the overall frequency response, phase '
        'response and delay in one step.',
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
          measurePhase: true,
        ),
      );
      if (data == null) return audioSweepError();
      final analysis = analyzeAudioSweep(data);
      final gain = analysis.gain;
      final phase = analysis.phase;
      final groupDelay = analysis.groupDelay;
      return {
        'source': data.source,
        'configSummary': data.configSummary,
        'pointCount': data.points.length,
        'validPointCount': analysis.validPointCount,
        'gain': {
          'peakGainDb': gain.peakGainDb,
          'peakFrequencyHz': gain.peakFrequencyHz,
          'minus3DbFrequencyHz': gain.minus3DbFrequencyHz,
          'lowerMinus3DbFrequencyHz': gain.lowerMinus3DbFrequencyHz,
          'bandwidthHz': audioSweepBandwidth(data),
          'qFactor': gain.qFactor,
          'unityCrossoverHz': gain.unityCrossoverHz,
        },
        'phase': {
          'startPhaseDeg': phase.startPhaseDeg,
          'stopPhaseDeg': phase.stopPhaseDeg,
          'phaseRangeDeg': phase.phaseRangeDeg,
        },
        'groupDelay': {
          'meanDelaySeconds': groupDelay.meanDelaySeconds,
          'minDelaySeconds': groupDelay.minDelaySeconds,
          'maxDelaySeconds': groupDelay.maxDelaySeconds,
        },
        'gainPoints': [
          for (final point in data.points)
            {
              'frequencyHz': point.frequencyHz,
              'gainDb': point.gainDb,
              'valid': point.valid,
            },
        ],
        'phasePoints': [
          for (final point in phase.points)
            {
              'frequencyHz': point.frequencyHz,
              'phaseDeg': point.phaseDeg,
              'unwrappedPhaseDeg': point.unwrappedPhaseDeg,
            },
        ],
        'groupDelayPoints': [
          for (final point in groupDelay.points)
            {
              'frequencyHz': point.frequencyHz,
              'delaySeconds': point.delaySeconds,
            },
        ],
        'notes': analysis.notes,
        'method': 'bode_sweep_full_analysis',
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureCoherence(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_coherence',
    agentName: agentName,
    description:
        'Estimates magnitude-squared coherence between two acquired '
        'channels with a Welch-style averaged cross-spectrum. Returns mean '
        'coherence in the selected band, coherence at the fundamental and '
        'low/mid/high band averages. Coherence near 1 means a stable linear '
        'relationship; near 0 means noise, nonlinearity or unrelated '
        'signals. The channels must share a sample rate.',
    properties: {
      'channelA': audioChannelProperty('First channel (default ch1).'),
      'channelB': audioChannelProperty('Second channel (default ch2).'),
      'fftSize': audioIntegerProperty(
        'FFT size per averaging segment.',
        minimum: 64,
        maximum: 65536,
      ),
      'overlap': audioNumberProperty(
        'Segment overlap fraction (0–0.9).',
        minimum: 0,
        maximum: 0.9,
      ),
      'bandStartHz': audioNumberProperty(
        'Coherence band start frequency.',
        minimum: 0,
      ),
      'bandEndHz': audioNumberProperty(
        'Coherence band end frequency.',
        minimum: 0.001,
      ),
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
          'error': 'The channels have different sample rates.',
          'channelA': a.label,
          'channelB': b.label,
        };
      }
      final spectrum = computeAudioSpectrum(a);
      final result = computeAudioCoherence(
        a,
        b,
        fftSize: audioIntOr(args, 'fftSize', 4096),
        overlap: audioDoubleOr(args, 'overlap', 0.5),
        bandStartHz: audioDoubleOr(args, 'bandStartHz', 20),
        bandEndHz: audioDoubleOr(args, 'bandEndHz', 20000),
        fundamentalHz: spectrum?.metrics.fundamentalHz,
      );
      if (result == null) {
        return {
          'error':
              'Coherence needs at least 64 samples per channel and equal '
              'sample rates.',
        };
      }
      return {
        'channelA': a.label,
        'channelB': b.label,
        'meanCoherence': result.meanCoherence,
        'coherenceAtFundamental': result.coherenceAtFundamental,
        'bandCoherence': result.bandCoherence,
        'fftSize': result.fftSize,
        'segmentCount': result.segmentCount,
        'resolutionHz': result.resolutionHz,
        'method': 'welch_cross_spectrum_coherence',
        'warnings': result.warnings,
      };
    },
  );
}

double? _interpolate(List<(double, double)> points, double frequency) {
  if (points.isEmpty) return null;
  final sorted = List<(double, double)>.of(points)
    ..sort((a, b) => a.$1.compareTo(b.$1));
  if (frequency <= sorted.first.$1) return sorted.first.$2;
  if (frequency >= sorted.last.$1) return sorted.last.$2;
  for (var i = 0; i + 1 < sorted.length; i++) {
    final (f0, v0) = sorted[i];
    final (f1, v1) = sorted[i + 1];
    if (frequency < f0 || frequency > f1) continue;
    final span = f1 - f0;
    if (span <= 0) return v0;
    return v0 + (v1 - v0) * (frequency - f0) / span;
  }
  return null;
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
