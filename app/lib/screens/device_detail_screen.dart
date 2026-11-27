import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/ui/mini_chart.dart';

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({
    super.key,
    required this.title,
    required this.records,
  });

  final String title;
  final List<LocalRecord> records;

  @override
  Widget build(BuildContext context) {
    final values = records
        .map((record) => _primary(record.measurement))
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(records.isEmpty ? '还没有历史读数' : '最近 ${records.length} 条'),
                  MiniChart(
                    values: values,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          for (final record in records)
            ListTile(
              title: Text(summarize(record.measurement)),
              subtitle: Text(
                record.measurement.recordedAt.toLocal().toString(),
              ),
            ),
        ],
      ),
    );
  }
}

double _primary(HealthMeasurement measurement) {
  final values = measurement.values;
  for (final key in [
    'systolic',
    'bpm',
    'spo2',
    'celsius',
    'steps',
    'duration_min',
    'stress',
    'hrv_ms',
  ]) {
    final value = values[key];
    if (value is num) return value.toDouble();
  }
  return 0;
}
