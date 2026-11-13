part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeSpectrum on _OsciHomePageState {
  /// Whether the last acquisition has enough usable samples and at least one
  /// channel with enough full periods for a useful spectrum.
  bool get _hasEnoughSpectrumData {
    final raw = _lastRawData;
    if (raw == null) return false;

    final rawByChannel = <String, Uint8List?>{
      'ch1': raw.ch1Raw,
      'ch2': raw.ch2Raw,
      'ch3': raw.ch3Raw,
      'ch4': raw.ch4Raw,
    };
    final measurements = _acquiredMeasurements();
    var hasUsableSamples = false;
    var sawMeasurement = false;

    for (final entry in rawByChannel.entries) {
      final bytes = entry.value;
      if (bytes == null) continue;
      final skip = bytes.length > _spectrumSettings.leadingSamplesToSkip * 4
          ? _spectrumSettings.leadingSamplesToSkip
          : 0;
      if (bytes.length - skip < minSpectrumSamples) continue;
      hasUsableSamples = true;

      final measurement = measurements[entry.key];
      if (measurement == null) return true;
      sawMeasurement = true;
      if (hasEnoughFftPeriods(measurement)) return true;
    }

    return hasUsableSamples && !sawMeasurement;
  }

  /// Enabled channels that cannot produce a spectrum trace.
  ///
  /// The spectrum view renders these reasons at its bottom so the user knows
  /// why a channel is missing and how to make its data visible.
  List<SpectrumChannelNotice> _spectrumChannelNotices() {
    final raw = _lastRawData;
    if (raw == null) return const [];
    final measurements = _acquiredMeasurements();
    final notices = <SpectrumChannelNotice>[];

    void checkChannel(
      int number,
      bool enabled,
      Uint8List? bytes,
      double? vdiv,
    ) {
      if (!enabled) return;
      if (bytes == null || bytes.isEmpty || vdiv == null || vdiv <= 0) {
        notices.add(
          SpectrumChannelNotice(
            channel: 'ch$number',
            issue: SpectrumChannelIssue.noData,
          ),
        );
        return;
      }
      final skip = bytes.length > _spectrumSettings.leadingSamplesToSkip * 4
          ? _spectrumSettings.leadingSamplesToSkip
          : 0;
      if (bytes.length - skip < minSpectrumSamples) {
        notices.add(
          SpectrumChannelNotice(
            channel: 'ch$number',
            issue: SpectrumChannelIssue.tooFewSamples,
          ),
        );
        return;
      }
      final measurement = measurements['ch$number'];
      if (measurement != null && !hasEnoughFftPeriods(measurement)) {
        notices.add(
          SpectrumChannelNotice(
            channel: 'ch$number',
            issue: SpectrumChannelIssue.tooFewPeriods,
          ),
        );
      }
    }

    checkChannel(1, _ch1Enabled, raw.ch1Raw, raw.vdivCh1);
    checkChannel(2, _ch2Enabled, raw.ch2Raw, raw.vdivCh2);
    if (_numChannels >= 4) {
      checkChannel(3, _ch3Enabled, raw.ch3Raw, raw.vdivCh3);
      checkChannel(4, _ch4Enabled, raw.ch4Raw, raw.vdivCh4);
    }
    return notices;
  }

  /// Computes (or returns the cached) spectrum of the last acquisition.
  ///
  /// The FFT runs in an isolate so a large record does not block the UI. The
  /// result feeds the PDF report and the spectrum view.
  Future<SpectrumResult?> _spectrumForReport() async {
    if (!_hasEnoughSpectrumData) return null;
    final cached = _spectrumResult;
    if (cached != null) return cached;
    final result = await _computeSpectrumNow();
    _spectrumResult = result;
    return result;
  }

  /// Recomputes the spectrum for the current acquisition and settings.
  Future<void> _recomputeSpectrum() async {
    final generation = ++_spectrumGeneration;
    if (_lastRawData == null || !_hasEnoughSpectrumData) {
      if (mounted) {
        _setState(() {
          _spectrumResult = null;
          _spectrumLoading = false;
        });
      }
      return;
    }
    _setState(() => _spectrumLoading = true);

    SpectrumResult? result;
    try {
      result = await _computeSpectrumNow();
    } catch (e) {
      AppLogger().error('Spectrum computation failed: $e');
      if (mounted) _showErrorSnackBar('Spectrum computation failed: $e');
    }

    if (!mounted || generation != _spectrumGeneration) return;
    _setState(() {
      _spectrumResult = result;
      _spectrumLoading = false;
      if (result != null &&
          result.traceFor(_spectrumChannel) == null &&
          result.traces.isNotEmpty) {
        _spectrumChannel = result.traces.first.channel;
      }
    });
  }

  void _onSpectrumSettingsChanged(SpectrumSettings settings) {
    _setState(() {
      _spectrumSettings = settings;
      _spectrumResult = null;
    });
    unawaited(_persistSpectrumSettings());
    if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum) {
      unawaited(_recomputeSpectrum());
    }
  }

  Future<void> _persistSpectrumSettings() async {
    await AppPreferences.setAll(_spectrumPreferenceEntries());
  }

  /// Preference entries of the current spectrum settings.
  ///
  /// Shared by the immediate persistence of the spectrum controls and the
  /// configuration dialog so both always write the same keys.
  Map<String, dynamic> _spectrumPreferenceEntries() => {
    'spectrum_window': _spectrumSettings.window.name,
    'spectrum_unit': _spectrumSettings.unit.name,
    'spectrum_fft_size': _spectrumSettings.fftSize,
    'spectrum_max_fft_size': _spectrumSettings.maxFftSize,
    'spectrum_remove_dc': _spectrumSettings.removeDc,
    'spectrum_peak_count': _spectrumSettings.peakCount,
    'spectrum_harmonic_count': _spectrumSettings.harmonicCount,
    'spectrum_skip_samples': _spectrumSettings.leadingSamplesToSkip,
  };

  Future<SpectrumResult?> _computeSpectrumNow() async {
    final raw = _lastRawData;
    if (raw == null || !_hasEnoughSpectrumData) return null;

    final channels = <SpectrumChannelInput>[];
    final measurements = _acquiredMeasurements();
    void addChannel(
      int number,
      Uint8List? bytes,
      double? vdiv,
      double? voffset,
    ) {
      if (bytes == null || bytes.isEmpty || vdiv == null || vdiv <= 0) return;
      final measurement = measurements['ch$number'];
      if (measurement != null && !hasEnoughFftPeriods(measurement)) {
        return;
      }
      channels.add(
        SpectrumChannelInput(
          label: 'ch$number',
          raw: bytes,
          vdiv: vdiv,
          voffset: voffset ?? 0,
        ),
      );
    }

    addChannel(1, raw.ch1Raw, raw.vdivCh1, raw.voffsetCh1);
    addChannel(2, raw.ch2Raw, raw.vdivCh2, raw.voffsetCh2);
    addChannel(3, raw.ch3Raw, raw.vdivCh3, raw.voffsetCh3);
    addChannel(4, raw.ch4Raw, raw.vdivCh4, raw.voffsetCh4);
    // The scope may sparse the transfer (WFSU SP); the stored raw bytes are
    // therefore sampled at the effective rate, not at the acquisition rate.
    final effectiveSampleRate = raw.effectiveSampleRate;
    if (channels.isEmpty || effectiveSampleRate <= 0) return null;

    final request = SpectrumRequest(
      channels: channels,
      sampleRate: effectiveSampleRate,
      settings: _spectrumSettings,
    );
    return compute(computeSpectrum, request);
  }
}
