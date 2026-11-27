import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/settings/settings_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.clientFactory,
    this.prefs,
  });

  final SettingsStore settings;
  final ServerClient Function(String baseUrl)? clientFactory;
  final CollectorPrefs? prefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.settings.getServerBaseUrl().then((url) {
      if (!mounted) {
        return;
      }
      _controller.text = url;
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (!isHttpUrl(url)) {
      _message('请填写 http 或 https 地址');
      return;
    }
    await widget.settings.setServerBaseUrl(url);
    _message('已保存');
  }

  Future<void> _check() async {
    final url = _controller.text.trim();
    if (!isHttpUrl(url)) {
      _message('请填写 http 或 https 地址');
      return;
    }
    setState(() => _busy = true);
    try {
      final client =
          (widget.clientFactory ?? (value) => ServerClient(baseUrl: value))(
            url,
          );
      await client.checkHealth();
      _message('服务器可连接');
    } catch (error) {
      _message('连接失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('服务器地址'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: _ready && !_busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: defaultServerBaseUrl,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            const Text('手机和电脑需要能互相访问。模拟器访问本机服务时，地址通常不是 127.0.0.1。'),
            const SizedBox(height: 16),
            if (widget.prefs != null)
              SwitchListTile(
                title: const Text('大字高对比'),
                value: widget.prefs!.elderMode,
                onChanged: (value) =>
                    setState(() => widget.prefs!.elderMode = value),
              ),
            FilledButton(
              onPressed: _ready && !_busy ? _save : null,
              child: const Text('保存'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _ready && !_busy ? _check : null,
              child: const Text('检测连接'),
            ),
          ],
        ),
      ),
    );
  }
}
