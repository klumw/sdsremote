/// In-memory history of the most recent waveform acquisitions.
///
/// The Waveform AI uses it to compare the last four measurements. Entries are
/// stored newest first and carry a 1-based sequence number and an ISO 8601
/// capture timestamp.
class WaveformHistoryStore {
  WaveformHistoryStore({this.maxEntries = 4});

  /// Maximum number of entries kept. Older entries are discarded.
  final int maxEntries;

  final List<Map<String, dynamic>> _entries = [];
  int _sequence = 0;

  /// Stored entries, newest first. The returned list is unmodifiable.
  List<Map<String, dynamic>> get entries =>
      List<Map<String, dynamic>>.unmodifiable(_entries);

  /// Adds [summary] as the newest entry and trims the history.
  void add(Map<String, dynamic> summary, {DateTime? capturedAt}) {
    _sequence++;
    final entry = <String, dynamic>{
      ...summary,
      'sequence': _sequence,
      'capturedAt': (capturedAt ?? DateTime.now()).toIso8601String(),
    };
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  /// Removes all entries and resets the sequence counter.
  void clear() {
    _entries.clear();
    _sequence = 0;
  }
}
