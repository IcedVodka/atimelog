import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/time_models.dart';

/// 负责所有本地 JSON 文件读写逻辑。
class TimeStorageService {
  TimeStorageService({this.deviceId = 'demo-device'});

  final String deviceId;
  Directory? _baseDirCache;

  Future<Directory> _ensureBaseDir() async {
    if (_baseDirCache != null) {
      return _baseDirCache!;
    }

    late final Directory target;
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      // 桌面端直接放在当前工程目录中，方便调试查看。
      target = Directory(p.join(Directory.current.path, 'atimelog_data'));
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      target = Directory(p.join(docDir.path, 'atimelog_data'));
    }

    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    _baseDirCache = target;
    return target;
  }

  Future<Directory> baseDir() => _ensureBaseDir();

  Future<Directory> _configDir() async {
    final base = await _ensureBaseDir();
    final config = Directory(p.join(base.path, 'config'));
    if (!await config.exists()) {
      await config.create(recursive: true);
    }
    return config;
  }

  Future<File> _currentSessionFile() async {
    final base = await _ensureBaseDir();
    final localDir = Directory(p.join(base.path, 'local'));
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }
    return File(p.join(localDir.path, 'current_session.json'));
  }

  Future<CurrentSession> loadSession() async {
    final file = await _currentSessionFile();
    if (!await file.exists()) {
      final session = CurrentSession.empty(deviceId: deviceId);
      await writeSession(session);
      return session;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      final session = CurrentSession.empty(deviceId: deviceId);
      await writeSession(session);
      return session;
    }
    final data = jsonDecode(content) as Map<String, dynamic>;
    return CurrentSession.fromJson(data);
  }

  Future<void> writeSession(CurrentSession session) async {
    final file = await _currentSessionFile();
    final payload = session.toJson();
    await file.writeAsString(prettyJson(payload));
  }

  Future<File> _dayFile(DateTime date) async {
    final base = await _ensureBaseDir();
    final month = DateFormat('yyyyMM').format(date);
    final day = DateFormat('yyyy-MM-dd').format(date);
    final dataDir = Directory(p.join(base.path, 'data', month));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    return File(p.join(dataDir.path, '$day.json'));
  }

  Future<void> appendActivity(ActivityRecord record) async {
    final file = await _dayFile(record.startTime);
    final day = DateFormat('yyyy-MM-dd').format(record.startTime);
    Map<String, dynamic> jsonMap;
    if (await file.exists()) {
      final content = await file.readAsString();
      jsonMap = content.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(content) as Map<String, dynamic>;
    } else {
      jsonMap = <String, dynamic>{};
    }

    final activities = (jsonMap['activities'] as List<dynamic>?) ?? <dynamic>[];
    activities.add(record.toJson());
    jsonMap['activities'] = activities;
    jsonMap['date'] = jsonMap['date'] ?? day;
    jsonMap['lastUpdated'] = DateTime.now().millisecondsSinceEpoch;

    await file.writeAsString(prettyJson(jsonMap));
  }

  Future<List<ActivityRecord>> loadDayRecords(DateTime date) async {
    final file = await _dayFile(date);
    if (!await file.exists()) {
      return const [];
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const [];
    }
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final activities = (jsonMap['activities'] as List<dynamic>?) ?? <dynamic>[];
    final records = activities
        .map((e) => ActivityRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    records.sort((a, b) => a.startTime.compareTo(b.startTime));
    return records;
  }

  Future<void> saveDayRecords(DateTime date, List<ActivityRecord> records, {int? lastUpdated}) async {
    final file = await _dayFile(date);
    final day = DateFormat('yyyy-MM-dd').format(date);
    final payload = {
      'date': day,
      'lastUpdated': lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
      'activities': records.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(prettyJson(payload));
  }

  Future<void> updateRecord({
    required DateTime date,
    required String recordId,
    required DateTime newStart,
    required DateTime newEnd,
    String? note,
  }) async {
    final records = await loadDayRecords(date);
    final index = records.indexWhere((element) => element.id == recordId);
    if (index == -1) {
      throw StateError('未找到要修改的记录');
    }
    final durationSeconds = newEnd.difference(newStart).inSeconds;
    records[index] = records[index].copyWith(
      startTime: newStart,
      endTime: newEnd,
      durationSeconds: durationSeconds <= 0 ? 1 : durationSeconds,
      note: note,
    );
    await saveDayRecords(date, records);
  }

  Future<void> deleteRecord(DateTime date, String recordId) async {
    final records = await loadDayRecords(date);
    records.removeWhere((element) => element.id == recordId);
    await saveDayRecords(date, records);
  }

  Future<List<ActivityRecord>> loadRangeRecords(DateTime start, DateTime end) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final records = <ActivityRecord>[];
    var cursor = startDay;
    while (!cursor.isAfter(endDay)) {
      records.addAll(await loadDayRecords(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return records;
  }

  Future<File> _categoriesFile() async {
    final config = await _configDir();
    return File(p.join(config.path, 'categories.json'));
  }

  Future<List<CategoryModel>> loadCategories() async {
    final file = await _categoriesFile();
    if (!await file.exists() || (await file.length()) == 0) {
      final defaults = _defaultCategories();
      await saveCategories(defaults);
      return defaults;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      final defaults = _defaultCategories();
      await saveCategories(defaults);
      return defaults;
    }
    final decoded = jsonDecode(content);
    List<dynamic> rawItems;
    if (decoded is Map<String, dynamic>) {
      rawItems = decoded['items'] as List<dynamic>? ?? <dynamic>[];
    } else if (decoded is List<dynamic>) {
      rawItems = decoded;
    } else {
      rawItems = <dynamic>[];
    }

    final list = rawItems
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
    if (list.isEmpty) {
      final defaults = _defaultCategories();
      await saveCategories(defaults);
      return defaults;
    }
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<void> saveCategories(List<CategoryModel> categories) async {
    final file = await _categoriesFile();
    final payload = [...categories]..sort((a, b) => a.order.compareTo(b.order));
    await file.writeAsString(prettyJson({
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'items': payload.map((e) => e.toJson()).toList(),
    }));
  }

  Future<AppSettings> loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) {
      final defaults = AppSettings.defaults();
      await saveSettings(defaults);
      return defaults;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      final defaults = AppSettings.defaults();
      await saveSettings(defaults);
      return defaults;
    }
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    return AppSettings.fromJson(jsonMap);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final file = await _settingsFile();
    await file.writeAsString(prettyJson(settings.toJson()));
  }

  Future<File> _settingsFile() async {
    final config = await _configDir();
    return File(p.join(config.path, 'settings.json'));
  }

  List<CategoryModel> _defaultCategories() {
    return [
      CategoryModel(
        id: 'web',
        name: '上网探索',
        iconCode: Icons.computer.codePoint,
        colorHex: '#2196F3',
        order: 1,
        group: '娱乐',
      ),
      CategoryModel(
        id: 'sleep',
        name: '睡眠',
        iconCode: Icons.hotel_outlined.codePoint,
        colorHex: '#8E44AD',
        order: 2,
        group: '休息',
      ),
      CategoryModel(
        id: 'nap',
        name: '午睡',
        iconCode: Icons.wb_sunny_outlined.codePoint,
        colorHex: '#FBC02D',
        order: 3,
        group: '休息',
      ),
      CategoryModel(
        id: 'commute',
        name: '通勤',
        iconCode: Icons.speed.codePoint,
        colorHex: '#E91E63',
        order: 4,
        group: '出行',
      ),
      CategoryModel(
        id: 'video',
        name: '刷视频',
        iconCode: Icons.movie_filter_outlined.codePoint,
        colorHex: '#00ACC1',
        order: 5,
        group: '娱乐',
      ),
      CategoryModel(
        id: 'meal',
        name: '用餐',
        iconCode: Icons.restaurant.codePoint,
        colorHex: '#7D6608',
        order: 6,
        group: '生活',
      ),
      CategoryModel(
        id: 'sports',
        name: '运动',
        iconCode: Icons.fitness_center.codePoint,
        colorHex: '#1565C0',
        order: 7,
        group: '健康',
      ),
      CategoryModel(
        id: 'game',
        name: '游戏',
        iconCode: Icons.sports_esports.codePoint,
        colorHex: '#5C6BC0',
        order: 8,
        group: '娱乐',
      ),
      CategoryModel(
        id: 'movie',
        name: '影音',
        iconCode: Icons.movie_creation_outlined.codePoint,
        colorHex: '#757575',
        order: 9,
        group: '娱乐',
      ),
      CategoryModel(
        id: 'chat',
        name: '聊天',
        iconCode: Icons.people.codePoint,
        colorHex: '#F4511E',
        order: 10,
        group: '社交',
      ),
      CategoryModel(
        id: 'house',
        name: '家务',
        iconCode: Icons.home.codePoint,
        colorHex: '#7CB342',
        order: 11,
        group: '生活',
      ),
      CategoryModel(
        id: 'reading',
        name: '阅读',
        iconCode: Icons.menu_book.codePoint,
        colorHex: '#8D6E63',
        order: 12,
        group: '学习',
      ),
      CategoryModel(
        id: 'work',
        name: '工作',
        iconCode: Icons.work_outline.codePoint,
        colorHex: '#FF9800',
        order: 13,
        group: '工作',
      ),
      CategoryModel(
        id: 'shopping',
        name: '购物',
        iconCode: Icons.shopping_cart.codePoint,
        colorHex: '#455A64',
        order: 14,
        group: '生活',
      ),
      CategoryModel(
        id: 'walk',
        name: '步行',
        iconCode: Icons.directions_walk.codePoint,
        colorHex: '#42A5F5',
        order: 15,
        group: '健康',
      ),
    ];
  }

  Future<File> createBackupZip() async {
    final base = await _ensureBaseDir();
    final archive = Archive();

    await for (final entity in base.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final bytes = await entity.readAsBytes();
      final relative = p.relative(entity.path, from: base.path);
      archive.addFile(ArchiveFile(relative, bytes.length, bytes));
    }

    final encoder = ZipEncoder();
    final zipped = encoder.encode(archive);
    final name = 'atimelog_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    final outFile = File(p.join(base.parent.path, name));
    await outFile.writeAsBytes(zipped ?? <int>[]);
    return outFile;
  }

  Future<void> restoreBackup(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw ArgumentError('备份文件不存在');
    }
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final base = await _ensureBaseDir();

    for (final entry in archive) {
      final entryPath = p.join(base.path, entry.name);
      if (entry.isFile) {
        final outFile = File(entryPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        final dir = Directory(entryPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
    }
  }
}
