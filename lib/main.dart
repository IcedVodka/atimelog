import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/time_models.dart';
import 'services/time_storage_service.dart';
import 'services/time_tracking_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp(controller: TimeTrackingController(TimeStorageService())));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = widget.controller.init();
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
  final GlobalKey<_ActivityTabState> _activityKey = GlobalKey<_ActivityTabState>();

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
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
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

  @override
  void initState() {
    super.initState();
    final cats = widget.controller.categories.where((e) => e.enabled).toList();
    if (cats.isNotEmpty) {
      _selectedCategoryId = cats.first.id;
    }
  }

  Future<void> _startFromSelected() async {
    final noteText = widget.noteController.text.trim();
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      _showSnack('暂无分类可用');
      return;
    }
    final catName = widget.controller.findCategory(categoryId)?.name ?? '未命名任务';
    final note = noteText.isEmpty ? catName : noteText;
    try {
      await widget.controller.startNewActivity(categoryId: categoryId, note: note, allowSwitch: true);
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

  Future<void> showManualDialog([CategoryModel? initialCategory]) async {
    final categories = widget.controller.categories.where((c) => c.enabled).toList();
    if (categories.isEmpty) {
      _showSnack('暂无分类可用于补录');
      return;
    }
    CategoryModel? selected = initialCategory ?? categories.first;
    DateTime selectedDate = DateTime.now();
    TimeOfDay start = TimeOfDay.fromDateTime(DateTime.now());
    TimeOfDay end = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 25)));
    final noteController = TextEditingController(
      text: widget.noteController.text.isNotEmpty ? widget.noteController.text : selected.name,
    );

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
                    onChanged: (value) => setSheetState(() => selected = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final pickedDate = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 30)),
                              lastDate: DateTime.now(),
                            );
                            if (pickedDate != null) {
                              setSheetState(() => selectedDate = pickedDate);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: start);
                            if (picked != null) {
                              setSheetState(() => start = picked);
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(start.format(context)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: end);
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
                        onPressed: selected == null ? null : () => Navigator.of(context).pop(true),
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
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      start.hour,
      start.minute,
    );
    final endDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      end.hour,
      end.minute,
    );
    try {
      await widget.controller.manualAddRecord(
        categoryId: cat.id,
        note: noteController.text.trim().isEmpty ? cat.name : noteController.text.trim(),
        startTime: startDateTime,
        endTime: endDateTime,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('补录完成')));
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final categories = widget.controller.categories.where((e) => e.enabled).toList();
        if (_selectedCategoryId == null && categories.isNotEmpty) {
          _selectedCategoryId = categories.first.id;
        }
        final activity = widget.controller.currentActivity;
        final recents = widget.controller.recentContexts;

        return SafeArea(
          child: ListView(
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('尚未开始', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '点击下方分类或输入记录内容开始新任务。',
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
                  backgroundColor: category?.color.withOpacity(0.15) ?? Colors.blue.withOpacity(0.15),
                  child: Icon(category?.iconData ?? Icons.timelapse, color: category?.color ?? Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category?.name ?? '进行中',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                    label: const Text('停止并移除'),
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
            const SizedBox(height: 8),
            TextField(
              controller: widget.noteController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '记录内容',
                hintText: '例如：编写需求文档',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '分类'),
                    items: categories
                        .map((cat) => DropdownMenuItem(
                              value: cat.id,
                              child: Row(
                                children: [
                                  Icon(cat.iconData, color: cat.color),
                                  const SizedBox(width: 8),
                                  Text(cat.name),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedCategoryId = value),
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
          final durationText = _formatDuration(Duration(seconds: item.accumulatedSeconds));
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: category?.color.withOpacity(0.1) ?? Colors.blue.withOpacity(0.1),
                    child: Icon(category?.iconData ?? Icons.history, color: category?.color ?? Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.note, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${category?.name ?? item.categoryId} · 已记录 $durationText · ${_formatLastActive(item.lastActiveTime)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _handleResume(item),
                    icon: const Icon(Icons.play_circle, color: Colors.green),
                    tooltip: '继续',
                  ),
                  IconButton(
                    onPressed: () async => widget.controller.removeRecentContext(item.groupId),
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: '移除',
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                widget.noteController.text =
                    widget.noteController.text.trim().isEmpty ? category.name : widget.noteController.text;
                try {
                  await widget.controller.switchToCategory(
                    categoryId: category.id,
                    note:
                        widget.noteController.text.trim().isEmpty ? category.name : widget.noteController.text.trim(),
                  );
                } catch (error) {
                  _showSnack(error.toString());
                }
              },
              onLongPress: () => showManualDialog(category),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: category.color.withOpacity(0.3)),
                ),
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(category.iconData, color: category.color, size: 28),
                    const SizedBox(height: 6),
                    Text(
                      category.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (category.group.isNotEmpty)
                      Text(
                        category.group,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

enum StatsRange { today, week, month }

class StatsTab extends StatefulWidget {
  const StatsTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  StatsRange _range = StatsRange.today;

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
                children: const [
                  Icon(Icons.analytics_outlined, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('统计与历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
              child: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.timeline), text: '时间线'),
                  Tab(icon: Icon(Icons.pie_chart), text: '饼图'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTimeline(),
                  _buildPie(),
                ],
              ),
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
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
              ),
              IconButton(
                onPressed: _selectedDate.isBefore(DateTime.now())
                    ? () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)))
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AggregatedTimelineGroup>>(
            future: widget.controller.aggregateDay(_selectedDate),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('加载失败: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              if (data.isEmpty) {
                return const Center(child: Text('当天暂无记录'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final group = data[index];
                  final category = widget.controller.findCategory(group.categoryId);
                  final color = category?.color ?? Theme.of(context).colorScheme.primary;
                  return Card(
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.15),
                        child: Icon(category?.iconData ?? Icons.category, color: color),
                      ),
                      title: Text(group.note),
                      subtitle: Text(
                        '${category?.name ?? group.categoryId} · 总计 ${_formatDuration(group.totalDuration)}',
                      ),
                      children: group.segments
                          .map(
                            (segment) => ListTile(
                              title: Text(
                                '${_formatClock(segment.startTime)} - ${_formatClock(segment.endTime)}',
                              ),
                              subtitle: Text(
                                '片段 ${_formatDuration(segment.duration)} · ${segment.note.isEmpty ? '无备注' : segment.note}',
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    tooltip: '编辑',
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editRecord(segment),
                                  ),
                                  IconButton(
                                    tooltip: '删除',
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteRecord(segment),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
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

  Widget _buildPie() {
    final dateRange = _resolveRange();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('今日'),
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
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, Duration>>(
            future: widget.controller.categoryDurations(dateRange.$1, dateRange.$2),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('加载失败: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final totals = snapshot.data!;
              final slices = totals.entries.map((entry) {
                final category = widget.controller.findCategory(entry.key);
                return PieSliceData(
                  label: category?.name ?? entry.key,
                  value: entry.value.inSeconds.toDouble(),
                  color: category?.color ?? Colors.grey,
                );
              }).toList();
              final totalSeconds = totals.values.fold<int>(0, (prev, dur) => prev + dur.inSeconds);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    SimplePieChart(
                      slices: slices,
                      size: 260,
                      centerLabel: _formatDuration(Duration(seconds: totalSeconds)),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '范围: ${DateFormat('MM-dd').format(dateRange.$1)} - ${DateFormat('MM-dd').format(dateRange.$2)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: slices
                          .map(
                            (slice) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: slice.color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${slice.label} · ${_formatDuration(Duration(seconds: slice.value.toInt()))}',
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    switch (_range) {
      case StatsRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start, start);
      case StatsRange.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        final rangeStart = DateTime(start.year, start.month, start.day);
        return (rangeStart, DateTime(now.year, now.month, now.day));
      case StatsRange.month:
        final start = DateTime(now.year, now.month, 1);
        return (start, DateTime(now.year, now.month, now.day));
    }
  }

  Future<void> _editRecord(ActivityRecord record) async {
    final noteController = TextEditingController(text: record.note);
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
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: start);
                    if (picked != null) {
                      setDialogState(() => start = picked);
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(start.format(context)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: end);
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      return;
    }
    final startTime = DateTime(
      record.startTime.year,
      record.startTime.month,
      record.startTime.day,
      start.hour,
      start.minute,
    );
    final endTime = DateTime(
      record.endTime.year,
      record.endTime.month,
      record.endTime.day,
      end.hour,
      end.minute,
    );
    if (!startTime.isBefore(endTime)) {
      _showSnack('结束时间需要晚于开始时间');
      return;
    }
    await widget.controller.updateRecord(
      date: record.startTime,
      recordId: record.id,
      newStart: startTime,
      newEnd: endTime,
      note: noteController.text.trim(),
    );
    final updatedRecords = await widget.controller.loadDayRecords(record.startTime);
    final hasOverlap = widget.controller.hasOverlap(updatedRecords, ignoringId: record.id);
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
        content: const Text('确认删除该片段？历史数据不会被同步删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
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
}

class CategoryManageTab extends StatefulWidget {
  const CategoryManageTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<CategoryManageTab> createState() => _CategoryManageTabState();
}

class _CategoryManageTabState extends State<CategoryManageTab> {
  final List<Color> _palette = const [
    Color(0xFF2196F3),
    Color(0xFF8E44AD),
    Color(0xFFE91E63),
    Color(0xFF00ACC1),
    Color(0xFF7CB342),
    Color(0xFFFF9800),
    Color(0xFF455A64),
    Color(0xFFFBC02D),
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
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final categories = [...widget.controller.categories]..sort((a, b) => a.order.compareTo(b.order));
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('分类管理', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                  padding: const EdgeInsets.only(left: 12, right: 12, bottom: 80),
                  itemCount: categories.length,
                  onReorder: (oldIndex, newIndex) async {
                    final updated = [...categories];
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = updated.removeAt(oldIndex);
                    updated.insert(newIndex, item);
                    await widget.controller.reorderCategories(updated);
                  },
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    return Card(
                      key: ValueKey(cat.id),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cat.color.withOpacity(0.15),
                          child: Icon(cat.iconData, color: cat.color),
                        ),
                        title: Text(cat.name),
                        subtitle: Text('${cat.group.isEmpty ? '未分组' : cat.group} · 顺序 ${cat.order}'),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            Switch(
                              value: cat.enabled,
                              onChanged: (val) => widget.controller.toggleCategory(cat.id, val),
                            ),
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showCategoryEditor(existing: cat),
                            ),
                            IconButton(
                              tooltip: '停用',
                              icon: const Icon(Icons.archive_outlined),
                              onPressed: () => widget.controller.toggleCategory(cat.id, false),
                            ),
                          ],
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

  Future<void> _showCategoryEditor({CategoryModel? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final groupController = TextEditingController(text: existing?.group ?? '');
    Color color = existing?.color ?? _palette.first;
    IconData icon = existing?.iconData ?? _iconOptions.first;
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
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: groupController,
                    decoration: const InputDecoration(labelText: '分组'),
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
                                  color: color == c ? Colors.black : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButton<IconData>(
                      isExpanded: true,
                      value: icon,
                      items: _iconOptions
                          .map(
                            (opt) => DropdownMenuItem(
                              value: opt,
                              child: Row(
                                children: [
                                  Icon(opt),
                                  const SizedBox(width: 8),
                                  Text(opt.codePoint.toString()),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() => icon = value ?? icon),
                    ),
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
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
    final id = existing?.id ?? _buildCategoryId(name);
    final updated = CategoryModel(
      id: id,
      name: name,
      iconCode: icon.codePoint,
      colorHex: colorToHex(color),
      order: existing?.order ?? widget.controller.categories.length,
      enabled: enabled,
      group: groupController.text.trim(),
    );
    await widget.controller.addOrUpdateCategory(updated);
  }

  String _buildCategoryId(String name) {
    final base = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final exists = widget.controller.categories.any((element) => element.id == base);
    if (!exists) {
      return base;
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份完成: ${file.path}')));
      setState(() {});
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _handleRestore() async {
    final pathController = TextEditingController(text: widget.controller.settings.lastBackupPath ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(labelText: 'zip 文件路径'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('恢复')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.controller.restoreBackup(pathController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('恢复完成')));
      setState(() {});
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
  });

  final List<PieSliceData> slices;
  final double size;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    if (total <= 0) {
      return SizedBox(
        height: size,
        child: const Center(child: Text('暂无数据')),
      );
    }
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _PiePainter(slices),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              Text(
                '共 ${slices.length} 类',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.slices);

  final List<PieSliceData> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = size.width * 0.18;
    final total = slices.fold<double>(0, (prev, e) => prev + e.value);
    double startRadian = -pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * pi;
      paint.color = slice.color;
      canvas.drawArc(rect.deflate(20), startRadian, sweep, false, paint);
      startRadian += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.slices != slices;
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
