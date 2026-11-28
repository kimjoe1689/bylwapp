import 'package:shared_preferences/shared_preferences.dart';

const defaultServerBaseUrl = 'https://bylw-api.zzjteacher.com';

abstract class SettingsStore {
  Future<String> getServerBaseUrl();

  Future<void> setServerBaseUrl(String url);

  Future<String> getDeviceToken();

  Future<String> getCollectorId();

  Future<void> setDeviceCredential({
    required String token,
    required String deviceId,
  });

  Future<void> setLastRing({required String name, required String address});

  Future<({String name, String address})?> getLastRing();

  Future<DateTime?> getLastRingHistoryAt();

  Future<void> setLastRingHistoryAt(DateTime time);

  Future<bool> getRingClockCorrected();

  Future<void> setRingClockCorrected();

  /// Record every ring packet. Defaults to on so a new install explores.
  Future<bool> getExploreEvents();

  Future<void> setExploreEvents(bool enabled);

  /// `continuous` or `interval` (30 seconds every 5 minutes).
  Future<String> getHeartSchedule();

  Future<void> setHeartSchedule(String mode);

  Future<bool> getGestureMark();

  Future<void> setGestureMark(bool enabled);
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({
    this.url = defaultServerBaseUrl,
    this.token = '',
    this.collectorId = 'phone-1',
  });

  String url;
  String token;
  String collectorId;
  String lastRingName = '';
  String lastRingAddress = '';
  DateTime? lastRingHistoryAt;
  bool ringClockCorrected = false;
  bool exploreEvents = true;
  String heartSchedule = 'interval';
  bool gestureMark = false;

  @override
  Future<String> getServerBaseUrl() async => url;

  @override
  Future<void> setServerBaseUrl(String value) async {
    url = value;
  }

  @override
  Future<String> getDeviceToken() async => token;

  @override
  Future<String> getCollectorId() async => collectorId;

  @override
  Future<void> setDeviceCredential({
    required String token,
    required String deviceId,
  }) async {
    this.token = token;
    collectorId = deviceId;
  }

  @override
  Future<void> setLastRing({
    required String name,
    required String address,
  }) async {
    lastRingName = name;
    lastRingAddress = address;
  }

  @override
  Future<({String name, String address})?> getLastRing() async {
    if (lastRingAddress.isEmpty) return null;
    return (name: lastRingName, address: lastRingAddress);
  }

  @override
  Future<DateTime?> getLastRingHistoryAt() async => lastRingHistoryAt;

  @override
  Future<void> setLastRingHistoryAt(DateTime time) async {
    lastRingHistoryAt = time.toUtc();
  }

  @override
  Future<bool> getRingClockCorrected() async => ringClockCorrected;

  @override
  Future<void> setRingClockCorrected() async {
    ringClockCorrected = true;
  }

  @override
  Future<bool> getExploreEvents() async => exploreEvents;

  @override
  Future<void> setExploreEvents(bool enabled) async {
    exploreEvents = enabled;
  }

  @override
  Future<String> getHeartSchedule() async => heartSchedule;

  @override
  Future<void> setHeartSchedule(String mode) async {
    heartSchedule = mode;
  }

  @override
  Future<bool> getGestureMark() async => gestureMark;

  @override
  Future<void> setGestureMark(bool enabled) async {
    gestureMark = enabled;
  }
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  static const key = 'server_base_url';
  static const tokenKey = 'device_token';
  static const collectorKey = 'collector_id';
  static const ringNameKey = 'last_ring_name';
  static const ringAddressKey = 'last_ring_address';
  static const ringHistoryKey = 'last_ring_history_at';
  static const ringClockKey = 'ring_clock_corrected';
  static const exploreKey = 'explore_events';
  static const heartScheduleKey = 'heart_schedule';
  static const gestureMarkKey = 'gesture_mark';
  final SharedPreferences _prefs;

  static Future<SharedPreferencesSettingsStore> open() async {
    return SharedPreferencesSettingsStore(
      await SharedPreferences.getInstance(),
    );
  }

  @override
  Future<String> getServerBaseUrl() async {
    return _prefs.getString(key) ?? defaultServerBaseUrl;
  }

  @override
  Future<void> setServerBaseUrl(String url) async {
    await _prefs.setString(key, url);
  }

  @override
  Future<String> getDeviceToken() async => _prefs.getString(tokenKey) ?? '';

  @override
  Future<String> getCollectorId() async =>
      _prefs.getString(collectorKey) ?? 'phone-1';

  @override
  Future<void> setDeviceCredential({
    required String token,
    required String deviceId,
  }) async {
    await _prefs.setString(tokenKey, token);
    await _prefs.setString(collectorKey, deviceId);
  }

  @override
  Future<void> setLastRing({
    required String name,
    required String address,
  }) async {
    await _prefs.setString(ringNameKey, name);
    await _prefs.setString(ringAddressKey, address);
  }

  @override
  Future<({String name, String address})?> getLastRing() async {
    final address = _prefs.getString(ringAddressKey) ?? '';
    if (address.isEmpty) return null;
    return (name: _prefs.getString(ringNameKey) ?? address, address: address);
  }

  @override
  Future<DateTime?> getLastRingHistoryAt() async {
    final raw = _prefs.getString(ringHistoryKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> setLastRingHistoryAt(DateTime time) async {
    await _prefs.setString(ringHistoryKey, time.toUtc().toIso8601String());
  }

  @override
  Future<bool> getRingClockCorrected() async =>
      _prefs.getBool(ringClockKey) ?? false;

  @override
  Future<void> setRingClockCorrected() async {
    await _prefs.setBool(ringClockKey, true);
  }

  @override
  Future<bool> getExploreEvents() async => _prefs.getBool(exploreKey) ?? true;

  @override
  Future<void> setExploreEvents(bool enabled) async {
    await _prefs.setBool(exploreKey, enabled);
  }

  @override
  Future<String> getHeartSchedule() async =>
      _prefs.getString(heartScheduleKey) ?? 'interval';

  @override
  Future<void> setHeartSchedule(String mode) async {
    await _prefs.setString(heartScheduleKey, mode);
  }

  @override
  Future<bool> getGestureMark() async =>
      _prefs.getBool(gestureMarkKey) ?? false;

  @override
  Future<void> setGestureMark(bool enabled) async {
    await _prefs.setBool(gestureMarkKey, enabled);
  }
}

class CollectorPrefs {
  CollectorPrefs({
    this.collectorId = 'phone-1',
    this.deviceToken = '',
    this.autoSync = true,
    this.elderMode = false,
    this.faultNetworkDown = false,
    this.faultTimeoutAfterCommit = false,
    this.faultClockSkew = false,
    this.careWindowMinutes = 30,
    this.showDemo = false,
    this.registerError = '',
  });

  String collectorId;
  String deviceToken;
  bool autoSync;
  bool elderMode;
  bool faultNetworkDown;
  bool faultTimeoutAfterCommit;
  bool faultClockSkew;
  int careWindowMinutes;

  /// Display-only sample readings. Never written to the journal or uploaded.
  bool showDemo;

  /// Last automatic registration failure. Empty after a token is stored.
  String registerError;
}

bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
