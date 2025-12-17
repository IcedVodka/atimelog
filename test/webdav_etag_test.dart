import 'dart:convert';
import 'dart:io';

import 'package:atimelog_demo/services/webdav_client.dart';

/// 简单的 WebDAV 上传/获取 ETag 自测脚本。
///
/// 用法（任选其一）：
/// 1) 通过参数：
///    dart run tool/webdav_etag_test.dart --url https://dav.example.com/remote.php/dav/files/me --user alice --pass secret --root /atimelog_data
/// 2) 通过环境变量：
///    WEBDAV_URL, WEBDAV_USER, WEBDAV_PASS, WEBDAV_ROOT (默认 /atimelog_data)
///
/// 成功时会输出服务端返回的 ETag 以及重新下载时拿到的 ETag。
Future<void> main(List<String> args) async {
  final params = _parseArgs(args);
  final url = params['url'] ?? Platform.environment['WEBDAV_URL'];
  final user = params['user'] ?? Platform.environment['WEBDAV_USER'] ?? '';
  final pass = params['pass'] ?? Platform.environment['WEBDAV_PASS'] ?? '';
  final root =
      params['root'] ?? Platform.environment['WEBDAV_ROOT'] ?? '/atimelog_data';

  if (url == null || url.trim().isEmpty) {
    stdout.writeln('缺少 WebDAV 地址，请使用 --url 或环境变量 WEBDAV_URL 设置。');
    return;
  }

  final client = WebDavClient(
    baseUrl: url.trim(),
    username: user.trim(),
    password: pass,
    rootPath: root.trim(),
  );

  final now = DateTime.now().toIso8601String().replaceAll(':', '-');
  final relativePath = 'current/etag_smoke_$now.json';
  final payload = {
    'hello': 'etag-smoke-test',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'note': '临时文件，可随时删除',
  };
  stdout.writeln('上传路径: $relativePath');
  try {
    await client.ensureDirectory('current');
    final uploadedEtag =
        await client.uploadFile(relativePath, jsonEncode(payload));
    stdout.writeln('上传完成，返回 ETag: $uploadedEtag');
    final downloaded = await client.downloadFile(relativePath);
    stdout.writeln('下载完成，响应 ETag: ${downloaded.etag}');
    stdout.writeln('ETag 是否一致: ${uploadedEtag == downloaded.etag}');
    stdout.writeln('下载内容: ${downloaded.content}');
  } catch (error, stack) {
    stderr.writeln('测试失败: $error');
    stderr.writeln(stack);
  } finally {
    await client.close();
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);
    final next = i + 1 < args.length ? args[i + 1] : null;
    if (next != null && !next.startsWith('--')) {
      map[key] = next;
      i++;
    } else {
      map[key] = 'true';
    }
  }
  return map;
}
