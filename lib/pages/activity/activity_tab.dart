import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/time_formatter.dart';
import '../../models/sync_models.dart';
import '../../models/time_models.dart';
import '../../services/time_tracking_controller.dart';

class ActivityTab extends StatefulWidget {
  const ActivityTab({
    super.key,
    required this.controller,
    required this.noteController,
  });

  final TimeTrackingController controller;
  final TextEditingController noteController;

  @override
  State<ActivityTab> createState() => ActivityTabState();
}

class ActivityTabState extends State<ActivityTab>
    with SingleTickerProviderStateMixin {
  String? _selectedCategoryId;
  bool _savingCurrentNote = false;
  String? _lastCurrentTempId;
  Timer? _noteSaveDebounce;
  late final AnimationController _syncSpinController;
  bool _syncIconSpinning = false;

  @override
  void initState() {
    super.initState();
    _syncSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final cats = widget.controller.categories.where((e) => e.enabled).toList();
    if (cats.isNotEmpty) {
      _selectedCategoryId = cats.first.id;
    }
  }

  @override
  void dispose() {
    _syncSpinController.dispose();
    _noteSaveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _startFromSelected() async {
    const noteText = '';
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      _showSnack('暂无分类可用');
      return;
    }
    try {
      await widget.controller.startNewActivity(
        categoryId: categoryId,
        note: noteText,
        allowSwitch: true,
      );
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handlePause() async {
    try {
      await widget.controller.stopCurrentActivity(pushToRecent: true);
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleStop() async {
    try {
      await widget.controller.stopCurrentActivity(pushToRecent: false);
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleResume(RecentContext contextItem) async {
    widget.noteController.text = contextItem.note;
    try {
      await widget.controller.resumeFromContext(contextItem);
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleEditStartTime(CurrentActivity current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.startTime),
    );
    if (picked == null) {
      return;
    }
    final updatedStart = DateTime(
      current.startTime.year,
      current.startTime.month,
      current.startTime.day,
      picked.hour,
      picked.minute,
    );
    await widget.controller.updateCurrentStartTime(updatedStart);
  }

  void _debounceCurrentNoteSave(CurrentActivity current) {
    if (widget.noteController.text.trim() == current.note.trim()) {
      return;
    }
    _noteSaveDebounce?.cancel();
    _noteSaveDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _handleEditCurrentNote(current),
    );
  }

  Future<void> _handleEditCurrentNote(CurrentActivity current) async {
    if (_savingCurrentNote) {
      _noteSaveDebounce?.cancel();
      _noteSaveDebounce = Timer(
        const Duration(milliseconds: 400),
        () => _handleEditCurrentNote(current),
      );
      return;
    }
    setState(() => _savingCurrentNote = true);
    try {
      await widget.controller.updateCurrentNote(
        widget.noteController.text.trim(),
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _savingCurrentNote = false);
    }
  }

  Future<void> _editRecentContext(RecentContext contextItem) async {
    final latest = await widget.controller.findLatestRecordForGroup(
      contextItem.groupId,
    );
    if (latest == null) {
      _showSnack('未找到可编辑的历史片段');
      return;
    }
    final category = widget.controller.findCategory(contextItem.categoryId);
    final noteController = TextEditingController(
      text: contextItem.note.isNotEmpty
          ? contextItem.note
          : (category?.name ?? ''),
    );
    DateTime startDate = latest.startTime;
    DateTime endDate = latest.endTime;
    TimeOfDay startTime = TimeOfDay.fromDateTime(latest.startTime);
    TimeOfDay endTime = TimeOfDay.fromDateTime(latest.endTime);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('编辑最近活动'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '记录内容'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 60),
                              ),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => startDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            DateFormat('yyyy-MM-dd').format(startDate),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 60),
                              ),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => endDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: Text(DateFormat('yyyy-MM-dd').format(endDate)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: startTime,
                            );
                            if (picked != null) {
                              setDialogState(() => startTime = picked);
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(startTime.format(context)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: endTime,
                            );
                            if (picked != null) {
                              setDialogState(() => endTime = picked);
                            }
                          },
                          icon: const Icon(Icons.stop),
                          label: Text(endTime.format(context)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      return;
    }

    final newStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.hour,
      startTime.minute,
    );
    final newEnd = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      endTime.hour,
      endTime.minute,
    );
    if (!newStart.isBefore(newEnd)) {
      _showSnack('结束时间需要晚于开始时间');
      return;
    }
    if (!isSameDay(newStart, latest.startTime)) {
      _showSnack('暂不支持跨日修改最近活动');
      return;
    }
    if (!isSameDay(newEnd, latest.endTime)) {
      _showSnack('暂不支持跨日修改最近活动');
      return;
    }
    final resolvedNote = noteController.text.trim().isEmpty
        ? (category?.name ?? '其他.${contextItem.categoryId}')
        : noteController.text.trim();
    await widget.controller.updateRecordWithSync(
      record: latest,
      newStart: newStart,
      newEnd: newEnd,
      note: resolvedNote,
      syncGroupNotes: true,
    );
    await widget.controller.updateRecentNote(contextItem.groupId, resolvedNote);
    setState(() {});
    _showSnack('已更新最近活动');
  }

  Future<void> showManualDialog([CategoryModel? initialCategory]) async {
    final categories = widget.controller.categories
        .where((c) => c.enabled)
        .toList();
    if (categories.isEmpty) {
      _showSnack('暂无分类可用于补录');
      return;
    }
    CategoryModel? selected = initialCategory ?? categories.first;
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    TimeOfDay start = TimeOfDay.fromDateTime(DateTime.now());
    TimeOfDay end = TimeOfDay.fromDateTime(
      DateTime.now().add(const Duration(minutes: 25)),
    );
    final noteController = TextEditingController(text: selected.name);
    bool noteTouched = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '手动补录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CategoryModel>(
                    decoration: const InputDecoration(labelText: '分类'),
                    value: selected,
                    items: categories
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat,
                            child: Row(
                              children: [
                                Icon(cat.iconData, color: cat.color),
                                const SizedBox(width: 8),
                                Text(cat.name),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setSheetState(() {
                      final previousName = selected?.name ?? '';
                      selected = value;
                      final currentText = noteController.text.trim();
                      final shouldSync =
                          !noteTouched ||
                          currentText.isEmpty ||
                          currentText == previousName;
                      if (value != null && shouldSync) {
                        noteController.text = value.name;
                        noteTouched = false;
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '记录内容'),
                    onChanged: (_) => noteTouched = true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              lastDate: DateTime.now(),
                            );
                            if (pickedDate != null) {
                              setSheetState(() => startDate = pickedDate);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            DateFormat('yyyy-MM-dd').format(startDate),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: start,
                            );
                            if (picked != null) {
                              setSheetState(() => start = picked);
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(start.format(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              lastDate: DateTime.now(),
                            );
                            if (pickedDate != null) {
                              setSheetState(() => endDate = pickedDate);
                            }
                          },
                          icon: const Icon(Icons.event),
                          label: Text(DateFormat('yyyy-MM-dd').format(endDate)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: end,
                            );
                            if (picked != null) {
                              setSheetState(() => end = picked);
                            }
                          },
                          icon: const Icon(Icons.stop),
                          label: Text(end.format(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: selected == null
                            ? null
                            : () => Navigator.of(context).pop(true),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (result != true || selected == null) {
      return;
    }
    final CategoryModel cat = selected!;
    final startDateTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      start.hour,
      start.minute,
    );
    final endDateTime = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      end.hour,
      end.minute,
    );
    if (!startDateTime.isBefore(endDateTime)) {
      _showSnack('结束时间需要晚于开始时间');
      return;
    }
    try {
      await widget.controller.manualAddRecord(
        categoryId: cat.id,
        note: noteController.text.trim().isEmpty
            ? cat.name
            : noteController.text.trim(),
        startTime: startDateTime,
        endTime: endDateTime,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('补录完成')));
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateSyncAnimation(bool syncing) {
    if (syncing && !_syncIconSpinning) {
      _syncIconSpinning = true;
      _syncSpinController
        ..reset()
        ..repeat();
    } else if (!syncing && _syncIconSpinning) {
      _syncIconSpinning = false;
      _syncSpinController
        ..stop()
        ..reset();
    }
  }

  bool _isDesktopPlatform() {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  String _syncDetailText(SyncStatus status, bool isReady) {
    final progress = status.progress;
    if (status.syncing && progress != null) {
      final detail = progress.detail?.trim();
      if (detail != null && detail.isNotEmpty) {
        return '${progress.stage} · $detail';
      }
      return progress.stage;
    }
    return status.lastSyncMessage ??
        (status.lastSyncSucceeded == true
            ? '最近已同步'
            : (isReady ? '点击手动同步' : '请在更多页面填写 WebDAV 信息'));
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

  Future<void> _showSyncDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final status = widget.controller.syncStatus;
            final config = widget.controller.syncConfig;
            final theme = Theme.of(context);
            final isReady = config.isConfigured;
            final detail = _syncDetailText(status, isReady);
            final counterText = _syncCounterText(status);
            final lastTime = status.lastSyncTime != null
                ? DateFormat('MM-dd HH:mm:ss').format(status.lastSyncTime!)
                : '暂无';
            Color titleColor;
            String statusLabel;
            if (!isReady) {
              titleColor = theme.colorScheme.error;
              statusLabel = '未配置 WebDAV';
            } else if (status.syncing) {
              titleColor = theme.colorScheme.primary;
              statusLabel = '同步中...';
            } else if (status.lastSyncSucceeded == true) {
              titleColor = Colors.green.shade600;
              statusLabel = '上次同步成功';
            } else if (status.lastSyncSucceeded == false) {
              titleColor = theme.colorScheme.error;
              statusLabel = '上次同步失败';
            } else {
              titleColor = theme.colorScheme.onSurfaceVariant;
              statusLabel = '尚未同步';
            }

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.sync, color: titleColor),
                  const SizedBox(width: 8),
                  const Text('同步'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('最近：$lastTime'),
                  const SizedBox(height: 6),
                  Text(detail),
                  if (counterText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(counterText),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                FilledButton.icon(
                  onPressed: status.syncing || !isReady
                      ? null
                      : () async {
                          await widget.controller.syncNow(
                            manual: true,
                            reason: '手动同步',
                          );
                        },
                  icon: status.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(status.syncing ? '同步中' : '手动同步'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSyncButton(SyncStatus status) {
    final theme = Theme.of(context);
    final isReady = widget.controller.syncConfig.isConfigured;
    final baseColor =
        isReady ? theme.colorScheme.primary : theme.colorScheme.error;
    return FloatingActionButton.small(
      heroTag: 'sync-fab',
      backgroundColor: theme.colorScheme.surface.withOpacity(0.92),
      foregroundColor: baseColor,
      onPressed: () => _showSyncDialog(),
      child: RotationTransition(
        turns: Tween(begin: 0.0, end: 1.0).animate(_syncSpinController),
        child: const Icon(Icons.sync),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final categories = widget.controller.categories
            .where((e) => e.enabled)
            .toList();
        if (_selectedCategoryId == null && categories.isNotEmpty) {
          _selectedCategoryId = categories.first.id;
        } else if (_selectedCategoryId != null &&
            categories.every((c) => c.id != _selectedCategoryId)) {
          _selectedCategoryId = categories.isNotEmpty ? categories.first.id : null;
        }
        final activity = widget.controller.currentActivity;
        final recents = widget.controller.recentContexts;
        final syncStatus = widget.controller.syncStatus;
        _updateSyncAnimation(syncStatus.syncing);

        return SafeArea(
          child: Stack(
            children: [
              ListView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _buildActiveCard(activity, categories),
                  const SizedBox(height: 12),
                  _buildRecents(recents),
                  const SizedBox(height: 12),
                  _buildCategoryGrid(categories),
                ],
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: _buildSyncButton(syncStatus),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveCard(
    CurrentActivity? current,
    List<CategoryModel> categories,
  ) {
    if (current == null) {
      _lastCurrentTempId = null;
      widget.noteController.text = '';
      final hasCategories = categories.isNotEmpty;
      final selectedId =
          hasCategories ? (_selectedCategoryId ?? categories.first.id) : null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('尚未开始', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;
                  final dropdown = InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '选择分类',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedId,
                        hint: const Text('暂无可用分类'),
                        onChanged: hasCategories
                            ? (value) =>
                                setState(() => _selectedCategoryId = value)
                            : null,
                        items: categories
                            .map(
                              (cat) => DropdownMenuItem(
                                value: cat.id,
                                child: Row(
                                  children: [
                                    Icon(cat.iconData, color: cat.color),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        cat.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  );
                  final startButton = ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48, minWidth: 140),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      onPressed: hasCategories ? _startFromSelected : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('开始计时'),
                    ),
                  );
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        dropdown,
                        const SizedBox(height: 12),
                        startButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: dropdown),
                      const SizedBox(width: 12),
                      startButton,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    final category = widget.controller.findCategory(current.categoryId);
    if (_lastCurrentTempId != current.tempId) {
      _lastCurrentTempId = current.tempId;
      widget.noteController.text = current.note;
    }
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      category?.color.withOpacity(0.15) ??
                      Colors.blue.withOpacity(0.15),
                  child: Icon(
                    category?.iconData ?? Icons.timelapse,
                    color: category?.color ?? Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category?.name ?? '进行中',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _handleEditStartTime(current),
                  icon: const Icon(Icons.edit_calendar),
                  tooltip: '修改开始时间',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.noteController,
              onChanged: (_) => _debounceCurrentNoteSave(current),
              decoration: InputDecoration(
                labelText: '记录内容',
                suffixIcon: _savingCurrentNote
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              formatDurationText(widget.controller.currentDuration),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: category?.color ?? Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _handlePause,
                    icon: const Icon(Icons.pause),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '暂停',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _handleStop,
                    icon: const Icon(Icons.stop),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '停止',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecents(List<RecentContext> recents) {
    if (recents.isEmpty) {
      return const Text('最近没有暂停的任务，暂停后可在这里继续。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近活动', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...recents.map((item) {
          final category = widget.controller.findCategory(item.categoryId);
          final isDeleted = category?.deleted ?? false;
          final isEnabled = category?.enabled ?? false;
          final statusLabel = isDeleted
              ? '（分类已删除）'
              : (!isEnabled ? '（已停用）' : '');
          final durationText = formatDurationText(
            Duration(seconds: item.accumulatedSeconds),
          );
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editRecentContext(item),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          category?.color.withOpacity(0.1) ??
                          Colors.blue.withOpacity(0.1),
                      child: Icon(
                        category?.iconData ?? Icons.history,
                        color: category?.color ?? Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category?.name ?? item.categoryId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$durationText · ${formatLastActiveText(item.lastActiveTime)}$statusLabel',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: isDeleted || !isEnabled
                              ? null
                              : () => _handleResume(item),
                          icon: const Icon(Icons.play_arrow_rounded),
                          tooltip: isDeleted
                              ? '分类已删除，无法继续'
                              : (!isEnabled ? '分类已停用，无法继续' : '继续'),
                        ),
                        IconButton(
                          onPressed: () async =>
                              widget.controller.removeRecentContext(
                            item.groupId,
                          ),
                          icon: const Icon(
                            Icons.archive_outlined,
                            color: Colors.redAccent,
                          ),
                          tooltip: '归档保存',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCategoryGrid(List<CategoryModel> categories) {
    final isDesktop = _isDesktopPlatform();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类网格', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = max(
              3,
              min(
                isDesktop ? 7 : 6,
                (width / (isDesktop ? 130 : 120)).floor(),
              ),
            );
            final spacing = isDesktop ? 8.0 : 10.0;
            final aspectRatio = isDesktop ? 1.05 : 0.78;
            return GridView.builder(
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final name = category.name.trim();
                final groupName = category.group.isNotEmpty
                    ? category.group
                    : (name.contains('.')
                          ? name.split('.').first.trim()
                          : name);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    const noteText = '';
                    try {
                      await widget.controller.switchToCategory(
                        categoryId: category.id,
                        note: noteText,
                      );
                    } catch (error) {
                      _showSnack(error.toString());
                    }
                  },
                  onLongPress: () => showManualDialog(category),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: category.color.withOpacity(0.35),
                      ),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: isDesktop ? 8 : 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          category.iconData,
                          color: category.color,
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          category.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (groupName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              groupName,
                              style: Theme.of(context).textTheme.labelSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
