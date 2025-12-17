import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/time_tracking_controller.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String? _backupPathInput;
  String? _restorePathInput;

  String? get _backupPath =>
      _backupPathInput ?? widget.controller.settings.lastBackupPath;

  String? get _restorePath =>
      _restorePathInput ?? widget.controller.settings.lastRestorePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: widget.controller.settings.darkMode,
            onChanged: (val) => widget.controller.toggleTheme(val),
            title: const Text('暗色模式'),
            subtitle: const Text('切换亮/暗主题'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildActionRow(
                    context: context,
                    icon: Icons.backup_outlined,
                    iconColor: theme.colorScheme.primary,
                    title: '备份 /atimelog_data',
                    subtitle: '生成压缩包，路径仅在本次运行有效',
                    pathLabel: '备份保存路径',
                    pathValue: _backupPath,
                    actionLabel: '备份',
                    tonalAction: false,
                    onPickPath: () => _pickBackupPath(),
                    onAction: _handleBackup,
                  ),
                  const Divider(height: 24),
                  _buildActionRow(
                    context: context,
                    icon: Icons.restore,
                    iconColor: theme.colorScheme.secondary,
                    title: '恢复备份',
                    subtitle: '指定 zip 文件恢复，不会覆盖备份路径',
                    pathLabel: '恢复文件路径',
                    pathValue: _restorePath,
                    actionLabel: '恢复',
                    tonalAction: true,
                    onPickPath: () => _pickRestorePath(),
                    onAction: _handleRestore,
                  ),
                ],
              ),
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
    final path = _backupPath ?? await _pickBackupPath();
    if (path == null || path.trim().isEmpty) {
      _showSnack('请先选择备份保存路径');
      return;
    }
    try {
      final file =
          await widget.controller.createBackup(targetPath: path.trim());
      if (!mounted) return;
      setState(() {
        _backupPathInput = file.path;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份完成: ${file.path}')));
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleRestore() async {
    final path = _restorePath ?? await _pickRestorePath();
    if (path == null || path.trim().isEmpty) {
      _showSnack('请先选择要恢复的备份文件');
      return;
    }
    try {
      final targetPath = path.trim();
      await widget.controller.restoreBackup(targetPath);
      if (!mounted) return;
      setState(() {
        _restorePathInput = targetPath;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('恢复完成')));
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<String?> _pickBackupPath() async {
    final defaultPath = _backupPath?.isNotEmpty == true
        ? _backupPath!
        : await widget.controller.suggestedBackupPath();
    final initialDirectory = p.dirname(defaultPath);
    final suggestedName = p.basename(defaultPath);
    final location = await getSaveLocation(
      initialDirectory: initialDirectory,
      suggestedName: suggestedName,
      confirmButtonText: '保存',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'zip', extensions: ['zip']),
      ],
    );
    if (location == null || location.path.trim().isEmpty) {
      return null;
    }
    final trimmed = location.path.trim();
    setState(() {
      _backupPathInput = trimmed;
    });
    return trimmed;
  }

  Future<String?> _pickRestorePath() async {
    final initialDirectory = _restorePath != null && _restorePath!.isNotEmpty
        ? p.dirname(_restorePath!)
        : (_backupPath != null && _backupPath!.isNotEmpty
            ? p.dirname(_backupPath!)
            : null);
    final file = await openFile(
      initialDirectory: initialDirectory,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'zip', extensions: ['zip']),
      ],
      confirmButtonText: '选择',
    );
    if (file == null) {
      return null;
    }
    setState(() {
      _restorePathInput = file.path;
    });
    return file.path;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildActionRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String pathLabel,
    required String? pathValue,
    required String actionLabel,
    required VoidCallback onPickPath,
    required VoidCallback onAction,
    bool tonalAction = false,
  }) {
    final theme = Theme.of(context);
    final String pathText =
        (pathValue != null && pathValue.trim().isNotEmpty) ? pathValue : '未选择';
    final highlight =
        theme.colorScheme.surfaceVariant.withOpacity(theme.brightness == Brightness.dark ? 0.6 : 0.8);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: highlight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.folder,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pathLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pathText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '选择路径',
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.9),
                  ),
                  onPressed: onPickPath,
                  icon: const Icon(Icons.folder_open),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: tonalAction
                      ? FilledButton.tonal(
                          onPressed: onAction, child: Text(actionLabel))
                      : FilledButton(
                          onPressed: onAction, child: Text(actionLabel)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
