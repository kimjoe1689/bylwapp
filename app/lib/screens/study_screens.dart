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
  const ReminderScreen({super.key, required this.study});

  final StudyBundle study;

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  String _kind = 'MEDICATION';
  final _minutes = TextEditingController(text: '1');

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final minutes = int.tryParse(_minutes.text) ?? 1;
    final id = 'rem-${DateTime.now().millisecondsSinceEpoch}';
    final item = widget.study.engine.schedule(
      scheduleId: id,
      kind: _kind,
      due: DateTime.now().toUtc().add(Duration(minutes: minutes)),
    );
    await widget.study.journalReminder(item);
    setState(() {});
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
    return Scaffold(
      appBar: AppBar(title: const Text('提醒')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('服药和喝水提醒会先写入本地日志。到点后点“检查到期”，再确认、错过或标记删失。'),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: _kind,
            items: const [
              DropdownMenuItem(value: 'MEDICATION', child: Text('服药')),
              DropdownMenuItem(value: 'HYDRATION', child: Text('喝水')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'MEDICATION'),
          ),
          TextField(
            controller: _minutes,
            decoration: const InputDecoration(labelText: '几分钟后提醒'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _add, child: const Text('添加提醒')),
          FilledButton(onPressed: _tick, child: const Text('检查到期')),
          for (final item in widget.study.engine.items)
            ListTile(
              title: Text('${item.kind} ${item.disposition}'),
              subtitle: Text(item.scheduleId),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => _ack(item),
                    child: const Text('确认'),
                  ),
                  TextButton(
                    onPressed: () => _censor(item),
                    child: const Text('删失'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('SUS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('10 题都回答后才计算分数。这只是记录，不是已完成的伦理评估。'),
          for (var i = 0; i < susPrompts.length; i++) ...[
            Text(susPrompts[i]),
            Slider(
              value: _answers[i].toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              label: _answers[i] == 0 ? '未答' : '${_answers[i]}',
              onChanged: (value) => setState(() => _answers[i] = value.round()),
            ),
          ],
          FilledButton(onPressed: _save, child: const Text('保存问卷')),
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
