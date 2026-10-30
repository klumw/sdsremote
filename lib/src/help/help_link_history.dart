/// Back/forward history for in-document links in the help window.
///
/// Targets are canonical heading slugs. Every visited target remains in the
/// list, including targets that were reached again after going back.
class HelpLinkHistory {
  final List<String> _targets = [];
  int _index = -1;

  bool get canGoBack => _index > 0;

  bool get canGoForward => _index >= 0 && _index < _targets.length - 1;

  String? get current => _index < 0 ? null : _targets[_index];

  /// Records [target] and returns whether the history changed.
  bool visit(String target) {
    if (target.isEmpty) return false;
    if (_index >= 0 && _targets[_index] == target) return false;
    _targets.add(target);
    _index = _targets.length - 1;
    return true;
  }

  /// Moves to the previous target and returns it, or null at the start.
  String? back() {
    if (!canGoBack) return null;
    _index--;
    return _targets[_index];
  }

  /// Moves to the next target and returns it, or null at the end.
  String? forward() {
    if (!canGoForward) return null;
    _index++;
    return _targets[_index];
  }

  void clear() {
    _targets.clear();
    _index = -1;
  }
}
