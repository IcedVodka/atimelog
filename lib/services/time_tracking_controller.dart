import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/sync_models.dart';
import '../models/time_models.dart';
import 'sync_service.dart';
import 'time_storage_service.dart';

enum OverlapUserDecision { cancel, skipFix, applyFix }

typedef OverlapConflictHandler = Future<OverlapUserDecision> Function(
  OverlapResolution resolution,
);

class OverlapResolution {
  OverlapResolution({
    required this.day,
    required this.anchor,
    required this.anchorLabel,
    required this.naiveRecords,
    required this.fixedRecords,
    required this.hasOverlap,
    required this.changeSummaries,
  });

  final DateTime day;
  final ActivityRecord anchor;
  final String anchorLabel;
  final List<ActivityRecord> naiveRecords;
  final List<ActivityRecord> fixedRecords;
  final bool hasOverlap;
  final List<String> changeSummaries;

  bool get hasChanges {
    if (!hasOverlap) return false;
    if (naiveRecords.length != fixedRecords.length) return true;
    for (var i = 0; i < naiveRecords.length; i++) {
      final a = naiveRecords[i];
      final b = fixedRecords[i];
      final sameTime =
          a.startTime.isAtSameMomentAs(b.startTime) &&
          a.endTime.isAtSameMomentAs(b.endTime);
      final sameMeta =
          a.id == b.id &&
          a.groupId == b.groupId &&
          a.categoryId == b.categoryId &&
          a.isCrossDaySplit == b.isCrossDaySplit &&
          a.durationSeconds == b.durationSeconds &&
          a.note == b.note;
      if (!sameTime || !sameMeta) {
        return true;
      }
    }
    return false;
  }
}

class _ResolvedRecords {
  const _ResolvedRecords({
    required this.records,
    required this.summaries,
  });

  final List<ActivityRecord> records;
  final List<String> summaries;
}

class _OverlapSaveResult {
  const _OverlapSaveResult({
    required this.saved,
    required this.corrected,
    required this.hadConflict,
    required this.touchedGroupIds,
  });

  final bool saved;
  final bool corrected;
  final bool hadConflict;
  final Set<String> touchedGroupIds;
}

class TimeTrackingController extends ChangeNotifier {
  TimeTrackingController(TimeStorageService storage)
    : _storage = storage,
      _syncService = SyncService(storage),
      _session = CurrentSession.empty(deviceId: storage.deviceId);

  final TimeStorageService _storage;
  final Uuid _uuid = const Uuid();
  final SyncService _syncService;

  CurrentSession _session;
  List<CategoryModel> _categories = const [];
  AppSettings _settings = AppSettings.defaults();
  SyncConfig _syncConfig = SyncConfig.defaults();
  SyncStatus _syncStatus = SyncStatus.initial();
  Timer? _ticker;
  Timer? _autoSyncTimer;
  bool _isInitialized = false;
  bool _handlingMidnight = false;

