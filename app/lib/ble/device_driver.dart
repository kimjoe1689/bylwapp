import 'package:bylwapp/models/health_record.dart';

class GattWatch {
  const GattWatch({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.indicate,
  });

  final String serviceUuid;
  final String characteristicUuid;

  /// Blood Pressure Measurement is indicated. Heart rate and the ring notify.
  final bool indicate;
}

abstract class HealthDeviceDriver {
  String get id;
  String get displayName;
  String get kind;
  String get targetModel;
  List<GattWatch> get watches;

  bool matches({
    required String advertisedName,
    required List<String> serviceUuids,
  });

  List<HealthMeasurement> parse(
    String characteristicUuid,
    List<int> packet, {
    required DateTime now,
  });
}
