import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../models/sync_models.dart';
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
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remotePathController;
  late final TextEditingController _intervalInputController;
  double _autoIntervalMinutes = 30;
  bool _autoSyncEnabled = false;
  bool _savingSync = false;
  bool _showPassword = false;

  String? get _backupPath =>
      _backupPathInput ?? widget.controller.settings.lastBackupPath;

  String? get _restorePath =>
      _restorePathInput ?? widget.controller.settings.lastRestorePath;

  @override
  void initState() {
    super.initState();
    final sync = widget.controller.syncConfig;
    _serverController = TextEditingController(text: sync.serverUrl);
    _usernameController = TextEditingController(text: sync.username);
    _passwordController = TextEditingController(text: sync.password);
    _remotePathController = TextEditingController(text: sync.remotePath);
    _autoIntervalMinutes =
        sync.autoIntervalMinutes > 0 ? sync.autoIntervalMinutes.toDouble() : 30;
    _intervalInputController =
        TextEditingController(text: _autoIntervalMinutes.round().toString());
    _autoSyncEnabled = sync.enabled;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remotePathController.dispose();
    _intervalInputController.dispose();
    super.dispose();
  }

  Future<void> _applySyncConfig({bool triggerSync = false}) async {
    final config = SyncConfig(
      enabled: _autoSyncEnabled,
      serverUrl: _serverController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      remotePath: _remotePathController.text.trim().isEmpty
          ? '/atimelog_data'
          : _remotePathController.text.trim(),
      autoIntervalMinutes: _autoIntervalMinutes.round(),
    );
    setState(() => _savingSync = true);
    try {
      await widget.controller.updateSyncConfig(
        config,
        triggerSync: triggerSync,
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _savingSync = false);
    }
  }

  String _syncMessageText(SyncStatus status) {
    final progress = status.progress;
    if (status.syncing && progress != null) {
      final detail = progress.detail?.trim();
      if (detail != null && detail.isNotEmpty) {
        return '${progress.stage} · $detail';
      }
      return progress.stage;
    }
    return status.lastSyncMessage ?? '点击同步或验证连接';
  }

  String _syncCounterText(SyncStatus status) {
    final progress = status.progress;
    if (status.syncing && progress != null) {
      return '↑${progress.uploaded}/${progress.totalUpload} '
          '↓${progress.downloaded}/${progress.totalDownload}';
    }
    if (status.lastSyncSucceeded == null) {
      return '';
    }
    return '↑${status.lastUploadCount} ↓${status.lastDownloadCount}'
        ' · ${status.lastDuration?.inSeconds ?? 0}s';
  }

  String _syncStatusLabel(SyncStatus status) {
    if (status.syncing) {
      return '同步中...';
    }
    if (status.lastSyncSucceeded == true) {
      return '上次同步成功';
    }
    if (status.lastSyncSucceeded == false) {
      return '上次同步失败';
    }
    return '尚未同步';
  }

  void _handleIntervalSubmit(String text) {
    final parsed = int.tryParse(text);
    if (parsed == null) {
      _intervalInputController.text =
          _autoIntervalMinutes.round().toString();
      return;
    }
    final clamped = parsed.clamp(5, 180);
    setState(() {
      _autoIntervalMinutes = clamped.toDouble();
      _intervalInputController.text = clamped.toString();
    });
    if (_autoSyncEnabled) {
      _applySyncConfig();
    }
  }

  Future<void> _handleManualSync() async {
    await _applySyncConfig();
    await widget.controller.syncNow(
      manual: true,
      reason: '设置页手动同步',
    );
  }

  Future<void> _handleVerify() async {
    await _applySyncConfig();
    await widget.controller.verifySyncConnection();
  }

  Widget _buildSyncCard(ThemeData theme) {
    final status = widget.controller.syncStatus;
    final statusLabel = _syncStatusLabel(status);
    final timeText = status.lastSyncTime != null
        ? DateFormat('MM-dd HH:mm').format(status.lastSyncTime!)
        : '暂无记录';
    final message = _syncMessageText(status);
    final counterText = _syncCounterText(status);
    final autoLabel = _autoSyncEnabled
        ? '每 ${_autoIntervalMinutes.round()} 分钟自动同步'
        : '自动同步已关闭';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 8),
                Text(
                  'WebDAV 同步',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: status.lastSyncSucceeded == false
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverController,
              onEditingComplete: _applySyncConfig,
              decoration: const InputDecoration(
                labelText: 'WebDAV 服务器地址',
                hintText: '例如 https://dav.example.com/remote.php/dav/files/me',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remotePathController,
              onEditingComplete: _applySyncConfig,
              decoration: const InputDecoration(
                labelText: '远程存储路径',
                hintText: '/atimelog_data',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    onEditingComplete: _applySyncConfig,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    obscureText: !_showPassword,
                    onEditingComplete: _applySyncConfig,
                    decoration: InputDecoration(
                      labelText: '密码 / 应用密钥',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _showPassword = !_showPassword,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _autoSyncEnabled,
              onChanged: (val) {
                setState(() => _autoSyncEnabled = val);
                _applySyncConfig();
              },
              title: const Text('开启自动同步'),
              subtitle: Text(autoLabel),
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _autoIntervalMinutes,
                    onChanged: _autoSyncEnabled
                        ? (val) => setState(() {
                              _autoIntervalMinutes = val;
                              _intervalInputController.text =
                                  val.round().toString();
                            })
                        : null,
                    onChangeEnd: _autoSyncEnabled
                        ? (_) => _applySyncConfig()
                        : null,
                    min: 5,
                    max: 180,
                    divisions: 35,
                    label: '${_autoIntervalMinutes.round()} 分钟',
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _intervalInputController,
                    enabled: _autoSyncEnabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: '分钟',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onSubmitted: _handleIntervalSubmit,
                    onEditingComplete: () => _handleIntervalSubmit(
                      _intervalInputController.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        status.verifying || _savingSync ? null : _handleVerify,
                    icon: status.verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        status.verifying ? '验证中' : '验证连接',
                        maxLines: 1,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        status.syncing || _savingSync ? null : _handleManualSync,
                    icon: status.syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        status.syncing ? '同步中...' : '立即同步',
                        maxLines: 1,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              (() {
                final parts = <String>[];
                if (status.syncing && status.progress != null) {
                  parts.add('进行中');
                } else {
                  parts.add('最近：$timeText');
                }
                parts.add(message);
                if (counterText.isNotEmpty) {
                  parts.add(counterText);
                }
                return parts.join(' · ');
              })(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            primary: false,
            padding: const EdgeInsets.all(16),
            children: [
              _buildSyncCard(theme),
              const SizedBox(height: 12),
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
      },
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

  Future<String?> _promptManualPath({
    required String title,
    required String initial,
    required String hint,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: '路径',
            hintText: hint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickBackupPath() async {
    final defaultPath = _backupPath?.isNotEmpty == true
        ? _backupPath!
        : await widget.controller.suggestedBackupPath();
    final initialDirectory = p.dirname(defaultPath);
    final suggestedName = p.basename(defaultPath);
    if (!Platform.isAndroid && !Platform.isIOS) {
      final location = await getSaveLocation(
        initialDirectory: initialDirectory,
        suggestedName: suggestedName,
        confirmButtonText: '保存',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'zip', extensions: ['zip']),
        ],
      );
      if (location != null && location.path.trim().isNotEmpty) {
        final trimmed = location.path.trim();
        setState(() {
          _backupPathInput = trimmed;
        });
        return trimmed;
      }
    }
    final manual = await _promptManualPath(
      title: '输入备份保存路径',
      initial: defaultPath,
      hint: '例如 /storage/emulated/0/Download/$suggestedName',
    );
    if (manual == null || manual.trim().isEmpty) {
      _showSnack('未选择路径，请重试');
      return null;
    }
    final trimmed = manual.trim();
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
    if (!Platform.isAndroid && !Platform.isIOS) {
      final file = await openFile(
        initialDirectory: initialDirectory,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'zip', extensions: ['zip']),
        ],
        confirmButtonText: '选择',
      );
      if (file != null) {
        setState(() {
          _restorePathInput = file.path;
        });
        return file.path;
      }
    }
    final defaultPath = _restorePath ??
        _backupPath ??
        await widget.controller.suggestedBackupPath();
    final manual = await _promptManualPath(
      title: '输入备份 zip 路径',
      initial: defaultPath,
      hint: '例如 /storage/emulated/0/Download/xxx.zip',
    );
    if (manual == null || manual.trim().isEmpty) {
      _showSnack('未选择路径，请重试');
      return null;
    }
    final trimmed = manual.trim();
    setState(() {
      _restorePathInput = trimmed;
    });
    return trimmed;
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
    final highlight = theme.colorScheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.6 : 0.8,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;
        final actions = Row(
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
        );

        final content = Row(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
            if (!isNarrow) ...[
              const SizedBox(width: 12),
              actions,
            ],
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              content,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: actions,
              ),
            ],
          );
        }

        return content;
      },
    );
  }
}
