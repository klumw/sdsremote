part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiFaults on _OsciHomePageState {
  Future<Map<String, dynamic>> _analyzeWaveformFaultsForAi({
    required List<String> tests,
    String? channel,
    String? channelB,
    Map<String, dynamic>? specification,
  }) async {
    final raw = _lastRawData;
    if (!_waveformAcquired || raw == null) {
      return <String, dynamic>{
        'error': 'No raw waveform data is available. Acquire a waveform first.',
      };
    }
    final primary = _faultTraceForChannel(channel);
    if (primary == null) {
      return <String, dynamic>{
        'error':
            'No raw waveform data is available for '
            '${channel ?? 'the first acquired channel'}.',
      };
    }
    final requested = <WaveformFaultTest>[];
    final invalid = <String>[];
    for (final id in tests) {
      final test = WaveformFaultTest.parse(id);
      if (test == null) {
        invalid.add(id);
      } else if (!requested.contains(test)) {
        requested.add(test);
      }
    }
    if (invalid.isNotEmpty) {
      return <String, dynamic>{
        'error':
            'Unknown fault test(s): ${invalid.join(', ')}. Valid tests: '
            '${WaveformFaultTest.values.map((test) => test.id).join(', ')}.',
      };
    }
    WaveformTrace? secondaryTrace;
    if (channelB != null && channelB.trim().isNotEmpty) {
      final secondary = _faultTraceForChannel(channelB);
      if (secondary == null) {
        return <String, dynamic>{
          'error': 'No raw waveform data is available for ${channelB.trim()}.',
        };
      }
      if (secondary.trace.channel == primary.trace.channel) {
        return <String, dynamic>{
          'error':
              'Choose two different channels for phase or crosstalk '
              'analysis.',
        };
      }
      secondaryTrace = secondary.trace;
    }
    final spec = specification ?? const <String, dynamic>{};
    final artifactValue = spec['measurement_artifacts'];
    final artifactSpec = artifactValue is Map
        ? Map<String, dynamic>.from(artifactValue)
        : const <String, dynamic>{};
    final probe = _faultNumberFrom(artifactSpec['probeAttenuation']);
    final adcBits = _faultNumberFrom(artifactSpec['adcBits'])?.round() ?? 8;
    final triggerLevel = _faultNumberFrom(artifactSpec['triggerLevelVolts']);
    final requests = requested.isEmpty
        ? [
            for (final test in WaveformFaultTest.values)
              WaveformFaultRequest(
                test: test,
                specification: _faultSpecificationForTest(spec, test),
              ),
          ]
        : [
            for (final test in requested)
              WaveformFaultRequest(
                test: test,
                specification: _faultSpecificationForTest(spec, test),
              ),
          ];
    final context = WaveformFaultContext(
      trace: primary.trace,
      channel: primary.trace.channel ?? 'ch1',
      secondTrace: secondaryTrace,
      secondChannel: secondaryTrace?.channel,
      sampleRateHz: raw.effectiveSampleRate,
      verticalScaleVoltsPerDiv: _rawVdiv(raw, primary.trace.channel),
      verticalOffsetVolts: _rawVoffset(raw, primary.trace.channel),
      timebaseSecondsPerDiv: raw.timebase,
      adcBits: adcBits <= 0 ? 8 : adcBits,
      probeAttenuation: probe ?? 1.0,
      probeAttenuationAssumed: probe == null,
      triggerLevelVolts: triggerLevel,
      triggerPosition: raw.triggerPosition,
      triggerDelaySeconds: raw.trdl,
      leadingSamplesExcluded: primary.leadingSamplesExcluded,
    );
    try {
      final report = await Isolate.run(
        () => const WaveformFaultAnalyzer().analyze(context, requests),
      );
      return report.toMap();
    } on Object catch (error) {
      AppLogger().error('Waveform fault analysis failed: $error');
      return <String, dynamic>{
        'error': 'Waveform fault analysis failed: $error',
      };
    }
  }

  /// Builds a trace from the complete raw channel data.
  ///
  /// The returned trace contains every transferred sample except the leading
  /// acquisition artifact that the display conversion also removes.
  ({WaveformTrace trace, int leadingSamplesExcluded})? _faultTraceForChannel(
    String? channel,
  ) {
    final raw = _lastRawData;
    if (raw == null) return null;
    final requested = channel?.trim().toLowerCase();
    final selected = requested == null || requested.isEmpty
        ? _defaultAnalysisChannel()
        : requested;
    if (selected == null) return null;
    final bytes = switch (selected) {
      'ch1' => raw.ch1Raw,
      'ch2' => raw.ch2Raw,
      'ch3' => raw.ch3Raw,
      'ch4' => raw.ch4Raw,
      _ => null,
    };
    final vdiv = _rawVdiv(raw, selected);
    final voffset = _rawVoffset(raw, selected);
    if (bytes == null || bytes.isEmpty || vdiv == null || voffset == null) {
      return null;
    }
    final voltages = WaveformConverter.convertVoltages(bytes, vdiv, voffset);
    final times = WaveformConverter.computeTimeAxis(
      voltages.length,
      raw.trdl,
      raw.timebase,
      raw.sampleRate,
      triggerPosition: raw.triggerPosition,
      sparsing: raw.sparsing,
    );
    const int leadingSamplesToSkip = 8;
    final start = voltages.length > leadingSamplesToSkip * 4
        ? leadingSamplesToSkip
        : 0;
    if (voltages.length - start < 2) return null;
    return (
      trace: WaveformTrace(
        times: Float64List.fromList([
          for (var index = start; index < voltages.length; index++)
            times[index],
        ]),
        volts: Float64List.fromList([
          for (var index = start; index < voltages.length; index++)
            voltages[index],
        ]),
        channel: selected,
      ),
      leadingSamplesExcluded: start,
    );
  }

  Map<String, dynamic> _faultSpecificationForTest(
    Map<String, dynamic> specification,
    WaveformFaultTest test,
  ) {
    final nested = specification[test.id];
    return nested is Map
        ? Map<String, dynamic>.from(nested)
        : const <String, dynamic>{};
  }

  double? _rawVdiv(WaveformRawData raw, String? channel) => switch (channel) {
    'ch1' => raw.vdivCh1,
    'ch2' => raw.vdivCh2,
    'ch3' => raw.vdivCh3,
    'ch4' => raw.vdivCh4,
    _ => null,
  };

  double? _rawVoffset(WaveformRawData raw, String? channel) =>
      switch (channel) {
        'ch1' => raw.voffsetCh1,
        'ch2' => raw.voffsetCh2,
        'ch3' => raw.voffsetCh3,
        'ch4' => raw.voffsetCh4,
        _ => null,
      };

  double? _faultNumberFrom(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// `manage_fault_analysis_profile` provider for the Waveform AI.
  ///
  /// The profile is a JSON file below the application data directory. It
  /// stores only user-supplied specifications, per channel, and never
  /// measured values or analysis results.
  Future<Map<String, dynamic>> _manageFaultAnalysisProfileForAi({
    required String action,
    String? channel,
    Map<String, dynamic>? specification,
    String? mode,
  }) async {
    try {
      switch (action.trim().toLowerCase()) {
        case 'read':
          return await _waveformFaultProfileStore.read(channel: channel);
        case 'save':
          if (channel == null || channel.trim().isEmpty) {
            return <String, dynamic>{'error': 'channel is required for save.'};
          }
          return await _waveformFaultProfileStore.save(
            channel: channel,
            specification: specification ?? const <String, dynamic>{},
            mode: mode ?? 'replace',
          );
        case 'clear':
          return await _waveformFaultProfileStore.clear(channel: channel);
        default:
          return <String, dynamic>{
            'error':
                'Unknown profile action "$action". Valid actions: read, save, '
                'clear.',
          };
      }
    } on Object catch (error) {
      AppLogger().error('Fault analysis profile operation failed: $error');
      return <String, dynamic>{
        'error': 'Fault analysis profile operation failed: $error',
      };
    }
  }
}