  bool get isInitialized => _isInitialized;
  bool get isRunning => _session.current != null;
  CurrentActivity? get currentActivity => _session.current;
  List<RecentContext> get recentContexts =>
      List.unmodifiable(_session.recentContexts);
  List<CategoryModel> get categories =>
      List.unmodifiable(_categories.where((element) => !element.deleted));
  List<CategoryModel> get allCategories => List.unmodifiable(_categories);
  AppSettings get settings => _settings;
  OverlapFixMode get overlapFixMode => _settings.overlapFixMode;
  SyncConfig get syncConfig => _syncConfig;
  SyncStatus get syncStatus => _syncStatus;

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
    _syncConfig = await _storage.loadSyncConfig();
    _isInitialized = true;
    if (_session.current != null) {
      _startTicker();
      await _checkMidnightSplit();
    }
    _scheduleAutoSync();
    notifyListeners();
    if (_syncConfig.isConfigured) {
      unawaited(syncNow(reason: '启动自动同步'));
    }
  }

  CategoryModel? findCategory(String id) {
    for (final cat in _categories) {
      if (cat.id == id) {
        return cat;
      }
    }
    return null;
  }

  CategoryModel _requireActiveCategory(String id) {
    final category = findCategory(id);
    if (category == null) {
      throw StateError('分类不存在或已被删除');
    }
    if (category.deleted) {
      throw StateError('该分类已删除，请先在分类管理中恢复');
    }
    if (!category.enabled) {
      throw StateError('该分类已停用，请先启用');
    }
    return category;
  }

  Future<void> setCategories(List<CategoryModel> categories) async {
    _categories = [...categories]..sort((a, b) => a.order.compareTo(b.order));
    await _storage.saveCategories(_categories);
    notifyListeners();
  }

  Future<void> addOrUpdateCategory(CategoryModel category) async {
    final existingIndex = _categories.indexWhere(
      (element) => element.id == category.id,
    );
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
    if (_categories[index].deleted) {
      return;
    }
    final updated = [..._categories];
    updated[index] = updated[index].copyWith(enabled: enabled);
    await setCategories(updated);
  }

  Future<void> setCategoryDeletion(String id, bool deleted) async {
    final index = _categories.indexWhere((element) => element.id == id);
    if (index == -1) {
      return;
    }
    final updated = [..._categories];
    updated[index] = updated[index].copyWith(
      deleted: deleted,
      enabled: deleted ? false : updated[index].enabled,
    );
    await setCategories(updated);
  }

  Future<void> removeCategory(String id) async {
    final updated = _categories.where((element) => element.id != id).toList();
    await setCategories(updated);
  }

  Future<void> startNewActivity({
    required String categoryId,
    required String note,
    bool allowSwitch = false,
  }) async {
    _requireActiveCategory(categoryId);
    if (_session.current != null && !allowSwitch) {
      throw StateError('当前已在计时，请先停止或暂停');
    }
    if (_session.current != null) {
      await stopCurrentActivity(pushToRecent: true);
    }
    await _startActivity(
      categoryId: categoryId,
      note: _resolveNote(categoryId, note),
      groupId: _uuid.v4(),
    );
  }

  Future<void> switchToCategory({
    required String categoryId,
    required String note,
  }) {
    return startNewActivity(
      categoryId: categoryId,
      note: note,
      allowSwitch: true,
    );
  }

  Future<void> resumeFromContext(RecentContext context) async {
    _requireActiveCategory(context.categoryId);
    if (_session.current != null) {
      await stopCurrentActivity(pushToRecent: true);
    }
    await _startActivity(
      categoryId: context.categoryId,
      note: _resolveNote(context.categoryId, context.note),
      groupId: context.groupId,
    );
  }

  Future<ActivityRecord?> stopCurrentActivity({
    bool pushToRecent = true,
    OverlapConflictHandler? onConflict,
  }) async {
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

    final saveResult = await _saveWithOverlapPolicy(
      anchor: record,
      includeAnchorInSave: true,
      onConflict: onConflict,
    );
    if (!saveResult.saved) {
      return null;
    }
    final updatedContexts = _buildRecentContexts(record, push: pushToRecent);
    final updatedSession = _session.copyWith(
      clearCurrent: true,
      lastUpdated: now.millisecondsSinceEpoch,
      recentContexts: updatedContexts,
    );
    _session = updatedSession;
    await _storage.writeSession(updatedSession);
    if ((saveResult.corrected || saveResult.hadConflict) &&
        saveResult.touchedGroupIds.isNotEmpty) {
      await _refreshRecentContextsForGroups(saveResult.touchedGroupIds);
    }
    _stopTicker();
    notifyListeners();
    return record;
  }

  Future<void> removeRecentContext(String groupId) async {
    final updated = _session.recentContexts
        .where((element) => element.groupId != groupId)
        .toList();
    _session = _session.copyWith(
      recentContexts: updated,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  Future<bool> updateCurrentStartTime(
    DateTime newStart, {
    OverlapConflictHandler? onConflict,
  }) async {
    final current = _session.current;
    if (current == null) {
      return false;
    }
    if (newStart.isAfter(DateTime.now())) {
      throw StateError('开始时间不能晚于当前时间');
    }
    if (_settings.overlapFixMode != OverlapFixMode.none) {
      final anchorEnd = DateTime.now();
      final anchorRecord = ActivityRecord(
        id: current.tempId,
        groupId: current.groupId,
        categoryId: current.categoryId,
        startTime: newStart,
        endTime: anchorEnd,
        durationSeconds: _ensurePositiveSeconds(
          anchorEnd.difference(newStart).inSeconds,
        ),
        note: current.note,
      );
      final saveResult = await _saveWithOverlapPolicy(
        anchor: anchorRecord,
        includeAnchorInSave: false,
        onConflict: onConflict,
      );
      if (!saveResult.saved) {
        return false;
      }
      if ((saveResult.corrected || saveResult.hadConflict) &&
          saveResult.touchedGroupIds.isNotEmpty) {
        await _refreshRecentContextsForGroups(saveResult.touchedGroupIds);
      }
    }
    _session = _session.copyWith(
      current: current.copyWith(startTime: newStart),
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
    return true;
  }

  Future<void> updateCurrentNote(String note) async {
    final current = _session.current;
    if (current == null) {
      return;
    }
    final resolved = _resolveNote(current.categoryId, note);
    _session = _session.copyWith(
      current: CurrentActivity(
        tempId: current.tempId,
        groupId: current.groupId,
        categoryId: current.categoryId,
        startTime: current.startTime,
        note: resolved,
      ),
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  Future<void> updateRecentNote(String groupId, String note) async {
    final updated = <RecentContext>[];
    for (final ctx in _session.recentContexts) {
      if (ctx.groupId == groupId) {
        updated.add(
          RecentContext(
            groupId: ctx.groupId,
            categoryId: ctx.categoryId,
            note: _resolveNote(ctx.categoryId, note),
            lastActiveTime: ctx.lastActiveTime,
            accumulatedSeconds: ctx.accumulatedSeconds,
          ),
        );
      } else {
        updated.add(ctx);
      }
    }
    _session = _session.copyWith(
      recentContexts: updated,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  Future<ActivityRecord?> manualAddRecord({
    required String categoryId,
    required String note,
    required DateTime startTime,
    required DateTime endTime,
    OverlapConflictHandler? onConflict,
  }) async {
    _requireActiveCategory(categoryId);
    if (!startTime.isBefore(endTime)) {
      throw StateError('结束时间必须晚于开始时间');
    }
    final resolvedNote = _resolveNote(categoryId, note);
    final groupId = _uuid.v4();
    final segments = <ActivityRecord>[];
    var cursorStart = startTime;
    while (cursorStart.isBefore(endTime)) {
      final endOfDay = DateTime(
        cursorStart.year,
        cursorStart.month,
        cursorStart.day,
        23,
        59,
        59,
        999,
      );
      final segmentEnd = endTime.isBefore(endOfDay) ? endTime : endOfDay;
      final durationSeconds = max(
        1,
        segmentEnd.difference(cursorStart).inSeconds,
      );
      segments.add(
        ActivityRecord(
          id: _uuid.v4(),
          groupId: groupId,
          categoryId: categoryId,
          startTime: cursorStart,
          endTime: segmentEnd,
          durationSeconds: durationSeconds,
          note: resolvedNote,
          isCrossDaySplit: !isSameDay(startTime, endTime),
        ),
      );
      if (!segmentEnd.isBefore(endTime)) {
        break;
      }
      cursorStart = DateTime(
        cursorStart.year,
        cursorStart.month,
        cursorStart.day,
      ).add(const Duration(days: 1));
    }

    final touchedGroups = <String>{};
    var needsRefresh = false;
    for (final segment in segments) {
      final saveResult = await _saveWithOverlapPolicy(
        anchor: segment,
        includeAnchorInSave: true,
        onConflict: onConflict,
      );
      if (!saveResult.saved) {
        return null;
      }
      touchedGroups.addAll(saveResult.touchedGroupIds);
      needsRefresh = needsRefresh || saveResult.corrected || saveResult.hadConflict;
    }
    final mergedRecord = ActivityRecord(
      id: segments.first.id,
      groupId: groupId,
      categoryId: categoryId,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: segments.fold(0, (prev, e) => prev + e.durationSeconds),
      note: resolvedNote,
    );

    final updatedContexts = _buildRecentContexts(mergedRecord, push: true);
    _session = _session.copyWith(
      recentContexts: updatedContexts,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    if (needsRefresh && touchedGroups.isNotEmpty) {
      await _refreshRecentContextsForGroups(touchedGroups);
    }
    notifyListeners();
    return mergedRecord;
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
      final sorted = [...entry.value]
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final first = sorted.first;
      final note = first.note.isNotEmpty
          ? first.note
          : (findCategory(first.categoryId)?.name ?? '');
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

  Future<bool> updateRecordWithSync({
    required ActivityRecord record,
    required DateTime newStart,
    required DateTime newEnd,
    required String note,
    bool syncGroupNotes = false,
    OverlapConflictHandler? onConflict,
  }) async {
    final resolved = _resolveNote(record.categoryId, note);
    final updated = record.copyWith(
      startTime: newStart,
      endTime: newEnd,
      durationSeconds: _ensurePositiveSeconds(
        newEnd.difference(newStart).inSeconds,
      ),
      note: resolved,
    );
    final saveResult = await _saveWithOverlapPolicy(
      anchor: updated,
      replaceId: record.id,
      includeAnchorInSave: true,
      onConflict: onConflict,
    );
    if (!saveResult.saved) {
      return false;
    }
    if (syncGroupNotes) {
      await _syncGroupNotes(updated, resolved);
    }
    if (saveResult.touchedGroupIds.isNotEmpty) {
      await _refreshRecentContextsForGroups(saveResult.touchedGroupIds);
    }
    return true;
  }

  Future<void> deleteRecord(DateTime date, String recordId) {
    return _storage.deleteRecord(date, recordId);
  }

  Future<List<ActivityRecord>> loadRangeRecords(DateTime start, DateTime end) {
    return _storage.loadRangeRecords(start, end);
  }

  Future<ActivityRecord?> findLatestRecordForGroup(
    String groupId, {
    int lookBackDays = 60,
  }) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: lookBackDays));
    final records = await _storage.loadRangeRecords(start, end);
    ActivityRecord? latest;
    for (final record in records) {
      if (record.groupId == groupId) {
        if (latest == null || record.startTime.isAfter(latest.startTime)) {
          latest = record;
        }
      }
    }
    return latest;
  }

  Future<Map<String, Duration>> categoryDurations(
    DateTime start,
    DateTime end,
  ) async {
    final records = await _storage.loadRangeRecords(start, end);
    final map = <String, int>{};
    for (final record in records) {
      // 仅统计与查询时间窗有交集的片段，按交集时长计入。
      if (!record.endTime.isAfter(start) || !record.startTime.isBefore(end)) {
        continue;
      }
      final clippedStart = record.startTime.isBefore(start)
          ? start
          : record.startTime;
      final clippedEnd = record.endTime.isAfter(end) ? end : record.endTime;
      final seconds = clippedEnd.difference(clippedStart).inSeconds;
      if (seconds <= 0) continue;
      map.update(
        record.categoryId,
        (value) => value + seconds,
        ifAbsent: () => seconds,
      );
    }
    return map.map((key, value) => MapEntry(key, Duration(seconds: value)));
  }

  Future<String> suggestedBackupPath() async {
    final base = await _storage.baseDir();
    final name =
        'atimelog_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    return p.join(base.parent.path, name);
  }

  Future<File> createBackup({String? targetPath}) async {
    final file = await _storage.createBackupZip(targetPath: targetPath);
    _settings = _settings.copyWith(lastBackupPath: file.path);
    notifyListeners();
    return file;
  }

  Future<void> restoreBackup(String path) async {
    await _storage.restoreBackup(path);
    _session = await _storage.loadSession();
    _categories = await _storage.loadCategories();
    _settings = (await _storage.loadSettings()).copyWith(
      lastRestorePath: path,
      lastBackupPath: _settings.lastBackupPath,
    );
    if (_session.current != null) {
      _startTicker();
      await _checkMidnightSplit();
    }
    notifyListeners();
  }

  Future<void> updateOverlapFixMode(OverlapFixMode mode) async {
    _settings = _settings.copyWith(overlapFixMode: mode);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDarkMode) async {
    _settings = _settings.copyWith(darkMode: isDarkMode);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    if (!_syncConfig.shouldAutoSync) {
      return;
    }
    final minutes =
        _syncConfig.autoIntervalMinutes.clamp(1, 1440).toInt();
    final interval = Duration(minutes: minutes);
    _autoSyncTimer = Timer.periodic(interval, (_) {
      if (_syncStatus.syncing || !_syncConfig.enabled) {
        return;
      }
      unawaited(syncNow(reason: '自动周期同步'));
    });
  }

  Future<void> updateSyncConfig(SyncConfig config,
      {bool triggerSync = false}) async {
    _syncConfig = config;
    await _storage.saveSyncConfig(config);
    _scheduleAutoSync();
    notifyListeners();
    if (triggerSync) {
      await syncNow(reason: '配置更新后同步', manual: true);
    }
  }

  Future<void> syncNow({bool manual = false, String? reason}) async {
    if (_syncStatus.syncing) {
      return;
    }
    if (!_syncConfig.isConfigured) {
      _syncStatus = _syncStatus.copyWith(
        lastSyncTime: DateTime.now(),
        lastSyncSucceeded: false,
        lastSyncMessage: '未完成 WebDAV 配置',
        syncing: false,
        clearProgress: true,
      );
      notifyListeners();
      return;
    }
    if (!_syncConfig.enabled && !manual) {
      _syncStatus = _syncStatus.copyWith(
        lastSyncTime: DateTime.now(),
        lastSyncSucceeded: false,
        lastSyncMessage: '自动同步已关闭',
        syncing: false,
        clearProgress: true,
      );
      notifyListeners();
      return;
    }
    _syncStatus = _syncStatus.copyWith(
      syncing: true,
      lastSyncSucceeded: null,
      lastDuration: null,
      lastSyncMessage: reason ?? (manual ? '手动同步中' : '自动同步中'),
      progress: SyncProgress(
        stage: reason ?? (manual ? '手动同步中' : '自动同步中'),
        detail: '准备同步...',
      ),
    );
    notifyListeners();
    final result = await _syncService.syncAll(
      _syncConfig,
      onProgress: _onSyncProgress,
    );
    _syncStatus = _syncStatus.copyWith(
      syncing: false,
      lastSyncTime: DateTime.now(),
      lastSyncSucceeded: result.success,
      lastSyncMessage: result.message,
      lastDuration: result.duration,
      lastUploadCount: result.uploaded,
      lastDownloadCount: result.downloaded,
      clearProgress: true,
    );
    notifyListeners();
  }

  Future<void> verifySyncConnection() async {
    if (_syncStatus.verifying) return;
    _syncStatus = _syncStatus.copyWith(verifying: true, lastSyncMessage: '验证中');
    notifyListeners();
    try {
      await _syncService.verifyConnection(_syncConfig);
      _syncStatus = _syncStatus.copyWith(
        verifying: false,
        lastSyncSucceeded: true,
        lastSyncTime: DateTime.now(),
        lastSyncMessage: '连接正常',
      );
    } catch (error) {
      _syncStatus = _syncStatus.copyWith(
        verifying: false,
        lastSyncSucceeded: false,
        lastSyncTime: DateTime.now(),
        lastSyncMessage: error.toString(),
      );
    }
    notifyListeners();
  }

  void _onSyncProgress(SyncProgress progress) {
    _syncStatus = _syncStatus.copyWith(
      syncing: true,
      progress: progress,
      lastSyncMessage: progress.stage,
      lastUploadCount: progress.uploaded,
      lastDownloadCount: progress.downloaded,
    );
    notifyListeners();
  }

  Future<void> _startActivity({
    required String categoryId,
    required String note,
    required String groupId,
    DateTime? startTime,
  }) async {
    final now = startTime ?? DateTime.now();
    final resolvedNote = _resolveNote(categoryId, note);
    final activity = CurrentActivity(
      tempId: _uuid.v4(),
      groupId: groupId,
      categoryId: categoryId,
      startTime: now,
      note: resolvedNote,
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
      final firstDuration = max(
        1,
        endOfDay.difference(current.startTime).inSeconds,
      );
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

  List<RecentContext> _buildRecentContexts(
    ActivityRecord record, {
    required bool push,
  }) {
    if (!push) {
      return _session.recentContexts
          .where((element) => element.groupId != record.groupId)
          .toList();
    }
    final now = DateTime.now();
    RecentContext? existed;
    for (final context in _session.recentContexts) {
      if (context.groupId == record.groupId) {
        existed = context;
        break;
      }
    }
    final merged = _session.recentContexts
        .where((element) => element.groupId != record.groupId)
        .toList();
    final accumulated =
        (existed?.accumulatedSeconds ?? 0) + record.durationSeconds;
    merged.insert(
      0,
      RecentContext(
        groupId: record.groupId,
        categoryId: record.categoryId,
        note: _resolveNote(record.categoryId, record.note),
        lastActiveTime: now,
        accumulatedSeconds: accumulated,
      ),
    );
    return merged.take(8).toList();
  }

  String _resolveNote(String categoryId, String note) {
    final trimmed = note.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final category = findCategory(categoryId);
    if (category != null) {
      return category.name;
    }
    final fallback = categoryId.trim().isEmpty ? '未命名' : categoryId.trim();
    return '其他.$fallback';
  }

  Future<void> _syncGroupNotes(ActivityRecord origin, String note) async {
    final resolved = _resolveNote(origin.categoryId, note);
    final rangeStart = origin.startTime.subtract(const Duration(days: 2));
    final rangeEnd = origin.endTime.add(const Duration(days: 2));
    final records = await _storage.loadRangeRecords(rangeStart, rangeEnd);
    for (final item in records) {
      if (item.groupId != origin.groupId || item.id == origin.id) {
        continue;
      }
      final closeToOrigin =
          item.isCrossDaySplit ||
          origin.isCrossDaySplit ||
          isSameDay(item.startTime, origin.startTime) ||
          item.startTime.difference(origin.startTime).inHours.abs() <= 30;
      if (!closeToOrigin) {
        continue;
      }
      if (item.note == resolved) {
        continue;
      }
      await _storage.updateRecord(
        date: item.startTime,
        recordId: item.id,
        newStart: item.startTime,
        newEnd: item.endTime,
        note: resolved,
      );
    }
  }

  Future<OverlapResolution> _buildOverlapResolution({
    required ActivityRecord anchor,
    String? replaceId,
  }) async {
    final day = DateTime(anchor.startTime.year, anchor.startTime.month, anchor.startTime.day);
    final existing = await _storage.loadDayRecords(day);
    final base = replaceId == null
        ? [...existing]
        : existing.where((element) => element.id != replaceId).toList();
    final naive = [...base, anchor]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final hasOverlap = base.any((element) => _isOverlap(anchor, element));
    if (!hasOverlap) {
      return OverlapResolution(
        day: day,
        anchor: anchor,
        anchorLabel: _recordLabel(anchor),
        naiveRecords: naive,
        fixedRecords: naive,
        hasOverlap: false,
        changeSummaries: const [],
      );
    }
    final resolved = _resolveAnchorConflicts(anchor, base);
    return OverlapResolution(
      day: day,
      anchor: anchor,
      anchorLabel: _recordLabel(anchor),
      naiveRecords: naive,
      fixedRecords: resolved.records,
      hasOverlap: true,
      changeSummaries: resolved.summaries,
    );
  }

  _ResolvedRecords _resolveAnchorConflicts(
    ActivityRecord anchor,
    List<ActivityRecord> records,
  ) {
    final resolved = <ActivityRecord>[];
    final summaries = <String>[];
    for (final record in records) {
      if (!_isOverlap(anchor, record)) {
        resolved.add(record);
        continue;
      }
      final segments = <ActivityRecord>[];
      if (record.startTime.isBefore(anchor.startTime)) {
        final end = anchor.startTime;
        if (end.isAfter(record.startTime)) {
          segments.add(
            record.copyWith(
              endTime: end,
              durationSeconds: _ensurePositiveSeconds(
                end.difference(record.startTime).inSeconds,
              ),
            ),
          );
        }
      }
      if (record.endTime.isAfter(anchor.endTime)) {
        final start = anchor.endTime;
        if (record.endTime.isAfter(start)) {
          segments.add(
            ActivityRecord(
              id: _uuid.v4(),
              groupId: record.groupId,
              categoryId: record.categoryId,
              startTime: start,
              endTime: record.endTime,
              durationSeconds: _ensurePositiveSeconds(
                record.endTime.difference(start).inSeconds,
              ),
              note: record.note,
              isCrossDaySplit: record.isCrossDaySplit,
            ),
          );
        }
      }
      if (segments.isEmpty) {
        summaries.add(
          '${_recordLabel(record)} ${_formatRange(record.startTime, record.endTime)} '
          '被 ${_formatRange(anchor.startTime, anchor.endTime)} 覆盖，已移除',
        );
        continue;
      }
      summaries.add(
        '${_recordLabel(record)} ${_formatRange(record.startTime, record.endTime)} '
        '→ ${segments.map((e) => _formatRange(e.startTime, e.endTime)).join(' / ')}',
      );
      resolved.addAll(segments);
    }
    resolved.add(anchor);
    resolved.sort((a, b) => a.startTime.compareTo(b.startTime));
    return _ResolvedRecords(records: resolved, summaries: summaries);
  }

  Future<_OverlapSaveResult> _saveWithOverlapPolicy({
    required ActivityRecord anchor,
    String? replaceId,
    required bool includeAnchorInSave,
    OverlapConflictHandler? onConflict,
  }) async {
    final resolution = await _buildOverlapResolution(
      anchor: anchor,
      replaceId: replaceId,
    );
    final touchedGroups = <String>{
      ...resolution.naiveRecords.map((e) => e.groupId),
      ...resolution.fixedRecords.map((e) => e.groupId),
    };
    final mode = _settings.overlapFixMode;
    List<ActivityRecord> selected = resolution.naiveRecords;
    bool corrected = false;

    if (resolution.hasOverlap) {
      switch (mode) {
        case OverlapFixMode.none:
          break;
        case OverlapFixMode.auto:
          selected = resolution.fixedRecords;
          corrected = resolution.hasChanges;
          break;
        case OverlapFixMode.ask:
          final handler = onConflict;
          if (handler != null) {
            final decision = await handler(resolution);
            if (decision == OverlapUserDecision.cancel) {
              return _OverlapSaveResult(
                saved: false,
                corrected: false,
                hadConflict: true,
                touchedGroupIds: touchedGroups,
              );
            }
            if (decision == OverlapUserDecision.applyFix) {
              selected = resolution.fixedRecords;
              corrected = resolution.hasChanges;
            } else {
              selected = resolution.naiveRecords;
            }
          } else {
            selected = resolution.fixedRecords;
            corrected = resolution.hasChanges;
          }
          break;
      }
    }

    if (!includeAnchorInSave) {
      selected = selected.where((element) => element.id != anchor.id).toList();
    }
    selected.sort((a, b) => a.startTime.compareTo(b.startTime));
    await _storage.saveDayRecords(resolution.day, selected);
    return _OverlapSaveResult(
      saved: true,
      corrected: corrected,
      hadConflict: resolution.hasOverlap,
      touchedGroupIds: touchedGroups,
    );
  }

  int _ensurePositiveSeconds(int raw) {
    return raw <= 0 ? 1 : raw;
  }

  bool _isOverlap(ActivityRecord a, ActivityRecord b) {
    return a.startTime.isBefore(b.endTime) && b.startTime.isBefore(a.endTime);
  }

  String _recordLabel(ActivityRecord record) {
    final category = findCategory(record.categoryId);
    final name = category?.name ?? record.categoryId;
    final note = record.note.trim();
    if (note.isEmpty || note == name) {
      return name;
    }
    return '$name · $note';
  }

  String _formatRange(DateTime start, DateTime end) {
    final formatter = DateFormat('HH:mm');
    return '${formatter.format(start)}-${formatter.format(end)}';
  }

  Future<void> _refreshRecentContextsForGroups(Set<String> groupIds) async {
    final targets = groupIds
        .where(
          (id) => _session.recentContexts.any(
            (ctx) => ctx.groupId == id,
          ),
        )
        .toSet();
    if (targets.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final records = await _storage.loadRangeRecords(
      now.subtract(const Duration(days: 365)),
      now,
    );
    final updated = <RecentContext>[];
    for (final ctx in _session.recentContexts) {
      if (!targets.contains(ctx.groupId)) {
        updated.add(ctx);
        continue;
      }
      final recalculated = _recalculateRecentContext(ctx.groupId, records);
      if (recalculated != null) {
        updated.add(recalculated);
      }
    }
    updated.sort(
      (a, b) => b.lastActiveTime.compareTo(a.lastActiveTime),
    );
    _session = _session.copyWith(
      recentContexts: updated.take(8).toList(),
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    notifyListeners();
  }

  RecentContext? _recalculateRecentContext(
    String groupId,
    List<ActivityRecord> allRecords,
  ) {
    final related = allRecords
        .where((record) => record.groupId == groupId)
        .toList()
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    if (related.isEmpty) {
      return null;
    }
    final latest = related.first;
    final totalSeconds = related.fold<int>(
      0,
      (prev, e) => prev + e.durationSeconds,
    );
    final resolvedNote = _resolveNote(latest.categoryId, latest.note);
    return RecentContext(
      groupId: latest.groupId,
      categoryId: latest.categoryId,
      note: resolvedNote,
      lastActiveTime: latest.endTime,
      accumulatedSeconds: totalSeconds,
    );
  }

  @override
  void dispose() {
    _stopTicker();
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
