/// Vertical settings written per channel by the waveform CSV export.
class WaveformCsvChannelSettings {
  /// Vertical scale in volts per division (`# CHn V/div:`).
  final double? vdivVolts;

  /// Vertical offset in volts (`# CHn Offset:`).
  final double? offsetVolts;

  const WaveformCsvChannelSettings({this.vdivVolts, this.offsetVolts});
}

/// Timing metadata written as comment lines by the waveform CSV export.
///
/// All values are optional: files from other tools or older SDS-Remote
/// versions may not contain them.
class WaveformCsvMetadata {
  /// Horizontal scale in seconds per division (`# Timebase:`).
  final double? timebaseSecondsPerDiv;

  /// Trigger delay in seconds (`# Trigger Delay:`).
  final double? triggerDelaySeconds;

  /// Acquisition sample rate in samples per second (`# Sample Rate:`).
  final double? sampleRateHz;

  /// Per-channel vertical settings keyed by `'ch1'` … `'ch4'`.
  final Map<String, WaveformCsvChannelSettings> channels;

  const WaveformCsvMetadata({
    this.timebaseSecondsPerDiv,
    this.triggerDelaySeconds,
    this.sampleRateHz,
    this.channels = const {},
  });

  /// Whether at least one timing value was present in the file.
  bool get hasTiming =>
      timebaseSecondsPerDiv != null ||
      triggerDelaySeconds != null ||
      sampleRateHz != null;
}

/// Parses a waveform CSV file content and returns the points of each channel.
/// Returns all-null when the CSV is unparseable or has no data rows.
///
/// Two headers are accepted:
///   Time (s),CH1 (V),CH2 (V)
///   Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)
///
/// The 5-column form is written for four-channel instruments. Comment lines
/// start with `#`; the timing comments written by the export are returned as
/// [WaveformCsvChannels.metadata].
typedef WaveformCsvChannels = ({
  List<(double, double)>? ch1,
  List<(double, double)>? ch2,
  List<(double, double)>? ch3,
  List<(double, double)>? ch4,
  WaveformCsvMetadata? metadata,
});

const WaveformCsvChannels _emptyWaveformCsv = (
  ch1: null,
  ch2: null,
  ch3: null,
  ch4: null,
  metadata: null,
);

/// Reads the number following [label] in a `#` comment line.
double? _commentNumber(String line, String label) {
  final pattern = RegExp(
    '^#\\s*${RegExp.escape(label)}\\s*'
    r'([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(line);
  return match == null ? null : double.tryParse(match.group(1)!);
}

WaveformCsvChannels parseWaveformCsv(String content) {
  const threeColumnHeader = 'Time (s),CH1 (V),CH2 (V)';
  const fourColumnHeader = 'Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)';

  final lines = content.split('\n');
  var columnCount = 0;
  List<(double, double)>? ch1;
  List<(double, double)>? ch2;
  List<(double, double)>? ch3;
  List<(double, double)>? ch4;
  double? timebase;
  double? triggerDelay;
  double? sampleRate;
  final channelSettings = <String, WaveformCsvChannelSettings>{};

  bool inData = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) {
      timebase ??= _commentNumber(trimmed, 'Timebase:');
      triggerDelay ??= _commentNumber(trimmed, 'Trigger Delay:');
      sampleRate ??= _commentNumber(trimmed, 'Sample Rate:');
      for (var channel = 1; channel <= 4; channel++) {
        final key = 'ch$channel';
        final vdiv = _commentNumber(trimmed, 'CH$channel V/div:');
        final offset = _commentNumber(trimmed, 'CH$channel Offset:');
        if (vdiv == null && offset == null) continue;
        final previous = channelSettings[key];
        channelSettings[key] = WaveformCsvChannelSettings(
          vdivVolts: vdiv ?? previous?.vdivVolts,
          offsetVolts: offset ?? previous?.offsetVolts,
        );
      }
      continue;
    }
    if (!inData) {
      // Validate the CSV header exactly matches one of the expected formats.
      if (trimmed == threeColumnHeader) {
        columnCount = 3;
      } else if (trimmed == fourColumnHeader) {
        columnCount = 5;
      } else if (trimmed.contains(',') &&
          (trimmed.toLowerCase().contains('time') ||
              trimmed.toLowerCase().contains('ch1') ||
              trimmed.toLowerCase().contains('ch2'))) {
        // Looks like a header row but doesn't match — reject the file.
        return _emptyWaveformCsv;
      } else {
        continue;
      }
      inData = true;
      ch1 = [];
      ch2 = [];
      if (columnCount == 5) {
        ch3 = [];
        ch4 = [];
      }
      continue;
    }

    final parts = trimmed.split(',');
    if (parts.length < 3) continue;

    final time = double.tryParse(parts[0].trim());
    if (time == null) continue;

    void addValue(List<(double, double)>? target, int index) {
      if (target == null || index >= parts.length) return;
      final value = double.tryParse(parts[index].trim());
      if (value != null) target.add((time, value));
    }

    addValue(ch1, 1);
    addValue(ch2, 2);
    addValue(ch3, 3);
    addValue(ch4, 4);
  }

  // Return null lists as null so caller knows they're unavailable.
  final hasCh1 = ch1 != null && ch1.isNotEmpty;
  final hasCh2 = ch2 != null && ch2.isNotEmpty;
  final hasCh3 = ch3 != null && ch3.isNotEmpty;
  final hasCh4 = ch4 != null && ch4.isNotEmpty;
  if (!hasCh1 && !hasCh2 && !hasCh3 && !hasCh4) return _emptyWaveformCsv;
  final metadata =
      (timebase == null &&
          triggerDelay == null &&
          sampleRate == null &&
          channelSettings.isEmpty)
      ? null
      : WaveformCsvMetadata(
          timebaseSecondsPerDiv: timebase,
          triggerDelaySeconds: triggerDelay,
          sampleRateHz: sampleRate,
          channels: channelSettings,
        );
  return (
    ch1: hasCh1 ? ch1 : null,
    ch2: hasCh2 ? ch2 : null,
    ch3: hasCh3 ? ch3 : null,
    ch4: hasCh4 ? ch4 : null,
    metadata: metadata,
  );
}
