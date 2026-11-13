import 'package:flutter/foundation.dart';

import '../app/app_preferences.dart';
import '../core/logger.dart';
import '../waveform/clock_detection.dart';
import '../waveform/waveform_measurements.dart';
import '../waveform/waveform_models.dart';
import 'spectrum_analysis.dart';
import 'spectrum_models.dart';
import 'windows.dart';

/// Owns the spectrum settings, the cached FFT result, and the view state.
///
/// The FFT runs in an isolate; the controller invalidates in-flight
/// computations with a generation counter and notifies the home page when the
/// result changes.
class SpectrumController extends ChangeNotifier {
  SpectrumController({
    required this.readRawData,
    required this.readMeasurements,
    required this.isChannelEnabled,
    required this.channelCount,
    required this.onShowError,
    required this.onChanged,
  });

  /// Returns the raw samples of the last acquisition.
  final WaveformRawData? Function() readRawData;

  /// Returns all acquired measurements, regardless of channel toggles.
  final Map<String, WaveformMeasurements> Function() readMeasurements;

  /// Whether the given 1-based channel is enabled for display.
  final bool Function(int channel) isChannelEnabled;

  /// Number of analog channels of the connected instrument.
  final int Function() channelCount;

  /// Reports a computation error to the user.
  final void Function(String message) onShowError;

  /// Called after the controller's state changed.
  final void Function() onChanged;

  SpectrumSettings _settings = const SpectrumSettings();
  SpectrumResult? _result;
  bool _loading = false;
  int _generation = 0;
  bool _disposed = false;

  /// Channel selected in the spectrum view.
  String channel = 'ch1';

  /// Whether the spectrum view shows all channels instead of one.
  bool showAll = true;
  bool logFrequency = false;

  SpectrumSettings get settings => _settings;

  /// Cached spectrum of the last acquisition.
  SpectrumResult? get result => _result;

  bool get loading => _loading;

