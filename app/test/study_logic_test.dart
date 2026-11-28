import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/journal/journal_store.dart';
import 'package:bylwapp/reminders/reminder_engine.dart';
import 'package:bylwapp/sync/sync_worker.dart';
import 'package:bylwapp/usability/sus.dart';

void main() {
  test('canonical hash matches the Go vector', () {
    final event = CanonicalEvent(
      eventId: 'evt-0001',
      deviceId: 'phone-1',
      sessionId: 'sess-1',
      sensorAddress: 'AA-BB-CC-DD-EE-01',
      sensorKind: 'blood_pressure',
      sensorModel: 'Yuwell YE680B',
      measurementType: 'blood_pressure',
      unit: 'mmHg',
      monotonicUs: 1000,
      wallTimeUtc: '2026-11-27T08:15:09Z',
      clockState: 'NTP_SYNCED',
      operatingState: 'NOMINAL',
      values: const {'systolic': 120, 'diastolic': 80, 'pulse': 72},
    );
    expect(
      event.canonicalJson,
      '{"clock_state":"NTP_SYNCED","device_id":"phone-1","event_id":"evt-0001","measurement_type":"blood_pressure","monotonic_us":1000,"operating_state":"NOMINAL","schema_version":"bylw-measure/1","sensor_address":"AA-BB-CC-DD-EE-01","sensor_kind":"blood_pressure","sensor_model":"Yuwell YE680B","session_id":"sess-1","unit":"mmHg","values":{"diastolic":80,"pulse":72,"systolic":120},"wall_time_utc":"2026-11-27T08:15:09Z"}',
    );
    expect(
      event.payloadHash,
      '9b9e90354ba15670c60fdf194a44d52eda406ca85a6c8e9c14c8ea14043777e4',
    );
    expect(sha256.convert(const []).toString(), isNotEmpty);
  });

  test('reminder ack, miss, and care window', () {
    final engine = ReminderEngine();
    final due = DateTime.utc(2026, 11, 27, 8);
    engine.schedule(
      scheduleId: 'med-1',
      kind: 'MEDICATION',
      due: due,
      ackWindow: const Duration(minutes: 15),
    );
    expect(engine.tick(due.subtract(const Duration(seconds: 1))), isEmpty);
    final fired = engine.tick(due);
    expect(fired.single.disposition, 'COMMAND_LOGGED');
    expect(
      engine
          .acknowledge('med-1', due.add(const Duration(minutes: 1)))!
          .disposition,
      'ACK_TIMELY',
    );

    final late = ReminderEngine();
    late.schedule(
      scheduleId: 'hyd-1',
      kind: 'HYDRATION',
      due: due,
      ackWindow: const Duration(minutes: 5),
    );
    late.tick(due);
    expect(
      late.tick(due.add(const Duration(minutes: 6))).single.disposition,
      'MISSED',
    );
    expect(
      careAttentionOverdue(
        now: due.add(const Duration(minutes: 40)),
        window: const Duration(minutes: 30),
        reminderFiredAt: due,
        lastMeasurementAt: due,
      ),
      isTrue,
    );
    expect(
      careAttentionOverdue(
        now: due.add(const Duration(minutes: 10)),
        window: const Duration(minutes: 30),
        reminderFiredAt: due,
        reminderAcknowledged: true,
        lastMeasurementAt: due,
      ),
      isFalse,
    );
  });

  test('SUS score needs every answer', () {
    expect(const SusResponse([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]).score, 100);
    expect(const SusResponse([5]).score, isNull);
  });

  test('journal confirms the written hash', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'journal-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final store = await JournalStore.openPath(path);
    addTearDown(() async {
      await store.close();
      final file = File(path);
      if (await file.exists()) await file.delete();
    });
    final event = CanonicalEvent(
      eventId: 'evt-local',
      deviceId: 'phone-1',
      sessionId: 'sess-1',
      sensorAddress: 'local',
      sensorKind: 'collector',
      sensorModel: 'bylwapp',
      measurementType: 'reminder',
      unit: 'state',
      monotonicUs: 1,
      wallTimeUtc: '2026-11-27T08:15:09Z',
      clockState: 'NTP_SYNCED',
      operatingState: 'NOMINAL',
      values: const {
        'schedule_id': 'med-1',
        'disposition': 'COMMAND_LOGGED',
        'kind': 'MEDICATION',
        'delay_ms': 0,
      },
    );
    expect(await store.append(event), isTrue);
    expect(await store.append(event), isTrue);
    expect((await store.pending()).single.payloadHash, event.payloadHash);
  });

  test('sync worker reconciles a timeout by read-back', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'sync-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final store = await JournalStore.openPath(path);
    addTearDown(() async => store.close());
    final event = CanonicalEvent(
      eventId: 'evt-sync',
      deviceId: 'phone-1',
      sessionId: 'sess-1',
      sensorAddress: 'local',
      sensorKind: 'collector',
      sensorModel: 'bylwapp',
      measurementType: 'operating_state',
      unit: 'state',
      monotonicUs: 3,
      wallTimeUtc: '2026-11-27T08:15:09Z',
      clockState: 'NTP_SYNCED',
      operatingState: 'NOMINAL',
      values: const {'state': 'NOMINAL'},
    );
    await store.append(event);
    final worker = SyncWorker(
      journal: store,
      baseUrl: 'http://example.test',
      token: 'device-token',
      faults: const SyncFaults(timeoutAfterCommit: true),
      client: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            '{"result":"stored","payload_hash":"${event.payloadHash}"}',
            201,
          );
        }
        return http.Response('{"payload_hash":"${event.payloadHash}"}', 200);
      }),
    );
    expect(await worker.syncOnce(), 1);
    expect((await store.recent()).single.syncState, 'synced');
  });

  test('ingest 403 adopts the device that owns the token', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = p.join(
      Directory.systemTemp.path,
      'sync-403-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final store = await JournalStore.openPath(path);
    addTearDown(() async => store.close());
    final event = CanonicalEvent(
      eventId: 'evt-ring',
      deviceId: 'phone-wrong',
      sessionId: 'sess-1',
      sensorAddress: '32-33-47-31-06-07',
      sensorKind: 'ring',
      sensorModel: 'R12_0607',
      measurementType: 'heart_rate',
      unit: 'bpm',
      monotonicUs: 82,
      wallTimeUtc: '2026-11-28T07:23:00Z',
      clockState: 'NTP_SYNCED',
      operatingState: 'NOMINAL',
      values: const {'bpm': 82},
    );
    await store.append(event);
    final paths = <String>[];
    final worker = SyncWorker(
      journal: store,
      baseUrl: 'http://example.test',
      token: 'device-token',
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.contains('phone-wrong')) {
          return http.Response(
            '{"error":"device token does not match the path","device_id":"phone-real"}',
            403,
          );
        }
        return http.Response('{"result":"stored"}', 201);
      }),
    );
    expect(await worker.syncOnce(), 1);
    expect(paths, [
      '/api/v1/devices/phone-wrong/events',
      '/api/v1/devices/phone-real/events',
    ]);
    expect((await store.recent()).single.event.deviceId, 'phone-real');
  });

  test(
    'ingest 403 without a named device renews a token for the event',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final path = p.join(
        Directory.systemTemp.path,
        'sync-renew-${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final store = await JournalStore.openPath(path);
      addTearDown(() async => store.close());
      final event = CanonicalEvent(
        eventId: 'evt-ring-2',
        deviceId: 'phone-kept',
        sessionId: 'sess-1',
        sensorAddress: '32-33-47-31-06-07',
        sensorKind: 'ring',
        sensorModel: 'R12_0607',
        measurementType: 'heart_rate',
        unit: 'bpm',
        monotonicUs: 80,
        wallTimeUtc: '2026-11-28T07:23:00Z',
        clockState: 'NTP_SYNCED',
        operatingState: 'NOMINAL',
        values: const {'bpm': 80},
      );
      await store.append(event);
      final headers = <String>[];
      final worker = SyncWorker(
        journal: store,
        baseUrl: 'http://example.test',
        token: 'stale',
        renewToken: (id) async {
          expect(id, 'phone-kept');
          return 'fresh';
        },
        client: MockClient((request) async {
          headers.add(request.headers['authorization'] ?? '');
          if (request.headers['authorization'] == 'Bearer stale') {
            return http.Response(
              '{"error":"device token does not match the path"}',
              403,
            );
          }
          return http.Response('{"result":"stored"}', 201);
        }),
      );
      expect(await worker.syncOnce(), 1);
      expect(headers, ['Bearer stale', 'Bearer fresh']);
    },
  );
}
