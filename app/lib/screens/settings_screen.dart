import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/settings/settings_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.clientFactory,
    this.prefs,
    this.embedded = false,
    this.onOpenDebug,
    this.onChanged,
  });

  final SettingsStore settings;
  final ServerClient Function(String baseUrl)? clientFactory;
  final CollectorPrefs? prefs;
  final bool embedded;
  final VoidCallback? onOpenDebug;
  final VoidCallback? onChanged;

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
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('我的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('后台地址'),
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
        const Text('安装后会自动连上默认服务器。需要改地址时，保存新的 http 或 https 地址即可。'),
        const SizedBox(height: 16),
        if (widget.prefs != null) ...[
          SwitchListTile(
            title: const Text('大字高对比'),
            value: widget.prefs!.elderMode,
            onChanged: (value) {
              setState(() => widget.prefs!.elderMode = value);
              widget.onChanged?.call();
            },
          ),
          SwitchListTile(
            title: const Text('演示数据'),
            subtitle: const Text('只改变首页显示，不写入日志，不上传，不进入导出'),
            value: widget.prefs!.showDemo,
            onChanged: (value) {
              setState(() => widget.prefs!.showDemo = value);
              widget.onChanged?.call();
            },
          ),
          SwitchListTile(
            title: const Text('自动同步'),
            value: widget.prefs!.autoSync,
            onChanged: (value) =>
                setState(() => widget.prefs!.autoSync = value),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _ready && !_busy ? _save : null,
              child: const Text('保存'),
            ),
            FilledButton.tonal(
              onPressed: _ready && !_busy ? _check : null,
              child: const Text('检测连接'),
            ),
            TextButton(
              onPressed: widget.onOpenDebug,
              child: const Text('蓝牙调试'),
            ),
          ],
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: body,
    );
  }
}
