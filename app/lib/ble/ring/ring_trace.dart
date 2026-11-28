import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bylwapp/ble/ring/ring_parser.dart';

class RingPacketLog {
  const RingPacketLog({
    this.id,
    required this.at,
    required this.direction,
    required this.characteristic,
    required this.hex,
    required this.label,
    required this.solicited,
    this.cmd,
    this.sub,
  });

  final int? id;
  final DateTime at;
  final String direction;
  final String characteristic;
  final String hex;
  final String label;
  final bool solicited;
  final int? cmd;
  final int? sub;

  bool get unknown => ringLabelUnknown(label);

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'direction': direction,
    'characteristic': characteristic,
    'hex': hex,
    'label': label,
    'solicited': solicited,
    'cmd': cmd,
    'sub': sub,
  };
}

class RingTraceGroup {
  const RingTraceGroup({
    required this.cmd,
    required this.sub,
    required this.count,
    required this.first,
    required this.last,
    required this.sampleHex,
    required this.label,
  });

  final int? cmd;
  final int? sub;
  final int count;
  final DateTime first;
  final DateTime last;
  final String sampleHex;
  final String label;
}

/// Remembers recent transmits so a reply of the same command is solicited.
class RingTxWindow {
  final Map<int, DateTime> _last = {};

  void sent(int command, DateTime at) {
    _last[command] = at;
  }

  bool replySolicited(int command, DateTime at) {
    final last = _last[command];
    if (last == null) return false;
    final gap = at.difference(last);
    return !gap.isNegative && gap <= const Duration(seconds: 2);
  }
}

class RingTraceStore {
  RingTraceStore(this._db);

  final Database _db;

  static Future<RingTraceStore> open() async {
    return openPath(p.join(await getDatabasesPath(), 'ring-trace.db'));
  }

  static Future<RingTraceStore> openPath(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ring_trace (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at TEXT NOT NULL,
            direction TEXT NOT NULL,
            characteristic TEXT NOT NULL,
            hex TEXT NOT NULL,
            label TEXT NOT NULL,
            solicited INTEGER NOT NULL,
            cmd INTEGER,
            sub INTEGER
          )
        ''');
      },
    );
    return RingTraceStore(db);
  }

  Future<void> close() => _db.close();

  Future<void> insert(RingPacketLog log) async {
    await _db.insert('ring_trace', {
      'at': log.at.toUtc().toIso8601String(),
      'direction': log.direction,
      'characteristic': log.characteristic,
      'hex': log.hex,
      'label': log.label,
      'solicited': log.solicited ? 1 : 0,
      'cmd': log.cmd,
      'sub': log.sub,
    });
  }

  Future<List<RingPacketLog>> recent({int limit = 5000}) async {
    final rows = await _db.query(
      'ring_trace',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(_log).toList();
  }

  Future<List<RingTraceGroup>> groups() async {
    final rows = await _db.rawQuery('''
      SELECT cmd, sub, COUNT(*) AS n, MIN(at) AS first_at, MAX(at) AS last_at,
             MAX(label) AS label, MAX(hex) AS hex
      FROM ring_trace
      GROUP BY cmd, sub
      ORDER BY n DESC
    ''');
    return [
      for (final row in rows)
        RingTraceGroup(
          cmd: row['cmd'] as int?,
          sub: row['sub'] as int?,
          count: row['n'] as int,
          first: DateTime.parse(row['first_at'] as String).toUtc(),
          last: DateTime.parse(row['last_at'] as String).toUtc(),
          sampleHex: row['hex'] as String,
          label: row['label'] as String,
        ),
    ];
  }

  Future<void> clear() => _db.delete('ring_trace');
}

RingPacketLog _log(Map<String, Object?> row) {
  return RingPacketLog(
    id: row['id'] as int?,
    at: DateTime.parse(row['at'] as String).toUtc(),
    direction: row['direction'] as String,
    characteristic: row['characteristic'] as String,
    hex: row['hex'] as String,
    label: row['label'] as String,
    solicited: (row['solicited'] as int) == 1,
    cmd: row['cmd'] as int?,
    sub: row['sub'] as int?,
  );
}

String ringTracesToJson(List<RingPacketLog> rows) {
  return jsonEncode([for (final row in rows) row.toJson()]);
}

String ringTracesToCsv(List<RingPacketLog> rows) {
  final lines = <String>[
    'at,direction,characteristic,cmd,sub,solicited,label,hex',
  ];
  for (final row in rows) {
    lines.add(
      [
        row.at.toUtc().toIso8601String(),
        row.direction,
        row.characteristic,
        row.cmd?.toString() ?? '',
        row.sub?.toString() ?? '',
        row.solicited ? '1' : '0',
        '"${row.label.replaceAll('"', '""')}"',
        '"${row.hex}"',
      ].join(','),
    );
  }
  return lines.join('\n');
}
