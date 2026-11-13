part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiAudio on _OsciHomePageState {
  /// `analyze_waveform_faults` provider for the Waveform AI.
  ///
  /// The analysis runs on the complete raw acquisition, not on the decimated
  /// display copy. A background isolate keeps the UI responsive for long
  /// records.
  /// Builds the audio analysis snapshot for the AudioAgent.
  ///
  /// The snapshot contains every acquired channel as a uniformly sampled
  /// voltage record. The known leading acquisition artifact is removed and
  /// the full scale is derived from V/div, matching the spectrum analysis.
  AudioAnalysisContext? _audioAnalysisContextForAi() {
    final raw = _lastRawData;
    if (!_waveformAcquired || raw == null) return null;
    final channels = <String, AudioChannelData>{};
    for (final id in const ['ch1', 'ch2', 'ch3', 'ch4']) {
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
      final voltages = WaveformConverter.convertVoltages(bytes, vdiv, voffset);
      const leadingSamplesToSkip = 8;
      final start = voltages.length > leadingSamplesToSkip * 4
          ? leadingSamplesToSkip
          : 0;
      final count = voltages.length - start;
      if (count < 16) continue;
      final samples = Float64List(count);
      for (var i = 0; i < count; i++) {
        samples[i] = voltages[start + i];
      }
      channels[id] = AudioChannelData(
        label: id,
        samples: samples,
        sampleRateHz: raw.effectiveSampleRate,
        fullScaleVolts: 128.0 * vdiv / 25.0,
        verticalScaleVoltsPerDiv: vdiv,
        verticalOffsetVolts: voffset,
        leadingSamplesRemoved: start,
      );
    }
    if (channels.isEmpty) return null;
    return AudioAnalysisContext(
      channels: channels,
      deviceName: _deviceName ?? _ipAddress,
      adcBits: 8,
    );
  }

  /// Runs a Bode sweep for the AudioAgent's sweep-based tools.
  ///
  /// The sweep uses a dedicated service so the Bode panel keeps its own
  /// state. The generator detector and panel are paused during the sweep,
  /// and the service restores the scope state in its own cleanup path.
  ///
  /// Throws [AudioSweepException] with the concrete cause when the sweep
  /// cannot run, so the audio tools can report the missing prerequisite
  /// instead of a generic "not available" message.
  Future<AudioSweepData?> _audioSweepForAi(AudioSweepRequest request) async {
    final generator = _sigGenService;
    if (generator == null) {
      throw const AudioSweepException(
        'The signal generator is not configured. Select a JDS6600 or FY6900 '
        'in the settings before starting a Bode sweep.',
        code: 'SWEEP_NO_GENERATOR',
      );
    }
    if (!generator.isConnected) {
      throw const AudioSweepException(
        'The signal generator is not connected. Check its USB connection and '
        'the selected serial port, then retry the sweep.',
        code: 'SWEEP_GENERATOR_OFFLINE',
      );
    }
    if (_bodeIsRunning) {
      throw const AudioSweepException(
        'Another Bode sweep is already running. Wait for it to finish, then '
        'retry the sweep.',
        code: 'SWEEP_BUSY',
      );
    }
    final cancelToken = request.cancelToken;
    if (cancelToken?.isCancelled == true) {
      throw const AudioSweepException(
        'The Bode sweep was cancelled.',
        code: 'SWEEP_CANCELLED',
      );
    }
    final requestedPoints = request.pointCount;
    final points = requestedPoints.clamp(2, 50).toInt();
    // The sweep changes the generator's CH1 waveform, frequency, amplitude and
    // offset. Refresh and snapshot them so the host can restore them without a
    // separate agent tool round trip after the sweep.
    try {
      await generator.refreshAll();
    } on Object catch (error) {
      AppLogger().warning('Generator refresh before Bode sweep failed: $error');
    }
    final ch1Before = generator.ch1;
    final service = BodePlotService(
      signalGenerator: generator,
      scope: Vxi11BodeScope(_getInstrument),
    );
    void stopSweep() {
      unawaited(service.stop());
    }

    cancelToken?.addListener(stopSweep);
    _bodeIsRunning = true;
    _sigGenDetector?.setPaused(true);
    generator.setPanelActive(false);
    if (mounted) _setState(() {});
    try {
      final useCurrentSettings = request.useCurrentGeneratorSettings;
      final generatorChannel = request.generatorChannel;
      final currentSettings = generator.channel(generatorChannel);
      final parsedWaveform = Jds6600Waveform.fromScpi(request.waveform);
      if (!useCurrentSettings && parsedWaveform == null) {
        throw AudioSweepException(
          'The generator waveform "${request.waveform}" is not supported.',
          code: 'SWEEP_INVALID_WAVEFORM',
        );
      }
      final amplitude = useCurrentSettings
          ? currentSettings.amplitudeVpp
          : request.amplitudeVpp;
      if (amplitude == null || !amplitude.isFinite || amplitude <= 0) {
        throw const AudioSweepException(
          'The generator amplitude is not usable. Set a positive amplitude or '
          'keep a configured generator signal.',
          code: 'SWEEP_INVALID_AMPLITUDE',
        );
      }
      final effectiveWaveform = useCurrentSettings
          ? currentSettings.waveform
          : parsedWaveform!;
      final effectiveOffset = useCurrentSettings
          ? currentSettings.offsetV
          : (request.offsetV ?? 0);
      AppLogger(agentName: 'AudioSweep', toolName: 'request').log(
        'Sweep request: start=${request.startFrequencyHz} Hz, '
        'stop=${request.stopFrequencyHz} Hz, points=$points, '
        'useCurrentGeneratorSettings=$useCurrentSettings, '
        'waveform=${effectiveWaveform.name}, amplitude=$amplitude Vpp, '
        'offset=$effectiveOffset V, generatorChannel=$generatorChannel',
      );
      await service.start(
        BodeConfig(
          startFrequencyHz: request.startFrequencyHz,
          stopFrequencyHz: request.stopFrequencyHz,
          pointCount: points,
          measurePhase: request.measurePhase,
          amplitudeVpp: amplitude,
          offsetV: effectiveOffset,
          waveform: effectiveWaveform,
          useCurrentGeneratorSettings: useCurrentSettings,
          settling: const Duration(milliseconds: 1000),
          vinChannel: 1,
          voutChannel: 2,
          generatorChannel: generatorChannel,
          turnOffOutputsAfterSweep: true,
        ),
      );
      if (service.status == BodeStatus.error) {
        throw AudioSweepException(
          service.errorMessage ?? 'The Bode sweep failed.',
          code: 'SWEEP_FAILED',
          hint:
              'The sweep needs a connected signal generator, the generator '
              'signal on CH1 (Vin) and the DUT output on CH2 (Vout). The '
              'scope traces are enabled by the sweep.',
        );
      }
      if (service.status == BodeStatus.cancelled) {
        throw const AudioSweepException(
          'The Bode sweep was cancelled.',
          code: 'SWEEP_CANCELLED',
        );
      }
      if (service.status != BodeStatus.completed) {
        throw AudioSweepException(
          'The Bode sweep did not complete (status: ${service.status.name}).',
          code: 'SWEEP_INCOMPLETE',
        );
      }
      if (service.points.isEmpty) {
        throw const AudioSweepException(
          'The Bode sweep completed without any measurement points.',
          code: 'SWEEP_EMPTY',
        );
      }
      return AudioSweepData(
        points: [
          for (final point in service.points)
            AudioSweepPoint(
              frequencyHz: point.frequencyHz,
              gainDb: point.gainDb,
              phaseDeg: point.phaseDeg,
              vinRms: point.vinRms,
              voutRms: point.voutRms,
              valid: point.valid,
              note: point.note,
            ),
        ],
        source: 'bode_sweep',
        configSummary:
            '${request.startFrequencyHz}…${request.stopFrequencyHz} Hz, '
            '$points points'
            '${points != requestedPoints ? ' (clamped from $requestedPoints)' : ''}, '
            'phase=${request.measurePhase}, '
            'generator=${useCurrentSettings ? 'current' : 'configured'} '
            '(${effectiveWaveform.name}, $amplitude Vpp, '
            'offset $effectiveOffset V)',
      );
    } on AudioSweepException {
      rethrow;
    } on Object catch (error) {
      AppLogger().warning('Audio sweep for AI failed: $error');
      throw AudioSweepException(
        'The Bode sweep failed: $error',
        code: 'SWEEP_FAILED',
      );
    } finally {
      cancelToken?.removeListener(stopSweep);
      _bodeIsRunning = false;
      _sigGenDetector?.setPaused(false);
      generator.setPanelActive(_sigGenWindowOpen);
      // Restore the pre-sweep CH1 parameters here so the agent does not need
      // an extra generator tool call after the sweep. Outputs stay off for
      // safety (the sweep config above uses turnOffOutputsAfterSweep).
      try {
        await generator.setWaveform(1, ch1Before.waveform);
        await generator.setAmplitude(1, ch1Before.amplitudeVpp);
        await generator.setOffset(1, ch1Before.offsetV);
        await generator.setFrequency(1, ch1Before.frequencyHz);
      } on Object catch (error) {
        AppLogger().warning(
          'Generator restore after Bode sweep failed: $error',
        );
      }
      service.dispose();
      if (mounted) _setState(() {});
    }
  }

  /// Runs a host-managed level series at explicit frequencies for the
  /// AudioAgent. The service configures the generator, adjusts the scope and
  /// restores both afterwards.
  Future<AudioFrequencySeriesData?> _audioFrequencySeriesForAi(
    AudioFrequencySeriesRequest request,
  ) async {
    final generator = _sigGenService;
    if (generator == null) {
      throw const AudioFrequencySeriesException(
        'The signal generator is not configured. Select a JDS6600 or FY6900 '
        'in the settings before starting a frequency series.',
        code: 'SERIES_NO_GENERATOR',
      );
    }
    if (!generator.isConnected) {
      throw const AudioFrequencySeriesException(
        'The signal generator is not connected. Check its USB connection and '
        'the selected serial port, then retry.',
        code: 'SERIES_GENERATOR_OFFLINE',
      );
    }
    final channel = int.tryParse(
      request.channel.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (channel == null || channel < 1 || channel > 4) {
      throw const AudioFrequencySeriesException(
        'Choose a scope channel between ch1 and ch4.',
        code: 'SERIES_INVALID_CHANNEL',
      );
    }

    _sigGenDetector?.setPaused(true);
    generator.setPanelActive(false);
    if (mounted) _setState(() {});
    try {
      final service = FrequencySeriesService(
        signalGenerator: generator,
        scope: Vxi11FrequencySeriesScope(_getInstrument),
      );
      final waveform = Jds6600Waveform.fromScpi(request.waveform);
      if (!request.useCurrentSettings && waveform == null) {
        throw AudioFrequencySeriesException(
          'The generator waveform "${request.waveform}" is not supported.',
          code: 'SERIES_INVALID_WAVEFORM',
        );
      }
      final result = await service.run(
        FrequencySeriesConfig(
          frequenciesHz: request.frequenciesHz,
          channel: channel,
          quantity: request.quantity,
          amplitudeVpp: request.amplitudeVpp,
          waveform: waveform ?? Jds6600Waveform.sine,
          useCurrentGeneratorSettings: request.useCurrentSettings,
          generatorChannel: request.generatorChannel,
          settling: Duration(milliseconds: request.settlingMs),
        ),
        cancelToken: request.cancelToken,
      );
      final unit = request.quantity == 'vrms' ? 'Vrms' : 'Vpp';
      return AudioFrequencySeriesData(
        points: [
          for (final point in result.points)
            AudioFrequencySeriesPoint(
              frequencyHz: point.frequencyHz,
              value: point.value,
              unit: unit,
              valid: point.valid,
              note: point.note,
            ),
        ],
        quantity: result.quantity,
        configSummary: result.configSummary,
      );
    } on AudioFrequencySeriesException {
      rethrow;
    } on Object catch (error) {
      AppLogger().warning('Frequency series for AI failed: $error');
      throw AudioFrequencySeriesException(
        'The frequency series failed: $error',
        code: 'SERIES_FAILED',
      );
    } finally {
      _sigGenDetector?.setPaused(false);
      generator.setPanelActive(_sigGenWindowOpen);
      if (mounted) _setState(() {});
    }
  }
}
