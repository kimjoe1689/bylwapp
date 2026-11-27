import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bylwapp/api/device_register.dart';

void main() {
  test('register stores the issued device token', () async {
    final result = await registerDevice(
      baseUrl: 'https://bylw-api.zzjteacher.com/',
      deviceId: 'phone-abc',
      client: MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://bylw-api.zzjteacher.com/api/v1/devices/register'),
        );
        expect(jsonDecode(request.body), {
          'device_id': 'phone-abc',
          'name': 'bylwapp',
        });
        return http.Response(
          jsonEncode({'token': 'issued-token', 'device_id': 'phone-abc'}),
          201,
        );
      }),
    );
    expect(result.token, 'issued-token');
    expect(result.deviceId, 'phone-abc');
  });
}
