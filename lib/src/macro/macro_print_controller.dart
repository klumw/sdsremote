import 'package:flutter/foundation.dart';

/// Collects the output of `print()` statements during macro playback.
///
/// The Macro Editor listens to this controller and shows a print panel as soon
/// as the first message arrives. Messages belong to the most recent playback;
/// the playback code calls [clear] when a new run starts.
class MacroPrintController extends ChangeNotifier {
  final List<String> _messages = <String>[];

  /// All messages of the current playback, in output order.
  List<String> get messages => List<String>.unmodifiable(_messages);

  /// Whether at least one `print()` statement produced output.
  bool get hasMessages => _messages.isNotEmpty;

  /// Appends one `print()` result.
  void add(String message) {
    _messages.add(message);
    notifyListeners();
  }

  /// Removes all messages. The print panel disappears as a result.
  void clear() {
    if (_messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }
}
