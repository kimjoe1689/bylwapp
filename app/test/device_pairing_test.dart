import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bylwapp/api/device_pairing.dart';
import 'package:bylwapp/settings/settings_store.dart';

void main() {
  test('default server is the workers https host', () {
    expect(defaultServerBaseUrl, 'https://bylw-api.zzjteacher.com');
    expect(isHttpUrl(defaultServerBaseUrl), isTrue);
  });

  test('pairing code redeems a device token over https', () async {
    final result = await redeemPairingCode(
      baseUrl: 'https://bylw-api.zzjteacher.com/',
      code: ' 123456 ',
      client: MockClient((request) async {
        expect(request.url, Uri.parse('https://bylw-api.zzjteacher.com/api/v1/devices/pair'));
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), {'code': '123456'});
        return http.Response(
          jsonEncode({
            'token': 'device-token',
            'device_id': 'phone-1',
            'note': 'Store this token on the collector. It is not shown again.',
          }),
          201,
        );
      }),
    );
    expect(result.token, 'device-token');
    expect(result.deviceId, 'phone-1');
  });

  test('a rejected pairing code surfaces the server error', () async {
    expect(
      () => redeemPairingCode(
        baseUrl: 'https://bylw-api.zzjteacher.com',
        code: '000000',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'error': 'pairing code rejected'}),
            400,
          ),
        ),
      ),
      throwsA(
        isA<PairingException>().having(
          (error) => error.message,
          'message',
          'pairing code rejected',
        ),
      ),
    );
  });
}
