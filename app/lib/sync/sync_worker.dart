import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:bylwapp/ble/bylw_log.dart';
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

class IngestException implements Exception {
  IngestException(this.statusCode, this.message, {this.deviceId});

  final int statusCode;
  final String message;
  final String? deviceId;

  @override
  String toString() => 'Exception: ingest $statusCode $message';
}

class SyncWorker {
  SyncWorker({
    required this.journal,
    required this.baseUrl,
    required this.token,
    http.Client? client,
    this.faults = const SyncFaults(),
    this.deviceId = '',
    this.renewToken,
    this.onDevice,
  }) : _client = client ?? http.Client();

  final JournalStore journal;
  final String baseUrl;
  final String token;
  final http.Client _client;
  final SyncFaults faults;

  /// When set, pending rows are moved onto this device before upload.
  /// Empty keeps each event on the device id it was journaled with.
  final String deviceId;

  /// Issues a token for the device id already stored on a rejected event.
  final Future<String?> Function(String deviceId)? renewToken;

  /// Called when a 403 names the device that owns the current token.
  final void Function(String deviceId)? onDevice;

  Future<int> syncOnce() async {
    final pending = await journal.pending();
    var synced = 0;
    var storedCount = 0;
    var duplicateCount = 0;
    var errorCount = 0;
    var activeToken = token;
    var activeDevice = deviceId;
    var renewed = false;
    for (final original in pending) {
      var record = original;
      if (activeDevice.isNotEmpty && record.event.deviceId != activeDevice) {
        record = await _rebind(record, activeDevice);
      }
      final attempts = record.attempts + 1;
      try {
        final result = await _post(record, activeToken);
        if (result == 'stored') storedCount++;
        if (result == 'duplicate') duplicateCount++;
        if (await _apply(record, result, attempts)) synced++;
      } on IngestException catch (error) {
        final named = error.deviceId;
        if (error.statusCode == 403 &&
            named != null &&
            named.isNotEmpty &&
            named != record.event.deviceId) {
          activeDevice = named;
          onDevice?.call(named);
          record = await _rebind(record, named);
          try {
            final result = await _post(record, activeToken);
            if (result == 'stored') storedCount++;
            if (result == 'duplicate') duplicateCount++;
            if (await _apply(record, result, attempts)) synced++;
            continue;
          } on IngestException catch (again) {
            errorCount++;
            await _fail(record, attempts, again);
            continue;
          }
        }
        if (error.statusCode == 403 && !renewed && renewToken != null) {
          final next = await renewToken!(record.event.deviceId);
          if (next != null && next.isNotEmpty) {
            activeToken = next;
            renewed = true;
            try {
              final result = await _post(record, activeToken);
              if (result == 'stored') storedCount++;
              if (result == 'duplicate') duplicateCount++;
              if (await _apply(record, result, attempts)) synced++;
              continue;
            } on IngestException catch (again) {
              errorCount++;
              await _fail(record, attempts, again);
              continue;
            }
          }
        }
        errorCount++;
        await _fail(record, attempts, error);
      } catch (error) {
        final read = await _read(
          record.event.deviceId,
          record.event.eventId,
          activeToken,
        );
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
        errorCount++;
        await journal.mark(
          record.event.eventId,
          state: attempts >= 3 ? 'retry_failed' : 'pending',
          error: '$error',
          attempts: attempts,
        );
      }
    }
    bylwLog(
      'sync stored=$storedCount duplicate=$duplicateCount error=$errorCount',
    );
    return synced;
  }

  Future<bool> _apply(JournalRecord record, String result, int attempts) async {
    if (result == 'stored' || result == 'duplicate') {
      await journal.mark(
        record.event.eventId,
        state: 'synced',
        attempts: attempts,
        serverReceivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      return true;
    }
    if (result == 'conflict') {
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
    return false;
  }

  Future<void> _fail(JournalRecord record, int attempts, Object error) async {
    await journal.mark(
      record.event.eventId,
      state: attempts >= 3 ? 'retry_failed' : 'pending',
      error: '$error',
      attempts: attempts,
    );
  }

  Future<JournalRecord> _rebind(JournalRecord record, String deviceId) async {
    final event = record.event.rebindDevice(deviceId);
    await journal.replace(event);
    return JournalRecord(
      event: event,
      payloadHash: event.payloadHash,
      syncState: 'pending',
      attempts: record.attempts,
      lastError: '',
      serverReceivedAt: record.serverReceivedAt,
    );
  }

  Future<String> _post(JournalRecord record, String bearer) async {
    if (faults.networkDown) {
      throw Exception('network down');
    }
    final response = await _client
        .post(
          _uri('/api/v1/devices/${record.event.deviceId}/events'),
          headers: {
            'Authorization': 'Bearer $bearer',
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
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (body != null && body['result'] is String) {
      return body['result'] as String;
    }
    final message = body != null && body['error'] is String
        ? body['error'] as String
        : 'rejected';
    final named = body != null && body['device_id'] is String
        ? body['device_id'] as String
        : null;
    throw IngestException(response.statusCode, message, deviceId: named);
  }

  Future<String?> _read(String deviceId, String eventId, String bearer) async {
    if (faults.networkDown) {
      return null;
    }
    final response = await _client
        .get(
          _uri('/api/v1/devices/$deviceId/events/$eventId'),
          headers: {'Authorization': 'Bearer $bearer'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404 || response.statusCode != 200) {
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
