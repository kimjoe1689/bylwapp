import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/screens/study_screens.dart';

class ResearchPage extends StatelessWidget {
  const ResearchPage({super.key, required this.study});

  final StudyBundle? study;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('研究记录', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('这些记录用于论文里的对照、任务和问卷。没有真实条目时，服务器导出的比率会保持「不可计算」。'),
        const SizedBox(height: 12),
        _Entry(
          icon: Icons.fact_check_outlined,
          title: '对照账',
          subtitle: '观察者记下佩戴、空档或提醒是否看见',
          onTap: study == null
              ? null
              : () => _open(context, LedgerScreen(study: study!)),
        ),
        _Entry(
          icon: Icons.quiz_outlined,
          title: 'SUS 问卷',
          subtitle: '一题一页，十题都答完才计分',
          onTap: study == null
              ? null
              : () => _open(context, SusScreen(study: study!)),
        ),
        _Entry(
          icon: Icons.timer_outlined,
          title: '任务计时',
          subtitle: '记录独立完成、协助或放弃',
          onTap: study == null
              ? null
              : () => _open(context, TaskLogScreen(study: study!)),
        ),
        const Card(
          margin: EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(Icons.file_download_outlined),
            title: Text('导出说明'),
            subtitle: Text('登录电脑上的管理后台，下载 RQ1 到 RQ4 的 JSON。手机上的演示数据不会出现在导出里。'),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (context) => page));
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
