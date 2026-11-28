/// Decides when a fast sensor stream may be written to the journal.
class PersistGate {
  PersistGate({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  final Map<String, DateTime> _last = {};
  final Set<String> _history = {};

  bool shouldPersist(String key, DateTime now) {
    final previous = _last[key];
    if (previous != null && now.difference(previous) < interval) {
      return false;
    }
    _last[key] = now;
    return true;
  }

  /// Historical ring rows are stored once per timestamp and kind.
  /// Realtime streams stay on the short gate.
  bool accept({
    required bool history,
    required String streamKey,
    required String historyKey,
    required DateTime now,
  }) {
    if (history) {
      return _history.add(historyKey);
    }
    return shouldPersist(streamKey, now);
  }
}
