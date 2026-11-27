import 'package:bylwapp/ble/blood_pressure/bp_driver.dart';
import 'package:bylwapp/ble/device_driver.dart';
import 'package:bylwapp/ble/heart_rate/hr_driver.dart';
import 'package:bylwapp/ble/ring/ring_driver.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';

const bloodPressureDriver = BloodPressureDriver();
const heartRateDriver = HeartRateDriver();
const yawellRingDriver = YawellRingDriver();

const healthDrivers = <HealthDeviceDriver>[
  bloodPressureDriver,
  heartRateDriver,
  yawellRingDriver,
];

HealthDeviceDriver? driverById(String? id) {
  for (final driver in healthDrivers) {
    if (driver.id == id) {
      return driver;
    }
  }
  return null;
}

HealthDeviceDriver? matchDriver({
  required String advertisedName,
  required List<String> serviceUuids,
}) {
  final name = advertisedName.toUpperCase();
  if (name.contains('YE680B')) {
    return bloodPressureDriver;
  }
  if (name.contains('H303') || name.contains('MAGENE')) {
    return heartRateDriver;
  }
  if (ringNameMatches(advertisedName)) {
    return yawellRingDriver;
  }
  for (final driver in healthDrivers) {
    if (driver.matches(
      advertisedName: advertisedName,
      serviceUuids: serviceUuids,
    )) {
      return driver;
    }
  }
  return null;
}
