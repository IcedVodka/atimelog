import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/time_models.dart';

typedef _CategoryConfig = ({List<CategoryModel> categories, bool darkMode});

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

  Future<Directory> _localDir() async {
    final base = await _ensureBaseDir();
    final local = Directory(p.join(base.path, 'local'));
    if (!await local.exists()) {
      await local.create(recursive: true);
    }
    return local;
  }

  Future<File> _legacyCategoriesFile() async {
    final base = await _ensureBaseDir();
    return File(p.join(base.path, 'config', 'categories.json'));
  }

  Future<File> _legacySettingsFile() async {
    final base = await _ensureBaseDir();
    return File(p.join(base.path, 'config', 'settings.json'));
  }

  Future<File> _currentSessionFile() async {
    final localDir = await _localDir();
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

  Future<void> saveDayRecords(
    DateTime date,
    List<ActivityRecord> records, {
    int? lastUpdated,
  }) async {
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

  Future<List<ActivityRecord>> loadRangeRecords(
    DateTime start,
    DateTime end,
  ) async {
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
    final local = await _localDir();
    final target = File(p.join(local.path, 'categories.json'));
    if (!await target.exists()) {
      final legacy = await _legacyCategoriesFile();
      if (await legacy.exists()) {
        await target.create(recursive: true);
        await target.writeAsBytes(await legacy.readAsBytes());
      }
    }
    return target;
  }

  Future<bool?> _loadLegacyDarkMode() async {
    final legacyFile = await _legacySettingsFile();
    if (!await legacyFile.exists()) {
      return null;
    }
    final content = await legacyFile.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded['darkMode'] as bool?;
    }
    return null;
  }

  Future<_CategoryConfig> _loadCategoryConfig({
    bool ensureDefaults = true,
  }) async {
    final file = await _categoriesFile();
    Map<String, dynamic>? mapContent;

    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          mapContent = decoded;
        } else if (decoded is List<dynamic>) {
          mapContent = {'items': decoded};
        }
      }
    }

    final rawItems = mapContent?['items'] as List<dynamic>? ?? <dynamic>[];
    bool? darkMode = mapContent?['darkMode'] as bool?;
    darkMode ??= await _loadLegacyDarkMode();

    var categories = rawItems
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .map(_normalizeCategory)
        .toList();
    if (categories.isEmpty && ensureDefaults) {
      categories = _defaultCategories().map(_normalizeCategory).toList();
      final resolvedDark = darkMode ?? false;
      await _writeCategoryConfig(
        categories: categories,
        darkMode: resolvedDark,
      );
      return (categories: categories, darkMode: resolvedDark);
    }
    categories.sort((a, b) => a.order.compareTo(b.order));
    return (
      categories: categories,
      darkMode: darkMode ?? false,
    );
  }

  Future<void> _writeCategoryConfig({
    required List<CategoryModel> categories,
    required bool darkMode,
  }) async {
    final file = await _categoriesFile();
    final normalized = categories.map(_normalizeCategory).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    await file.writeAsString(
      prettyJson({
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'darkMode': darkMode,
        'items': normalized.map((e) => e.toJson()).toList(),
      }),
    );
  }

  Future<List<CategoryModel>> loadCategories() async {
    final config = await _loadCategoryConfig();
    if (config.categories.isEmpty) {
      final defaults = _defaultCategories().map(_normalizeCategory).toList();
      await _writeCategoryConfig(
        categories: defaults,
        darkMode: config.darkMode,
      );
      return defaults;
    }
    return config.categories;
  }

  Future<void> saveCategories(List<CategoryModel> categories) async {
    final normalized = categories.map(_normalizeCategory).toList();
    final config = await _loadCategoryConfig(ensureDefaults: false);
    await _writeCategoryConfig(
      categories: normalized,
      darkMode: config.darkMode,
    );
  }

  Future<AppSettings> loadSettings() async {
    final config = await _loadCategoryConfig();
    if (config.categories.isEmpty) {
      await _writeCategoryConfig(
        categories: _defaultCategories().map(_normalizeCategory).toList(),
        darkMode: config.darkMode,
      );
    }
    return AppSettings(darkMode: config.darkMode);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final config = await _loadCategoryConfig();
    final categories = config.categories.isEmpty
        ? _defaultCategories().map(_normalizeCategory).toList()
        : config.categories;
    await _writeCategoryConfig(
      categories: categories,
      darkMode: settings.darkMode,
    );
  }

  CategoryModel _normalizeCategory(CategoryModel category) {
    CategoryModel normalized = category;
    if (category.id == 'nap' && category.name == '午睡') {
      normalized = category.copyWith(name: '睡眠.午睡', group: '睡眠');
    }
    if (category.id == 'web' && category.name == '上网探索') {
      normalized = category.copyWith(name: '上网探究');
    }
    final name = normalized.name.trim();
    final hasDot = name.contains('.');
    final derivedGroup = hasDot ? name.split('.').first.trim() : name;
    if (derivedGroup.isNotEmpty && normalized.group != derivedGroup) {
      normalized = normalized.copyWith(group: derivedGroup);
    }
    return normalized;
  }

  List<CategoryModel> _defaultCategories() {
    return [
      CategoryModel(
        id: 'web',
        name: '上网探究',
        iconCode: Icons.computer.codePoint,
        colorHex: '#2196F3',
        order: 1,
        group: '',
      ),
      CategoryModel(
        id: 'sleep',
        name: '睡眠',
        iconCode: Icons.hotel_outlined.codePoint,
        colorHex: '#8E44AD',
        order: 2,
        group: '',
      ),
      CategoryModel(
        id: 'nap',
        name: '睡眠.午睡',
        iconCode: Icons.wb_sunny_outlined.codePoint,
        colorHex: '#FBC02D',
        order: 3,
        group: '',
      ),
      CategoryModel(
        id: 'commute',
        name: '通勤',
        iconCode: Icons.speed.codePoint,
        colorHex: '#E91E63',
        order: 4,
        group: '',
      ),
      CategoryModel(
        id: 'video',
        name: '刷视频',
        iconCode: Icons.movie_filter_outlined.codePoint,
        colorHex: '#00ACC1',
        order: 5,
        group: '',
      ),
      CategoryModel(
        id: 'meal',
        name: '用餐',
        iconCode: Icons.restaurant.codePoint,
        colorHex: '#7D6608',
        order: 6,
        group: '',
      ),
      CategoryModel(
        id: 'sports',
        name: '运动',
        iconCode: Icons.fitness_center.codePoint,
        colorHex: '#1565C0',
        order: 7,
        group: '',
      ),
      CategoryModel(
        id: 'game',
        name: '游戏',
        iconCode: Icons.sports_esports.codePoint,
        colorHex: '#5C6BC0',
        order: 8,
        group: '',
      ),
      CategoryModel(
        id: 'movie',
        name: '影音',
        iconCode: Icons.movie_creation_outlined.codePoint,
        colorHex: '#757575',
        order: 9,
        group: '',
      ),
      CategoryModel(
        id: 'chat',
        name: '聊天',
        iconCode: Icons.people.codePoint,
        colorHex: '#F4511E',
        order: 10,
        group: '',
      ),
      CategoryModel(
        id: 'house',
        name: '家务',
        iconCode: Icons.home.codePoint,
        colorHex: '#7CB342',
        order: 11,
        group: '',
      ),
      CategoryModel(
        id: 'reading',
        name: '阅读',
        iconCode: Icons.menu_book.codePoint,
        colorHex: '#8D6E63',
        order: 12,
        group: '',
      ),
      CategoryModel(
        id: 'work',
        name: '工作',
        iconCode: Icons.work_outline.codePoint,
        colorHex: '#FF9800',
        order: 13,
        group: '',
      ),
      CategoryModel(
        id: 'shopping',
        name: '购物',
        iconCode: Icons.shopping_cart.codePoint,
        colorHex: '#455A64',
        order: 14,
        group: '',
      ),
      CategoryModel(
        id: 'walk',
        name: '步行',
        iconCode: Icons.directions_walk.codePoint,
        colorHex: '#42A5F5',
        order: 15,
        group: '',
      ),
    ];
  }

  Future<File> createBackupZip({String? targetPath}) async {
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
    final name =
        'atimelog_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';
    final resolvedPath = () {
      final trimmed = targetPath?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return p.join(base.parent.path, name);
      }
      final looksLikeFile = trimmed.toLowerCase().endsWith('.zip');
      if (looksLikeFile) {
        return trimmed;
      }
      return p.join(trimmed, name);
    }();
    final outFile = File(resolvedPath);
    await outFile.parent.create(recursive: true);
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
