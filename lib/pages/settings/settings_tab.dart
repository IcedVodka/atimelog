import 'package:flutter/material.dart';

import '../../services/time_tracking_controller.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return SafeArea(
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: settings.darkMode,
            onChanged: (val) => widget.controller.toggleTheme(val),
            title: const Text('暗色模式'),
            subtitle: const Text('切换亮/暗主题'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('备份 /atimelog_data'),
                  subtitle: Text(settings.lastBackupPath ?? '尚未备份'),
                  trailing: FilledButton(
                    onPressed: _handleBackup,
                    child: const Text('创建备份'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('恢复备份'),
                  subtitle: const Text('输入备份 zip 路径进行恢复'),
                  trailing: FilledButton.tonal(
                    onPressed: _handleRestore,
                    child: const Text('选择路径'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              subtitle: const Text('AtimeLog Phase 2 Demo'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBackup() async {
    try {
      final file = await widget.controller.createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份完成: ${file.path}')));
      setState(() {});
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleRestore() async {
    final pathController = TextEditingController(
      text: widget.controller.settings.lastBackupPath ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(labelText: 'zip 文件路径'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.controller.restoreBackup(pathController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('恢复完成')));
      setState(() {});
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
