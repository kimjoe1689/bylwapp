class ReminderDraft {
  ReminderDraft({
    required this.scheduleId,
    required this.kind,
    required this.due,
    this.ackWindow = const Duration(minutes: 15),
  });

  final String scheduleId;
  final String kind;
  DateTime due;
  Duration ackWindow;
  String disposition = 'SCHEDULED';
  DateTime? firedAt;
  DateTime? ackAt;

  int delayMs(DateTime now) {
    final start = firedAt ?? due;
    final end = ackAt ?? now;
    final ms = end.difference(start).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }
}

class ReminderEngine {
  final List<ReminderDraft> items = [];

  ReminderDraft schedule({
    required String scheduleId,
    required String kind,
    required DateTime due,
    Duration ackWindow = const Duration(minutes: 15),
  }) {
    final item = ReminderDraft(
      scheduleId: scheduleId,
      kind: kind,
      due: due,
      ackWindow: ackWindow,
    );
    items.add(item);
    return item;
  }

  List<ReminderDraft> tick(DateTime now) {
    final changed = <ReminderDraft>[];
    for (final item in items) {
      if (item.disposition == 'SCHEDULED' && !now.isBefore(item.due)) {
        item.disposition = 'COMMAND_LOGGED';
        item.firedAt = now;
        changed.add(item);
      } else if (item.disposition == 'COMMAND_LOGGED' &&
          item.firedAt != null &&
          now.isAfter(item.firedAt!.add(item.ackWindow))) {
        item.disposition = 'MISSED';
        changed.add(item);
      }
    }
    return changed;
  }

  ReminderDraft? acknowledge(String scheduleId, DateTime now) {
    final item = _find(scheduleId);
    if (item == null ||
        item.disposition != 'COMMAND_LOGGED' ||
        item.firedAt == null) {
      return null;
    }
    item.ackAt = now;
    item.disposition = now.isAfter(item.firedAt!.add(item.ackWindow))
        ? 'ACK_DELAYED'
        : 'ACK_TIMELY';
    return item;
  }

  ReminderDraft? censor(String scheduleId) {
    final item = _find(scheduleId);
    if (item == null ||
        item.disposition == 'ACK_TIMELY' ||
        item.disposition == 'ACK_DELAYED') {
      return null;
    }
    item.disposition = 'CENSORED';
    return item;
  }

  ReminderDraft? _find(String scheduleId) {
    for (final item in items) {
      if (item.scheduleId == scheduleId) {
        return item;
      }
    }
    return null;
  }
}

/// Operational stand-in for the thesis care-attention rule.
/// It is not a clinical judgment. It becomes true when a fired reminder has no
/// acknowledgment inside [window], or when no measurement arrived inside [window].
bool careAttentionOverdue({
  required DateTime now,
  required Duration window,
  DateTime? reminderFiredAt,
  bool reminderAcknowledged = false,
  DateTime? lastMeasurementAt,
}) {
  final reminderLate =
      reminderFiredAt != null &&
      !reminderAcknowledged &&
      now.isAfter(reminderFiredAt.add(window));
  final measurementGap =
      lastMeasurementAt == null || now.isAfter(lastMeasurementAt.add(window));
  return reminderLate || measurementGap;
}
