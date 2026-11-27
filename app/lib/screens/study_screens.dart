import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/journal/journal_store.dart';
import 'package:bylwapp/reminders/reminder_engine.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/usability/sus.dart';

class StudyBundle {
  StudyBundle({
    required this.journal,
    required this.prefs,
    required this.engine,
    required this.sessionId,
  });

  final JournalStore journal;
  final CollectorPrefs prefs;
  final ReminderEngine engine;
  final String sessionId;
  int _ticks = 0;
  DateTime? lastMeasurementAt;

  Future<void> journalReminder(ReminderDraft item) async {
    final now = DateTime.now().toUtc();
    await journal.append(
      CanonicalEvent(
        eventId: pathToken(
          'rem-${item.scheduleId}-${item.disposition}-$_ticks',
        ),
        deviceId: pathToken(prefs.collectorId),
        sessionId: sessionId,
        sensorAddress: 'local',
        sensorKind: 'collector',
        sensorModel: 'bylwapp',
        measurementType: 'reminder',
        unit: 'state',
        monotonicUs: _ticks++,
        wallTimeUtc: prefs.faultClockSkew ? null : zulu(now),
        clockState: prefs.faultClockSkew ? 'INVALID' : 'NTP_SYNCED',
        operatingState: prefs.faultClockSkew ? 'CLOCK_DEGRADED' : 'NOMINAL',
        values: {
          'schedule_id': item.scheduleId,
          'match_key': item.scheduleId,
          'kind': item.kind,
          'disposition': item.disposition,
          'delay_ms': item.delayMs(now),
        },
      ),
    );
  }
}

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key, required this.study, this.embedded = false});

  final StudyBundle study;
  final bool embedded;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  Timer? _timer;
  DateTime? _lastCareLog;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _add(String kind, int minutes) async {
    final id = 'rem-${DateTime.now().millisecondsSinceEpoch}';
    final item = widget.study.engine.schedule(
      scheduleId: id,
      kind: kind,
      due: DateTime.now().toUtc().add(Duration(minutes: minutes)),
    );
    await widget.study.journalReminder(item);
    if (mounted) setState(() {});
  }

  Future<void> _openAdd() async {
    var kind = 'MEDICATION';
    var minutes = 15;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('添加提醒', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ChoiceChip(
                        label: const Text('服药'),
                        avatar: const Icon(Icons.medication_outlined, size: 18),
                        selected: kind == 'MEDICATION',
                        onSelected: (_) => setSheet(() => kind = 'MEDICATION'),
                      ),
                      ChoiceChip(
                        label: const Text('喝水'),
                        avatar: const Icon(Icons.water_drop_outlined, size: 18),
                        selected: kind == 'HYDRATION',
                        onSelected: (_) => setSheet(() => kind = 'HYDRATION'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('多久之后'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in const [1, 5, 15, 30, 60])
                        ChoiceChip(
                          label: Text('$option 分钟'),
                          selected: minutes == option,
                          onSelected: (_) => setSheet(() => minutes = option),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('添加'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (saved == true) {
      await _add(kind, minutes);
    }
  }

  Future<void> _tick() async {
    final changed = widget.study.engine.tick(DateTime.now().toUtc());
    for (final item in changed) {
      await widget.study.journalReminder(item);
    }
    await _maybeCare();
    setState(() {});
  }

  Future<void> _ack(ReminderDraft item) async {
    final updated = widget.study.engine.acknowledge(
      item.scheduleId,
      DateTime.now().toUtc(),
    );
    if (updated != null) {
      await widget.study.journalReminder(updated);
    }
    setState(() {});
  }

  Future<void> _miss(ReminderDraft item) async {
    final updated = widget.study.engine.markMissed(
      item.scheduleId,
      DateTime.now().toUtc(),
    );
    if (updated != null) {
      await widget.study.journalReminder(updated);
    }
    if (mounted) setState(() {});
  }

  Future<void> _censor(ReminderDraft item) async {
    final updated = widget.study.engine.censor(item.scheduleId);
    if (updated != null) {
      await widget.study.journalReminder(updated);
    }
    setState(() {});
  }

  Future<void> _maybeCare() async {
    final window = Duration(minutes: widget.study.prefs.careWindowMinutes);
    ReminderDraft? fired;
    for (final item in widget.study.engine.items) {
      if (item.firedAt != null) {
        fired = item;
      }
    }
    final overdue = careAttentionOverdue(
      now: DateTime.now().toUtc(),
      window: window,
      reminderFiredAt: fired?.firedAt,
      reminderAcknowledged:
          fired != null &&
          (fired.disposition == 'ACK_TIMELY' ||
              fired.disposition == 'ACK_DELAYED'),
      lastMeasurementAt: widget.study.lastMeasurementAt,
    );
    if (!overdue) {
      return;
    }
    final now = DateTime.now().toUtc();
    if (_lastCareLog != null && now.difference(_lastCareLog!) < window) {
      return;
    }
    _lastCareLog = now;
    await widget.study.journal.append(
      CanonicalEvent(
        eventId: pathToken('care-${DateTime.now().microsecondsSinceEpoch}'),
        deviceId: pathToken(widget.study.prefs.collectorId),
        sessionId: widget.study.sessionId,
        sensorAddress: 'local',
        sensorKind: 'collector',
        sensorModel: 'bylwapp',
        measurementType: 'care_attention',
        unit: 'flag',
        monotonicUs: DateTime.now().microsecondsSinceEpoch,
        wallTimeUtc: zulu(DateTime.now()),
        clockState: 'NTP_SYNCED',
        operatingState: 'NOMINAL',
        values: {
          'flag': 'CARE_ATTENTION_OVERDUE',
          'match_key': fired?.scheduleId ?? 'measurement-gap',
          'reason': 'window',
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('提醒', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '服药和喝水先记在手机上。到点后确认，或标成错过、删失。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _openAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('添加提醒'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _tick,
                    icon: const Icon(Icons.update),
                    label: const Text('检查到期'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _tick,
            child: _ReminderList(
              items: widget.study.engine.items,
              onAck: _ack,
              onMiss: _miss,
              onCensor: _censor,
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(body: body);
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.items,
    required this.onAck,
    required this.onMiss,
    required this.onCensor,
  });

  final List<ReminderDraft> items;
  final Future<void> Function(ReminderDraft item) onAck;
  final Future<void> Function(ReminderDraft item) onMiss;
  final Future<void> Function(ReminderDraft item) onCensor;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 48),
          Center(child: Icon(Icons.event_available_outlined, size: 48)),
          SizedBox(height: 12),
          Text('还没有提醒', textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('用上面的「添加提醒」记下服药或喝水', textAlign: TextAlign.center),
        ],
      );
    }
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    bool finished(ReminderDraft item) {
      return item.disposition == 'ACK_TIMELY' ||
          item.disposition == 'ACK_DELAYED' ||
          item.disposition == 'MISSED' ||
          item.disposition == 'CENSORED';
    }

    final today = <ReminderDraft>[];
    final upcoming = <ReminderDraft>[];
    final done = <ReminderDraft>[];
    for (final item in items) {
      if (finished(item)) {
        done.add(item);
      } else if (item.due.toLocal().isBefore(endOfToday)) {
        today.add(item);
      } else {
        upcoming.add(item);
      }
    }
    final sections = [('今天', today), ('即将到期', upcoming), ('已完成', done)];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final section in sections)
          if (section.$2.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                section.$1,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final item in section.$2)
              _ReminderTile(
                item: item,
                onAck: finished(item) ? null : () => onAck(item),
                onMiss: finished(item) ? null : () => onMiss(item),
                onCensor: finished(item) ? null : () => onCensor(item),
              ),
          ],
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.item,
    required this.onAck,
    required this.onMiss,
    required this.onCensor,
  });

  final ReminderDraft item;
  final VoidCallback? onAck;
  final VoidCallback? onMiss;
  final VoidCallback? onCensor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final water = item.kind == 'HYDRATION';
    final due = item.due.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final when = '${two(due.hour)}:${two(due.minute)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: water
              ? scheme.secondaryContainer
              : scheme.primaryContainer,
          child: Icon(
            water ? Icons.water_drop_outlined : Icons.medication_outlined,
          ),
        ),
        title: Text(water ? '喝水' : '服药'),
        subtitle: Text('$when · ${_reminderLabel(item.disposition)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.disposition == 'COMMAND_LOGGED')
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(64, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onAck,
                child: const Text('确认'),
              ),
            if (onMiss != null || onCensor != null)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'miss') onMiss?.call();
                  if (value == 'censor') onCensor?.call();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'miss', child: Text('错过')),
                  PopupMenuItem(value: 'censor', child: Text('删失')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _reminderLabel(String disposition) {
  switch (disposition) {
    case 'SCHEDULED':
      return '已安排';
    case 'COMMAND_LOGGED':
      return '到期';
    case 'ACK_TIMELY':
      return '及时确认';
    case 'ACK_DELAYED':
      return '延迟确认';
    case 'MISSED':
      return '错过';
    case 'CENSORED':
      return '已删失';
    default:
      return disposition;
  }
}

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.study});

  final StudyBundle study;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _key = TextEditingController();
  String _type = 'worn';
  String _value = 'true';

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final match = _key.text.trim().isEmpty
        ? 'obs-${DateTime.now().millisecondsSinceEpoch}'
        : _key.text.trim();
    await widget.study.journal.append(
      CanonicalEvent(
        eventId: pathToken(
          'gt-$match-${DateTime.now().microsecondsSinceEpoch}',
        ),
        deviceId: pathToken(widget.study.prefs.collectorId),
        sessionId: widget.study.sessionId,
        sensorAddress: 'observer',
        sensorKind: 'collector',
        sensorModel: 'observer-ledger',
        measurementType: _type == 'worn'
            ? 'worn_state'
            : (_type == 'data_gap' ? 'data_gap' : 'care_attention'),
        unit: 'reference',
        monotonicUs: DateTime.now().microsecondsSinceEpoch,
        wallTimeUtc: zulu(DateTime.now()),
        clockState: 'NTP_SYNCED',
        operatingState: 'NOMINAL',
        values: {
          'match_key': pathToken(match),
          'reference_type': _type,
          'reference_value': _value,
          'observer': 'in-app',
          if (_type == 'worn') 'worn': _value == 'true',
          if (_type == 'data_gap') 'gap': _value == 'true',
          if (_type == 'care_attention')
            'flag': _value == 'true' ? 'CARE_ATTENTION_OVERDUE' : 'CLEAR',
        },
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对照记录已写入本地日志，同步后才能进入服务器指标。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('独立对照账')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('观察者在这里记下对照事实。没有对照行时，RQ2 比例保持不可计算，不会被写成 0。'),
          DropdownButton<String>(
            value: _type,
            items: const [
              DropdownMenuItem(value: 'worn', child: Text('是否佩戴')),
              DropdownMenuItem(value: 'data_gap', child: Text('是否数据空档')),
              DropdownMenuItem(value: 'care_attention', child: Text('是否照护逾期')),
              DropdownMenuItem(
                value: 'reminder_perceived',
                child: Text('是否看见提醒'),
              ),
            ],
            onChanged: (value) => setState(() => _type = value ?? 'worn'),
          ),
          DropdownButton<String>(
            value: _value,
            items: const [
              DropdownMenuItem(value: 'true', child: Text('是')),
              DropdownMenuItem(value: 'false', child: Text('否')),
            ],
            onChanged: (value) => setState(() => _value = value ?? 'true'),
          ),
          TextField(
            controller: _key,
            decoration: const InputDecoration(labelText: '对照键 match_key'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('写入对照')),
        ],
      ),
    );
  }
}

