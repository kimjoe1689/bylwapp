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
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  static const key = 'server_base_url';
  static const tokenKey = 'device_token';
  static const collectorKey = 'collector_id';
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
