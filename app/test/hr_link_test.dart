import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/ble/heart_rate/hr_parser.dart';
import 'package:bylwapp/ble/persist_gate.dart';
import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/journal/journal_store.dart';

void main() {
  test('persist gate samples a fast heart-rate stream', () {
    final gate = PersistGate(interval: const Duration(seconds: 5));
    final start = DateTime.utc(2026, 11, 27, 8);
    expect(gate.shouldPersist('hr', start), isTrue);
    expect(
      gate.shouldPersist('hr', start.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      gate.shouldPersist('hr', start.add(const Duration(seconds: 5))),
      isTrue,
    );
  });

  test('connection state lives outside the scan page', () {
    final devices = BleDeviceManager()
      ..applyLink(
        const BleLink(
          phase: BleLinkPhase.connected,
          address: 'AA:BB',
          name: 'H303',
          driverId: 'heart_rate',
        ),
      );
    expect(devices.isConnectedTo('aa:bb'), isTrue);
    expect(devices.phaseLabel('heart_rate'), '已连接');
    expect(devices.phaseLabel('ring'), '未连接');
    devices.applyLink(
      const BleLink(
        phase: BleLinkPhase.disconnected,
        address: 'AA:BB',
        name: 'H303',
        driverId: 'heart_rate',
      ),
    );
    expect(devices.isConnectedTo('AA:BB'), isFalse);
    expect(devices.phaseLabel('heart_rate'), '已断开');
  });

  test('H303 packets are parsed and stored in the journal', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final journal = await JournalStore.openPath(inMemoryDatabasePath);
    final samples = [
      const [0x16, 0x48, 0x00, 0x04],
      const [0x06, 0x48],
      const [0x00, 0x00],
    ];
    for (var i = 0; i < samples.length; i++) {
      final reading = parseHeartRate(samples[i]);
      final measurement = reading.toMeasurement(
        DateTime.utc(2026, 11, 27, 8, 0, i),
      );
      final saved = await journal.append(
        CanonicalEvent(
          eventId: 'hr-$i',
          deviceId: 'phone-1',
          sessionId: 'sess-1',
          sensorAddress: 'AA-BB',
          sensorKind: 'heart_rate',
          sensorModel: 'Magene H303',
          measurementType: measurement.type,
          unit: measurement.unit,
          monotonicUs: i,
          wallTimeUtc: '2026-11-27T08:00:0${i}Z',
          clockState: 'NTP_SYNCED',
          operatingState: 'NOMINAL',
          values: {...measurement.values, 'match_key': 'AA-BB-heart_rate'},
        ),
      );
      expect(saved, isTrue, reason: 'packet $i');
    }
    final rows = await journal.recent();
    expect(rows, hasLength(3));
    expect(rows.first.event.values['bpm'], 0);
    expect(rows.first.event.values['raw'], '00 00');
    expect(rows.last.event.values['bpm'], 72);
    expect(rows.last.event.values['sensor_contact'], 'detected');
    expect(rows.last.event.values['raw'], '16 48 00 04');
  });
}
