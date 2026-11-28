class RingNotice {
  const RingNotice({required this.at, required this.hex, required this.label});

  final DateTime at;
  final String hex;
  final String label;
}

class RingAction {
  const RingAction(this.id, {this.metric, this.enabled, this.minutes});

  final String id;
  final String? metric;
  final bool? enabled;
  final int? minutes;

  static const find = RingAction('find');
  static const syncTime = RingAction('time');
  static const syncHistory = RingAction('history');
  static const battery = RingAction('battery');
  static const powerOff = RingAction('power');
  static const factoryReset = RingAction('factory');
  static const startHeart = RingAction('live-start', metric: 'heart_rate');
  static const stopHeart = RingAction('live-stop', metric: 'heart_rate');

  static RingAction readAuto(String metric) =>
      RingAction('auto-read', metric: metric);

  static RingAction writeAuto(
    String metric, {
    required bool enabled,
    required int minutes,
  }) {
    return RingAction(
      'auto-write',
      metric: metric,
      enabled: enabled,
      minutes: minutes,
    );
  }
}

class RingActionResult {
  const RingActionResult({
    required this.supported,
    this.message = '',
    this.batteryPercent,
    this.charging,
    this.enabled,
    this.minutes,
  });

  final bool supported;
  final String message;
  final int? batteryPercent;
  final bool? charging;
  final bool? enabled;
  final int? minutes;

  static const unsupported = RingActionResult(supported: false, message: '不支持');
  static const ok = RingActionResult(supported: true, message: '已发送');
}
