import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/time_models.dart';
import 'time_storage_service.dart';

class TimeTrackingController extends ChangeNotifier {
  TimeTrackingController(TimeStorageService storage)
      : _storage = storage,
        _session = CurrentSession.empty(deviceId: storage.deviceId);

  final TimeStorageService _storage;
  final Uuid _uuid = const Uuid();

  CurrentSession _session;
  List<CategoryModel> _categories = const [];
  AppSettings _settings = AppSettings.defaults();
  Timer? _ticker;
  bool _isInitialized = false;
  bool _handlingMidnight = false;

  bool get isInitialized => _isInitialized;
  bool get isRunning => _session.current != null;
  CurrentActivity? get currentActivity => _session.current;
  List<RecentContext> get recentContexts => List.unmodifiable(_session.recentContexts);
  List<CategoryModel> get categories => List.unmodifiable(_categories);
  AppSettings get settings => _settings;

  Duration get currentDuration {
    final current = _session.current;
    if (current == null) {
      return Duration.zero;
    }
    final now = DateTime.now();
    return now.difference(current.startTime);
  }

  Future<void> init() async {
    _settings = await _storage.loadSettings();
    _session = await _storage.loadSession();
    _categories = await _storage.loadCategories();
    _isInitialized = true;
    if (_session.current != null) {
      _startTicker();
      await _checkMidnightSplit();
    }
    notifyListeners();
  }

  CategoryModel? findCategory(String id) {
    for (final cat in _categories) {
      if (cat.id == id) {
        return cat;
      }
    }
    return null;
  }

  Future<void> setCategories(List<CategoryModel> categories) async {
    _categories = [...categories]..sort((a, b) => a.order.compareTo(b.order));
    await _storage.saveCategories(_categories);
    notifyListeners();
  }

  Future<void> addOrUpdateCategory(CategoryModel category) async {
    final existingIndex = _categories.indexWhere((element) => element.id == category.id);
    if (existingIndex == -1) {
      _categories = [..._categories, category];
    } else {
      final updated = [..._categories];
      updated[existingIndex] = category;
      _categories = updated;
    }
    await setCategories(_categories);
  }

  Future<void> reorderCategories(List<CategoryModel> ordered) async {
    final updated = <CategoryModel>[];
    for (var i = 0; i < ordered.length; i++) {
      updated.add(ordered[i].copyWith(order: i));
    }
    await setCategories(updated);
  }

  Future<void> toggleCategory(String id, bool enabled) async {
    final index = _categories.indexWhere((element) => element.id == id);
    if (index == -1) {
      return;
    }
    final updated = [..._categories];
    updated[index] = updated[index].copyWith(enabled: enabled);
    await setCategories(updated);
  }

  Future<void> startNewActivity({
    required String categoryId,
    required String note,
    bool allowSwitch = false,
  }) async {
    if (_session.current != null && !allowSwitch) {
      throw StateError('当前已在计时，请先停止或暂停');
    }
    if (_session.current != null) {
      await stopCurrentActivity(pushToRecent: true);
    }
    await _startActivity(
      categoryId: categoryId,
      note: note.isEmpty ? (findCategory(categoryId)?.name ?? '未命名任务') : note,
      groupId: _uuid.v4(),
    );
  }

  Future<void> switchToCategory({
    required String categoryId,
    required String note,
  }) {
    return startNewActivity(categoryId: categoryId, note: note, allowSwitch: true);
  }

  Future<void> resumeFromContext(RecentContext context) async {
    if (_session.current != null) {
      await stopCurrentActivity(pushToRecent: true);
    }
    await _startActivity(
      categoryId: context.categoryId,
      note: context.note,
      groupId: context.groupId,
    );
  }

  Future<ActivityRecord?> stopCurrentActivity({bool pushToRecent = true}) async {
    final current = _session.current;
    if (current == null) {
      return null;
    }
    await _checkMidnightSplit();
    final now = DateTime.now();
    final durationSeconds = max(1, now.difference(current.startTime).inSeconds);
    final record = ActivityRecord(
      id: _uuid.v4(),
      groupId: current.groupId,
      categoryId: current.categoryId,
      startTime: current.startTime,
      endTime: now,
      durationSeconds: durationSeconds,
      note: current.note,
    );

    await _storage.appendActivity(record);
    final updatedContexts = _buildRecentContexts(record, push: pushToRecent);
    final updatedSession = _session.copyWith(
      clearCurrent: true,
      lastUpdated: now.millisecondsSinceEpoch,
      recentContexts: updatedContexts,
    );
    _session = updatedSession;
    await _storage.writeSession(updatedSession);
    _stopTicker();
    notifyListeners();
    return record;
  }