class SusScreen extends StatefulWidget {
  const SusScreen({super.key, required this.study});

  final StudyBundle study;

  @override
  State<SusScreen> createState() => _SusScreenState();
}

class _SusScreenState extends State<SusScreen> {
  final List<int> _answers = List<int>.filled(10, 0);
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final response = SusResponse(_answers);
    await widget.study.journal.append(
      CanonicalEvent(
        eventId: pathToken('sus-${DateTime.now().microsecondsSinceEpoch}'),
        deviceId: pathToken(widget.study.prefs.collectorId),
        sessionId: widget.study.sessionId,
        sensorAddress: 'local',
        sensorKind: 'collector',
        sensorModel: 'bylwapp',
        measurementType: 'sus',
        unit: 'score',
        monotonicUs: DateTime.now().microsecondsSinceEpoch,
        wallTimeUtc: zulu(DateTime.now()),
        clockState: 'NTP_SYNCED',
        operatingState: 'NOMINAL',
        values: {
          for (var i = 0; i < 10; i++) 'q${i + 1}': _answers[i],
          'match_key': 'sus',
        },
      ),
    );
    if (!mounted) {
      return;
    }
    final score = response.score;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(score == null ? '有题目未作答，不计算总分。' : '已记录，分数 $score'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SUS ${_page + 1}/10')),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_page + 1) / 10),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: 10,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        susPrompts[index],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      Slider(
                        value: _answers[index].toDouble(),
                        min: 0,
                        max: 5,
                        divisions: 5,
                        label: _answers[index] == 0
                            ? '未答'
                            : '${_answers[index]}',
                        onChanged: (value) =>
                            setState(() => _answers[index] = value.round()),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: index == 9
                            ? _save
                            : () => _pages.nextPage(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOut,
                              ),
                        child: Text(index == 9 ? '保存问卷' : '下一题'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TaskLogScreen extends StatefulWidget {
  const TaskLogScreen({super.key, required this.study});

  final StudyBundle study;

  @override
  State<TaskLogScreen> createState() => _TaskLogScreenState();
}

class _TaskLogScreenState extends State<TaskLogScreen> {
  DateTime? _started;

  Future<void> _finish(String disposition) async {
    final start = _started;
    final duration = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds;
    await widget.study.journal.append(
      CanonicalEvent(
        eventId: pathToken('task-${DateTime.now().microsecondsSinceEpoch}'),
        deviceId: pathToken(widget.study.prefs.collectorId),
        sessionId: widget.study.sessionId,
        sensorAddress: 'local',
        sensorKind: 'collector',
        sensorModel: 'bylwapp',
        measurementType: 'usability_task',
        unit: 'ms',
        monotonicUs: DateTime.now().microsecondsSinceEpoch,
        wallTimeUtc: zulu(DateTime.now()),
        clockState: 'NTP_SYNCED',
        operatingState: 'NOMINAL',
        values: {
          'task_id': 'recognize-reminder',
          'disposition': disposition,
          'duration_ms': duration,
          'match_key': 'task',
        },
      ),
    );
    setState(() => _started = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务计时')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: () => setState(() => _started = DateTime.now()),
            child: const Text('开始：认出一条提醒'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _started == null ? null : () => _finish('unassisted'),
            child: const Text('独立完成'),
          ),
          FilledButton(
            onPressed: _started == null ? null : () => _finish('assisted'),
            child: const Text('协助完成'),
          ),
          FilledButton(
            onPressed: _started == null ? null : () => _finish('abandoned'),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
  }
}
