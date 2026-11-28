import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bylwapp/data/sqlite_health_repository.dart';
import 'package:bylwapp/models/health_record.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('sqlite repository deduplicates and marks uploads', () async {
    final path = p.join(
      Directory.systemTemp.path,
      'bylw-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final repository = await SqliteHealthRepository.openPath(path);
    addTearDown(() async {
      await repository.close();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    });

    const device = HealthDevice(
      name: 'H303',
      kind: 'heart_rate',
      address: 'F0:12:34:56:78:9A',
      model: 'Magene H303',
    );
    final measurement = HealthMeasurement(
      type: 'heart_rate',
      unit: 'bpm',
      recordedAt: DateTime.utc(2026, 11, 27, 9),
      values: const {'bpm': 72, 'sensor_contact': 'detected'},
    );
    await repository.upsertDevice(device);
    expect(
      await repository.insertMeasurement(device.address, measurement),
      isTrue,
    );
    expect(
      await repository.insertMeasurement(device.address, measurement),
      isFalse,
    );

    final recent = await repository.listRecent();
    expect(recent, hasLength(1));
    expect(recent.single.measurement.values['bpm'], 72);
    expect(recent.single.synced, isFalse);

    await repository.markSynced([recent.single.id!]);
    expect(await repository.listUnsynced(), isEmpty);
  });
}
