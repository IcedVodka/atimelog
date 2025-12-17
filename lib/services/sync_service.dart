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

enum _SyncDirection { upload, download }

class _SyncAction {
  _SyncAction({
    required this.direction,
    required this.relativePath,
    required this.etagKey,
    this.preDownloaded,
    this.remoteEtag,
  });

  final _SyncDirection direction;
  final String relativePath;
  final String etagKey;
  final DownloadedRemoteFile? preDownloaded;
  final String? remoteEtag;
}

class SyncService {
  SyncService(this._storage);

  final TimeStorageService _storage;

  Future<SyncResult> syncAll(
    SyncConfig config, {
    SyncProgressCallback? onProgress,
  }) async {
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
    onProgress?.call(
      SyncProgress(stage: '准备同步', detail: '正在连接 WebDAV...'),
    );
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
      onProgress?.call(
        SyncProgress(stage: '检查远程目录', detail: '创建 data / current'),
      );
      await client.ensureDirectory('data');
      await client.ensureDirectory('current');
      final currentSummary =
          await _syncCurrent(client, onProgress: onProgress);
      counters += currentSummary;
      final dataSummary = await _syncData(
        client,
        onProgress: onProgress,
        uploadedBase: counters.uploaded,
        downloadedBase: counters.downloaded,
        totalUploadBase: counters.uploaded,
        totalDownloadBase: counters.downloaded,
      );
      counters += dataSummary;
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

  Future<_SyncCounters> _syncCurrent(
    WebDavClient client, {
    SyncProgressCallback? onProgress,
  }) async {
    const excluded = {'sync_settings.json'};
    onProgress?.call(
      SyncProgress(stage: 'current', detail: '获取远程文件列表...'),
    );
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
    final actions = <_SyncAction>[];

    for (final entry in remoteFiles.entries) {
      final filename = entry.key;
      final remoteEtag = entry.value;
      final path = p.posix.join('current', filename);
      final key = 'current/$filename';
      final cached = cachedEtags[key];
      final hasLocal = localFiles.contains(filename);

      if (!hasLocal) {
        final remote = await client.downloadFile(path);
        actions.add(
          _SyncAction(
            direction: _SyncDirection.download,
            relativePath: path,
            etagKey: key,
            preDownloaded: remote,
            remoteEtag: remote.etag ?? remoteEtag,
          ),
        );
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
        actions.add(
          _SyncAction(
            direction: _SyncDirection.download,
            relativePath: path,
            etagKey: key,
            preDownloaded: remote,
            remoteEtag: remote.etag ?? remoteEtag,
          ),
        );
      } else if ((remoteTs ?? 0) < localTs) {
        actions.add(
          _SyncAction(
            direction: _SyncDirection.upload,
            relativePath: path,
            etagKey: key,
            remoteEtag: remote.etag ?? remoteEtag,
          ),
        );
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
      actions.add(
        _SyncAction(
          direction: _SyncDirection.upload,
          relativePath: path,
          etagKey: key,
        ),
      );
    }

    final totalUpload = actions
        .where((action) => action.direction == _SyncDirection.upload)
        .length;
    final totalDownload = actions
        .where((action) => action.direction == _SyncDirection.download)
        .length;
    onProgress?.call(
      SyncProgress(
        stage: 'current',
        detail: '预计上传 $totalUpload 个，下载 $totalDownload 个',
        uploaded: 0,
        downloaded: 0,
        totalUpload: totalUpload,
        totalDownload: totalDownload,
      ),
    );

    var uploaded = 0;
    var downloaded = 0;
    for (final action in actions) {
      if (action.direction == _SyncDirection.download) {
        final remote =
            action.preDownloaded ?? await client.downloadFile(action.relativePath);
        await _storage.writeFileContent(action.relativePath, remote.content);
        final etagToSave = remote.etag ?? action.remoteEtag;
        if (etagToSave != null && etagToSave.isNotEmpty) {
          updatedEtags[action.etagKey] = etagToSave;
        }
        downloaded++;
        onProgress?.call(
          SyncProgress(
            stage: '下载 $downloaded/$totalDownload',
            detail: action.relativePath,
            uploaded: uploaded,
            downloaded: downloaded,
            totalUpload: totalUpload,
            totalDownload: totalDownload,
          ),
        );
      } else {
        final content = await _storage.readFileContent(action.relativePath);
        final newEtag = await client.uploadFile(action.relativePath, content);
        final etagToSave = newEtag ?? action.remoteEtag;
        if (etagToSave != null && etagToSave.isNotEmpty) {
          updatedEtags[action.etagKey] = etagToSave;
        }
        uploaded++;
        onProgress?.call(
          SyncProgress(
            stage: '上传 $uploaded/$totalUpload',
            detail: action.relativePath,
            uploaded: uploaded,
            downloaded: downloaded,
            totalUpload: totalUpload,
            totalDownload: totalDownload,
          ),
        );
      }
    }

    await _storage.saveCurrentEtags(updatedEtags);
    onProgress?.call(
      SyncProgress(
        stage: 'current 完成',
        detail: '完成 current 目录同步',
        uploaded: uploaded,
        downloaded: downloaded,
        totalUpload: totalUpload,
        totalDownload: totalDownload,
      ),
    );
    return _SyncCounters(uploaded: uploaded, downloaded: downloaded);
  }

  Future<_SyncCounters> _syncData(
    WebDavClient client, {
    SyncProgressCallback? onProgress,
    int uploadedBase = 0,
    int downloadedBase = 0,
    int totalUploadBase = 0,
    int totalDownloadBase = 0,
  }) async {
    List<String> remoteMonths = const [];
    try {
      onProgress?.call(
        SyncProgress(stage: 'data', detail: '获取远程月份目录...'),
      );
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

    var stageUploaded = 0;
    var stageDownloaded = 0;
    var progressUploaded = uploadedBase;
    var progressDownloaded = downloadedBase;
    var progressTotalUpload = totalUploadBase;
    var progressTotalDownload = totalDownloadBase;
    for (final month in allMonths) {
      onProgress?.call(
        SyncProgress(
          stage: '扫描 $month',
          detail: '读取文件列表...',
          uploaded: progressUploaded,
          downloaded: progressDownloaded,
          totalUpload: progressTotalUpload,
          totalDownload: progressTotalDownload,
        ),
      );
      final remoteFiles = await _safeFetchFiles(
        client,
        p.posix.join('data', month),
        treatMissingAsEmpty: true,
      );
      final localFiles = await _storage.getLocalFilesInMonth(month);
      final monthEtags = await _storage.loadMonthEtags(month);
      final updatedEtags = <String, String>{};
      final prefix = 'data/$month';
      final actions = <_SyncAction>[];

      for (final entry in remoteFiles.entries) {
        final filename = entry.key;
        final remoteEtag = entry.value;
        final relative = '$prefix/$filename';
        final key = '$month/$filename';
        final cached = monthEtags[key];
        final hasLocal = localFiles.contains(filename);

        if (!hasLocal) {
          final remote = await client.downloadFile(relative);
          actions.add(
            _SyncAction(
              direction: _SyncDirection.download,
              relativePath: relative,
              etagKey: key,
              preDownloaded: remote,
              remoteEtag: remote.etag ?? remoteEtag,
            ),
          );
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
          actions.add(
            _SyncAction(
              direction: _SyncDirection.download,
              relativePath: relative,
              etagKey: key,
              preDownloaded: remote,
              remoteEtag: remote.etag ?? remoteEtag,
            ),
          );
        } else if ((remoteTs ?? 0) < localTs) {
          actions.add(
            _SyncAction(
              direction: _SyncDirection.upload,
              relativePath: relative,
              etagKey: key,
              remoteEtag: remote.etag ?? remoteEtag,
            ),
          );
        } else {
          updatedEtags[key] = remote.etag ?? remoteEtag;
        }
      }

      for (final filename in localFiles) {
        if (remoteFiles.containsKey(filename)) continue;
        final relative = '$prefix/$filename';
        final key = '$month/$filename';
        actions.add(
          _SyncAction(
            direction: _SyncDirection.upload,
            relativePath: relative,
            etagKey: key,
          ),
        );
      }

      final monthUploadCount = actions
          .where((action) => action.direction == _SyncDirection.upload)
          .length;
      final monthDownloadCount = actions
          .where((action) => action.direction == _SyncDirection.download)
          .length;
      progressTotalUpload += monthUploadCount;
      progressTotalDownload += monthDownloadCount;
      onProgress?.call(
        SyncProgress(
          stage: '准备 $month',
          detail: '预计上传 $monthUploadCount 个，下载 $monthDownloadCount 个',
          uploaded: progressUploaded,
          downloaded: progressDownloaded,
          totalUpload: progressTotalUpload,
          totalDownload: progressTotalDownload,
        ),
      );
      for (final action in actions) {
        if (action.direction == _SyncDirection.download) {
          final remote = action.preDownloaded ??
              await client.downloadFile(action.relativePath);
          await _storage.writeFileContent(action.relativePath, remote.content);
          final etagToSave = remote.etag ?? action.remoteEtag;
          if (etagToSave != null && etagToSave.isNotEmpty) {
            updatedEtags[action.etagKey] = etagToSave;
          }
          stageDownloaded++;
          progressDownloaded++;
          onProgress?.call(
            SyncProgress(
              stage: '下载 $progressDownloaded/$progressTotalDownload',
              detail: action.relativePath,
              uploaded: progressUploaded,
              downloaded: progressDownloaded,
              totalUpload: progressTotalUpload,
              totalDownload: progressTotalDownload,
            ),
          );
        } else {
          final content = await _storage.readFileContent(action.relativePath);
          final newEtag = await client.uploadFile(action.relativePath, content);
          final etagToSave = newEtag ?? action.remoteEtag;
          if (etagToSave != null && etagToSave.isNotEmpty) {
            updatedEtags[action.etagKey] = etagToSave;
          }
          stageUploaded++;
          progressUploaded++;
          onProgress?.call(
            SyncProgress(
              stage: '上传 $progressUploaded/$progressTotalUpload',
              detail: action.relativePath,
              uploaded: progressUploaded,
              downloaded: progressDownloaded,
              totalUpload: progressTotalUpload,
              totalDownload: progressTotalDownload,
            ),
          );
        }
      }
      await _storage.saveMonthEtags(month, updatedEtags);
      onProgress?.call(
        SyncProgress(
          stage: '完成 $month',
          detail: '本月同步完成',
          uploaded: progressUploaded,
          downloaded: progressDownloaded,
          totalUpload: progressTotalUpload,
          totalDownload: progressTotalDownload,
        ),
      );
    }

    return _SyncCounters(
      uploaded: stageUploaded,
      downloaded: stageDownloaded,
    );
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
