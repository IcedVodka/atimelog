import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/sync_models.dart';
import 'time_storage_service.dart';
import 'webdav_client.dart';

class _SyncCounters {
  const _SyncCounters({this.uploaded = 0, this.downloaded = 0});
  final int uploaded;
  final int downloaded;

  _SyncCounters operator +(_SyncCounters other) {
    return _SyncCounters(
      uploaded: uploaded + other.uploaded,
      downloaded: downloaded + other.downloaded,
    );
  }
}

class SyncService {
  SyncService(this._storage);

  final TimeStorageService _storage;

  Future<SyncResult> syncAll(SyncConfig config) async {
    if (!config.isConfigured) {
      return const SyncResult(
        success: false,
        message: '未配置 WebDAV，同步已跳过',
        uploaded: 0,
        downloaded: 0,
        duration: Duration.zero,
      );
    }
    final stopwatch = Stopwatch()..start();
    final client = WebDavClient(
      baseUrl: config.serverUrl.trim(),
      username: config.username.trim(),
      password: config.password,
      rootPath: config.remotePath.trim().isEmpty
          ? '/atimelog_data'
          : config.remotePath.trim(),
    );
    var counters = const _SyncCounters();

    try {
      await client.ensureDirectory('data');
      await client.ensureDirectory('current');
      counters += await _syncCurrent(client);
      counters += await _syncData(client);
      stopwatch.stop();
      return SyncResult(
        success: true,
        message: '同步完成',
        uploaded: counters.uploaded,
        downloaded: counters.downloaded,
        duration: stopwatch.elapsed,
      );
    } catch (error) {
      stopwatch.stop();
      return SyncResult(
        success: false,
        message: error.toString(),
        uploaded: counters.uploaded,
        downloaded: counters.downloaded,
        duration: stopwatch.elapsed,
      );
    } finally {
      await client.close();
    }
  }

  Future<void> verifyConnection(SyncConfig config) async {
    if (!config.isConfigured) {
      throw StateError('请先完整填写 WebDAV 配置');
    }
    final client = WebDavClient(
      baseUrl: config.serverUrl.trim(),
      username: config.username.trim(),
      password: config.password,
      rootPath: config.remotePath.trim().isEmpty
          ? '/atimelog_data'
          : config.remotePath.trim(),
    );
    try {
      await client.ping();
    } finally {
      await client.close();
    }
  }

  Future<_SyncCounters> _syncCurrent(WebDavClient client) async {
    const excluded = {'sync_settings.json'};
    final remoteFiles = await _safeFetchFiles(
      client,
      'current',
      treatMissingAsEmpty: true,
    )..removeWhere((key, _) => excluded.contains(key));
    final localFiles = (await _storage.getLocalCurrentFiles())
        .where((element) => !excluded.contains(element))
        .toList();
    final cachedEtags = await _storage.loadCurrentEtags();
    final updatedEtags = <String, String>{};
    var uploaded = 0;
    var downloaded = 0;

    for (final entry in remoteFiles.entries) {
      final filename = entry.key;
      final remoteEtag = entry.value;
      final path = p.posix.join('current', filename);
      final key = 'current/$filename';
      final cached = cachedEtags[key];
      final hasLocal = localFiles.contains(filename);

      if (!hasLocal) {
        final remote = await client.downloadFile(path);
        await _storage.writeFileContent(path, remote.content);
        updatedEtags[key] = remote.etag ?? remoteEtag;
        downloaded++;
        continue;
      }
      if (cached != null && cached == remoteEtag) {
        updatedEtags[key] = cached;
        continue;
      }
      final remote = await client.downloadFile(path);
      final remoteTs = _extractLastUpdated(remote.content);
      final localTs = await _storage.readLocalFileTimestamp(path) ?? 0;
      if ((remoteTs ?? 0) > localTs) {
        await _storage.writeFileContent(path, remote.content);
        updatedEtags[key] = remote.etag ?? remoteEtag;
        downloaded++;
      } else if ((remoteTs ?? 0) < localTs) {
        final content = await _storage.readFileContent(path);
        final newEtag = await client.uploadFile(path, content);
        updatedEtags[key] = newEtag ?? remoteEtag;
        uploaded++;
      } else {
        updatedEtags[key] = remote.etag ?? remoteEtag;
      }
    }

    for (final filename in localFiles) {
      if (remoteFiles.containsKey(filename)) {
        continue;
      }
      final path = p.posix.join('current', filename);
      final key = 'current/$filename';
      final content = await _storage.readFileContent(path);
      final newEtag = await client.uploadFile(path, content);
      if (newEtag != null && newEtag.isNotEmpty) {
        updatedEtags[key] = newEtag;
      }
      uploaded++;
    }

    await _storage.saveCurrentEtags(updatedEtags);
    return _SyncCounters(uploaded: uploaded, downloaded: downloaded);
  }

