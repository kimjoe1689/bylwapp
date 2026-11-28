import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/models/health_record.dart';

void main() {
  test('uploads measurements and reads the sync ack', () async {
    final client = ServerClient(
      baseUrl: 'http://127.0.0.1:8080/',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/sync');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device']['kind'], 'ring');
        expect((body['measurements'] as List).single['type'], 'spo2');
        return http.Response(
          jsonEncode({'device_id': 4, 'inserted': 1, 'skipped': 0}),
          200,
        );
      }),
    );

    final ack = await client.upload(
      device: const HealthDevice(
        name: 'R09_ABCD',
        kind: 'ring',
        address: 'R09',
        model: 'Colmi R09',
      ),
      measurements: [
        HealthMeasurement(
          type: 'spo2',
          unit: '%',
          recordedAt: DateTime.utc(2026, 11, 27, 1),
          values: const {'spo2': 98},
        ),
      ],
    );
    expect(ack.deviceId, 4);
    expect(ack.inserted, 1);
  });

  test('health check accepts a 200 response', () async {
    final client = ServerClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response('{"status":"ok"}', 200);
      }),
    );
    await client.checkHealth();
  });
}
