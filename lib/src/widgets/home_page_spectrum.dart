part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

/// Bridges the private home-page state to [SpectrumController].
extension _HomeSpectrum on _OsciHomePageState {
  /// Whether the last acquisition has enough usable samples and at least one
  /// channel with enough full periods for a useful spectrum.
  bool get _hasEnoughSpectrumData => _spectrumController.hasEnoughData;

  /// Enabled channels that cannot produce a spectrum trace.
  List<SpectrumChannelNotice> _spectrumChannelNotices() =>
      _spectrumController.channelNotices();

  /// Computes (or returns the cached) spectrum of the last acquisition.
  Future<SpectrumResult?> _spectrumForReport() =>
      _spectrumController.spectrumForReport();

  /// Recomputes the spectrum for the current acquisition and settings.
  Future<void> _recomputeSpectrum() => _spectrumController.recompute();

  SpectrumSettings get _spectrumSettings => _spectrumController.settings;

  SpectrumResult? get _spectrumResult => _spectrumController.result;

  bool get _spectrumLoading => _spectrumController.loading;

  String get _spectrumChannel => _spectrumController.channel;
  set _spectrumChannel(String value) => _spectrumController.channel = value;

  bool get _spectrumShowAll => _spectrumController.showAll;
  set _spectrumShowAll(bool value) => _spectrumController.showAll = value;

  bool get _spectrumLogFrequency => _spectrumController.logFrequency;
  set _spectrumLogFrequency(bool value) =>
      _spectrumController.logFrequency = value;

  void _onSpectrumSettingsChanged(SpectrumSettings settings) {
    _spectrumController.applySettings(settings);
    unawaited(_spectrumController.persistSettings());
    if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum) {
      unawaited(_recomputeSpectrum());
    }
  }

  /// Preference entries of the current spectrum settings.
  Map<String, dynamic> _spectrumPreferenceEntries() =>
      _spectrumController.preferenceEntries();
}