  Future<_SyncCounters> _syncData(WebDavClient client) async {
    List<String> remoteMonths = const [];
    try {
      remoteMonths = await client.listRemoteSubdirectories('data');
    } catch (_) {
      remoteMonths = const [];
    }
    final localMonths = await _storage.getLocalMonthFolders();
    final allMonths = {
      ...remoteMonths,
      ...localMonths,
    }.toList()
      ..sort();

    var uploaded = 0;
    var downloaded = 0;
    for (final month in allMonths) {
      final remoteFiles = await _safeFetchFiles(
        client,
        p.posix.join('data', month),
        treatMissingAsEmpty: true,
      );
      final localFiles = await _storage.getLocalFilesInMonth(month);
      final monthEtags = await _storage.loadMonthEtags(month);
      final updatedEtags = <String, String>{};
      final prefix = 'data/$month';

      for (final entry in remoteFiles.entries) {
        final filename = entry.key;
        final remoteEtag = entry.value;
        final relative = '$prefix/$filename';
        final key = '$month/$filename';
        final cached = monthEtags[key];
        final hasLocal = localFiles.contains(filename);

        if (!hasLocal) {
          final remote = await client.downloadFile(relative);
          await _storage.writeFileContent(relative, remote.content);
          updatedEtags[key] = remote.etag ?? remoteEtag;
          downloaded++;
          continue;
        }
        if (cached != null && cached == remoteEtag) {
          updatedEtags[key] = cached;
          continue;
        }
        final remote = await client.downloadFile(relative);
        final remoteTs = _extractLastUpdated(remote.content);
        final localTs = await _storage.readLocalFileTimestamp(relative) ?? 0;
        if ((remoteTs ?? 0) > localTs) {
          await _storage.writeFileContent(relative, remote.content);
          updatedEtags[key] = remote.etag ?? remoteEtag;
          downloaded++;
        } else if ((remoteTs ?? 0) < localTs) {
          final content = await _storage.readFileContent(relative);
          final newEtag = await client.uploadFile(relative, content);
          updatedEtags[key] = newEtag ?? remoteEtag;
          uploaded++;
        } else {
          updatedEtags[key] = remote.etag ?? remoteEtag;
        }
      }

      for (final filename in localFiles) {
        if (remoteFiles.containsKey(filename)) continue;
        final relative = '$prefix/$filename';
        final key = '$month/$filename';
        final content = await _storage.readFileContent(relative);
        final newEtag = await client.uploadFile(relative, content);
        if (newEtag != null && newEtag.isNotEmpty) {
          updatedEtags[key] = newEtag;
        }
        uploaded++;
      }

      await _storage.saveMonthEtags(month, updatedEtags);
    }

    return _SyncCounters(uploaded: uploaded, downloaded: downloaded);
  }

  Future<Map<String, String>> _safeFetchFiles(
    WebDavClient client,
    String relativePath, {
    bool treatMissingAsEmpty = false,
  }) async {
    try {
      return await client.fetchFolderFileList(relativePath);
    } catch (_) {
      if (treatMissingAsEmpty) {
        return {};
      }
      rethrow;
    }
  }

  int? _extractLastUpdated(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final ts = decoded['lastUpdated'];
        if (ts is int) return ts;
        if (ts is String) return int.tryParse(ts);
      }
    } catch (_) {
      // ignore parse error, fall through
    }
    return null;
  }
}
