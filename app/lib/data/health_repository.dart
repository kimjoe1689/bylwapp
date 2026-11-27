import 'package:bylwapp/models/health_record.dart';

abstract class HealthRepository {
  Future<void> upsertDevice(HealthDevice device);

  /// Returns false when the same device, type, and timestamp were already stored.
  Future<bool> insertMeasurement(
    String deviceAddress,
    HealthMeasurement measurement,
  );

  Future<List<LocalRecord>> listRecent({int limit = 100});

  Future<List<LocalRecord>> listUnsynced();

  Future<void> markSynced(List<int> ids);
}
