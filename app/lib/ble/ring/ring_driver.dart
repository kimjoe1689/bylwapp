import 'package:bylwapp/ble/device_driver.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';
import 'package:bylwapp/ble/uuids.dart';
import 'package:bylwapp/models/health_record.dart';

class YawellRingDriver implements HealthDeviceDriver {
  const YawellRingDriver();

  @override
  String get id => 'yawell_ring';

  @override
  String get displayName => 'QRing 戒指';

  @override
  String get kind => 'ring';

  @override
  String get targetModel => 'Colmi R09 / Yawell R05';

  @override
  List<GattWatch> get watches => const [
    GattWatch(
      serviceUuid: ringServiceV1Uuid,
      characteristicUuid: ringNotifyV1Uuid,
      indicate: false,
    ),
    GattWatch(
      serviceUuid: ringServiceV2Uuid,
      characteristicUuid: ringNotifyV2Uuid,
      indicate: false,
    ),
  ];

  @override
  bool matches({
    required String advertisedName,
    required List<String> serviceUuids,
  }) {
    return ringNameMatches(advertisedName) ||
        serviceListHas(serviceUuids, ringServiceV1Uuid);
  }

  bool supportsTemperature(String advertisedName) =>
      ringNameSupportsTemperature(advertisedName);

  @override
  List<HealthMeasurement> parse(
    String characteristicUuid,
    List<int> packet, {
    required DateTime now,
  }) {
    final today = DateTime.utc(
      now.toUtc().year,
      now.toUtc().month,
      now.toUtc().day,
    );
    return parseRingPacket(packet, today: today, now: now.toUtc()).measurements;
  }
}
