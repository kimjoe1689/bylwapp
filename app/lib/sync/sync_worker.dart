import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bylwapp/journal/journal_store.dart';

class SyncFaults {
  const SyncFaults({
    this.networkDown = false,
    this.timeoutAfterCommit = false,
    this.clockSkew = false,
  });

  final bool networkDown;
  final bool timeoutAfterCommit;
  final bool clockSkew;
}

class SyncWorker {
  SyncWorker({
    required this.journal,
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.faults = const SyncFaults(),
  }) : _client = client ?? http.Client();

  final JournalStore journal;
  final String baseUrl;
  final String token;
  final http.Client _client;
  final SyncFaults faults;

  Future<int> syncOnce() async {
    final pending = await journal.pending();
    var synced = 0;
    for (final record in pending) {
      final attempts = record.attempts + 1;
      try {
        final result = await _post(record);
        if (result == 'stored' || result == 'duplicate') {
          await journal.mark(
            record.event.eventId,
            state: 'synced',
            attempts: attempts,
            serverReceivedAt: DateTime.now().toUtc().toIso8601String(),
          );
          synced++;
        } else if (result == 'conflict') {
          await journal.mark(
            record.event.eventId,
            state: 'conflict',
            error: 'server kept the first receipt',
            attempts: attempts,
          );
        } else if (result == 'auth_blocked') {
          await journal.mark(
            record.event.eventId,
            state: 'auth_blocked',
            error: 'device token rejected',
            attempts: attempts,
          );
        }
      } catch (error) {
        final read = await _read(record.event.deviceId, record.event.eventId);
        if (read == record.payloadHash) {
          await journal.mark(
            record.event.eventId,
            state: 'synced',
            attempts: attempts,
            serverReceivedAt: DateTime.now().toUtc().toIso8601String(),
          );
          synced++;
          continue;
        }
        if (read != null) {
          await journal.mark(
            record.event.eventId,
            state: 'conflict',
            error: 'read-back hash differs',
            attempts: attempts,
          );
          continue;
        }
        await journal.mark(
          record.event.eventId,
          state: attempts >= 3 ? 'retry_failed' : 'pending',
          error: '$error',
          attempts: attempts,
        );
      }
    }
    return synced;
  }

  Future<String> _post(JournalRecord record) async {
    if (faults.networkDown) {
      throw Exception('network down');
    }
    final response = await _client
        .post(
          _uri('/api/v1/devices/${record.event.deviceId}/events'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'event': jsonDecode(record.event.canonicalJson),
            'payload_hash': record.payloadHash,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (faults.timeoutAfterCommit) {
      throw Exception('timeout after commit');
    }
    if (response.statusCode == 401) {
      return 'auth_blocked';
    }
    final body = jsonDecode(response.body);
    if (body is Map && body['result'] is String) {
      return body['result'] as String;
    }
    throw Exception('ingest ${response.statusCode}');
  }

  Future<String?> _read(String deviceId, String eventId) async {
    if (faults.networkDown) {
      return null;
    }
    final response = await _client
        .get(
          _uri('/api/v1/devices/$deviceId/events/$eventId'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      return null;
    }
    final body = jsonDecode(response.body);
    if (body is Map && body['payload_hash'] is String) {
      return body['payload_hash'] as String;
    }
    return null;
  }

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }
}
