/// Parses a waveform CSV file content and returns (ch1Points, ch2Points).
/// Returns null if the CSV is unparseable or has no data rows.
///
/// The CSV format is:
///   # comment lines (ignored)
///   Time (s),CH1 (V),CH2 (V)
///   0,0.16,1.24
///   0.000000002,-1.12,1.20
///
/// Both channels may be present, one may be empty, or one may be missing.
(List<(double, double)>?, List<(double, double)>?) parseWaveformCsv(
  String content,
) {
  final lines = content.split('\n');
  List<(double, double)>? ch1;
  List<(double, double)>? ch2;

  bool inData = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!inData) {
      // Validate the CSV header exactly matches the expected format.
      if (trimmed == 'Time (s),CH1 (V),CH2 (V)') {
        inData = true;
        ch1 = [];
        ch2 = [];
      } else if (trimmed.contains(',') &&
          (trimmed.toLowerCase().contains('time') ||
              trimmed.toLowerCase().contains('ch1') ||
              trimmed.toLowerCase().contains('ch2'))) {
        // Looks like a header row but doesn't match — reject the file.
        return (null, null);
      }
      continue;
    }

    final parts = trimmed.split(',');
    if (parts.length < 3) continue;

    final time = double.tryParse(parts[0].trim());
    if (time == null) continue;

    final ch1Str = parts[1].trim();
    final ch2Str = parts[2].trim();

    if (ch1Str.isNotEmpty) {
      final v = double.tryParse(ch1Str);
      if (v != null) ch1?.add((time, v));
    }
    if (ch2Str.isNotEmpty) {
      final v = double.tryParse(ch2Str);
      if (v != null) ch2?.add((time, v));
    }
  }

  // Return null lists as null so caller knows they're unavailable
  final hasCh1 = ch1 != null && ch1.isNotEmpty;
  final hasCh2 = ch2 != null && ch2.isNotEmpty;
  if (!hasCh1 && !hasCh2) return (null, null);
  return (hasCh1 ? ch1 : null, hasCh2 ? ch2 : null);
}
