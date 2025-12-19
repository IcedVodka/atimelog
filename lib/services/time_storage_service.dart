import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/sync_models.dart';
import '../models/time_models.dart';

typedef _CategoryConfig = ({
  List<CategoryModel> categories,
  bool darkMode,
  OverlapFixMode overlapFixMode,
});

const int _bootstrapLastUpdated = 0;

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
  Future<Directory> currentDir() => _currentDir();

  Future<Directory> _currentDir() async {
    final base = await _ensureBaseDir();
    final current = Directory(p.join(base.path, 'current'));
    if (!await current.exists()) {
      final legacy = Directory(p.join(base.path, 'local'));
      if (await legacy.exists()) {
        try {
          await legacy.rename(current.path);
        } catch (_) {
          await current.create(recursive: true);
          await for (final entity
              in legacy.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final relative = p.relative(entity.path, from: legacy.path);
            final target = File(p.join(current.path, relative));
            await target.parent.create(recursive: true);
            await target.writeAsBytes(await entity.readAsBytes());
          }
        }
      } else {
        await current.create(recursive: true);
      }
    }
    return current;
  }

  Future<Directory> _etagDir() async {
    final base = await _ensureBaseDir();
    final etagRoot = Directory(p.join(base.parent.path, 'etag'));
    if (!await etagRoot.exists()) {
      await etagRoot.create(recursive: true);
    }
    return etagRoot;
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
    final currentDir = await _currentDir();
    return File(p.join(currentDir.path, 'current_session.json'));
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
    await _invalidateEtag('current/${p.basename(file.path)}');
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
    final month = DateFormat('yyyyMM').format(record.startTime);
    final relativePath = p.posix.join('data', month, '$day.json');
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
    await _invalidateEtag(relativePath);
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
    final month = DateFormat('yyyyMM').format(date);
    final relativePath = p.posix.join('data', month, '$day.json');
    final sorted = [...records]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final payload = {
      'date': day,
      'lastUpdated': lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
      'activities': sorted.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(prettyJson(payload));
    await _invalidateEtag(relativePath);
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
    final current = await _currentDir();
    final target = File(p.join(current.path, 'categories.json'));
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
    final fileExists = await file.exists();
    Map<String, dynamic>? mapContent;

    if (fileExists) {
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
    final overlapRaw = mapContent?['overlapFixMode'] as String?;
    final shouldUseBootstrapLastUpdated =
        !fileExists || mapContent == null || rawItems.isEmpty;

    var categories = rawItems
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .map(_normalizeCategory)
        .toList();
    if (categories.isEmpty && ensureDefaults) {
      categories = _defaultCategories().map(_normalizeCategory).toList();
      final resolvedDark = darkMode ?? false;
      final resolvedOverlap = parseOverlapFixMode(overlapRaw);
      await _writeCategoryConfig(
        categories: categories,
        darkMode: resolvedDark,
        overlapFixMode: resolvedOverlap,
        lastUpdated: shouldUseBootstrapLastUpdated
            ? _bootstrapLastUpdated
            : null,
      );
      return (
        categories: categories,
        darkMode: resolvedDark,
        overlapFixMode: resolvedOverlap,
      );
    }
    categories.sort((a, b) => a.order.compareTo(b.order));
    return (
      categories: categories,
      darkMode: darkMode ?? false,
      overlapFixMode: parseOverlapFixMode(overlapRaw),
    );
  }

  Future<void> _writeCategoryConfig({
    required List<CategoryModel> categories,
    required bool darkMode,
    required OverlapFixMode overlapFixMode,
    int? lastUpdated,
  }) async {
    final file = await _categoriesFile();
    final normalized = categories.map(_normalizeCategory).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    await file.writeAsString(
      prettyJson({
        'lastUpdated': lastUpdated ?? DateTime.now().millisecondsSinceEpoch,
        'darkMode': darkMode,
        'overlapFixMode': overlapFixMode.name,
        'items': normalized.map((e) => e.toJson()).toList(),
      }),
    );
    await _invalidateEtag('current/${p.basename(file.path)}');
  }

  Future<List<CategoryModel>> loadCategories() async {
    final config = await _loadCategoryConfig();
    if (config.categories.isEmpty) {
      final defaults = _defaultCategories().map(_normalizeCategory).toList();
      await _writeCategoryConfig(
        categories: defaults,
        darkMode: config.darkMode,
        overlapFixMode: config.overlapFixMode,
        lastUpdated: _bootstrapLastUpdated,
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
      overlapFixMode: config.overlapFixMode,
    );
  }

  Future<AppSettings> loadSettings() async {
    final config = await _loadCategoryConfig();
    if (config.categories.isEmpty) {
      await _writeCategoryConfig(
        categories: _defaultCategories().map(_normalizeCategory).toList(),
        darkMode: config.darkMode,
        overlapFixMode: config.overlapFixMode,
        lastUpdated: _bootstrapLastUpdated,
      );
    }
    return AppSettings(
      darkMode: config.darkMode,
      overlapFixMode: config.overlapFixMode,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final config = await _loadCategoryConfig();
    final categories = config.categories.isEmpty
        ? _defaultCategories().map(_normalizeCategory).toList()
        : config.categories;
    await _writeCategoryConfig(
      categories: categories,
      darkMode: settings.darkMode,
      overlapFixMode: settings.overlapFixMode,
    );
  }

  Future<File> _syncSettingsFile() async {
    final current = await _currentDir();
    return File(p.join(current.path, 'sync_settings.json'));
  }

  Future<SyncConfig> loadSyncConfig() async {
    final file = await _syncSettingsFile();
    if (!await file.exists()) {
      return SyncConfig.defaults();
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return SyncConfig.defaults();
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return SyncConfig.fromJson(decoded);
      }
    } catch (_) {
      // ignore malformed content
    }
    return SyncConfig.defaults();
  }

  Future<void> saveSyncConfig(SyncConfig config) async {
    final file = await _syncSettingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config.toJson()));
    await _invalidateEtag('current/${p.basename(file.path)}');
  }

  Future<File> resolveRelativeFile(String relativePath) async {
    final base = await _ensureBaseDir();
    return File(p.join(base.path, relativePath));
  }

  Future<String> readFileContent(String relativePath) async {
    final file = await resolveRelativeFile(relativePath);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> writeFileContent(String relativePath, String content) async {
    final file = await resolveRelativeFile(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<List<String>> getLocalMonthFolders() async {
    final base = await _ensureBaseDir();
    final dataDir = Directory(p.join(base.path, 'data'));
    if (!await dataDir.exists()) {
      return const [];
    }
    final items = <String>[];
    await for (final entity in dataDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (RegExp(r'^\d{6}$').hasMatch(name)) {
        items.add(name);
      }
    }
    items.sort();
    return items;
  }

  Future<List<String>> getLocalFilesInMonth(String month) async {
    final base = await _ensureBaseDir();
    final dir = Directory(p.join(base.path, 'data', month));
    if (!await dir.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.toLowerCase().endsWith('.json')) {
        files.add(name);
      }
    }
    files.sort();
    return files;
  }

  Future<List<String>> getLocalCurrentFiles() async {
    final current = await _currentDir();
    if (!await current.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in current.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.toLowerCase().endsWith('.json')) {
        files.add(name);
      }
    }
    files.sort();
    return files;
  }

  Future<int?> readLocalFileTimestamp(String relativePath) async {
    final file = await resolveRelativeFile(relativePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final ts = decoded['lastUpdated'];
        if (ts is int) return ts;
        if (ts is String) return int.tryParse(ts);
      }
    } catch (_) {
      // ignore parse errors
    }
    final stat = await file.stat();
    return stat.modified.millisecondsSinceEpoch;
  }

  Future<File> _currentEtagFile() async {
    final etagRoot = await _etagDir();
    return File(p.join(etagRoot.path, 'current_etag.json'));
  }

  Future<Directory> _etagDataDir() async {
    final etagRoot = await _etagDir();
    final dataDir = Directory(p.join(etagRoot.path, 'etagdata'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return dataDir;
  }

  Future<File> _monthEtagFile(String month) async {
    final dir = await _etagDataDir();
    return File(p.join(dir.path, '${month}_etag.json'));
  }

  Future<Map<String, String>> _readEtagMap(File file) async {
    if (!await file.exists()) {
      return {};
    }
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded.map(
          (key, value) => MapEntry(key, value?.toString() ?? ''),
        );
      }
    } catch (_) {
      // ignore malformed content
    }
    return {};
  }

  Future<Map<String, String>> _pruneLocalChanges(
    Map<String, String> etags, {
    required int etagModified,
    required String basePrefix,
  }) async {
    final result = <String, String>{};
    for (final entry in etags.entries) {
      final relativePath =
          basePrefix.isEmpty ? entry.key : p.join(basePrefix, entry.key);
      final localFile = await resolveRelativeFile(relativePath);
      if (await localFile.exists()) {
        final localStat = await localFile.stat();
        if (localStat.modified.millisecondsSinceEpoch > etagModified) {
          // 本地文件在缓存 ETag 之后被修改，清理掉对应的记录。
          continue;
        }
      }
      result[entry.key] = entry.value;
    }
    return result;
  }

  Future<void> _invalidateEtag(String relativePath) async {
    final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    if (normalized.startsWith('data/')) {
      final parts = normalized.split('/');
      if (parts.length >= 3) {
        final month = parts[1];
        final fileName = parts.sublist(2).join('/');
        final etags = await loadMonthEtags(month);
        etags.remove('$month/$fileName');
        await saveMonthEtags(month, etags);
      }
      return;
    }
    if (normalized.startsWith('current/')) {
      final etags = await loadCurrentEtags();
      etags.remove(normalized);
      await saveCurrentEtags(etags);
    }
  }

  Future<Map<String, String>> loadCurrentEtags() async {
    final file = await _currentEtagFile();
    if (!await file.exists()) return {};
    final map = await _readEtagMap(file);
    if (map.isEmpty) return {};
    final stat = await file.stat();
    return _pruneLocalChanges(
      map,
      etagModified: stat.modified.millisecondsSinceEpoch,
      basePrefix: '',
    );
  }

  Future<void> saveCurrentEtags(Map<String, String> data) async {
    final file = await _currentEtagFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data));
  }

  Future<Map<String, String>> loadMonthEtags(String month) async {
    final file = await _monthEtagFile(month);
    if (!await file.exists()) return {};
    final map = await _readEtagMap(file);
    if (map.isEmpty) return {};
    final stat = await file.stat();
    return _pruneLocalChanges(
      map,
      etagModified: stat.modified.millisecondsSinceEpoch,
      basePrefix: 'data',
    );
  }

  Future<void> saveMonthEtags(String month, Map<String, String> data) async {
    final file = await _monthEtagFile(month);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data));
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
