import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/time_models.dart';
import 'services/time_storage_service.dart';
import 'services/time_tracking_controller.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    title: 'AtimeLog',
    minimumSize: Size(420, 640),
  );
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktop) {
    await _initDesktopWindow();
  }
  await initializeDateFormatting('zh_CN', null);
  Intl.defaultLocale = 'zh_CN';
  runApp(MyApp(controller: TimeTrackingController(TimeStorageService())));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener, TrayListener {
  late Future<void> _initFuture;
  bool _trayReady = false;
  bool get _supportsTrayPopup => _isDesktop && !Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _initFuture = widget.controller.init();
    if (_isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      unawaited(_initSystemTray());
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      trayManager.destroy();
    }
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    final iconPath = _resolveTrayIconPath();
    if (iconPath == null) {
      return;
    }
    try {
      await trayManager.setIcon(iconPath);
      if (!Platform.isLinux) {
        await trayManager.setToolTip('AtimeLog');
      }
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open-panel', label: '打开面板'),
            MenuItem.separator(),
            MenuItem(key: 'exit-app', label: '退出'),
          ],
        ),
      );
      _trayReady = true;
    } catch (error) {
      debugPrint('初始化托盘失败: $error');
    }
  }

  String? _resolveTrayIconPath() {
    if (!_isDesktop) {
      return null;
    }
    return Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';
  }

  Future<void> _hideToTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _restoreFromTray() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitFromTray() async {
    if (!_isDesktop) {
      return;
    }
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onTrayIconMouseDown() {
    if (_trayReady && _supportsTrayPopup) {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_trayReady && _supportsTrayPopup) {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (!_trayReady) {
      return;
    }
    switch (menuItem.key) {
      case 'open-panel':
        unawaited(_restoreFromTray());
        break;
      case 'exit-app':
        unawaited(_exitFromTray());
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (!_isDesktop) {
      return;
    }
    final preventClose = await windowManager.isPreventClose();
    if (preventClose) {
      if (_trayReady) {
        await _hideToTray();
      } else {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      }
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            theme: _buildTheme(Brightness.light),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            theme: _buildTheme(Brightness.light),
            home: Scaffold(
              body: Center(child: Text('初始化失败: ${snapshot.error}')),
            ),
          );
        }
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final darkMode = widget.controller.settings.darkMode;
            return MaterialApp(
              title: 'AtimeLog',
              theme: _buildTheme(Brightness.light),
              darkTheme: _buildTheme(Brightness.dark),
              themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
              home: HomeShell(controller: widget.controller),
            );
          },
        );
      },
    );
  }
}

