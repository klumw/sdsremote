/// Parses a waveform CSV file content and returns the points of each channel.
/// Returns all-null when the CSV is unparseable or has no data rows.
///
/// Two headers are accepted:
///   Time (s),CH1 (V),CH2 (V)
///   Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)
///
/// The 5-column form is written for four-channel instruments. Comment lines
/// start with `#`.
typedef WaveformCsvChannels = ({
  List<(double, double)>? ch1,
  List<(double, double)>? ch2,
  List<(double, double)>? ch3,
  List<(double, double)>? ch4,
});

const WaveformCsvChannels _emptyWaveformCsv = (
  ch1: null,
  ch2: null,
  ch3: null,
  ch4: null,
);

WaveformCsvChannels parseWaveformCsv(String content) {
  const threeColumnHeader = 'Time (s),CH1 (V),CH2 (V)';
  const fourColumnHeader = 'Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)';

  final lines = content.split('\n');
  var columnCount = 0;
  List<(double, double)>? ch1;
  List<(double, double)>? ch2;
  List<(double, double)>? ch3;
  List<(double, double)>? ch4;

  bool inData = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
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
  return (
    ch1: hasCh1 ? ch1 : null,
    ch2: hasCh2 ? ch2 : null,
    ch3: hasCh3 ? ch3 : null,
    ch4: hasCh4 ? ch4 : null,
  );
}
