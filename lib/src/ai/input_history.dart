/// Bounded history of the most recent user inputs of an AI chat.
///
/// The chat window shows these entries behind its history button. Selecting
/// one sends that prompt again. The behavior matches the Waveform AI
/// assistant: the newest entry comes first, duplicate entries move to the
/// front, and at most [maxEntries] entries are kept.
class InputHistory {
  InputHistory({this.maxEntries = 5});

  /// Maximum number of entries kept in the history.
  final int maxEntries;

  final List<String> _entries = [];

  /// Most recent inputs, newest first.
  List<String> get entries => List<String>.unmodifiable(_entries);

  /// Records [text] as the newest input, moving an existing equal entry to
  /// the front and trimming the oldest entries beyond [maxEntries].
  void record(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _entries.remove(trimmed);
    _entries.insert(0, trimmed);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
  }

  /// Removes every entry.
  void clear() => _entries.clear();
}
