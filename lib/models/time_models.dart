import 'dart:convert';

/// 表示当前正在计时的活动。
class CurrentActivity {
  const CurrentActivity({
    required this.tempId,
    required this.groupId,
    required this.categoryId,
    required this.startTime,
    required this.note,
  });

  final String tempId;
  final String groupId;
  final String categoryId;
  final DateTime startTime;
  final String note;

  Map<String, dynamic> toJson() {
    return {
      'tempId': tempId,
      'groupId': groupId,
      'categoryId': categoryId,
      'startTime': startTime.millisecondsSinceEpoch,
      'note': note,
    };
  }

  factory CurrentActivity.fromJson(Map<String, dynamic> json) {
    return CurrentActivity(
      tempId: json['tempId'] as String,
      groupId: json['groupId'] as String,
      categoryId: json['categoryId'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int),
      note: json['note'] as String? ?? '',
    );
  }

  CurrentActivity copyWith({DateTime? startTime}) {
    return CurrentActivity(
      tempId: tempId,
      groupId: groupId,
      categoryId: categoryId,
      startTime: startTime ?? this.startTime,
      note: note,
    );
  }
}

/// 最近上下文，便于快速续记。
class RecentContext {
  const RecentContext({
    required this.groupId,
    required this.categoryId,
    required this.note,
    required this.lastActiveTime,
  });

  final String groupId;
  final String categoryId;
  final String note;
  final DateTime lastActiveTime;

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'categoryId': categoryId,
      'note': note,
      'lastActiveTime': lastActiveTime.millisecondsSinceEpoch,
    };
  }

  factory RecentContext.fromJson(Map<String, dynamic> json) {
    return RecentContext(
      groupId: json['groupId'] as String,
      categoryId: json['categoryId'] as String,
      note: json['note'] as String? ?? '',
      lastActiveTime: DateTime.fromMillisecondsSinceEpoch(json['lastActiveTime'] as int),
    );
  }
}

/// 热状态文件模型，记录当前任务和最近上下文。
class CurrentSession {
  const CurrentSession({
    required this.deviceId,
    required this.lastUpdated,
    required this.current,
    required this.recentContexts,
  });

  final String deviceId;
  final int lastUpdated;
  final CurrentActivity? current;
  final List<RecentContext> recentContexts;

  CurrentSession copyWith({
    String? deviceId,
    int? lastUpdated,
    CurrentActivity? current,
    bool clearCurrent = false,
    List<RecentContext>? recentContexts,
  }) {
    return CurrentSession(
      deviceId: deviceId ?? this.deviceId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      current: clearCurrent ? null : (current ?? this.current),
      recentContexts: recentContexts ?? this.recentContexts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'lastUpdated': lastUpdated,
      'current': current?.toJson(),
      'recentContexts': recentContexts.map((e) => e.toJson()).toList(),
    };
  }

  factory CurrentSession.fromJson(Map<String, dynamic> json) {
    final current = json['current'];
    final contexts = json['recentContexts'] as List<dynamic>?;
    return CurrentSession(
      deviceId: json['deviceId'] as String? ?? 'demo-device',
      lastUpdated: json['lastUpdated'] as int? ?? 0,
      current: current == null
          ? null
          : CurrentActivity.fromJson(current as Map<String, dynamic>),
      recentContexts: contexts == null
          ? const []
          : contexts
              .map((e) => RecentContext.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  static CurrentSession empty({required String deviceId}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return CurrentSession(
      deviceId: deviceId,
      lastUpdated: now,
      current: null,
      recentContexts: const [],
    );
  }
}

/// 历史归档活动片段。
class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.groupId,
    required this.categoryId,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.note,
    this.isCrossDaySplit = false,
  });

  final String id;
  final String groupId;
  final String categoryId;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;
  final String note;
  final bool isCrossDaySplit;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'categoryId': categoryId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'duration': durationSeconds,
      'note': note,
      'isCrossDaySplit': isCrossDaySplit,
    };
  }
}

String prettyJson(Map<String, dynamic> payload) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(payload);
}
