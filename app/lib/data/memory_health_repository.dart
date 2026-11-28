import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';

class MemoryHealthRepository implements HealthRepository {
  final Map<String, HealthDevice> _devices = {};
  final List<LocalRecord> _records = [];
  int _nextId = 1;

  @override
  Future<void> upsertDevice(HealthDevice device) async {
    _devices[device.address] = device;
  }

  @override
  Future<bool> insertMeasurement(
    String deviceAddress,
    HealthMeasurement measurement,
  ) async {
    final device = _devices[deviceAddress];
    if (device == null) {
      throw StateError('unknown device $deviceAddress');
    }
    final exists = _records.any(
      (record) =>
          record.device.address == deviceAddress &&
          record.measurement.type == measurement.type &&
          record.measurement.recordedAt.toUtc() ==
              measurement.recordedAt.toUtc(),
    );
    if (exists) {
      return false;
    }
    _records.add(
      LocalRecord(id: _nextId++, device: device, measurement: measurement),
    );
    return true;
  }

  @override
  Future<List<LocalRecord>> listRecent({int limit = 100}) async {
    final sorted = [..._records]
      ..sort(
        (a, b) => b.measurement.recordedAt.compareTo(a.measurement.recordedAt),
      );
    return sorted.take(limit).toList();
  }

  @override
  Future<List<LocalRecord>> listUnsynced() async {
    return _records.where((record) => !record.synced).toList();
  }

  @override
  Future<void> markSynced(List<int> ids) async {
    final wanted = ids.toSet();
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      if (record.id != null && wanted.contains(record.id)) {
        _records[i] = LocalRecord(
          id: record.id,
          device: record.device,
          measurement: record.measurement,
          synced: true,
        );
      }
    }
  }
}
