/// Decides when a fast sensor stream may be written to the journal.
class PersistGate {
  PersistGate({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  final Map<String, DateTime> _last = {};

  bool shouldPersist(String key, DateTime now) {
    final previous = _last[key];
    if (previous != null && now.difference(previous) < interval) {
      return false;
    }
    _last[key] = now;
    return true;
  }
}
