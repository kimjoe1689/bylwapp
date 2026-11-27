import 'package:shared_preferences/shared_preferences.dart';

const defaultServerBaseUrl = 'https://bylw-api.zzjteacher.com';

abstract class SettingsStore {
  Future<String> getServerBaseUrl();

  Future<void> setServerBaseUrl(String url);
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({this.url = defaultServerBaseUrl});

  String url;

  @override
  Future<String> getServerBaseUrl() async => url;

  @override
  Future<void> setServerBaseUrl(String value) async {
    url = value;
  }
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  static const key = 'server_base_url';
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
}

bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
