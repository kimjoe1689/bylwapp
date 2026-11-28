import 'package:bylwapp/ble/blood_pressure/bp_parser.dart';
import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/device_driver.dart';
import 'package:bylwapp/ble/uuids.dart';
import 'package:bylwapp/models/health_record.dart';

class BloodPressureDriver implements HealthDeviceDriver {
  const BloodPressureDriver();

  @override
  String get id => 'blood_pressure';

  @override
  String get displayName => '标准血压计';

  @override
  String get kind => 'blood_pressure';

  @override
  String get targetModel => 'Yuwell YE680B';

  @override
  List<GattWatch> get watches => const [
    GattWatch(
      serviceUuid: bpServiceUuid,
      characteristicUuid: bpMeasurementUuid,
      indicate: true,
    ),
  ];

  @override
  bool matches({
    required String advertisedName,
    required List<String> serviceUuids,
  }) {
    if (advertisedName.toUpperCase().contains('YE680B')) {
      return true;
    }
    return serviceUuids.map(normalizeUuid).contains(bpServiceUuid);
  }

  @override
  List<HealthMeasurement> parse(
    String characteristicUuid,
    List<int> packet, {
    required DateTime now,
  }) {
    if (normalizeUuid(characteristicUuid) != bpMeasurementUuid) {
      return const [];
    }
    return [parseBloodPressure(packet).toMeasurement(now)];
  }

  /// Bytes for Date Time (0x2A08) and Current Time (0x2A2B).
  /// TODO(hardware): confirm which characteristic the YE680B actually exposes.
  List<TimeSyncWrite> timeSync(DateTime time) {
    return [
      TimeSyncWrite(
        serviceUuid: bpServiceUuid,
        characteristicUuid: dateTimeUuid,
        bytes: encodeDateTime(time),
      ),
      TimeSyncWrite(
        serviceUuid: currentTimeServiceUuid,
        characteristicUuid: currentTimeUuid,
        bytes: encodeCurrentTime(time),
      ),
    ];
  }
}

class TimeSyncWrite {
  const TimeSyncWrite({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.bytes,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final List<int> bytes;
}
