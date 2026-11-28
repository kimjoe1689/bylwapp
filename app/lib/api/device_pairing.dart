import 'dart:convert';

import 'package:http/http.dart' as http;

class DevicePairing {
  const DevicePairing({required this.token, required this.deviceId});

  final String token;
  final String deviceId;
}

class PairingException implements Exception {
  PairingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Exchanges a 6-digit admin pairing code for a collector device token.
/// The settings screen can still point [baseUrl] at a LAN Go server.
Future<DevicePairing> redeemPairingCode({
  required String baseUrl,
  required String code,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  try {
    final response = await httpClient
        .post(
          Uri.parse('$root/api/v1/devices/pair'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'code': code.trim()}),
        )
        .timeout(const Duration(seconds: 8));
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode != 201 ||
        decoded is! Map ||
        decoded['token'] is! String ||
        decoded['device_id'] is! String) {
      final message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : '配对失败';
      throw PairingException(message, statusCode: response.statusCode);
    }
    return DevicePairing(
      token: decoded['token'] as String,
      deviceId: decoded['device_id'] as String,
    );
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
