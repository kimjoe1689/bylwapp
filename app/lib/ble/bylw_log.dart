import 'package:flutter/services.dart';

const _channel = MethodChannel('bylw/log');

/// Release builds drop [debugPrint]. This reaches `adb logcat -s BYLW`.
void bylwLog(String message) {
  // ignore: avoid_print
  print('BYLW $message');
  _channel
      .invokeMethod<void>('log', {'message': message})
      .catchError((Object _) {});
}
