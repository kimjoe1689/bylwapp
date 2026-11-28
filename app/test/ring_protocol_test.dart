import 'package:flutter_test/flutter_test.dart';

import 'package:bylwapp/ble/persist_gate.dart';
import 'package:bylwapp/ble/ring/ring_packet.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';
import 'package:bylwapp/ui/ring_control_page.dart';

void main() {
  final today = DateTime.utc(2026, 11, 27);
  final now = DateTime.utc(2026, 11, 27, 12);

  test('checksums a 16-byte command and rejects a bad trailer', () {
    final battery = RingPacket.build(const [RingPacket.cmdBattery]);
    expect(battery, hasLength(16));
    expect(battery[0], 0x03);
    expect(battery[15], 0x03);
    expect(RingPacket.checksumValid(battery), isTrue);

    final find = RingPacket.build(const [0x50, 0x55, 0xAA]);
    expect(find[15], 0x4F);
    find[15] = 0x00;
    expect(RingPacket.checksumValid(find), isFalse);
  });

  test('encodes the ring clock as local decimal nibbles', () {
    final packet = RingPacket.encodeDateTime(DateTime(2026, 11, 27, 8, 15, 9));
    expect(packet.sublist(0, 7), [0x01, 0x26, 0x11, 0x27, 0x08, 0x15, 0x09]);
    expect(packet[15], 0x85);
    final utc = DateTime.utc(2026, 11, 27, 8, 15, 9).toLocal();
    final shifted = RingPacket.encodeDateTime(
      DateTime.utc(2026, 11, 27, 8, 15, 9),
    );
    expect(shifted[4], ((utc.hour ~/ 10) << 4) | (utc.hour % 10));
  });

  test('realtime heart rate starts with 0x69 and continues with 0x1e', () {
    final start = RingPacket.startRealtimeHeartRate();
    expect(start.sublist(0, 3), [0x69, 0x01, 0x01]);
    expect(RingPacket.checksumValid(start), isTrue);
    final keep = RingPacket.continueRealtimeHeartRate();
    expect(keep[0], 0x1e);
    expect(keep[15], 0x1e);
    expect(RingPacket.stopRealtimeHeartRate()[0], 0x6a);
    expect(RingPacket.batteryRequest()[0], 0x03);
  });

  test('ring tools and auto-measure commands use the documented opcodes', () {
    expect(RingPacket.findRing().sublist(0, 2), [0x10, 0x01]);
    expect(RingPacket.powerOff()[0], 0x08);
    expect(RingPacket.factoryReset()[0], 0xff);
    expect(RingPacket.todaySummary()[0], 0x48);
    expect(RingPacket.readAuto(RingPacket.cmdAutoHeartRate)[0], 0x16);
    expect(RingPacket.readAuto(RingPacket.cmdAutoSpo2)[0], 0x2c);
    expect(RingPacket.readAuto(RingPacket.cmdAutoStress)[0], 0x36);
    final written = RingPacket.writeAuto(0x16, enabled: true, minutes: 30);
    expect(written.sublist(0, 4), [0x16, 0x02, 0x01, 30]);
    expect(RingPacket.checksumValid(written), isTrue);
  });

  test('temperature logging command is the R09/R05 preference write', () {
    final packet = RingPacket.temperatureLogging(enabled: true);
    expect(packet.sublist(0, 4), [0x3A, 0x03, 0x02, 0x01]);
    expect(packet[15], 0x40);
    expect(RingPacket.temperatureLogging(enabled: false)[3], 0x00);
  });

  test('crc16 modbus matches the standard check vector', () {
    expect(RingPacket.crc16Modbus('123456789'.codeUnits), 0x4B37);
    expect(RingPacket.crc16Modbus(const []), 0xFFFF);
  });

  test('reassembles a split big-data frame', () {
    final payload = List<int>.filled(14, 0x11);
    final frame = RingPacket.buildBigData(
      type: RingPacket.bigDataSpo2,
      payload: payload,
    );
    final assembler = BigDataAssembler();
    expect(assembler.add(frame.sublist(0, 10)), isNull);
    expect(assembler.add(frame.sublist(10)), frame);
  });

  test('decodes an activity sample', () {
    final packet = RingPacket.build(const [
      0x43,
      0x26,
      0x11,
      0x27,
      36,
      0x00,
      0x01,
      0x64,
      0x00,
      0xE8,
      0x03,
      0x2C,
      0x01,
    ]);
    expect(packet[15], 0x42);
    final parsed = parseRingPacket(packet, today: today, now: now);
    final sample = parsed.measurements.single;
    expect(sample.type, 'steps');
    expect(sample.recordedAt, ringWallClock(2026, 11, 27, 9));
    expect(sample.values['steps'], 1000);
    expect(sample.values['calories'], 100);
    expect(sample.values['distance_m'], 300);
    expect(parsed.dayComplete, isTrue);
  });

  test('decodes heart-rate history and skips future slots', () {
    final packet = RingPacket.build([
      RingPacket.cmdSyncHeartRate,
      0x01,
      0,
      0,
      0,
      0,
      70,
      0,
      71,
    ]);
    final morning = DateTime.utc(2026, 11, 27, 0, 5);
    final parsed = parseRingPacket(packet, today: today, now: morning);
    expect(parsed.measurements.map((item) => item.values['bpm']).toList(), [
      70,
    ]);
    expect(
      parsed.measurements.single.recordedAt,
      ringWallClock(2026, 11, 27),
    );
  });

  test('decodes live steps, realtime heart rate, and battery', () {
    final live = parseLiveActivity(const [
      0x73,
      0x12,
      0x00,
      0x03,
      0xE8,
      0x00,
      0x00,
      0x96,
      0x00,
      0x00,
      0xFA,
    ]);
    expect(live!.steps, 1000);
    expect(live.calories, 15);
    expect(live.distanceMeters, 250);

    final hr = RingPacket.build(const [RingPacket.cmdRealtimeHeartRate, 80]);
    expect(
      parseRingPacket(
        hr,
        today: today,
        now: now,
      ).measurements.single.values['bpm'],
      80,
    );

    final manual = RingPacket.build(const [
      RingPacket.cmdManualHeartRate,
      0x00,
      0x00,
      72,
    ]);
    expect(
      parseRingPacket(
        manual,
        today: today,
        now: now,
      ).measurements.single.values['source'],
      'manual',
    );

    final worn = RingPacket.build(const [
      RingPacket.cmdManualHeartRate,
      0x00,
      0x01,
      0,
    ]);
    expect(parseRingPacket(worn, today: today, now: now).measurements, isEmpty);

    final battery = parseBattery(
      RingPacket.build(const [RingPacket.cmdBattery, 85, 1]),
    );
    expect(battery!.percent, 85);
    expect(battery.charging, isTrue);
  });

  test('decodes spo2, sleep, stress, hrv, and temperature history', () {
    final spo2Payload = <int>[0, 97, 99, ...List<int>.filled(46, 0)];
    final spo2 = RingPacket.buildBigData(
      type: RingPacket.bigDataSpo2,
      payload: spo2Payload,
    );
    final spo2Sample = parseRingPacket(
      spo2,
      today: today,
      now: now,
    ).measurements.single;
    expect(spo2Sample.values['spo2'], 98);
    expect(spo2Sample.values['min'], 97);
    expect(spo2Sample.values['max'], 99);

    final sleepPayload = <int>[
      1,
      0,
      8,
      0x64, 0x05, // 1380 minutes, 23:00 previous day
      0xA4, 0x01, // 420 minutes, 07:00
      RingPacket.sleepDeep, 60,
      RingPacket.sleepLight, 120,
    ];
    final sleep = RingPacket.buildBigData(
      type: RingPacket.bigDataSleep,
      payload: sleepPayload,
    );
    final sleepParsed = parseRingPacket(
      sleep,
      today: today,
      now: now,
    ).measurements;
    expect(sleepParsed.first.type, 'sleep_session');
    expect(sleepParsed.first.recordedAt, ringWallClock(2026, 11, 26, 23));
    expect(sleepParsed[1].values['stage'], 'deep');
    expect(sleepParsed[2].values['stage'], 'light');
    expect(sleepParsed[2].recordedAt, ringWallClock(2026, 11, 27));

    final stress = RingPacket.build([
      RingPacket.cmdSyncStress,
      0x01,
      0x00,
      40,
      0,
      41,
    ]);
    final stressSamples = parseRingPacket(
      stress,
      today: today,
      now: now,
    ).measurements;
    expect(stressSamples.map((item) => item.values['stress']).toList(), [
      40,
      41,
    ]);
    expect(stressSamples[1].recordedAt, ringWallClock(2026, 11, 27, 1));

    final hrv = RingPacket.build([RingPacket.cmdSyncHrv, 0x01, 0x00, 45]);
    final hrvSample = parseRingPacket(
      hrv,
      today: today,
      now: now,
      daysAgo: 1,
    ).measurements.single;
    expect(hrvSample.values['hrv_ms'], 45);
    expect(hrvSample.recordedAt, ringWallClock(2026, 11, 26));

    final tempPayload = <int>[0, 0x1E, 165, 0, ...List<int>.filled(46, 0)];
    expect(tempPayload, hasLength(50));
    final temp = RingPacket.buildBigData(
      type: RingPacket.bigDataTemperature,
      payload: tempPayload,
    );
    final tempSample = parseRingPacket(
      temp,
      today: today,
      now: now,
    ).measurements.single;
    expect(tempSample.values['celsius'], 36.5);
    expect(tempSample.unit, '°C');

    final badCrc = [...temp];
    badCrc[4] = 0;
    expect(parseRingPacket(badCrc, today: today, now: now).ignored, isTrue);
  });

  test('history sync walks activity days and enables temperature before fetching it', () {
    final cursor = RingSyncCursor(now: now, temperatureCapable: true);
    final first = cursor.nextCommand()!;
    expect(first.bytes.sublist(0, 6), [0x43, 0x00, 0x0F, 0x00, 0x5F, 0x01]);
    expect(first.characteristicUuid, isNot(contains('de5bf72a')));

    cursor.consume(RingPacket.build(const [RingPacket.cmdSyncActivity, 0xFF]));
    expect(cursor.daysAgo, 1);
    expect(cursor.awaitingMore, isFalse);

    cursor.phase = RingSyncPhase.temperature;
    cursor.temperatureLoggingEnabled = false;
    final enable = cursor.nextCommand()!;
    expect(enable.label, 'enable-temperature');
    expect(enable.bytes.sublist(0, 4), [0x3A, 0x03, 0x02, 0x01]);
    cursor.consume(enable.bytes);
    final history = cursor.nextCommand()!;
    expect(history.bytes, [0xBC, 0x25, 0x00, 0x00, 0xFF, 0xFF]);
  });

  test('a timed-out day stops the older days in that stage', () {
    final cursor = RingSyncCursor(now: now, temperatureCapable: false);
    expect(cursor.nextCommand()!.label, 'activity-0');
    expect(cursor.commandTimeout, const Duration(seconds: 8));
    cursor.skipCurrent();
    expect(cursor.phase, RingSyncPhase.heartRate);
    expect(cursor.nextCommand()!.label, 'heart-rate-0');
  });

  test('history only walks days since the last success', () {
    final cursor = RingSyncCursor(
      now: now,
      temperatureCapable: false,
      maxDaysAgo: 0,
    );
    expect(cursor.nextCommand()!.label, 'activity-0');
    cursor.consume(RingPacket.build(const [RingPacket.cmdSyncActivity, 0xFF]));
    expect(cursor.nextCommand()!.label, 'heart-rate-0');
    expect(ringHistoryDepth(null, DateTime(2026, 11, 28, 16)), 1);
    expect(
      ringHistoryDepth(DateTime(2026, 11, 28, 9), DateTime(2026, 11, 28, 16)),
      0,
    );
    expect(
      ringHistoryDepth(DateTime(2026, 11, 26, 9), DateTime(2026, 11, 28, 16)),
      2,
    );
  });

  test('manual temperature uses the 0x69 subtype and local history clocks', () {
    final packet = RingPacket.build(const [
      RingPacket.cmdManualHeartRate,
      RingPacket.manualTemperature,
      0x00,
      165,
    ]);
    final parsed = parseRingPacket(packet, today: today, now: now);
    expect(parsed.measurements.single.values['celsius'], 36.5);
    expect(ringNoticeLabel(packet), '体温 36.5');
    expect(
      ringNoticeLabel(RingPacket.build(const [RingPacket.cmdSyncHeartRate])),
      isNull,
    );
    final wall = ringWallClock(2026, 11, 28, 16, 30);
    expect(wall.hour, 16);
    expect(wall.minute, 30);
    expect(wall.isUtc, isFalse);
    final fixed = correctedRingInstant(DateTime.utc(2026, 11, 28, 23, 30));
    expect(fixed.toLocal().hour, 23);
    expect(fixed.toLocal().minute, 30);
  });

  test('history rows bypass the realtime persist gate', () {
    final gate = PersistGate(interval: const Duration(seconds: 5));
    final now = DateTime.utc(2026, 11, 27, 8);
    expect(
      gate.accept(
        history: true,
        streamKey: 'addr|heart_rate',
        historyKey: 'addr|heart_rate|1',
        now: now,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        history: true,
        streamKey: 'addr|heart_rate',
        historyKey: 'addr|heart_rate|1',
        now: now,
      ),
      isFalse,
    );
    expect(
      gate.accept(
        history: true,
        streamKey: 'addr|heart_rate',
        historyKey: 'addr|heart_rate|2',
        now: now,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        history: false,
        streamKey: 'addr|heart_rate',
        historyKey: 'ignored',
        now: now,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        history: false,
        streamKey: 'addr|heart_rate',
        historyKey: 'ignored',
        now: now.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });

  test('ring notices hide the realtime heart-rate stream', () {
    expect(ringNoticeLabel(const [0x69, 0x01, 0x00, 0x52]), isNull);
    expect(ringNoticeLabel(const [0x1e]), isNull);
    expect(ringNoticeLabel(const [0x03, 0x64]), '电量 100%');
    expect(ringNoticeLabel(const [0x10, 0x01]), '戒指已响应寻找');
    expect(ringNoticeLabel(const [0x55]), 'unknown 0x55');
  });

  test('distance under a kilometre stays in meters', () {
    expect(formatRingDistance(38), '38 米');
    expect(formatRingDistance(6120), '6.1 公里');
    expect(formatRingSleep(null), '还没有睡眠记录');
  });

  test('short manual heart-rate notifies still parse', () {
    final parsed = parseRingPacket(
      const [0x69, 0x01, 0x00, 0x52],
      today: today,
      now: now,
    );
    expect(parsed.measurements.single.values['bpm'], 82);
    expect(parsed.measurements.single.values['source'], 'manual');
  });

  test('R09 and R05 are the temperature models', () {
    expect(ringNameSupportsTemperature('R09_1234'), isTrue);
    expect(ringNameSupportsTemperature('R05_AB12'), isTrue);
    expect(ringNameSupportsTemperature('R02_1234'), isFalse);
    expect(ringNameSupportsTemperature('R05_zzzz'), isFalse);
  });
}
