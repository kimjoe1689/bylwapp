import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bylwapp/journal/canonical_event.dart';

class JournalRecord {
  const JournalRecord({
    required this.event,
    required this.payloadHash,
    required this.syncState,
    required this.attempts,
    required this.lastError,
    this.serverReceivedAt,
  });

  final CanonicalEvent event;
  final String payloadHash;
  final String syncState;
  final int attempts;
  final String lastError;
  final String? serverReceivedAt;
}

class JournalStore {
  JournalStore(this._db);

  final Database _db;

  static Future<JournalStore> open() async {
    return openPath(p.join(await getDatabasesPath(), 'bylw-journal.db'));
  }

  static Future<JournalStore> openPath(String path) async {
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE journal (
            event_id TEXT PRIMARY KEY,
            canonical_json TEXT NOT NULL,
            payload_hash TEXT NOT NULL,
            sync_state TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            last_error TEXT NOT NULL,
            server_received_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
    return JournalStore(db);
  }

  Future<void> close() => _db.close();

  /// Local confirmation: write the canonical row, then read it back.
  Future<bool> append(CanonicalEvent event) async {
    final body = event.canonicalJson;
    final hash = event.payloadHash;
    await _db.rawInsert(
      '''
      INSERT OR IGNORE INTO journal
        (event_id, canonical_json, payload_hash, sync_state, attempts, last_error, created_at)
      VALUES (?, ?, ?, 'pending', 0, '', ?)
      ''',
      [event.eventId, body, hash, DateTime.now().toUtc().toIso8601String()],
    );
    final rows = await _db.query(
      'journal',
      where: 'event_id = ?',
      whereArgs: [event.eventId],
    );
    if (rows.isEmpty) {
      return false;
    }
    return rows.single['payload_hash'] == hash &&
        rows.single['canonical_json'] == body;
  }

  /// Rewrites the stored event, keeping [event.eventId].
  Future<void> replace(CanonicalEvent event, {bool pending = true}) async {
    await _db.update(
      'journal',
      {
        'canonical_json': event.canonicalJson,
        'payload_hash': event.payloadHash,
        if (pending) 'sync_state': 'pending',
        if (pending) 'last_error': '',
      },
      where: 'event_id = ?',
      whereArgs: [event.eventId],
    );
  }

  Future<List<JournalRecord>> all() async {
    final rows = await _db.query('journal', orderBy: 'created_at ASC');
    return rows.map(_record).toList();
  }

  Future<String?> latestSyncedAt() async {
    final rows = await _db.query(
      'journal',
      columns: ['server_received_at'],
      where: "sync_state = 'synced' AND server_received_at IS NOT NULL",
      orderBy: 'server_received_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['server_received_at'] as String?;
  }

  Future<List<JournalRecord>> pending() async {
    final rows = await _db.query(
      'journal',
      where: "sync_state = 'pending' OR sync_state = 'retry_failed'",
      orderBy: 'created_at ASC',
    );
    return rows.map(_record).toList();
  }

  /// Newest matching rows. [offset] skips matches, not raw table rows.
  Future<List<JournalRecord>> matching({
    required bool Function(JournalRecord row) match,
    int limit = 20,
    int offset = 0,
  }) async {
    final found = <JournalRecord>[];
    var skipped = 0;
    var dbOffset = 0;
    const batch = 80;
    while (found.length < limit) {
      final rows = await _db.query(
        'journal',
        orderBy: 'created_at DESC',
        limit: batch,
        offset: dbOffset,
      );
      if (rows.isEmpty) {
        break;
      }
      dbOffset += rows.length;
      for (final row in rows.map(_record)) {
        if (!match(row)) {
          continue;
        }
        if (skipped < offset) {
          skipped++;
          continue;
        }
        found.add(row);
        if (found.length == limit) {
          return found;
        }
      }
      if (rows.length < batch) {
        break;
      }
    }
    return found;
  }

  Future<List<JournalRecord>> recent({int limit = 100}) async {
    final rows = await _db.query(
      'journal',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_record).toList();
  }

  Future<void> mark(
    String eventId, {
    required String state,
    String error = '',
    String? serverReceivedAt,
    int? attempts,
  }) async {
    await _db.update(
      'journal',
      {
        'sync_state': state,
        'last_error': error,
        'server_received_at': ?serverReceivedAt,
        'attempts': ?attempts,
      },
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }
}

JournalRecord _record(Map<String, Object?> row) {
  final decoded =
      jsonDecode(row['canonical_json'] as String) as Map<String, dynamic>;
  final values = <String, Object?>{};
  final rawValues = decoded['values'];
  if (rawValues is Map) {
    rawValues.forEach((key, value) => values['$key'] = value);
  }
  return JournalRecord(
    payloadHash: row['payload_hash'] as String,
    syncState: row['sync_state'] as String,
    attempts: row['attempts'] as int,
    lastError: (row['last_error'] as String?) ?? '',
    serverReceivedAt: row['server_received_at'] as String?,
    event: CanonicalEvent(
      eventId: decoded['event_id'] as String,
      deviceId: decoded['device_id'] as String,
      sessionId: decoded['session_id'] as String,
      sensorAddress: decoded['sensor_address'] as String,
      sensorKind: decoded['sensor_kind'] as String,
      sensorModel: decoded['sensor_model'] as String,
      measurementType: decoded['measurement_type'] as String,
      unit: decoded['unit'] as String,
      monotonicUs: (decoded['monotonic_us'] as num).toInt(),
      wallTimeUtc: decoded['wall_time_utc'] as String?,
      clockState: decoded['clock_state'] as String,
      operatingState: decoded['operating_state'] as String,
      values: values,
    ),
  );
}