  /// Whether the last acquisition has enough usable samples and at least one
  /// channel with enough full periods for a useful spectrum.
  bool get hasEnoughData {
    final raw = readRawData();
    if (raw == null) return false;

    final rawByChannel = <String, Uint8List?>{
      'ch1': raw.ch1Raw,
      'ch2': raw.ch2Raw,
      'ch3': raw.ch3Raw,
      'ch4': raw.ch4Raw,
    };
    final measurements = readMeasurements();
    var hasUsableSamples = false;
    var sawMeasurement = false;

    for (final entry in rawByChannel.entries) {
      final bytes = entry.value;
      if (bytes == null) continue;
      final skip = bytes.length > _settings.leadingSamplesToSkip * 4
          ? _settings.leadingSamplesToSkip
          : 0;
      if (bytes.length - skip < minSpectrumSamples) continue;

      final measurement = measurements[entry.key];
      // A signal below the level threshold is excluded from the spectrum, so
      // it must not keep the spectrum tab enabled either.
      if (measurement != null && !hasEnoughSpectrumSignalLevel(measurement)) {
        continue;
      }
      hasUsableSamples = true;
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
  List<SpectrumChannelNotice> channelNotices() {
    final raw = readRawData();
    if (raw == null) return const [];
    final measurements = readMeasurements();
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
      final skip = bytes.length > _settings.leadingSamplesToSkip * 4
          ? _settings.leadingSamplesToSkip
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
      if (measurement != null && !hasEnoughSpectrumSignalLevel(measurement)) {
        notices.add(
          SpectrumChannelNotice(
            channel: 'ch$number',
            issue: SpectrumChannelIssue.signalTooSmall,
          ),
        );
        return;
      }
      if (measurement != null && !hasEnoughFftPeriods(measurement)) {
        notices.add(
          SpectrumChannelNotice(
            channel: 'ch$number',
            issue: SpectrumChannelIssue.tooFewPeriods,
          ),
        );
      }
    }

    checkChannel(1, isChannelEnabled(1), raw.ch1Raw, raw.vdivCh1);
    checkChannel(2, isChannelEnabled(2), raw.ch2Raw, raw.vdivCh2);
    if (channelCount() >= 4) {
      checkChannel(3, isChannelEnabled(3), raw.ch3Raw, raw.vdivCh3);
      checkChannel(4, isChannelEnabled(4), raw.ch4Raw, raw.vdivCh4);
    }
    return notices;
  }

  /// Computes (or returns the cached) spectrum of the last acquisition.
  ///
  /// The result feeds the PDF report and the spectrum view.
  Future<SpectrumResult?> spectrumForReport() async {
    if (!hasEnoughData) return null;
    final cached = _result;
    if (cached != null) return cached;
    final result = await _computeNow();
    _result = result;
    return result;
  }

  /// Recomputes the spectrum for the current acquisition and settings.
  Future<void> recompute() async {
    final generation = ++_generation;
    if (readRawData() == null || !hasEnoughData) {
      _result = null;
      _loading = false;
      _notify();
      return;
    }
    _loading = true;
    _notify();

    SpectrumResult? result;
    try {
      result = await _computeNow();
    } catch (e) {
      AppLogger().error('Spectrum computation failed: $e');
      onShowError('Spectrum computation failed: $e');
    }

    if (_disposed || generation != _generation) return;
    _result = result;
    _loading = false;
    if (result != null &&
        result.traceFor(channel) == null &&
        result.traces.isNotEmpty) {
      channel = result.traces.first.channel;
    }
    _notify();
  }

  /// Applies new settings and drops the cached result.
  void applySettings(SpectrumSettings settings) {
    _settings = settings;
    _result = null;
    _notify();
  }

  /// Persists the current settings in the application preferences.
  Future<void> persistSettings() async {
    await AppPreferences.setAll(preferenceEntries());
  }

  /// Preference entries of the current spectrum settings.
  ///
  /// Shared by the immediate persistence of the spectrum controls and the
  /// configuration dialog so both always write the same keys.
  Map<String, dynamic> preferenceEntries() => {
    'spectrum_window': _settings.window.name,
    'spectrum_unit': _settings.unit.name,
    'spectrum_fft_size': _settings.fftSize,
    'spectrum_max_fft_size': _settings.maxFftSize,
    'spectrum_remove_dc': _settings.removeDc,
    'spectrum_peak_count': _settings.peakCount,
    'spectrum_harmonic_count': _settings.harmonicCount,
    'spectrum_skip_samples': _settings.leadingSamplesToSkip,
  };

  /// Loads the persisted spectrum settings.
  Future<void> loadSettings() async {
    const defaults = SpectrumSettings();
    final windowName = await AppPreferences.getString('spectrum_window');
    final unitName = await AppPreferences.getString('spectrum_unit');
    final window = windowName == null
        ? defaults.window
        : SpectrumWindow.values.firstWhere(
            (value) => value.name == windowName,
            orElse: () => defaults.window,
          );
    final unit = unitName == null
        ? defaults.unit
        : SpectrumUnit.values.firstWhere(
            (value) => value.name == unitName,
            orElse: () => defaults.unit,
          );

    final settings = SpectrumSettings(
      window: window,
      fftSize:
          await AppPreferences.getInt('spectrum_fft_size') ?? defaults.fftSize,
      maxFftSize:
          await AppPreferences.getInt('spectrum_max_fft_size') ??
          defaults.maxFftSize,
      unit: unit,
      removeDc:
          await AppPreferences.getBool('spectrum_remove_dc') ??
          defaults.removeDc,
      peakCount:
          await AppPreferences.getInt('spectrum_peak_count') ??
          defaults.peakCount,
      harmonicCount:
          await AppPreferences.getInt('spectrum_harmonic_count') ??
          defaults.harmonicCount,
      leadingSamplesToSkip:
          await AppPreferences.getInt('spectrum_skip_samples') ??
          defaults.leadingSamplesToSkip,
    );

    _settings = settings;
    _result = null;
    _notify();
  }

  /// Drops the cached result without invalidating in-flight computations.
  void clearResultSilently() {
    _result = null;
  }

  /// Invalidates the cached result and any in-flight computation.
  void invalidateSilently() {
    _result = null;
    _loading = false;
    _generation++;
  }

  Future<SpectrumResult?> _computeNow() async {
    final raw = readRawData();
    if (raw == null || !hasEnoughData) return null;

    final channels = <SpectrumChannelInput>[];
    final measurements = readMeasurements();
    void addChannel(
      int number,
      Uint8List? bytes,
      double? vdiv,
      double? voffset,
    ) {
      if (bytes == null || bytes.isEmpty || vdiv == null || vdiv <= 0) return;
      final measurement = measurements['ch$number'];
      if (measurement != null && !hasEnoughSpectrumSignalLevel(measurement)) {
        return;
      }
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
      settings: _settings,
    );
    return compute(computeSpectrum, request);
  }

  void _notify() {
    if (_disposed) return;
    onChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
