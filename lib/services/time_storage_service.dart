import 'dart:convert';
import 'dart:io';

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

  Future<void> appendActivity(ActivityRecord record) async {
    final base = await _ensureBaseDir();
    final month = DateFormat('yyyyMM').format(record.startTime);
    final day = DateFormat('yyyy-MM-dd').format(record.startTime);
    final dataDir = Directory(p.join(base.path, 'data', month));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final file = File(p.join(dataDir.path, '$day.json'));
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
}
