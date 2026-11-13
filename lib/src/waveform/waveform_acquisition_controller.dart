import 'dart:typed_data';

import '../core/logger.dart';
import 'waveform_measurements.dart';
import 'waveform_models.dart';

/// Owns the acquisition state, the derived measurement maps, and the bounded
/// per-channel measurement history.
///
/// The acquisition orchestration (SCPI transfer, panel switching, live-screen
/// handover) stays in the home page; this controller holds the data those
/// steps produce and the measurement helpers derived from it.
class WaveformAcquisitionController {
  WaveformAcquisitionController({
    required this.isChannelEnabled,
    required this.channelCount,
  });

  /// Whether the given 1-based channel is enabled for display.
  final bool Function(int channel) isChannelEnabled;

  /// Number of analog channels of the connected instrument.
  final int Function() channelCount;

  /// Maximum number of measurements kept per channel.
  static const int _measurementHistoryLimit = 20;

  bool isAcquiring = false;
  bool isAcquiringWaveform = false;
  Uint8List? screenDump;

  /// Time the current [screenDump] was captured, shown in the PDF report.
  DateTime? screenDumpCapturedAt;

  WaveformData? ch1;
  WaveformData? ch2;
  WaveformData? ch3;
  WaveformData? ch4;

  /// Raw samples of the last acquisition, retained for the spectrum analysis
  /// and the PDF report. Invalidated by a new acquisition.
  WaveformRawData? lastRawData;

  /// Time-domain measurements of the last acquisition, computed from the raw
  /// samples before the display decimation.
  WaveformMeasurements? measurementsCh1;
  WaveformMeasurements? measurementsCh2;
  WaveformMeasurements? measurementsCh3;
  WaveformMeasurements? measurementsCh4;

  /// Bounded measurement history per channel, used for the statistics line
  /// in the measurement panel.
  final List<WaveformMeasurements> historyCh1 = [];
  final List<WaveformMeasurements> historyCh2 = [];
  final List<WaveformMeasurements> historyCh3 = [];
  final List<WaveformMeasurements> historyCh4 = [];

  /// Incremented after every successful acquisition so the AI acquisition
  /// tool can distinguish success from a handled failure.
  int acquisitionGeneration = 0;

  /// All acquired measurements, regardless of the display channel toggles.
  Map<String, WaveformMeasurements> get acquiredMeasurements => {
    'ch1': ?measurementsCh1,
    'ch2': ?measurementsCh2,
    'ch3': ?measurementsCh3,
    'ch4': ?measurementsCh4,
  };

  /// Measurements of the channels currently enabled for display.
  Map<String, WaveformMeasurements> currentMeasurements() {
    final measurements = <String, WaveformMeasurements>{};
    void add(String channel, bool enabled, WaveformMeasurements? value) {
      if (enabled && value != null) measurements[channel] = value;
    }

    add('ch1', isChannelEnabled(1), measurementsCh1);
    add('ch2', isChannelEnabled(2), measurementsCh2);
    add('ch3', channelCount() >= 4 && isChannelEnabled(3), measurementsCh3);
    add('ch4', channelCount() >= 4 && isChannelEnabled(4), measurementsCh4);
    return measurements;
  }

  /// Enabled live channels that can serve as a reference.
  Map<String, WaveformData> enabledLiveChannels() {
    final channels = <String, WaveformData>{};
    void add(String channel, bool enabled, WaveformData? data) {
      if (enabled && data != null && data.points.isNotEmpty) {
        channels[channel] = data;
      }
    }

    add('ch1', isChannelEnabled(1), ch1);
    add('ch2', isChannelEnabled(2), ch2);
    add('ch3', channelCount() >= 4 && isChannelEnabled(3), ch3);
    add('ch4', channelCount() >= 4 && isChannelEnabled(4), ch4);
    return channels;
  }

  bool get hasCurrentWaveform => enabledLiveChannels().isNotEmpty;

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
  measureRawChannels(WaveformRawData raw) {
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
  void logWaveformMeasurements() {
    for (final measurement in [
      measurementsCh1,
      measurementsCh2,
      measurementsCh3,
      measurementsCh4,
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
  void recordMeasurementHistory(
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
      if (history.length > _measurementHistoryLimit) {
        history.removeAt(0);
      }
    }

    add(historyCh1, measurements.$1);
    add(historyCh2, measurements.$2);
    add(historyCh3, measurements.$3);
    add(historyCh4, measurements.$4);
  }

  /// Serializes one channel's measurements for the Waveform AI summary.
  Map<String, dynamic> measurementSummaryForAi(
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
  Map<String, WaveformChannelStatistics> measurementStatistics() {
    final statistics = <String, WaveformChannelStatistics>{};
    void add(String channel, List<WaveformMeasurements> history) {
      if (history.length > 1) {
        statistics[channel] = measureChannelStatistics(history);
      }
    }

    add('ch1', historyCh1);
    add('ch2', historyCh2);
    add('ch3', historyCh3);
    add('ch4', historyCh4);
    return statistics;
  }

  /// Longest stored history across all channels.
  int get measurementHistoryCount {
    var count = 0;
    for (final history in [historyCh1, historyCh2, historyCh3, historyCh4]) {
      if (history.length > count) count = history.length;
    }
    return count;
  }

  /// Clears the per-channel measurement history.
  void clearHistory() {
    historyCh1.clear();
    historyCh2.clear();
    historyCh3.clear();
    historyCh4.clear();
  }
}