  Future<void> removeRecentContext(String groupId) async {
    final updated = _session.recentContexts.where((element) => element.groupId != groupId).toList();
    _session = _session.copyWith(
      recentContexts: updated,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  Future<void> updateCurrentStartTime(DateTime newStart) async {
    final current = _session.current;
    if (current == null) {
      return;
    }
    _session = _session.copyWith(
      current: current.copyWith(startTime: newStart),
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  Future<ActivityRecord> manualAddRecord({
    required String categoryId,
    required String note,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (!startTime.isBefore(endTime)) {
      throw StateError('结束时间必须晚于开始时间');
    }
    if (!isSameDay(startTime, endTime)) {
      throw StateError('补录暂时只支持同一天');
    }
    final record = ActivityRecord(
      id: _uuid.v4(),
      groupId: _uuid.v4(),
      categoryId: categoryId,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: max(1, endTime.difference(startTime).inSeconds),
      note: note,
    );
    await _storage.appendActivity(record);
    final updatedContexts = _buildRecentContexts(record, push: true);
    _session = _session.copyWith(
      recentContexts: updatedContexts,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
    return record;
  }

  Future<List<ActivityRecord>> loadDayRecords(DateTime date) {
    return _storage.loadDayRecords(date);
  }

  Future<List<AggregatedTimelineGroup>> aggregateDay(DateTime date) async {
    final records = await loadDayRecords(date);
    final groups = <String, List<ActivityRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.groupId, () => []).add(record);
    }
    final aggregated = groups.entries.map((entry) {
      final sorted = [...entry.value]..sort((a, b) => a.startTime.compareTo(b.startTime));
      final first = sorted.first;
      final note = first.note.isNotEmpty ? first.note : (findCategory(first.categoryId)?.name ?? '');
      return AggregatedTimelineGroup(
        groupId: entry.key,
        categoryId: first.categoryId,
        note: note,
        segments: sorted,
      );
    }).toList();
    aggregated.sort((a, b) => a.start.compareTo(b.start));
    return aggregated;
  }

  bool hasOverlap(List<ActivityRecord> records, {String? ignoringId}) {
    if (records.length < 2) {
      return false;
    }
    final sorted = [...records]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];
      if (prev.id == ignoringId || curr.id == ignoringId) {
        continue;
      }
      if (curr.startTime.isBefore(prev.endTime)) {
        return true;
      }
    }
    return false;
  }

  Future<void> updateRecord({
    required DateTime date,
    required String recordId,
    required DateTime newStart,
    required DateTime newEnd,
    String? note,
  }) {
    return _storage.updateRecord(
      date: date,
      recordId: recordId,
      newStart: newStart,
      newEnd: newEnd,
      note: note,
    );
  }

  Future<void> deleteRecord(DateTime date, String recordId) {
    return _storage.deleteRecord(date, recordId);
  }

  Future<Map<String, Duration>> categoryDurations(DateTime start, DateTime end) async {
    final records = await _storage.loadRangeRecords(start, end);
    final map = <String, int>{};
    for (final record in records) {
      map.update(record.categoryId, (value) => value + record.durationSeconds, ifAbsent: () => record.durationSeconds);
    }
    return map.map((key, value) => MapEntry(key, Duration(seconds: value)));
  }

  Future<File> createBackup() async {
    final file = await _storage.createBackupZip();
    _settings = _settings.copyWith(lastBackupPath: file.path);
    await _storage.saveSettings(_settings);
    notifyListeners();
    return file;
  }

  Future<void> restoreBackup(String path) async {
    await _storage.restoreBackup(path);
    _session = await _storage.loadSession();
    _categories = await _storage.loadCategories();
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDarkMode) async {
    _settings = _settings.copyWith(darkMode: isDarkMode);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> _startActivity({
    required String categoryId,
    required String note,
    required String groupId,
    DateTime? startTime,
  }) async {
    final now = startTime ?? DateTime.now();
    final activity = CurrentActivity(
      tempId: _uuid.v4(),
      groupId: groupId,
      categoryId: categoryId,
      startTime: now,
      note: note,
    );
    _session = _session.copyWith(
      current: activity,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    _startTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkMidnightSplit();
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _checkMidnightSplit() async {
    if (_handlingMidnight) {
      return;
    }
    final current = _session.current;
    if (current == null) {
      return;
    }
    final now = DateTime.now();
    if (isSameDay(current.startTime, now)) {
      return;
    }

    _handlingMidnight = true;
    try {
      final endOfDay = DateTime(
        current.startTime.year,
        current.startTime.month,
        current.startTime.day,
        23,
        59,
        59,
        999,
      );
      final firstDuration = max(1, endOfDay.difference(current.startTime).inSeconds);
      final record = ActivityRecord(
        id: _uuid.v4(),
        groupId: current.groupId,
        categoryId: current.categoryId,
        startTime: current.startTime,
        endTime: endOfDay,
        durationSeconds: firstDuration,
        note: current.note,
        isCrossDaySplit: true,
      );
      await _storage.appendActivity(record);

      final nextStart = DateTime(now.year, now.month, now.day);
      final updatedCurrent = current.copyWith(startTime: nextStart);
      _session = _session.copyWith(
        current: updatedCurrent,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );
      await _storage.writeSession(_session);
    } finally {
      _handlingMidnight = false;
    }
    notifyListeners();
  }

  List<RecentContext> _buildRecentContexts(ActivityRecord record, {required bool push}) {
    if (!push) {
      return _session.recentContexts.where((element) => element.groupId != record.groupId).toList();
    }
    final now = DateTime.now();
    RecentContext? existed;
    for (final context in _session.recentContexts) {
      if (context.groupId == record.groupId) {
        existed = context;
        break;
      }
    }
    final merged = _session.recentContexts.where((element) => element.groupId != record.groupId).toList();
    final accumulated = (existed?.accumulatedSeconds ?? 0) + record.durationSeconds;
    merged.insert(
      0,
      RecentContext(
        groupId: record.groupId,
        categoryId: record.categoryId,
        note: record.note,
        lastActiveTime: now,
        accumulatedSeconds: accumulated,
      ),
    );
    return merged.take(8).toList();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
