part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeSnapshots on _OsciHomePageState {
  /// Stores the current acquisition in the four-entry Waveform AI history.
  ///
  /// Manual and AI-triggered acquisitions both pass through
  /// [_acquireWaveform], so the history always reflects the last four captures.
  void _recordWaveformHistory() {
    final summary = _waveformSummaryForAi();
    if (summary == null) return;
    _waveformHistory.add(summary);
  }

  /// Last four acquisitions for the `read_waveform_history` tool.
  List<Map<String, dynamic>> _waveformHistoryForAi() =>
      _waveformHistory.entries;

  /// Runs a complete acquisition for the `acquire_waveform` tool.
  ///
  /// Returns a structured error instead of throwing so the agent can explain
  /// the failure. The acquisition itself updates the chart and measurements
  /// and appends to the history.
  Future<Map<String, dynamic>> _acquireWaveformForAi() async {
    if (_isAcquiringWaveform) {
      return {'error': 'A waveform acquisition is already running.'};
    }
    if (!_isOnline) {
      return {'error': 'The oscilloscope is offline.'};
    }
    final generation = _acquisitionGeneration;
    // An AI-triggered refresh (for example the automatic refresh after ASET)
    // updates the data but must not close the panel the user is working in.
    await _acquireWaveform(keepPanels: true);
    if (_acquisitionGeneration == generation) {
      return {
        'error':
            'The waveform acquisition failed. Check the connection and the '
            'application log.',
      };
    }
    final summary = _waveformSummaryForAi();
    if (summary == null) {
      return {
        'error': 'The acquisition completed but no measurements are available.',
      };
    }
    return {'acquired': true, 'measurements': summary};
  }

  /// Compact description of the displayed waveform for the Control Panel AI's
  /// `read_waveform_summary` tool.
  ///
  /// Returns null while no waveform is displayed so the tool can tell the user
  /// to acquire one first. The values are the already computed measurements;
  /// the assistant only explains them and never recalculates them.
  Map<String, dynamic>? _waveformSummaryForAi() {
    if (!_waveformAcquired) return null;
    final measurements = _currentMeasurements();
    if (measurements.isEmpty && _refWaveform == null) return null;

    final params = _deviceParams;
    final comparison = _comparison;
    final mask = _maskResult;
    final fftPreparation = _fftPreparationForAi();

    return <String, dynamic>{
      'displayed': true,
      'channels': {
        for (final entry in measurements.entries)
          entry.key: _measurementSummaryForAi(entry.value, params),
      },
      'fftPreparation': ?fftPreparation,
      if (params != null)
        'device': {
          'timebaseSecondsPerDiv': params.timebase,
          'triggerDelaySeconds': params.trdl,
          'sampleRatePerSecond': params.sampleRate,
        },
      if (_refWaveform != null)
        'reference': {
          'fileName': _refFileName,
          'sourceChannel': _refChannelOrigin,
          'visible': _refVisible,
          'verticalScaleVoltsPerDiv': _refVdivVolts,
          'offsetVolts': _refOffsetVolts,
          'timebaseSecondsPerDiv': _refMetadata?.timebaseSecondsPerDiv,
          'triggerDelaySeconds': _refMetadata?.triggerDelaySeconds,
          'sampleRatePerSecond': _refMetadata?.sampleRateHz,
          'settingsDifferFromCurrent': [
            for (final mismatch in _referenceTimingMismatches())
              {
                'setting': mismatch.field.name,
                'referenceValue': mismatch.referenceValue,
                'currentValue': mismatch.currentValue,
              },
          ],
          if (_refMeasurements != null)
            'measurements': _measurementSummaryForAi(
              _refMeasurements!,
              params,
              verticalScaleVoltsPerDiv: _refVdivVolts,
              offsetVolts: _refOffsetVolts,
            ),
        },
      if (comparison != null)
        'referenceComparison': {
          'rmsErrorVolts': comparison.rmsErrorVolts,
          'maxAbsDeviationVolts': comparison.maxAbsDeviationVolts,
          'meanErrorVolts': comparison.meanErrorVolts,
          'coveragePercent': comparison.coveragePercent,
        },
      if (_maskSettings.enabled && mask != null)
        'mask': {
          'passed': mask.passed,
          'violations': mask.violations,
          'checkedPoints': mask.checkedPoints,
          'maxViolationVolts': mask.maxViolationVolts,
          'toleranceValue': _maskSettings.toleranceValue,
          'toleranceIsPercentOfVpp': _maskSettings.usePercent,
        },
    };
  }

  /// Deterministic FFT timebase preparation for the current acquisition.
  ///
  /// Agents must quote these values verbatim instead of deriving a timebase
  /// from `timebaseSecondsPerDiv` or `sampleRatePerSecond`. The trigger-source
  /// channel wins; when it has no reliable frequency the first acquired
  /// channel with a periodic signal is used.
  Map<String, Object?>? _fftPreparationForAi() {
    final trigger = _triggerSourceMeasurement;
    final candidates = <WaveformMeasurements>[
      ?trigger,
      ..._currentMeasurements().values,
      ..._acquiredMeasurements().values,
    ];
    for (final measurement in candidates) {
      final preparation = fftPreparationForMeasurement(measurement);
      if (preparation != null) return preparation;
    }
    return null;
  }

  /// Spectrum analysis of the displayed waveform for the Waveform AI's
  /// `read_spectrum_summary` tool.
  ///
  /// The spectrum is computed on demand with the current settings, so the
  /// assistant sees the same data as the Spectrum tab even when it has not
  /// been opened yet. Returns null while no waveform is displayed.
  Future<Map<String, dynamic>?> _spectrumSummaryForAi() async {
    if (!_waveformAcquired || _lastRawData == null) return null;

    SpectrumResult? result;
    try {
      result = await _spectrumForReport();
    } catch (e) {
      AppLogger().warning('Spectrum summary for AI failed: $e');
      return null;
    }
    if (result == null) return null;

    final settings = result.settings;
    return <String, dynamic>{
      'available': true,
      'viewMode': _effectiveWaveformViewMode.name,
      'selectedChannel': _spectrumChannel,
      'showAllChannels': _spectrumShowAll,
      'settings': {
        'window': settings.window.name,
        'requestedFftSize': settings.fftSize == 0 ? 'auto' : settings.fftSize,
        'maxFftSize': settings.maxFftSize,
        'unit': settings.unit.name,
        'removeDc': settings.removeDc,
        'peakCount': settings.peakCount,
        'harmonicCount': settings.harmonicCount,
        'leadingSamplesSkipped': settings.leadingSamplesToSkip,
      },
      'channels': [
        for (final trace in result.traces)
          {
            'channel': trace.channel,
            'fftSize': trace.fftSize,
            'sampleRateHz': trace.sampleRate,
            'frequencyResolutionHz': trace.resolutionHz,
            'fullScaleVolts': trace.fullScaleVolts,
            'metrics': {
              'fundamentalFrequencyHz': _finiteOrNull(
                trace.metrics.fundamentalHz,
              ),
              'fundamentalAmplitudeVpk': _finiteOrNull(
                trace.metrics.fundamentalVpk,
              ),
              'fundamentalDbfs': _finiteOrNull(trace.metrics.fundamentalDbfs),
              'thdPercent': _finiteOrNull(trace.metrics.thdPercent),
              'thdDb': _finiteOrNull(trace.metrics.thdDb),
              'thdPlusNoiseDb': _finiteOrNull(trace.metrics.thdPlusNDb),
              'snrDb': _finiteOrNull(trace.metrics.snrDb),
              'sinadDb': _finiteOrNull(trace.metrics.sinadDb),
              'enobBits': _finiteOrNull(trace.metrics.enobBits),
              'sfdrDbc': _finiteOrNull(trace.metrics.sfdrDb),
              'noiseFloorDbfs': _finiteOrNull(trace.metrics.noiseFloorDbfs),
              'harmonicsUsed': trace.metrics.harmonicsUsed,
              'nyquistHz': _finiteOrNull(trace.metrics.nyquistHz),
              'resolutionHz': _finiteOrNull(trace.metrics.resolutionHz),
            },
            'peaks': [
              for (final peak in trace.peaks)
                {
                  'marker': peak.marker,
                  'frequencyHz': _finiteOrNull(peak.frequencyHz),
                  'amplitudeVpk': _finiteOrNull(peak.amplitudeVpk),
                  'levelDb': _finiteOrNull(peak.levelDb),
                  'dbfs': _finiteOrNull(peak.dbfs),
                  'relativeToFundamentalDb': _finiteOrNull(
                    peak.relativeToFundamentalDb,
                  ),
                  'isFundamental': peak.isFundamental,
                },
            ],
          },
      ],
    };
  }

  /// JSON-safe representation of a spectrum value.
  ///
  /// THD, SINAD, ENOB and similar metrics are infinite or NaN for signals
  /// without a usable carrier (for example pure noise), and JSON has no
  /// representation for those values.
  double? _finiteOrNull(double value) => value.isFinite ? value : null;
}
