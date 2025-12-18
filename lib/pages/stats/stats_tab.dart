import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/time_formatter.dart';
import '../../models/time_models.dart';
import '../../services/time_tracking_controller.dart';
import '../../widgets/simple_pie_chart.dart';
import '../../widgets/overlap_fix_dialog.dart';

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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabBarWidth = math.max(constraints.maxWidth * 0.6, 200.0);
                  final toggleWidth = math.max(tabBarWidth / 4, 80.0);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceVariant.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: tabBarWidth,
                            child: const TabBar(
                              tabs: [
                                Tab(icon: Icon(Icons.timeline), text: '时间线'),
                                Tab(icon: Icon(Icons.pie_chart), text: '饼图'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: toggleWidth,
                                child: _mergeToggle(
                                  label: '事件',
                                  value: _mergePause,
                                  onChanged: (val) =>
                                      setState(() => _mergePause = val),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: toggleWidth,
                                child: _mergeToggle(
                                  label: '群组',
                                  value: _groupMerge,
                                  onChanged: (val) =>
                                      setState(() => _groupMerge = val),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
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

  Widget _mergeToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: value
            ? theme.colorScheme.primary.withOpacity(0.14)
            : theme.colorScheme.surfaceVariant.withOpacity(0.45),
        foregroundColor:
            value ? theme.colorScheme.primary : theme.colorScheme.onSurface,
        elevation: 0,
      ),
      onPressed: () => onChanged(!value),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    Widget modeChip(String label, TimelineRangeMode mode) {
      return ChoiceChip(
        label: Text(label),
        selected: _timelineMode == mode,
        onSelected: (_) => setState(() => _timelineMode = mode),
      );
    }

    final modeChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          modeChip('近24小时', TimelineRangeMode.last24h),
          const SizedBox(width: 8),
          modeChip('指定日期', TimelineRangeMode.day),
          const SizedBox(width: 8),
          modeChip('自定义范围', TimelineRangeMode.custom),
        ],
      ),
    );

    final searchField = SizedBox(
      height: 42,
      child: TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onChanged: (value) => setState(() => _timelineKeyword = value),
      ),
    );

    Widget rangeDisplay() {
      final theme = Theme.of(context);
      final borderColor = theme.colorScheme.outline.withOpacity(0.4);
      final boxDecoration = BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      );
      if (_timelineMode == TimelineRangeMode.day) {
        final today = DateTime.now();
        final todayDate = DateTime(today.year, today.month, today.day);
        final currentDate = DateTime(
          _timelineDate.year,
          _timelineDate.month,
          _timelineDate.day,
        );
        final canForward = currentDate.isBefore(todayDate);
        return Container(
          decoration: boxDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 38, height: 38),
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                  DateFormat('yyyy-MM-dd').format(_timelineDate),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 38, height: 38),
                onPressed: canForward
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
        );
      }
      if (_timelineMode == TimelineRangeMode.custom) {
        final custom = _currentCustomRange();
        return Container(
          decoration: boxDecoration,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rangeValue(
                custom.start,
                label: '起',
                onTap: () => _pickCustomStart(custom),
              ),
              const SizedBox(height: 4),
              _rangeValue(
                custom.end,
                label: '止',
                onTap: () => _pickCustomEnd(custom),
              ),
            ],
          ),
        );
      }
      return Container(
        decoration: boxDecoration,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '近24小时',
          style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );
    }

    return FutureBuilder<List<_TimelineGroupDisplay>>(
      future: _loadTimelineGroups(),
      builder: (context, snapshot) {
        final slivers = <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  modeChips,
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 1,
                        child: searchField,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: rangeDisplay(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
            sliver: SliverToBoxAdapter(
              child: _buildTimelineContent(snapshot),
            ),
          ),
        ];

        return CustomScrollView(
          primary: false,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: slivers,
        );
      },
    );
  }

  DateTimeRange _currentCustomRange() {
    final now = DateTime.now();
    return _timelineCustomRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 1)),
          end: now,
        );
  }

  Widget _rangeValue(
    DateTime time, {
    String? label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                '$label：',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 2),
            ],
            Text(
              DateFormat('MM-dd HH:mm').format(time),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomStart(DateTimeRange current) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current.start,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.start),
    );
    final time = pickedTime ?? TimeOfDay.fromDateTime(current.start);
    final updated = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      time.hour,
      time.minute,
    );
    if (!updated.isBefore(current.end)) {
      _showSnack('开始时间需早于结束时间');
      return;
    }
    setState(() {
      _timelineCustomRange = DateTimeRange(
        start: updated,
        end: current.end,
      );
    });
  }

  Future<void> _pickCustomEnd(DateTimeRange current) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current.end,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current.end),
    );
    final time = pickedTime ?? TimeOfDay.fromDateTime(current.end);
    final updated = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      time.hour,
      time.minute,
    );
    if (!updated.isAfter(current.start)) {
      _showSnack('结束时间需要晚于开始时间');
      return;
    }
    setState(() {
      _timelineCustomRange = DateTimeRange(
        start: current.start,
        end: updated,
      );
    });
  }

  Widget _buildTimelineContent(
    AsyncSnapshot<List<_TimelineGroupDisplay>> snapshot,
  ) {
    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: Text('加载失败: ${snapshot.error}')),
      );
    }
    if (!snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final groups = snapshot.data!;
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: Text('当前范围暂无记录')),
      );
    }
    final dayGroups = <DateTime, List<_TimelineGroupDisplay>>{};
    for (final group in groups) {
      dayGroups.putIfAbsent(group.day, () => []).add(group);
    }
    final days = dayGroups.keys.toList()..sort((a, b) => b.compareTo(a));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MM月 dd日，EEEE', 'zh_CN').format(day),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...([...dayGroups[day]!]..sort((a, b) => b.end.compareTo(a.end)))
                    .map((item) => _buildTimelineCard(item))
                    .toList(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTimelineCard(_TimelineGroupDisplay group) {
    final category = widget.controller.findCategory(group.categoryId);
    final color = _categoryColor(group.categoryId);
    final displayName = _groupMerge
        ? group.groupLabel
        : _categoryDisplayName(group.categoryId);
    final totalText = formatDurationText(group.totalDuration);

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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '总计 $totalText',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...group.segments.map(
              (segment) {
                final note = segment.note.trim();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatClock(segment.startTime)} - ${formatClock(segment.endTime)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  note,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatDurationText(segment.duration),
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
                );
              },
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('近24小时'),
                  selected: _range == StatsRange.last24h,
                  onSelected: (_) => setState(() => _range = StatsRange.last24h),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本日'),
                  selected: _range == StatsRange.today,
                  onSelected: (_) => setState(() => _range = StatsRange.today),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本周'),
                  selected: _range == StatsRange.week,
                  onSelected: (_) => setState(() => _range = StatsRange.week),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('本月'),
                  selected: _range == StatsRange.month,
                  onSelected: (_) => setState(() => _range = StatsRange.month),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('自定义'),
                  selected: _range == StatsRange.custom,
                  onSelected: (_) => setState(() => _range = StatsRange.custom),
                ),
              ],
            ),
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
              return LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth - 48;
                  final chartSize = math.max(
                    180.0,
                    math.min(230.0, available),
                  );
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        children: [
                          SimplePieChart(
                            slices: slices,
                            size: chartSize,
                            centerLabel: formatDurationText(
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
                                  ? '已选：${slices[activeIndex].label} · ${formatDurationText(Duration(seconds: slices[activeIndex].value.round()))} · ${(slices[activeIndex].value / totalSeconds * 100).toStringAsFixed(1)}%'
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
                                          borderRadius:
                                              BorderRadius.circular(4),
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
                                              '${formatDurationText(Duration(seconds: slice.value.round()))} · ${percent.toStringAsFixed(1)}%',
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
    final saved = await widget.controller.updateRecordWithSync(
      record: record,
      newStart: startTime,
      newEnd: endTime,
      note: resolvedNote,
      syncGroupNotes: true,
      onConflict: _handleOverlapConflict,
    );
    if (!saved) {
      return;
    }
    final updatedRecords = await widget.controller.loadDayRecords(
      record.startTime,
    );
    final hasOverlap = widget.controller.hasOverlap(updatedRecords);
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

  Future<OverlapUserDecision> _handleOverlapConflict(
    OverlapResolution resolution,
  ) {
    return showOverlapFixDialog(context, resolution);
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
