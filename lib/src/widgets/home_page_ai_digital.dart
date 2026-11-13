part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiDigital on _OsciHomePageState {
  /// Raw acquisition trace of one channel for the digital measurements.
  ///
  /// The digital timing tools need the un-decimated acquisition, not the
  /// display copy. The known leading acquisition artifact is removed.
  WaveformTrace? _digitalTraceForChannel(String? channel) {
    final raw = _lastRawData;
    if (raw == null) return null;
    final requested = channel?.trim().toLowerCase();
    final candidates = requested == null || requested.isEmpty
        ? const ['ch1', 'ch2', 'ch3', 'ch4']
        : [requested];
    for (final id in candidates) {
      final bytes = switch (id) {
        'ch1' => raw.ch1Raw,
        'ch2' => raw.ch2Raw,
        'ch3' => raw.ch3Raw,
        'ch4' => raw.ch4Raw,
        _ => null,
      };
      final vdiv = _rawVdiv(raw, id);
      final voffset = _rawVoffset(raw, id);
      if (bytes == null || bytes.isEmpty || vdiv == null || voffset == null) {
        continue;
      }
      final volts = WaveformConverter.convertVoltages(bytes, vdiv, voffset);
      const leadingSamplesToSkip = 8;
      final start = volts.length > leadingSamplesToSkip
          ? leadingSamplesToSkip
          : 0;
      final count = volts.length - start;
      if (count < 16) continue;
      final times = WaveformConverter.computeTimeAxis(
        volts.length,
        raw.trdl,
        raw.timebase,
        raw.sampleRate,
        triggerPosition: raw.triggerPosition,
        sparsing: raw.sparsing,
      );
      final values = Float64List(count);
      final adjustedTimes = Float64List(count);
      for (var i = 0; i < count; i++) {
        values[i] = volts[start + i];
        adjustedTimes[i] = times[start + i];
      }
      return WaveformTrace(times: adjustedTimes, volts: values, channel: id);
    }
    return null;
  }

  /// Runs one dedicated digital measurement for the DigitalAgent.
  Future<Map<String, dynamic>> _digitalMeasurementForAi(
    DigitalMeasurementRequest request,
  ) async {
    if (!_waveformAcquired || _lastRawData == null) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    final trace = _digitalTraceForChannel(request.channel);
    if (trace == null) {
      return <String, dynamic>{
        'error':
            'No acquired waveform data is available for '
            '${request.channel ?? 'the first channel'}. Acquire the channel '
            'first.',
      };
    }
    switch (request.type) {
      case DigitalMeasurementType.riseFallTime:
        final features = await _waveformAnalysisService.featuresAsync(trace);
        return digitalRiseFallTime(features, channel: trace.channel);
      case DigitalMeasurementType.pulseWidth:
        return digitalPulseWidth(trace, channel: trace.channel);
      case DigitalMeasurementType.edgeStatistics:
        return digitalEdgeStatistics(
          trace,
          channel: trace.channel,
          edge: request.edge,
        );
      case DigitalMeasurementType.jitter:
        return digitalJitter(trace, channel: trace.channel);
      case DigitalMeasurementType.clockStability:
        return digitalClockStability(
          trace,
          channel: trace.channel,
          nominalFrequencyHz: request.nominalFrequencyHz,
        );
      case DigitalMeasurementType.setupHold:
        final dataTrace = _digitalTraceForChannel(request.channelB);
        if (dataTrace == null) {
          return <String, dynamic>{
            'error':
                'No acquired waveform data is available for the data channel '
                '${request.channelB ?? ''}.',
          };
        }
        return digitalSetupHold(
          trace,
          dataTrace,
          clockEdge: request.clockEdge,
          clockThresholdVolts: request.thresholdVolts,
          dataThresholdVolts: request.thresholdVolts,
        );
      case DigitalMeasurementType.skew:
        final traceB = _digitalTraceForChannel(request.channelB);
        if (traceB == null) {
          return <String, dynamic>{
            'error':
                'No acquired waveform data is available for channel B '
                '${request.channelB ?? ''}.',
          };
        }
        return digitalSkew(
          trace,
          traceB,
          edge: request.edge,
          thresholdA: request.thresholdVolts,
          thresholdB: request.thresholdVolts,
        );
      case DigitalMeasurementType.glitches:
        return digitalGlitches(
          trace,
          channel: trace.channel,
          maxPulseWidthSeconds: request.maxPulseWidthSeconds,
          thresholdVolts: request.thresholdVolts,
        );
      case DigitalMeasurementType.overshootUndershoot:
        final features = await _waveformAnalysisService.featuresAsync(trace);
        return digitalOvershootUndershoot(features, channel: trace.channel);
    }
  }

  /// Runs a host-managed digital frequency series for the DigitalAgent.
  ///
  /// The series preserves the generator waveform, amplitude and offset, only
  /// steps the frequency and restores the device state afterwards.
  Future<DigitalFrequencySeriesData?> _digitalFrequencySeriesForAi(
    DigitalFrequencySeriesRequest request,
  ) async {
    final generator = _sigGenService;
    if (generator == null) {
      throw const DigitalFrequencySeriesException(
        'The signal generator is not configured. Select a JDS6600 or FY6900 '
        'in the settings before starting a frequency series.',
        code: 'SERIES_NO_GENERATOR',
      );
    }
    if (!generator.isConnected) {
      throw const DigitalFrequencySeriesException(
        'The signal generator is not connected. Check its USB connection and '
        'the selected serial port, then retry.',
        code: 'SERIES_GENERATOR_OFFLINE',
      );
    }
    final channel = int.tryParse(
      request.channel.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (channel == null || channel < 1 || channel > 4) {
      throw const DigitalFrequencySeriesException(
        'Choose a scope channel between ch1 and ch4.',
        code: 'SERIES_INVALID_CHANNEL',
      );
    }

    _sigGenDetector?.setPaused(true);
    generator.setPanelActive(false);
    if (mounted) _setState(() {});
    try {
      await generator.refreshAll();
      final service = FrequencySeriesService(
        signalGenerator: generator,
        scope: Vxi11FrequencySeriesScope(_getInstrument),
      );
      final useCurrentSettings = request.useCurrentSettings;
      final waveform = Jds6600Waveform.fromScpi(request.waveform);
      if (!useCurrentSettings && waveform == null) {
        throw DigitalFrequencySeriesException(
          'The generator waveform "${request.waveform}" is not supported.',
          code: 'SERIES_INVALID_WAVEFORM',
        );
      }
      final amplitude = request.amplitudeVpp;
      if (!useCurrentSettings &&
          (amplitude == null || !amplitude.isFinite || amplitude <= 0)) {
        throw const DigitalFrequencySeriesException(
          'The generator amplitude is required when the current settings are '
          'not kept.',
          code: 'SERIES_INVALID_AMPLITUDE',
        );
      }
      final result = await service.runQuantities(
        FrequencySeriesQuantitiesConfig(
          frequenciesHz: request.frequenciesHz,
          channel: channel,
          quantities: digitalFrequencySeriesQuantities,
          generatorChannel: request.generatorChannel,
          generatorWaveform: useCurrentSettings ? null : waveform,
          amplitudeVpp: useCurrentSettings ? null : amplitude,
          offsetV: useCurrentSettings ? null : (request.offsetV ?? 0),
          settling: Duration(milliseconds: request.settlingMs),
        ),
        cancelToken: request.cancelToken,
      );
      return DigitalFrequencySeriesData(
        points: <DigitalFrequencySeriesPoint>[
          for (final point in result.points)
            DigitalFrequencySeriesPoint(
              frequencyHz: point.frequencyHz,
              values: point.values,
              valid: point.valid,
              note: point.note,
            ),
        ],
        configSummary: result.configSummary,
      );
    } on DigitalFrequencySeriesException {
      rethrow;
    } on AudioFrequencySeriesException catch (error) {
      throw DigitalFrequencySeriesException(
        error.message,
        code: error.code,
        hint: error.hint,
      );
    } on Object catch (error) {
      AppLogger().warning('Digital frequency series for AI failed: $error');
      throw DigitalFrequencySeriesException(
        'The digital frequency series failed: $error',
        code: 'SERIES_FAILED',
      );
    } finally {
      _sigGenDetector?.setPaused(false);
      generator.setPanelActive(_sigGenWindowOpen);
      if (mounted) _setState(() {});
    }
  }
}
