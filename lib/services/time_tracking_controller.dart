import 'dart:async';

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
  Timer? _ticker;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  bool get isRunning => _session.current != null;
  CurrentActivity? get currentActivity => _session.current;
  List<RecentContext> get recentContexts => List.unmodifiable(_session.recentContexts);
  String get currentNote => _session.current?.note ?? '';

  Duration get currentDuration {
    final current = _session.current;
    if (current == null) {
      return Duration.zero;
    }
    final now = DateTime.now();
    return now.difference(current.startTime);
  }

  Future<void> init() async {
    _session = await _storage.loadSession();
    _isInitialized = true;
    if (_session.current != null) {
      _startTicker();
    }
    notifyListeners();
  }

  Future<void> startNewActivity({
    required String categoryId,
    required String note,
  }) async {
    if (_session.current != null) {
      throw StateError('当前已在计时，请先停止');
    }

    final now = DateTime.now();
    final activity = CurrentActivity(
      tempId: _uuid.v4(),
      groupId: _uuid.v4(),
      categoryId: categoryId,
      startTime: now,
      note: note,
    );

    _session = _session.copyWith(
      lastUpdated: now.millisecondsSinceEpoch,
      current: activity,
    );
    await _storage.writeSession(_session);
    _startTicker();
    notifyListeners();
  }

  Future<void> resumeFromContext(RecentContext context) async {
    if (_session.current != null) {
      await stopCurrentActivity();
    }
    final now = DateTime.now();
    final activity = CurrentActivity(
      tempId: _uuid.v4(),
      groupId: context.groupId,
      categoryId: context.categoryId,
      startTime: now,
      note: context.note,
    );

    _session = _session.copyWith(
      current: activity,
      lastUpdated: now.millisecondsSinceEpoch,
    );
    await _storage.writeSession(_session);
    _startTicker();
    notifyListeners();
  }

  Future<void> stopCurrentActivity() async {
    final current = _session.current;
    if (current == null) {
      return;
    }
    final now = DateTime.now();
    final durationSeconds = now.difference(current.startTime).inSeconds;
    final record = ActivityRecord(
      id: _uuid.v4(),
      groupId: current.groupId,
      categoryId: current.categoryId,
      startTime: current.startTime,
      endTime: now,
      durationSeconds: durationSeconds <= 0 ? 1 : durationSeconds,
      note: current.note,
    );

    await _storage.appendActivity(record);
    final updatedContexts = _buildRecentContexts(record);
    final updatedSession = _session.copyWith(
      clearCurrent: true,
      lastUpdated: now.millisecondsSinceEpoch,
      recentContexts: updatedContexts,
    );
    _session = updatedSession;
    await _storage.writeSession(updatedSession);
    _stopTicker();
    notifyListeners();
  }

  List<RecentContext> _buildRecentContexts(ActivityRecord record) {
    final now = DateTime.now();
    final newContext = RecentContext(
      groupId: record.groupId,
      categoryId: record.categoryId,
      note: record.note,
      lastActiveTime: now,
    );

    final filtered = _session.recentContexts
        .where((element) => element.groupId != record.groupId)
        .toList();
    return <RecentContext>[newContext, ...filtered].take(5).toList();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