class _TabInfo {
  const _TabInfo(this.title, this.icon);
  final String title;
  final IconData icon;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late final TabController _tabController;
  final List<_TabInfo> _tabs = const [
    _TabInfo('活动', Icons.timer_outlined),
    _TabInfo('分类', Icons.grid_view_rounded),
    _TabInfo('统计', Icons.pie_chart_outline_rounded),
    _TabInfo('更多', Icons.more_horiz),
  ];
  final TextEditingController _noteController = TextEditingController();
  final GlobalKey<_ActivityTabState> _activityKey =
      GlobalKey<_ActivityTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    if (widget.controller.currentActivity != null) {
      _noteController.text = widget.controller.currentActivity?.note ?? '';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _headerSubtitle() {
    final now = DateTime.now();
    final dateText = DateFormat('MM月dd日, EEE').format(now);
    if (widget.controller.isRunning) {
      return '正在计时 · $dateText';
    }
    return '等待开始 · $dateText';
  }

  Widget? _buildFab() {
    if (_tabController.index == 0) {
      return FloatingActionButton(
        onPressed: () => _activityKey.currentState?.showManualDialog(),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _tabs[_tabController.index].title;
    return Scaffold(
      floatingActionButton: _buildFab(),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            backgroundColor: Colors.blue,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.only(left: 24, right: 16, bottom: 48),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTitle,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _headerSubtitle(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                color: Colors.blueGrey.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: _tabs
                      .map(
                        (tab) => Tab(
                          icon: Icon(tab.icon, size: 22),
                          text: tab.title,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            ActivityTab(
              key: _activityKey,
              controller: widget.controller,
              noteController: _noteController,
            ),
            CategoryManageTab(controller: widget.controller),
            StatsTab(controller: widget.controller),
            SettingsTab(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}

class ActivityTab extends StatefulWidget {
  const ActivityTab({
    super.key,
    required this.controller,
    required this.noteController,
  });

  final TimeTrackingController controller;
  final TextEditingController noteController;

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  String? _selectedCategoryId;
  bool _savingCurrentNote = false;
  String? _lastCurrentTempId;
  Timer? _noteSaveDebounce;

  @override
  void initState() {
    super.initState();
    final cats = widget.controller.categories.where((e) => e.enabled).toList();
    if (cats.isNotEmpty) {
      _selectedCategoryId = cats.first.id;
    }
  }

  @override
  void dispose() {
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
        }
        final activity = widget.controller.currentActivity;
        final recents = widget.controller.recentContexts;

        return SafeArea(
          child: ListView(
            primary: false,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _buildActiveCard(activity),
              const SizedBox(height: 12),
              _buildQuickStart(categories),
              const SizedBox(height: 12),
              _buildRecents(recents),
              const SizedBox(height: 12),
              _buildCategoryGrid(categories),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveCard(CurrentActivity? current) {
    if (current == null) {
      _lastCurrentTempId = null;
      widget.noteController.text = '';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('尚未开始', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '点击下方分类开始新任务，记录内容默认使用分类名称，可在开始后修改。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _startFromSelected,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始计时'),
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
                      const SizedBox(height: 4),
                      Text(
                        current.note,
                        style: Theme.of(context).textTheme.bodyMedium,
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
                    : const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.check_circle, size: 18),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _formatDuration(widget.controller.currentDuration),
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
                    onPressed: _handlePause,
                    icon: const Icon(Icons.pause),
                    label: const Text('暂停 (归档)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _handleStop,
                    icon: const Icon(Icons.stop),
                    label: const Text('停止并归档保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStart(List<CategoryModel> categories) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('快速开始', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '分类',
                    ),
                    items: categories
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat.id,
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
                    onChanged: (value) =>
                        setState(() => _selectedCategoryId = value),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _startFromSelected,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始'),
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
          final durationText = _formatDuration(
            Duration(seconds: item.accumulatedSeconds),
          );
          return Card(
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.note,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${category?.name ?? item.categoryId}$statusLabel · 已记录 $durationText · ${_formatLastActive(item.lastActiveTime)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: isDeleted || !isEnabled
                        ? null
                        : () => _handleResume(item),
                    icon: const Icon(Icons.play_circle, color: Colors.green),
                    tooltip: isDeleted
                        ? '分类已删除，无法继续'
                        : (!isEnabled ? '分类已停用，无法继续' : '继续'),
                  ),
                  IconButton(
                    onPressed: () => _editRecentContext(item),
                    icon: const Icon(Icons.edit_note_outlined),
                    tooltip: '编辑',
                  ),
                  IconButton(
                    onPressed: () async =>
                        widget.controller.removeRecentContext(item.groupId),
                    icon: const Icon(
                      Icons.archive_outlined,
                      color: Colors.redAccent,
                    ),
                    tooltip: '归档保存',
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCategoryGrid(List<CategoryModel> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类网格', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = max(5, min(8, (width / 90).floor()));
            return GridView.builder(
              primary: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
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

enum TimelineRangeMode { day, last24h, custom }

enum StatsRange { today, week, month, last24h, custom }

class StatsTab extends StatefulWidget {
  const StatsTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab>
    with SingleTickerProviderStateMixin {
  TimelineRangeMode _timelineMode = TimelineRangeMode.day;
  DateTime _timelineDate = DateTime.now();
  DateTimeRange? _timelineCustomRange;
  String _timelineKeyword = '';
  bool _mergePause = true;
  bool _groupMerge = false;

  StatsRange _range = StatsRange.today;
  DateTimeRange? _pieCustomRange;
  int? _activeSliceIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    '统计与历史',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('合并暂停片段'),
                        selected: _mergePause,
                        onSelected: (val) => setState(() => _mergePause = val),
                      ),
                      FilterChip(
                        label: const Text('合并群组'),
                        selected: _groupMerge,
                        onSelected: (val) => setState(() => _groupMerge = val),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              color: Theme.of(
                context,
              ).colorScheme.surfaceVariant.withOpacity(0.6),
              child: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.timeline), text: '时间线'),
                  Tab(icon: Icon(Icons.pie_chart), text: '饼图'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(children: [_buildTimeline(), _buildPie()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('最近24小时'),
                      selected: _timelineMode == TimelineRangeMode.last24h,
                      onSelected: (_) => setState(
                        () => _timelineMode = TimelineRangeMode.last24h,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('指定日期'),
                      selected: _timelineMode == TimelineRangeMode.day,
                      onSelected: (_) =>
                          setState(() => _timelineMode = TimelineRangeMode.day),
                    ),
                    ChoiceChip(
                      label: const Text('自定义范围'),
                      selected: _timelineMode == TimelineRangeMode.custom,
                      onSelected: (_) => setState(
                        () => _timelineMode = TimelineRangeMode.custom,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '搜索记录内容 / 分类',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setState(() => _timelineKeyword = value),
                ),
              ),
            ],
          ),
        ),
        if (_timelineMode == TimelineRangeMode.day)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => _timelineDate = _timelineDate.subtract(
                      const Duration(days: 1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _timelineDate,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _timelineDate = picked);
                    }
                  },
                  child: Text(DateFormat('yyyy-MM-dd').format(_timelineDate)),
                ),
                IconButton(
                  onPressed: _timelineDate.isBefore(DateTime.now())
                      ? () => setState(
                          () => _timelineDate = _timelineDate.add(
                            const Duration(days: 1),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        if (_timelineMode == TimelineRangeMode.custom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Builder(
              builder: (context) {
                final now = DateTime.now();
                final custom =
                    _timelineCustomRange ??
                    DateTimeRange(
                      start: now.subtract(const Duration(days: 1)),
                      end: now,
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('MM-dd HH:mm').format(custom.start)} - ${DateFormat('MM-dd HH:mm').format(custom.end)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              initialDateRange: custom,
                              firstDate: now.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: now,
                            );
                            if (picked != null) {
                              setState(() {
                                _timelineCustomRange = DateTimeRange(
                                  start: DateTime(
                                    picked.start.year,
                                    picked.start.month,
                                    picked.start.day,
                                  ),
                                  end: DateTime(
                                    picked.end.year,
                                    picked.end.month,
                                    picked.end.day,
                                    23,
                                    59,
                                    59,
                                  ),
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('日期范围'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: custom.start,
                              firstDate: now.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: now,
                            );
                            if (pickedDate == null) return;
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(custom.start),
                            );
                            final time =
                                pickedTime ??
                                TimeOfDay.fromDateTime(custom.start);
                            final updated = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              time.hour,
                              time.minute,
                            );
                            if (updated.isAfter(custom.end)) {
                              _showSnack('开始时间需早于结束时间');
                              return;
                            }
                            setState(() {
                              _timelineCustomRange = DateTimeRange(
                                start: updated,
                                end: custom.end,
                              );
                            });
                          },
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('起始时间'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: custom.end,
                              firstDate: now.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: now,
                            );
                            if (pickedDate == null) return;
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(custom.end),
                            );
                            final time =
                                pickedTime ??
                                TimeOfDay.fromDateTime(custom.end);
                            final updated = DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              time.hour,
                              time.minute,
                            );
                            if (!updated.isAfter(custom.start)) {
                              _showSnack('结束时间需要晚于开始时间');
                              return;
                            }
                            setState(() {
                              _timelineCustomRange = DateTimeRange(
                                start: custom.start,
                                end: updated,
                              );
                            });
                          },
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('结束时间'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<_TimelineGroupDisplay>>(
            future: _loadTimelineGroups(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('加载失败: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final groups = snapshot.data!;
              if (groups.isEmpty) {
                return const Center(child: Text('当前范围暂无记录'));
              }
              final dayGroups = <DateTime, List<_TimelineGroupDisplay>>{};
              for (final group in groups) {
                dayGroups.putIfAbsent(group.day, () => []).add(group);
              }
              final days = dayGroups.keys.toList()
                ..sort((a, b) => b.compareTo(a));
              return ListView.builder(
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final grouped = dayGroups[day]!
                    ..sort((a, b) => b.end.compareTo(a.end));
                  final dayLabel = DateFormat(
                    'MM月 dd日，EEEE',
                    'zh_CN',
                  ).format(day);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayLabel,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...grouped.map(_buildTimelineCard),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(_TimelineGroupDisplay group) {
    final category = widget.controller.findCategory(group.categoryId);
    final color = _categoryColor(group.categoryId);
    final displayName = _groupMerge
        ? group.groupLabel
        : _categoryDisplayName(group.categoryId);
    Widget infoPill(String text, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(
                    category?.iconData ?? Icons.category,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          infoPill(
                            '群组 ${group.groupLabel}',
                            Icons.folder_special_outlined,
                          ),
                          infoPill(
                            '总计 ${_formatDuration(group.totalDuration)}',
                            Icons.av_timer,
                          ),
                          infoPill(
                            '片段 ${group.segments.length}',
                            Icons.view_agenda_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...group.segments.map(
              (segment) => Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_formatClock(segment.startTime)} - ${_formatClock(segment.endTime)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            segment.note.isEmpty
                                ? '记录内容：无'
                                : '记录内容：${segment.note}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDuration(segment.duration),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editRecord(segment),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteRecord(segment),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPie() {
    final dateRange = _resolvePieRange();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('最近24小时'),
                selected: _range == StatsRange.last24h,
                onSelected: (_) => setState(() => _range = StatsRange.last24h),
              ),
              ChoiceChip(
                label: const Text('本日'),
                selected: _range == StatsRange.today,
                onSelected: (_) => setState(() => _range = StatsRange.today),
              ),
              ChoiceChip(
                label: const Text('本周'),
                selected: _range == StatsRange.week,
                onSelected: (_) => setState(() => _range = StatsRange.week),
              ),
              ChoiceChip(
                label: const Text('本月'),
                selected: _range == StatsRange.month,
                onSelected: (_) => setState(() => _range = StatsRange.month),
              ),
              ChoiceChip(
                label: const Text('自定义'),
                selected: _range == StatsRange.custom,
                onSelected: (_) => setState(() => _range = StatsRange.custom),
              ),
            ],
          ),
        ),
        if (_range == StatsRange.custom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _pieCustomRange == null
                        ? '请选择统计范围'
                        : '${DateFormat('MM-dd').format(_pieCustomRange!.start)} - ${DateFormat('MM-dd').format(_pieCustomRange!.end)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange:
                          _pieCustomRange ??
                          DateTimeRange(
                            start: now.subtract(const Duration(days: 6)),
                            end: now,
                          ),
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setState(() {
                        _pieCustomRange = DateTimeRange(
                          start: DateTime(
                            picked.start.year,
                            picked.start.month,
                            picked.start.day,
                          ),
                          end: DateTime(
                            picked.end.year,
                            picked.end.month,
                            picked.end.day,
                            23,
                            59,
                            59,
                          ),
                        );
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('选择范围'),
                ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<Map<String, Duration>>(
            future: widget.controller.categoryDurations(
              dateRange.$1,
              dateRange.$2,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('加载失败: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final totals = snapshot.data!;
              final slices = _buildPieSlices(totals);
              final totalSeconds = totals.values.fold<int>(
                0,
                (prev, dur) => prev + dur.inSeconds,
              );
              final idx = _activeSliceIndex;
              final activeIndex = (idx != null && idx < slices.length)
                  ? idx
                  : null;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    children: [
                      SimplePieChart(
                        slices: slices,
                        size: 280,
                        centerLabel: _formatDuration(
                          Duration(seconds: totalSeconds),
                        ),
                        highlightedIndex: activeIndex,
                        onSliceTap: (index) =>
                            setState(() => _activeSliceIndex = index),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '范围: ${DateFormat('MM-dd').format(dateRange.$1)} - ${DateFormat('MM-dd').format(dateRange.$2)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          activeIndex != null && totalSeconds > 0
                              ? '已选：${slices[activeIndex].label} · ${_formatDuration(Duration(seconds: slices[activeIndex].value.round()))} · ${(slices[activeIndex].value / totalSeconds * 100).toStringAsFixed(1)}%'
                              : '点击饼图扇区查看具体占比',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: slices.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final slice = entry.value;
                          final percent = totalSeconds == 0
                              ? 0
                              : (slice.value / totalSeconds) * 100;
                          final selected = idx == activeIndex;
                          return InkWell(
                            onTap: () =>
                                setState(() => _activeSliceIndex = idx),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? slice.color.withOpacity(0.12)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceVariant
                                          .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: slice.color.withOpacity(0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: slice.color,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          slice.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_formatDuration(Duration(seconds: slice.value.round()))} · ${percent.toStringAsFixed(1)}%',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${percent.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: slice.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  (DateTime, DateTime) _resolvePieRange() {
    final now = DateTime.now();
    switch (_range) {
      case StatsRange.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = start
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return (start, end);
      case StatsRange.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final rangeStart = DateTime(start.year, start.month, start.day);
        final rangeEnd = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
          999,
        );
        return (rangeStart, rangeEnd);
      case StatsRange.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return (start, end);
      case StatsRange.last24h:
        final end = now;
        final start = now.subtract(const Duration(hours: 24));
        return (start, end);
      case StatsRange.custom:
        final fallback = DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
        final picked = _pieCustomRange ?? fallback;
        return (picked.start, picked.end);
    }
  }

  Future<void> _editRecord(ActivityRecord record) async {
    final noteController = TextEditingController(text: record.note);
    DateTime startDate = record.startTime;
    DateTime endDate = record.endTime;
    TimeOfDay start = TimeOfDay.fromDateTime(record.startTime);
    TimeOfDay end = TimeOfDay.fromDateTime(record.endTime);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('编辑记录'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setDialogState(() => startDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(DateFormat('yyyy-MM-dd').format(startDate)),
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
                              const Duration(days: 365),
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
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: start,
                    );
                    if (picked != null) {
                      setDialogState(() => start = picked);
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(start.format(context)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: end,
                    );
                    if (picked != null) {
                      setDialogState(() => end = picked);
                    }
                  },
                  icon: const Icon(Icons.stop),
                  label: Text(end.format(context)),
                ),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
              ],
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
    final startTime = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      start.hour,
      start.minute,
    );
    final endTime = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      end.hour,
      end.minute,
    );
    if (!startTime.isBefore(endTime)) {
      _showSnack('结束时间需要晚于开始时间');
      return;
    }
    if (!isSameDay(startTime, record.startTime)) {
      _showSnack('暂不支持跨日修改，若需跨日请拆分记录');
      return;
    }
    if (!isSameDay(endTime, record.endTime)) {
      _showSnack('暂不支持跨日修改，若需跨日请拆分记录');
      return;
    }
    final resolvedNote = noteController.text.trim().isEmpty
        ? _resolveNote(record)
        : noteController.text.trim();
    await widget.controller.updateRecordWithSync(
      record: record,
      newStart: startTime,
      newEnd: endTime,
      note: resolvedNote,
      syncGroupNotes: true,
    );
    final updatedRecords = await widget.controller.loadDayRecords(
      record.startTime,
    );
    final hasOverlap = widget.controller.hasOverlap(
      updatedRecords,
      ignoringId: record.id,
    );
    if (hasOverlap) {
      _showSnack('已保存，但存在时间段重叠');
    }
    setState(() {});
  }

  Future<void> _deleteRecord(ActivityRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确认删除该片段？删除后历史数据将被移除且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.controller.deleteRecord(record.startTime, record.id);
      setState(() {});
    }
  }

  void _showSnack(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<List<_TimelineGroupDisplay>> _loadTimelineGroups() async {
    final range = _timelineRange();
    final records = await widget.controller.loadRangeRecords(
      range.$1,
      range.$2,
    );
    final keyword = _timelineKeyword.trim().toLowerCase();

    bool matchKeyword(ActivityRecord record) {
      if (keyword.isEmpty) return true;
      final noteText = record.note.toLowerCase();
      final catName = _categoryDisplayName(record.categoryId).toLowerCase();
      final groupLabel = _groupLabel(
        widget.controller.findCategory(record.categoryId),
      ).toLowerCase();
      return noteText.contains(keyword) ||
          catName.contains(keyword) ||
          groupLabel.contains(keyword);
    }

    final filtered =
        records
            .where(
              (r) =>
                  r.endTime.isAfter(range.$1) &&
                  r.startTime.isBefore(range.$2) &&
                  matchKeyword(r),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (filtered.isEmpty) {
      return const [];
    }

    List<_TimelineGroupDisplay> base;
    if (_mergePause) {
      final byGroupId = <String, List<ActivityRecord>>{};
      for (final record in filtered) {
        byGroupId.putIfAbsent(record.groupId, () => []).add(record);
      }
      final aggregated = byGroupId.entries.map((entry) {
        final segs = [...entry.value]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        final first = segs.first;
        return _TimelineGroupDisplay(
          title: _categoryDisplayName(first.categoryId),
          categoryId: first.categoryId,
          groupLabel: _groupLabel(
            widget.controller.findCategory(first.categoryId),
          ),
          segments: segs,
          day: DateTime(
            first.startTime.year,
            first.startTime.month,
            first.startTime.day,
          ),
        );
      }).toList()..sort((a, b) => a.start.compareTo(b.start));
      base = _groupMerge ? _mergeByGroupLabel(aggregated) : aggregated;
    } else if (_groupMerge) {
      final byGroupLabel = <String, List<ActivityRecord>>{};
      for (final record in filtered) {
        final key = _groupLabel(
          widget.controller.findCategory(record.categoryId),
        );
        byGroupLabel.putIfAbsent(key, () => []).add(record);
      }
      final grouped = byGroupLabel.entries.map((entry) {
        final segs = [...entry.value]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        final first = segs.first;
        return _TimelineGroupDisplay(
          title: entry.key,
          categoryId: first.categoryId,
          groupLabel: entry.key,
          segments: segs,
          day: DateTime(
            first.startTime.year,
            first.startTime.month,
            first.startTime.day,
          ),
        );
      }).toList()..sort((a, b) => a.start.compareTo(b.start));
      base = grouped;
    } else {
      base = filtered
          .map(
            (r) => _TimelineGroupDisplay(
              title: _categoryDisplayName(r.categoryId),
              categoryId: r.categoryId,
              groupLabel: _groupLabel(
                widget.controller.findCategory(r.categoryId),
              ),
              segments: [r],
              day: DateTime(
                r.startTime.year,
                r.startTime.month,
                r.startTime.day,
              ),
            ),
          )
          .toList();
    }

    return _splitGroupsByDay(base);
  }

  (DateTime, DateTime) _timelineRange() {
    final now = DateTime.now();
    switch (_timelineMode) {
      case TimelineRangeMode.day:
        final start = DateTime(
          _timelineDate.year,
          _timelineDate.month,
          _timelineDate.day,
        );
        final end = start
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return (start, end);
      case TimelineRangeMode.last24h:
        final end = now;
        final start = now.subtract(const Duration(hours: 24));
        return (start, end);
      case TimelineRangeMode.custom:
        final fallback = DateTimeRange(
          start: now.subtract(const Duration(days: 1)),
          end: now,
        );
        final picked = _timelineCustomRange ?? fallback;
        return (picked.start, picked.end);
    }
  }

  List<_TimelineGroupDisplay> _splitGroupsByDay(
    List<_TimelineGroupDisplay> items,
  ) {
    final result = <_TimelineGroupDisplay>[];
    for (final item in items) {
      final byDay = <DateTime, List<ActivityRecord>>{};
      for (final seg in item.segments) {
        final dayKey = DateTime(
          seg.startTime.year,
          seg.startTime.month,
          seg.startTime.day,
        );
        byDay.putIfAbsent(dayKey, () => []).add(seg);
      }
      byDay.forEach((day, segs) {
        final ordered = [...segs]
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
        result.add(
          _TimelineGroupDisplay(
            title: item.title,
            categoryId: item.categoryId,
            groupLabel: item.groupLabel,
            segments: ordered,
            day: day,
          ),
        );
      });
    }
    result.sort((a, b) => b.end.compareTo(a.end));
    return result;
  }

  List<PieSliceData> _buildPieSlices(Map<String, Duration> totals) {
    if (!_groupMerge) {
      return totals.entries.map((entry) {
        return PieSliceData(
          label: _categoryDisplayName(entry.key),
          value: entry.value.inSeconds.toDouble(),
          color: _categoryColor(entry.key),
        );
      }).toList();
    }

    final groupDurations = <String, int>{};
    totals.forEach((catId, duration) {
      final key = _groupLabel(widget.controller.findCategory(catId));
      groupDurations.update(
        key,
        (value) => value + duration.inSeconds,
        ifAbsent: () => duration.inSeconds,
      );
    });

    return groupDurations.entries.map((entry) {
      return PieSliceData(
        label: entry.key,
        value: entry.value.toDouble(),
        color: _groupColor(entry.key),
      );
    }).toList();
  }

  String _categoryDisplayName(String categoryId) {
    final category = widget.controller.findCategory(categoryId);
    if (category != null) {
      return category.name;
    }
    final fallback = categoryId.trim().isEmpty ? '未命名' : categoryId.trim();
    return '其他.$fallback';
  }

  Color _categoryColor(String categoryId) {
    final category = widget.controller.findCategory(categoryId);
    return category?.color ?? Colors.grey;
  }

  Color _groupColor(String groupLabel) {
    for (final cat in widget.controller.allCategories) {
      if (_groupLabel(cat) == groupLabel) {
        return cat.color;
      }
    }
    return Colors.grey;
  }

  String _resolveNote(ActivityRecord record) {
    if (record.note.trim().isNotEmpty) return record.note.trim();
    return _categoryDisplayName(record.categoryId);
  }

  String _groupLabel(CategoryModel? category) {
    if (category == null) return '其他';
    if (category.group.trim().isNotEmpty) {
      return category.group.trim();
    }
    if (category.name.contains('.')) {
      return category.name.split('.').first;
    }
    return category.name.trim();
  }

  List<_TimelineGroupDisplay> _mergeByGroupLabel(
    List<_TimelineGroupDisplay> items,
  ) {
    final map = <String, List<ActivityRecord>>{};
    for (final item in items) {
      map.putIfAbsent(item.groupLabel, () => []).addAll(item.segments);
    }
    final result = map.entries.map((entry) {
      final segs = [...entry.value]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final first = segs.first;
      return _TimelineGroupDisplay(
        title: entry.key,
        categoryId: first.categoryId,
        groupLabel: entry.key,
        segments: segs,
        day: DateTime(
          first.startTime.year,
          first.startTime.month,
          first.startTime.day,
        ),
      );
    }).toList()..sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
}

class _TimelineGroupDisplay {
  _TimelineGroupDisplay({
    required this.title,
    required this.categoryId,
    required this.groupLabel,
    required this.segments,
    required this.day,
  });

  final String title;
  final String categoryId;
  final String groupLabel;
  final List<ActivityRecord> segments;
  final DateTime day;

  Duration get totalDuration {
    final seconds = segments.fold<int>(
      0,
      (prev, e) => prev + e.durationSeconds,
    );
    return Duration(seconds: seconds);
  }

  DateTime get start =>
      segments.map((e) => e.startTime).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get end =>
      segments.map((e) => e.endTime).reduce((a, b) => a.isAfter(b) ? a : b);
}

class CategoryManageTab extends StatefulWidget {
  const CategoryManageTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<CategoryManageTab> createState() => _CategoryManageTabState();
}

class _CategoryManageTabState extends State<CategoryManageTab> {
  final List<Color> _palette = const [
    Color(0xFF1565C0), // 蓝
    Color(0xFF1E88E5),
    Color(0xFF90CAF9),
    Color(0xFF0D47A1),
    Color(0xFF6A1B9A), // 紫
    Color(0xFF8E24AA),
    Color(0xFFBA68C8),
    Color(0xFF9C27B0),
    Color(0xFFC2185B), // 粉
    Color(0xFFE91E63),
    Color(0xFFFF80AB),
    Color(0xFFD81B60),
    Color(0xFF00897B), // 青
    Color(0xFF26A69A),
    Color(0xFF26C6DA),
    Color(0xFF4DD0E1),
    Color(0xFF2E7D32), // 绿
    Color(0xFF43A047),
    Color(0xFF81C784),
    Color(0xFFA5D6A7),
    Color(0xFFFFB300), // 黄/橙
    Color(0xFFFFD54F),
    Color(0xFFFF8F00),
    Color(0xFFFF7043),
    Color(0xFF6D4C41), // 棕
    Color(0xFF8D6E63),
    Color(0xFF455A64), // 深灰
    Color(0xFF607D8B),
    Color(0xFF9E9E9E),
  ];
  final List<IconData> _iconOptions = const [
    Icons.computer,
    Icons.hotel_outlined,
    Icons.movie_filter_outlined,
    Icons.fitness_center,
    Icons.sports_esports,
    Icons.home,
    Icons.people,
    Icons.book_outlined,
    Icons.shopping_cart,
    Icons.work_outline,
    Icons.fastfood,
    Icons.code,
    Icons.brush_outlined,
    Icons.music_note,
    Icons.pets,
    Icons.child_friendly,
    Icons.school,
    Icons.car_rental,
    Icons.self_improvement,
    Icons.travel_explore,
    Icons.coffee,
    Icons.nightlight_round,
    Icons.camera_alt_outlined,
    Icons.flight_takeoff,
    Icons.hiking,
    Icons.public,
    Icons.lightbulb_outline,
    Icons.laptop_mac,
    Icons.directions_bike,
    Icons.local_hospital,
    Icons.mediation,
    Icons.palette_outlined,
    Icons.waves,
    Icons.timer,
    Icons.restaurant_menu,
    Icons.spa,
    Icons.emoji_events,
    Icons.handyman_outlined,
    Icons.build_circle_outlined,
    Icons.cake_outlined,
  ];
  int? _draggingIndex;
  List<IconData> _buildIconOptions(IconData current) {
    final seen = <String>{};
    final result = <IconData>[];
    String keyFor(IconData icon) =>
        '${icon.fontFamily ?? 'MaterialIcons'}-${icon.codePoint}';
    void addIcon(IconData icon) {
      final key = keyFor(icon);
      if (seen.add(key)) {
        result.add(icon);
      }
    }

    addIcon(current);
    for (final icon in _iconOptions) {
      addIcon(icon);
    }
    return result;
  }

  String _deriveGroupFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parts = trimmed.split('.');
    if (parts.length >= 2 && parts.first.trim().isNotEmpty) {
      return parts.first.trim();
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final categories = [...widget.controller.allCategories]
          ..sort((a, b) => a.order.compareTo(b.order));
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '分类管理',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCategoryEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('新增'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                  buildDefaultDragHandles: false,
                  itemCount: categories.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final updated = [...categories];
                    final item = updated.removeAt(oldIndex);
                    updated.insert(newIndex, item);
                    await widget.controller.reorderCategories(updated);
                    setState(() {});
                  },
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final groupLabel = _deriveGroupFromName(cat.name);
                    return Container(
                      key: ValueKey(cat.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: _categoryCard(
                        cat,
                        groupLabel: groupLabel,
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryCard(
    CategoryModel cat, {
    required String groupLabel,
    Widget? dragHandle,
  }) {
    final resolvedGroup = groupLabel.isEmpty ? cat.name : groupLabel;
    final theme = Theme.of(context);
    final isDeleted = cat.deleted;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cat.color.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: cat.color.withOpacity(0.12),
                  child: Icon(cat.iconData, color: cat.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      if (isDeleted)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '已删除（仅配置文件）',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      Text(
                        resolvedGroup,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: cat.enabled,
                  onChanged: isDeleted
                      ? null
                      : (val) => widget.controller.toggleCategory(cat.id, val),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (dragHandle != null) dragHandle,
                const SizedBox(width: 6),
                Text('顺序 ${cat.order}', style: theme.textTheme.bodySmall),
                const Spacer(),
                IconButton(
                  tooltip: '编辑',
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showCategoryEditor(existing: cat),
                ),
                IconButton(
                  tooltip: '删除（从配置移除，不影响历史数据）',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _deleteCategory(cat),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCategoryEditor({CategoryModel? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    Color color = existing?.color ?? _palette.first;
    IconData icon = existing?.iconData ?? _iconOptions.first;
    String derivedGroup = _deriveGroupFromName(nameController.text);
    bool enabled = existing?.enabled ?? true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? '新增分类' : '编辑分类'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      helperText: '使用“群组.子类”自动分组，例如：睡眠.午睡',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        derivedGroup = _deriveGroupFromName(value);
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '当前群组: ${derivedGroup.isEmpty ? '填写名称后自动生成' : derivedGroup}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _palette
                        .map(
                          (c) => GestureDetector(
                            onTap: () => setDialogState(() => color = c),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == c
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '图标',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildIconOptions(icon)
                        .map(
                          (opt) => ChoiceChip(
                            label: Icon(
                              opt,
                              color: opt == icon
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                            ),
                            selected: opt == icon,
                            selectedColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onSelected: (_) => setDialogState(() => icon = opt),
                          ),
                        )
                        .toList(),
                  ),
                  SwitchListTile(
                    title: const Text('启用'),
                    value: enabled,
                    onChanged: (val) => setDialogState(() => enabled = val),
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
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('名称不能为空');
      return;
    }
    final parsedGroup = _deriveGroupFromName(name);
    final id = existing?.id ?? _buildCategoryId(name);
    final updated = CategoryModel(
      id: id,
      name: name,
      iconCode: icon.codePoint,
      colorHex: colorToHex(color),
      order: existing?.order ?? widget.controller.allCategories.length,
      enabled: enabled,
      group: parsedGroup,
    );
    await widget.controller.addOrUpdateCategory(updated);
  }

  String _buildCategoryId(String name) {
    final base = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final exists = widget.controller.allCategories.any(
      (element) => element.id == base,
    );
    if (!exists) {
      return base;
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: const Text('将从 categories.json 中移除该分类，历史数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.removeCategory(cat.id);
    if (!mounted) return;
    _showSnack('已删除 ${cat.name}');
  }
}

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

class PieSliceData {
  PieSliceData({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

class SimplePieChart extends StatelessWidget {
  const SimplePieChart({
    super.key,
    required this.slices,
    this.size = 220,
    this.centerLabel,
    this.highlightedIndex,
    this.onSliceTap,
  });

  final List<PieSliceData> slices;
  final double size;
  final String? centerLabel;
  final int? highlightedIndex;
  final ValueChanged<int>? onSliceTap;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    if (total <= 0) {
      return SizedBox(
        height: size,
        child: const Center(child: Text('暂无数据')),
      );
    }
    final outerRadius = size / 2 - 20;
    final maxStroke = size * 0.22;
    final innerRadius = outerRadius - maxStroke;
    Widget chart = CustomPaint(
      size: Size.square(size),
      painter: _PiePainter(slices, highlightedIndex),
    );
    if (onSliceTap != null) {
      chart = GestureDetector(
        onTapDown: (details) {
          final local = details.localPosition;
          final center = Offset(size / 2, size / 2);
          final dx = local.dx - center.dx;
          final dy = local.dy - center.dy;
          final distance = sqrt(dx * dx + dy * dy);
          if (distance < innerRadius ||
              distance > outerRadius + maxStroke / 2) {
            return;
          }
          double angle = atan2(dy, dx);
          angle = (angle + 2 * pi) % (2 * pi);
          double cursor = -pi / 2;
          for (var i = 0; i < slices.length; i++) {
            final sweep = (slices[i].value / total) * 2 * pi;
            if (angle >= cursor && angle <= cursor + sweep) {
              onSliceTap!(i);
              break;
            }
            cursor += sweep;
          }
        },
        child: chart,
      );
    }
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          chart,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Text(
                '共 ${slices.length} 类',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.slices, this.highlightedIndex);

  final List<PieSliceData> slices;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(20);
    final paint = Paint()..style = PaintingStyle.stroke;
    final baseStroke = size.width * 0.18;
    final highlightStroke = size.width * 0.22;
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    double startRadian = -pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final sweep = (slice.value / total) * 2 * pi;
      paint.color = slice.color;
      paint.strokeWidth = i == highlightedIndex ? highlightStroke : baseStroke;
      canvas.drawArc(rect, startRadian, sweep, false, paint);
      startRadian += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.highlightedIndex != highlightedIndex;
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write(hours.toString().padLeft(2, '0'));
    buffer.write(':');
  }
  buffer.write(minutes.toString().padLeft(2, '0'));
  buffer.write(':');
  buffer.write(seconds.toString().padLeft(2, '0'));
  return buffer.toString();
}

String _formatLastActive(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  return DateFormat('MM-dd HH:mm').format(time);
}

String _formatClock(DateTime dateTime) {
  return DateFormat('HH:mm').format(dateTime);
}
