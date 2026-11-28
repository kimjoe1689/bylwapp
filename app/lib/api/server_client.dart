import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bylwapp/models/health_record.dart';

class ServerException implements Exception {
  ServerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SyncAck {
  const SyncAck({
    required this.deviceId,
    required this.inserted,
    required this.skipped,
  });

  final int deviceId;
  final int inserted;
  final int skipped;
}

class ServerClient {
  ServerClient({required this.baseUrl, http.Client? httpClient})
    : _client = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<void> checkHealth() async {
    final response = await _client
        .get(_uri('/health'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw ServerException('服务器健康检查失败', statusCode: response.statusCode);
    }
  }

  Future<SyncAck> upload({
    required HealthDevice device,
    required List<HealthMeasurement> measurements,
  }) async {
    final response = await _client
        .post(
          _uri('/api/sync'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device': device.toJson(),
            'measurements': measurements.map((item) => item.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ServerException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return SyncAck(
      deviceId: body['device_id'] as int,
      inserted: body['inserted'] as int,
      skipped: body['skipped'] as int,
    );
  }

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        return body['error'] as String;
      }
    } catch (_) {
      // Fall through to the status code.
    }
    return '上传失败 (${response.statusCode})';
  }
}
