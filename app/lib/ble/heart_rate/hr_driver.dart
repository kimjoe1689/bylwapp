import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/device_driver.dart';
import 'package:bylwapp/ble/heart_rate/hr_parser.dart';
import 'package:bylwapp/ble/uuids.dart';
import 'package:bylwapp/models/health_record.dart';

class HeartRateDriver implements HealthDeviceDriver {
  const HeartRateDriver();

  @override
  String get id => 'heart_rate';

  @override
  String get displayName => '标准心率带';

  @override
  String get kind => 'heart_rate';

  @override
  String get targetModel => 'Magene H303';

  @override
  List<GattWatch> get watches => const [
    GattWatch(
      serviceUuid: hrServiceUuid,
      characteristicUuid: hrMeasurementUuid,
      indicate: false,
    ),
  ];

  @override
  bool matches({
    required String advertisedName,
    required List<String> serviceUuids,
  }) {
    final name = advertisedName.toUpperCase();
    if (name.contains('H303') || name.contains('MAGENE')) {
      return true;
    }
    return serviceUuids.map(normalizeUuid).contains(hrServiceUuid);
  }

  @override
  List<HealthMeasurement> parse(
    String characteristicUuid,
    List<int> packet, {
    required DateTime now,
  }) {
    if (normalizeUuid(characteristicUuid) != hrMeasurementUuid) {
      return const [];
    }
    return [parseHeartRate(packet).toMeasurement(now)];
  }
}
