part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAcquisition on _OsciHomePageState {
  bool get _isAcquiring => _acquisitionController.isAcquiring;

  bool get _isAcquiringWaveform => _acquisitionController.isAcquiringWaveform;

  Uint8List? get _screenDump => _acquisitionController.screenDump;

  DateTime? get _screenDumpCapturedAt =>
      _acquisitionController.screenDumpCapturedAt;

  WaveformData? get _waveformCh1 => _acquisitionController.ch1;
  WaveformData? get _waveformCh2 => _acquisitionController.ch2;
  WaveformData? get _waveformCh3 => _acquisitionController.ch3;
  WaveformData? get _waveformCh4 => _acquisitionController.ch4;

  WaveformRawData? get _lastRawData => _acquisitionController.lastRawData;

  int get _acquisitionGeneration =>
      _acquisitionController.acquisitionGeneration;

  Future<void> _acquireScreenDump({bool keepPanels = false}) =>
      _acquisitionOrchestrator.acquireScreenDump(keepPanels: keepPanels);

  /// Acquires a new waveform and updates the analysis view.
  ///
  /// [keepPanels] keeps the currently open panel (for example the main AI
  /// chat) instead of switching to the waveform view. Background refreshes
  /// triggered by an AI scope command use it so the acquisition never
  /// navigates the user away from the conversation.
  Future<void> _acquireWaveform({bool keepPanels = false}) =>
      _acquisitionOrchestrator.acquireWaveform(keepPanels: keepPanels);

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
