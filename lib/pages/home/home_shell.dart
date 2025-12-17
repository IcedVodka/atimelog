import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/time_tracking_controller.dart';
import '../activity/activity_tab.dart';
import '../categories/category_manage_tab.dart';
import '../settings/settings_tab.dart';
import '../stats/stats_tab.dart';

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
  final GlobalKey<ActivityTabState> _activityKey =
      GlobalKey<ActivityTabState>();

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
