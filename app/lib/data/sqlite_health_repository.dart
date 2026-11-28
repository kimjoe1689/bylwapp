import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';

class SqliteHealthRepository implements HealthRepository {
  SqliteHealthRepository(this._db);

  final Database _db;

  static Future<SqliteHealthRepository> open() async {
    return openPath(p.join(await getDatabasesPath(), 'bylwapp.db'));
  }

  static Future<SqliteHealthRepository> openPath(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE devices (
            address TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            model TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE measurements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_address TEXT NOT NULL,
            type TEXT NOT NULL,
            unit TEXT NOT NULL,
            recorded_at TEXT NOT NULL,
            values_json TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            UNIQUE(device_address, type, recorded_at)
          )
        ''');
      },
    );
    return SqliteHealthRepository(db);
  }

  Future<void> close() => _db.close();

  /// History rows stored the ring's local clock as UTC. Shift them back once.
  Future<int> correctRingHistoryClock() async {
    final rows = await _db.rawQuery('''
      SELECT m.id, m.recorded_at
      FROM measurements m
      JOIN devices d ON d.address = m.device_address
      WHERE d.kind = 'ring' AND m.values_json LIKE '%"stream":"history"%'
    ''');
    var changed = 0;
    for (final row in rows) {
      final stored = DateTime.parse(row['recorded_at'] as String).toUtc();
      final fixed = DateTime(
        stored.year,
        stored.month,
        stored.day,
        stored.hour,
        stored.minute,
        stored.second,
        stored.millisecond,
        stored.microsecond,
      ).toUtc();
      if (fixed == stored) continue;
      try {
        await _db.update(
          'measurements',
          {'recorded_at': fixed.toIso8601String()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        changed++;
      } catch (_) {}
    }
    return changed;
  }

  @override
  Future<void> upsertDevice(HealthDevice device) async {
    await _db.insert('devices', {
      'address': device.address,
      'name': device.name,
      'kind': device.kind,
      'model': device.model,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<bool> insertMeasurement(
    String deviceAddress,
    HealthMeasurement measurement,
  ) async {
    await _db.rawInsert(
      '''
      INSERT OR IGNORE INTO measurements
        (device_address, type, unit, recorded_at, values_json, synced, created_at)
      VALUES (?, ?, ?, ?, ?, 0, ?)
      ''',
      [
        deviceAddress,
        measurement.type,
        measurement.unit,
        measurement.recordedAt.toUtc().toIso8601String(),
        jsonEncode(measurement.values),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    final changed =
        Sqflite.firstIntValue(await _db.rawQuery('SELECT changes()')) ?? 0;
    return changed > 0;
  }

  @override
  Future<List<LocalRecord>> listRecent({int limit = 100}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT m.id, m.type, m.unit, m.recorded_at, m.values_json, m.synced,
             d.address, d.name, d.kind, d.model
      FROM measurements m
      JOIN devices d ON d.address = m.device_address
      ORDER BY m.recorded_at DESC, m.id DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(_record).toList();
  }

  @override
  Future<List<LocalRecord>> listUnsynced() async {
    final rows = await _db.rawQuery('''
      SELECT m.id, m.type, m.unit, m.recorded_at, m.values_json, m.synced,
             d.address, d.name, d.kind, d.model
      FROM measurements m
      JOIN devices d ON d.address = m.device_address
      WHERE m.synced = 0
      ORDER BY m.recorded_at ASC, m.id ASC
      ''');
    return rows.map(_record).toList();
  }

  @override
  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final marks = List.filled(ids.length, '?').join(', ');
    await _db.rawUpdate(
      'UPDATE measurements SET synced = 1 WHERE id IN ($marks)',
      ids,
    );
  }
}

LocalRecord _record(Map<String, Object?> row) {
  final values = <String, Object?>{};
  final decoded = jsonDecode(row['values_json'] as String);
  if (decoded is Map) {
    decoded.forEach((key, value) => values['$key'] = value);
  }
  return LocalRecord(
    id: row['id'] as int,
    synced: (row['synced'] as int) == 1,
    device: HealthDevice(
      name: row['name'] as String,
      kind: row['kind'] as String,
      address: row['address'] as String,
      model: row['model'] as String,
    ),
    measurement: HealthMeasurement(
      type: row['type'] as String,
      unit: row['unit'] as String,
      recordedAt: DateTime.parse(row['recorded_at'] as String).toUtc(),
      values: values,
    ),
  );
}
