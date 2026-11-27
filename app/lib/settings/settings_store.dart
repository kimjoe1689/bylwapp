import 'package:shared_preferences/shared_preferences.dart';

const defaultServerBaseUrl = 'http://127.0.0.1:8080';

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

bool isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}
