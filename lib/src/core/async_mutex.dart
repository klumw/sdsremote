import 'dart:async';

/// Serialises asynchronous operations.
///
/// Critical sections submitted through [protect] run one after another in
/// submission order. An error in one critical section is reported to that
/// caller only and does not stall the operations queued behind it.
class AsyncMutex {
  Future<void> _last = Future<void>.value();

  Future<T> protect<T>(Future<T> Function() criticalSection) {
    final completer = Completer<void>();
    final next = _last.then((_) => criticalSection()).whenComplete(() {
      if (!completer.isCompleted) completer.complete();
    });
    _last = completer.future;
    return next;
  }
}
