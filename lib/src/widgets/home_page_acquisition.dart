part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAcquisition on _OsciHomePageState {
  bool get _isAcquiring => _acquisitionController.isAcquiring;
  set _isAcquiring(bool value) => _acquisitionController.isAcquiring = value;

  bool get _isAcquiringWaveform => _acquisitionController.isAcquiringWaveform;
  set _isAcquiringWaveform(bool value) =>
      _acquisitionController.isAcquiringWaveform = value;

  Uint8List? get _screenDump => _acquisitionController.screenDump;
  set _screenDump(Uint8List? value) =>
      _acquisitionController.screenDump = value;

  DateTime? get _screenDumpCapturedAt =>
      _acquisitionController.screenDumpCapturedAt;
  set _screenDumpCapturedAt(DateTime? value) =>
      _acquisitionController.screenDumpCapturedAt = value;

  WaveformData? get _waveformCh1 => _acquisitionController.ch1;
  set _waveformCh1(WaveformData? value) => _acquisitionController.ch1 = value;

  WaveformData? get _waveformCh2 => _acquisitionController.ch2;
  set _waveformCh2(WaveformData? value) => _acquisitionController.ch2 = value;

  WaveformData? get _waveformCh3 => _acquisitionController.ch3;
  set _waveformCh3(WaveformData? value) => _acquisitionController.ch3 = value;

  WaveformData? get _waveformCh4 => _acquisitionController.ch4;
  set _waveformCh4(WaveformData? value) => _acquisitionController.ch4 = value;

  WaveformRawData? get _lastRawData => _acquisitionController.lastRawData;
  set _lastRawData(WaveformRawData? value) =>
      _acquisitionController.lastRawData = value;

  set _measurementsCh1(WaveformMeasurements? value) =>
      _acquisitionController.measurementsCh1 = value;

  set _measurementsCh2(WaveformMeasurements? value) =>
      _acquisitionController.measurementsCh2 = value;

  set _measurementsCh3(WaveformMeasurements? value) =>
      _acquisitionController.measurementsCh3 = value;

  set _measurementsCh4(WaveformMeasurements? value) =>
      _acquisitionController.measurementsCh4 = value;

  List<WaveformMeasurements> get _measurementHistoryCh1 =>
      _acquisitionController.historyCh1;
  List<WaveformMeasurements> get _measurementHistoryCh2 =>
      _acquisitionController.historyCh2;
  List<WaveformMeasurements> get _measurementHistoryCh3 =>
      _acquisitionController.historyCh3;
  List<WaveformMeasurements> get _measurementHistoryCh4 =>
      _acquisitionController.historyCh4;

  int get _acquisitionGeneration =>
      _acquisitionController.acquisitionGeneration;
  set _acquisitionGeneration(int value) =>
      _acquisitionController.acquisitionGeneration = value;

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
      _spectrumController.clearResultSilently();
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
        // Invalidate an in-flight spectrum computation from the previous
        // acquisition so it cannot publish stale FFT values.
        _spectrumController.invalidateSilently();
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
  (
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
  )
  _measureRawChannels(WaveformRawData raw) =>
      _acquisitionController.measureRawChannels(raw);

  /// Writes the latest waveform measurements to the debug log.
  void _logWaveformMeasurements() =>
      _acquisitionController.logWaveformMeasurements();

  /// Appends the current measurements to the bounded per-channel history.
  void _recordMeasurementHistory(
    (
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
    )
    measurements,
  ) => _acquisitionController.recordMeasurementHistory(measurements);

  /// Measurements of the channels currently enabled for display.
  Map<String, WaveformMeasurements> _currentMeasurements() =>
      _acquisitionController.currentMeasurements();

  /// All acquired measurements, regardless of the display channel toggles.
  Map<String, WaveformMeasurements> _acquiredMeasurements() =>
      _acquisitionController.acquiredMeasurements;

  /// Serializes one channel's measurements for [_waveformSummaryForAi].
  Map<String, dynamic> _measurementSummaryForAi(
    WaveformMeasurements measurement,
    DeviceParams? params, {
    double? verticalScaleVoltsPerDiv,
    double? offsetVolts,
  }) => _acquisitionController.measurementSummaryForAi(
    measurement,
    params,
    verticalScaleVoltsPerDiv: verticalScaleVoltsPerDiv,
    offsetVolts: offsetVolts,
  );

  /// Statistics over the stored measurement history.
  Map<String, WaveformChannelStatistics> _measurementStatistics() =>
      _acquisitionController.measurementStatistics();

  /// Longest stored history across all channels.
  int _measurementHistoryCount() =>
      _acquisitionController.measurementHistoryCount;

  /// Enabled live channels that can serve as a reference.
  Map<String, WaveformData> _enabledLiveChannels() =>
      _acquisitionController.enabledLiveChannels();

  bool _hasCurrentWaveform() => _acquisitionController.hasCurrentWaveform;

  /// Clears the Waveform AI acquisition history and the per-channel
  /// measurement history used by the statistics line.
  void _clearMeasurementHistory() {
    _waveformHistory.clear();
    if (!mounted) return;
    _setState(() => _acquisitionController.clearHistory());
  }
}
