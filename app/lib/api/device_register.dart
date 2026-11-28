import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bylwapp/api/device_pairing.dart';

/// Creates a collector on an open register endpoint and returns its token.
/// Pairing codes stay available for an admin who wants them, but install does
/// not require one.
Future<DevicePairing> registerDevice({
  required String baseUrl,
  required String deviceId,
  String name = 'bylwapp',
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  try {
    final response = await httpClient
        .post(
          Uri.parse('$root/api/v1/devices/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'device_id': deviceId, 'name': name}),
        )
        .timeout(const Duration(seconds: 8));
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode != 201 ||
        decoded is! Map ||
        decoded['token'] is! String ||
        decoded['device_id'] is! String) {
      final message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : '注册失败';
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

/// Device id that owns [token], or null when the server has no such route yet.
Future<String?> deviceForToken({
  required String baseUrl,
  required String token,
  http.Client? client,
}) async {
  if (token.isEmpty) return null;
  final httpClient = client ?? http.Client();
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  try {
    final response = await httpClient
        .get(
          Uri.parse('$root/api/v1/devices/me'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['device_id'] is String) {
      final id = (decoded['device_id'] as String).trim();
      return id.isEmpty ? null : id;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}
