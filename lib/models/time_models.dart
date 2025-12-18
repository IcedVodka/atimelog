import 'dart:convert';

import 'package:flutter/material.dart';

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
    this.accumulatedSeconds = 0,
  });

  final String groupId;
  final String categoryId;
  final String note;
  final DateTime lastActiveTime;
  // 累积时长，便于在 UI 上展示已归档的时间。
  final int accumulatedSeconds;

  Map<String, dynamic> toJson() {
    return {
      'groupId': groupId,
      'categoryId': categoryId,
      'note': note,
      'lastActiveTime': lastActiveTime.millisecondsSinceEpoch,
      'accumulatedSeconds': accumulatedSeconds,
    };
  }

  factory RecentContext.fromJson(Map<String, dynamic> json) {
    return RecentContext(
      groupId: json['groupId'] as String,
      categoryId: json['categoryId'] as String,
      note: json['note'] as String? ?? '',
      lastActiveTime: DateTime.fromMillisecondsSinceEpoch(
        json['lastActiveTime'] as int,
      ),
      accumulatedSeconds: json['accumulatedSeconds'] as int? ?? 0,
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

  factory ActivityRecord.fromJson(Map<String, dynamic> json) {
    final startRaw = json['startTime'];
    final endRaw = json['endTime'];
    DateTime parseTime(dynamic raw) {
      if (raw is String) {
        return DateTime.parse(raw);
      }
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      throw ArgumentError('无法解析时间: $raw');
    }

    final start = parseTime(startRaw);
    final end = parseTime(endRaw);
    final durationSeconds =
        json['duration'] as int? ??
        json['durationSeconds'] as int? ??
        end.difference(start).inSeconds;
    return ActivityRecord(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      startTime: start,
      endTime: end,
      durationSeconds: durationSeconds,
      note: json['note'] as String? ?? '',
      isCrossDaySplit: json['isCrossDaySplit'] as bool? ?? false,
    );
  }

  ActivityRecord copyWith({
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    String? note,
    bool? isCrossDaySplit,
  }) {
    return ActivityRecord(
      id: id,
      groupId: groupId,
      categoryId: categoryId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      note: note ?? this.note,
      isCrossDaySplit: isCrossDaySplit ?? this.isCrossDaySplit,
    );
  }

  Duration get duration => Duration(seconds: durationSeconds);
}

/// 分类配置。
class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorHex,
    required this.order,
    this.enabled = true,
    this.deleted = false,
    this.group = '',
  });

  final String id;
  final String name;
  final int iconCode;
  final String colorHex;
  final int order;
  final bool enabled;
  final bool deleted;
  final String group;

  IconData get iconData => IconData(iconCode, fontFamily: 'MaterialIcons');
  Color get color => colorFromHex(colorHex);

  CategoryModel copyWith({
    String? name,
    int? iconCode,
    String? colorHex,
    int? order,
    bool? enabled,
    bool? deleted,
    String? group,
  }) {
    return CategoryModel(
      id: id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      colorHex: colorHex ?? this.colorHex,
      order: order ?? this.order,
      enabled: enabled ?? this.enabled,
      deleted: deleted ?? this.deleted,
      group: group ?? this.group,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconCode': iconCode,
      'colorHex': colorHex,
      'order': order,
      'enabled': enabled,
      'group': group,
    };
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      iconCode: json['iconCode'] as int? ?? Icons.category.codePoint,
      colorHex: json['colorHex'] as String? ?? '#2196F3',
      order: json['order'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      deleted: json['deleted'] as bool? ?? false,
      group: json['group'] as String? ?? '',
    );
  }
}

String prettyJson(Map<String, dynamic> payload) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(payload);
}

enum OverlapFixMode {
  none,
  ask,
  auto,
}

OverlapFixMode parseOverlapFixMode(String? raw) {
  switch (raw) {
    case 'none':
      return OverlapFixMode.none;
    case 'auto':
      return OverlapFixMode.auto;
    case 'ask':
    default:
      return OverlapFixMode.ask;
  }
}

/// 应用基础设置。
class AppSettings {
  const AppSettings({
    required this.darkMode,
    this.lastBackupPath,
    this.lastRestorePath,
    this.overlapFixMode = OverlapFixMode.ask,
  });

  final bool darkMode;
  final String? lastBackupPath;
  final String? lastRestorePath;
  final OverlapFixMode overlapFixMode;

  AppSettings copyWith({
    bool? darkMode,
    String? lastBackupPath,
    String? lastRestorePath,
    OverlapFixMode? overlapFixMode,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      lastBackupPath: lastBackupPath ?? this.lastBackupPath,
      lastRestorePath: lastRestorePath ?? this.lastRestorePath,
      overlapFixMode: overlapFixMode ?? this.overlapFixMode,
    );
  }

  Map<String, dynamic> toJson() {
    // 仅保留主题配置，备份/恢复路径不再持久化。
    return {
      'darkMode': darkMode,
      'overlapFixMode': overlapFixMode.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      darkMode: json['darkMode'] as bool? ?? false,
      lastBackupPath: json['lastBackupPath'] as String?,
      lastRestorePath: json['lastRestorePath'] as String?,
      overlapFixMode: parseOverlapFixMode(
        json['overlapFixMode'] as String?,
      ),
    );
  }

  static AppSettings defaults() {
    return const AppSettings(
      darkMode: false,
      overlapFixMode: OverlapFixMode.ask,
    );
  }
}

/// 同一天内的 group 聚合。
class AggregatedTimelineGroup {
  const AggregatedTimelineGroup({
    required this.groupId,
    required this.categoryId,
    required this.note,
    required this.segments,
  });

  final String groupId;
  final String categoryId;
  final String note;
  final List<ActivityRecord> segments;

  Duration get totalDuration {
    final seconds = segments.fold<int>(
      0,
      (prev, e) => prev + e.durationSeconds,
    );
    return Duration(seconds: seconds);
  }

  DateTime get start =>
      segments.isEmpty ? DateTime.now() : segments.first.startTime;
  DateTime get end => segments.isEmpty ? DateTime.now() : segments.last.endTime;
}

Color colorFromHex(String hexString) {
  var hex = hexString.replaceFirst('#', '');
  if (hex.length == 6) {
    hex = 'FF$hex';
  }
  final intVal = int.tryParse(hex, radix: 16) ?? 0xFF2196F3;
  return Color(intVal);
}

String colorToHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
