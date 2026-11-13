part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAcquisition on _OsciHomePageState {
  Future<void> _acquireScreenDump({bool keepPanels = false}) async {
    if (_isAcquiring || _isAcquiringWaveform || _timelapseRunning) return;

    // Stop the Data Logger immediately when switching away from it
    if (!keepPanels && _activePanel == ActivePanel.dataLogger) {
      _stopDataLoggerIfRunning();
      _stopBodeIfRunning();
    }

    _setState(() {
      _isAcquiring = true;
      if (!keepPanels) {
        _activePanel = ActivePanel.none;
        _previousPanel = ActivePanel.none;
      }
    });

    try {
      final instr = await _getInstrument();
      if (instr == null) return;

      _setState(() => _isOnline = true);
      final data = await instr.getScreenDump();

      final processedData = await compute(processScreenDump, data);

      if (mounted) {
        _setState(() {
          _screenDump = processedData;
          _screenDumpCapturedAt = DateTime.now();
          _waveformCh1 = null;
          _waveformCh2 = null;
          _waveformCh3 = null;
          _waveformCh4 = null;
          _measurementsCh1 = null;
          _measurementsCh2 = null;
          _measurementsCh3 = null;
          _measurementsCh4 = null;
          _measurementHistoryCh1.clear();
          _measurementHistoryCh2.clear();
          _measurementHistoryCh3.clear();
          _measurementHistoryCh4.clear();
          _diffTrace = null;
          _comparison = null;
          _maskBand = null;
          _maskResult = null;
          _deviceParams = null;
          _isOnline = true;
          _waveformAcquired = false;
        });
        // Opening the Control Panel is the moment the Live toggle matters;
        // probe right away instead of waiting for the next ping tick, and
        // restore the live screen when it was active before.
        if (!keepPanels) {
          unawaited(_refreshVncAndRestoreLive());
        }
      }
    } catch (e) {
      if (mounted) {
        AppLogger().error('Acquire display error: $e');
        // If it's a connection error, close the instrument so we retry next time
        _closeInstrument();
      }
      _setState(() {
        _isOnline = false;
      });
      _restoreLiveOnPanelReturn = false;
      _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
      _clearVncAvailability();
    } finally {
      if (mounted) {
        _setState(() {
          _isAcquiring = false;
        });
      }
    }
  }

  /// Acquires a new waveform and updates the analysis view.
  ///
  /// [keepPanels] keeps the currently open panel (for example the main AI
  /// chat) instead of switching to the waveform view. Background refreshes
  /// triggered by an AI scope command use it so the acquisition never
  /// navigates the user away from the conversation.
  Future<void> _acquireWaveform({bool keepPanels = false}) async {
    if (_timelapseRunning) return;
    // Stop the Data Logger immediately when switching away from it
    _stopDataLoggerIfRunning();
    _stopBodeIfRunning();
    _stopAutoCapture();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();

    _setState(() {
      _isAcquiringWaveform = true;
      if (!keepPanels) {
        _activePanel = ActivePanel.none;
        _previousPanel = ActivePanel.none;
      }
      // Clear the previous capture immediately: while the new acquisition is
      // in flight the chart and measurement cards must not keep showing the
      // old trace. The device parameters stay so the grid and axes remain.
      _waveformCh1 = null;
      _waveformCh2 = null;
      _waveformCh3 = null;
      _waveformCh4 = null;
      _measurementsCh1 = null;
      _measurementsCh2 = null;
      _measurementsCh3 = null;
      _measurementsCh4 = null;
      _lastRawData = null;
      _spectrumResult = null;
      _diffTrace = null;
      _comparison = null;
      _maskBand = null;
      _maskResult = null;
    });

    try {
      final instr = await _getInstrument();
      final bool fourChannel = _numChannels >= 4;
      final raw = await WaveformAcquisition(_ipAddress).acquire(
        ch1: _ch1Enabled,
        ch2: _ch2Enabled,
        ch3: fourChannel && _ch3Enabled,
        ch4: fourChannel && _ch4Enabled,
        instr: instr,
      );

      String? triggerSourceChannel;
      var triggerSourceQueried = false;
      try {
        final triggerResponse = await instr?.queryString('TRSE?');
        if (triggerResponse != null) {
          triggerSourceChannel = ScpiParser.parseTriggerSourceChannel(
            triggerResponse,
          );
          triggerSourceQueried = true;
        }
      } catch (e) {
        AppLogger().warning('Failed to query trigger source: $e');
      }

      // Run conversion on the main thread instead of via compute() because
      // Dart's isolate serialization does not support record types
      // ((double, double) pairs) — they get silently truncated to ~726 points
      // instead of the full 1201 points sent by the scope (WFSU NP=1201).
      final result = convertRawData(raw);
      // Measure the raw samples before the display decimation so rise/fall
      // times and overshoot keep the full acquisition resolution.
      final measurements = _measureRawChannels(raw);

      _setState(() {
        _waveformCh1 = result.$1;
        _waveformCh2 = result.$2;
        _waveformCh3 = result.$3;
        _waveformCh4 = result.$4;
        _measurementsCh1 = measurements.$1;
        _measurementsCh2 = measurements.$2;
        _measurementsCh3 = measurements.$3;
        _measurementsCh4 = measurements.$4;
        _recordMeasurementHistory(measurements);
        _deviceParams = result.$5;
        if (triggerSourceQueried) {
          _triggerSourceChannel = triggerSourceChannel;
        }
        _screenDump = null;
        _screenDumpCapturedAt = null;
        _isOnline = true;
        _waveformAcquired = true;
        _lastRawData = raw;
        _spectrumResult = null;
        _spectrumLoading = false;
        // Invalidate an in-flight spectrum computation from the previous
        // acquisition so it cannot publish stale FFT values.
        _spectrumGeneration++;
        if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum &&
            !_hasEnoughSpectrumData) {
          _waveformViewMode = _WaveformViewMode.time;
        }
        _acquisitionGeneration++;
        // Reset zoom state on every new acquisition so the user sees the full
        // waveform (14 divisions) instead of a zoomed-in view from a previous
        // interaction that showed only ~4 waves.
        _zoomState = const ZoomState();
      });
      _logWaveformMeasurements();
      _recomputeReferenceAnalysis();
      _recordWaveformHistory();
      if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum) {
        unawaited(_recomputeSpectrum());
      }
    } catch (e) {
      AppLogger().error('Acquire waveform error: $e');
      final reason = e is AcquisitionException ? e.reason : e.toString();
      AppLogger().error('Popup: Waveform error: $reason');
      _showErrorSnackBar('Waveform error: $reason');
    } finally {
      if (mounted) {
        _setState(() {
          _isAcquiringWaveform = false;
        });
      }
    }
  }

  /// Measures every acquired raw channel before display decimation.
  ///
  /// Channels that were not acquired, or whose vertical settings are
  /// missing, yield `null`.
  (
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
  )
  _measureRawChannels(WaveformRawData raw) {
    /// Effective interval between the transferred samples of a channel.
    ///
    /// With WFSU sparsing the record contains only every `sparsing`-th
    /// acquisition sample, so the spacing is `sparsing / sampleRate`. This
    /// mirrors `WaveformConverter.computeTimeAxis` and avoids stretching a
    /// short sparsed record over the 14-division display window, which would
    /// scale every measured frequency down by the sparsing factor.
    double? sampleIntervalFor(int rawLength) {
      if (rawLength < 2) return null;
      return raw.effectiveSampleRate > 0 ? 1 / raw.effectiveSampleRate : null;
    }

    WaveformMeasurements? measure(
      String channel,
      Uint8List? data,
      double? vdiv,
      double? voffset,
    ) {
      if (data == null || vdiv == null || voffset == null || data.isEmpty) {
        return null;
      }
      return measureRawChannel(
        channel: channel,
        rawData: data,
        vdiv: vdiv,
        voffset: voffset,
        sampleRate: raw.effectiveSampleRate,
        sampleIntervalSeconds: sampleIntervalFor(data.length),
      );
    }

    return (
      measure('ch1', raw.ch1Raw, raw.vdivCh1, raw.voffsetCh1),
      measure('ch2', raw.ch2Raw, raw.vdivCh2, raw.voffsetCh2),
      measure('ch3', raw.ch3Raw, raw.vdivCh3, raw.voffsetCh3),
      measure('ch4', raw.ch4Raw, raw.vdivCh4, raw.voffsetCh4),
    );
  }

  /// Writes the latest waveform measurements to the debug log.
  ///
  /// The values are consumed by the measurement panel in the next phase; the
  /// debug entry keeps the computation observable in the meantime.
  void _logWaveformMeasurements() {
    for (final measurement in [
      _measurementsCh1,
      _measurementsCh2,
      _measurementsCh3,
      _measurementsCh4,
    ]) {
      if (measurement == null) continue;
      AppLogger().debug(
        'Measurements ${measurement.channel}: '
        'Vpp=${measurement.vPp}, '
        'frequency=${measurement.frequencyHz}, '
        'duty=${measurement.dutyPercent}, '
        'samples=${measurement.sampleCount}, '
        'notes=${measurement.notes}',
      );
    }
  }

  /// Appends the current measurements to the bounded per-channel history.
  void _recordMeasurementHistory(
    (
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
    )
    measurements,
  ) {
    void add(List<WaveformMeasurements> history, WaveformMeasurements? value) {
      if (value == null) return;
      history.add(value);
      if (history.length > _OsciHomePageState._measurementHistoryLimit) {
        history.removeAt(0);
      }
    }

    add(_measurementHistoryCh1, measurements.$1);
    add(_measurementHistoryCh2, measurements.$2);
    add(_measurementHistoryCh3, measurements.$3);
    add(_measurementHistoryCh4, measurements.$4);
  }

  /// Measurements of the channels currently enabled for display.
  Map<String, WaveformMeasurements> _currentMeasurements() {
    final measurements = <String, WaveformMeasurements>{};
    void add(String channel, bool enabled, WaveformMeasurements? value) {
      if (enabled && value != null) measurements[channel] = value;
    }

    add('ch1', _ch1Enabled, _measurementsCh1);
    add('ch2', _ch2Enabled, _measurementsCh2);
    add('ch3', _numChannels >= 4 && _ch3Enabled, _measurementsCh3);
    add('ch4', _numChannels >= 4 && _ch4Enabled, _measurementsCh4);
    return measurements;
  }

  /// All acquired measurements, regardless of the display channel toggles.
  Map<String, WaveformMeasurements> _acquiredMeasurements() => {
    'ch1': ?_measurementsCh1,
    'ch2': ?_measurementsCh2,
    'ch3': ?_measurementsCh3,
    'ch4': ?_measurementsCh4,
  };

  /// Serializes one channel's measurements for [_waveformSummaryForAi].
  Map<String, dynamic> _measurementSummaryForAi(
    WaveformMeasurements measurement,
    DeviceParams? params, {
    double? verticalScaleVoltsPerDiv,
    double? offsetVolts,
  }) => {
    'verticalScaleVoltsPerDiv':
        verticalScaleVoltsPerDiv ?? params?.vdivFor(measurement.channel),
    'offsetVolts': offsetVolts ?? params?.voffsetFor(measurement.channel),
    'vMaxVolts': measurement.vMax,
    'vMinVolts': measurement.vMin,
    'vppVolts': measurement.vPp,
    'meanVolts': measurement.vMean,
    'rmsVolts': measurement.vRms,
    'topVolts': measurement.vTop,
    'baseVolts': measurement.vBase,
    'frequencyHz': measurement.frequencyHz,
    'periodSeconds': measurement.periodSeconds,
    'dutyPercent': measurement.dutyPercent,
    'pulseWidthSeconds': measurement.pulseWidthSeconds,
    'riseTimeSeconds': measurement.riseTimeSeconds,
    'fallTimeSeconds': measurement.fallTimeSeconds,
    'overshootPercent': measurement.overshootPercent,
    'undershootPercent': measurement.undershootPercent,
    'risingEdgeCount': measurement.risingEdgeCount,
    'fallingEdgeCount': measurement.fallingEdgeCount,
    'sampleCount': measurement.sampleCount,
    'sampleIntervalSeconds': measurement.sampleIntervalSeconds,
    'notes': measurement.notes,
  };

  /// Statistics over the stored measurement history.
  ///
  /// Channels with only one stored acquisition are omitted: a standard
  /// deviation needs at least two runs.
  Map<String, WaveformChannelStatistics> _measurementStatistics() {
    final statistics = <String, WaveformChannelStatistics>{};
    void add(String channel, List<WaveformMeasurements> history) {
      if (history.length > 1) {
        statistics[channel] = measureChannelStatistics(history);
      }
    }

    add('ch1', _measurementHistoryCh1);
    add('ch2', _measurementHistoryCh2);
    add('ch3', _measurementHistoryCh3);
    add('ch4', _measurementHistoryCh4);
    return statistics;
  }

  /// Longest stored history across all channels.
  int _measurementHistoryCount() {
    var count = 0;
    for (final history in [
      _measurementHistoryCh1,
      _measurementHistoryCh2,
      _measurementHistoryCh3,
      _measurementHistoryCh4,
    ]) {
      if (history.length > count) count = history.length;
    }
    return count;
  }

  /// Enabled live channels that can serve as a reference.
  Map<String, WaveformData> _enabledLiveChannels() {
    final channels = <String, WaveformData>{};
    void add(String channel, bool enabled, WaveformData? data) {
      if (enabled && data != null && data.points.isNotEmpty) {
        channels[channel] = data;
      }
    }

    add('ch1', _ch1Enabled, _waveformCh1);
    add('ch2', _ch2Enabled, _waveformCh2);
    add('ch3', _numChannels >= 4 && _ch3Enabled, _waveformCh3);
    add('ch4', _numChannels >= 4 && _ch4Enabled, _waveformCh4);
    return channels;
  }

  bool _hasCurrentWaveform() => _enabledLiveChannels().isNotEmpty;

  /// Clears the Waveform AI acquisition history and the per-channel
  /// measurement history used by the statistics line.
  void _clearMeasurementHistory() {
    _waveformHistory.clear();
    if (!mounted) return;
    _setState(() {
      _measurementHistoryCh1.clear();
      _measurementHistoryCh2.clear();
      _measurementHistoryCh3.clear();
      _measurementHistoryCh4.clear();
    });
  }
}
