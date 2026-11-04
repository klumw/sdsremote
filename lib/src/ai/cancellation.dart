/// One-shot cancellation signal shared by a chat request and its tools.
///
/// The Waveform Agent creates a token for every request and passes it through
/// the service and its sub-agents. Cancelling the request cancels the token,
/// which stops the AudioAgent stream and the running Bode sweep immediately.
library;

class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether the request has already been cancelled.
  bool get isCancelled => _cancelled;

  /// Cancels the request and notifies every registered listener once.
  ///
  /// Listener errors are ignored so one faulty listener cannot prevent the
  /// remaining tools from stopping.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } on Object {
        // Cancellation must continue even if a listener fails.
      }
    }
  }

  /// Registers [listener].
  ///
  /// When the token is already cancelled, the listener runs immediately.
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
