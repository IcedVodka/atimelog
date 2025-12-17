import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class WebDavEntry {
  const WebDavEntry({
    required this.path,
    required this.isCollection,
    this.etag,
  });

  final String path;
  final bool isCollection;
  final String? etag;
}

class DownloadedRemoteFile {
  const DownloadedRemoteFile({required this.content, this.etag});

  final String content;
  final String? etag;
}

class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required String username,
    required String password,
    required String rootPath,
    http.Client? client,
  }) : _baseUrl = baseUrl,
       _username = username,
       _password = password,
       _rootPath = rootPath,
       _client = client ?? http.Client();

  final String _baseUrl;
  final String _username;
  final String _password;
  final String _rootPath;
  final http.Client _client;

  Uri _buildUri(String relativePath) {
    final baseUri = Uri.parse(_baseUrl);
    final cleanedRoot = _rootPath.replaceFirst(RegExp('^/+'), '');
    final cleanedRelative = relativePath.replaceFirst(RegExp('^/+'), '');
    final joined = cleanedRelative.isEmpty
        ? cleanedRoot
        : p.posix.join(cleanedRoot, cleanedRelative);
    final normalized = p.posix.normalize(joined);
    final mergedPath = baseUri.path.isEmpty || baseUri.path == '/'
        ? '/$normalized'
        : p.posix.normalize(p.posix.join(baseUri.path, normalized));
    return baseUri.replace(path: mergedPath);
  }

  Map<String, String> _authHeaders({int? depth}) {
    final headers = <String, String>{
      'Accept': '*/*',
    };
    if (_username.isNotEmpty || _password.isNotEmpty) {
      final token = base64.encode(utf8.encode('$_username:$_password'));
      headers['Authorization'] = 'Basic $token';
    }
    if (depth != null) {
      headers['Depth'] = depth.toString();
    }
    return headers;
  }

  Future<List<WebDavEntry>> _propfind(
    String relativePath, {
    int depth = 1,
    bool includeSelf = false,
  }) async {
    final targetPath = () {
      if (relativePath.isEmpty) return relativePath;
      if (relativePath.endsWith('/')) return relativePath;
      // depth>0 一般用于目录，补一个斜杠以兼容部分服务端；depth=0 通常是文件，保持原样。
      return depth > 0 ? '$relativePath/' : relativePath;
    }();
    final uri = _buildUri(targetPath);
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll(_authHeaders(depth: depth))
      ..headers['Content-Type'] = 'text/xml'
      ..body =
          '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:">'
          '<d:prop><d:getetag/><d:resourcetype/></d:prop>'
          '</d:propfind>';
    final response = await _client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw HttpException(
        'PROPFIND ${uri.path} 失败: ${response.statusCode}',
      );
    }
    return _parsePropfind(body, uri.path, includeSelf: includeSelf);
  }

  List<WebDavEntry> _parsePropfind(
    String xmlBody,
    String requestedPath, {
    required bool includeSelf,
  }) {
    final entries = <WebDavEntry>[];
    final doc = XmlDocument.parse(xmlBody);
    final normalizedRequested = _stripTrailingSlash(requestedPath);

    for (final response in doc.findAllElements('response', namespace: '*')) {
      final hrefNode = _first(response.findElements('href', namespace: '*'));
      if (hrefNode == null) {
        continue;
      }
      final hrefText = Uri.decodeFull(hrefNode.innerText.trim());
      final hrefPath = _stripTrailingSlash(_extractPathFromHref(hrefText));
      if (!includeSelf && hrefPath == normalizedRequested) {
        // 跳过自身
        continue;
      }
      final typeNode =
          _first(response.findAllElements('resourcetype', namespace: '*'));
      final isCollection = typeNode
              ?.findAllElements('collection', namespace: '*')
              .isNotEmpty ==
          true;
      final etagNode = _first(response.findAllElements('getetag', namespace: '*'));
      final etag = etagNode?.innerText.trim().replaceAll('"', '');
      final relative = _relativeFromRequested(normalizedRequested, hrefPath);
      entries.add(WebDavEntry(path: relative, isCollection: isCollection, etag: etag));
    }
    return entries;
  }

  String _relativeFromRequested(String requested, String hrefPath) {
    if (hrefPath.startsWith(requested)) {
      final trimmed = hrefPath.substring(requested.length);
      final cleaned = trimmed.replaceFirst(RegExp('^/+'), '');
      if (cleaned.isEmpty) {
        return p.posix.basename(hrefPath);
      }
      return cleaned;
    }
    return hrefPath.replaceFirst(RegExp('^/+'), '');
  }

  String _extractPathFromHref(String href) {
    if (href.startsWith('http')) {
      final uri = Uri.parse(href);
      return uri.path;
    }
    return href;
  }

  XmlElement? _first(Iterable<XmlElement> nodes) {
    if (nodes.isEmpty) {
      return null;
    }
    return nodes.first;
  }

  String _stripTrailingSlash(String value) {
    if (value.endsWith('/') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<bool> exists(String relativePath) async {
    final uri = _buildUri(relativePath);
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll(_authHeaders(depth: 0))
      ..headers['Content-Type'] = 'text/xml';
    final response = await _client.send(request);
    return response.statusCode < 400;
  }

  Future<void> ensureDirectory(String relativePath) async {
    final normalized =
        relativePath.replaceFirst(RegExp('^/+'), '').replaceAll('\\', '/');
    if (normalized.isEmpty) {
      return;
    }
    final segments = normalized.split('/');
    var current = '';
    for (final seg in segments) {
      if (seg.trim().isEmpty) continue;
      current = current.isEmpty ? seg : p.posix.join(current, seg);
      if (await exists('$current/')) {
        continue;
      }
      final uri = _buildUri('$current/');
      final request = http.Request('MKCOL', uri)
        ..headers.addAll(_authHeaders());
      final response = await _client.send(request);
      if (response.statusCode >= 400 && response.statusCode != 405) {
        throw HttpException('创建目录 $current 失败: ${response.statusCode}');
      }
    }
  }

  Future<List<String>> listRemoteSubdirectories(String relativePath) async {
    final entries = await _propfind(relativePath, depth: 1);
    return entries
        .where((e) => e.isCollection)
        .map((e) => _stripTrailingSlash(p.posix.basename(e.path)))
        .where((element) => element.isNotEmpty)
        .toList();
  }

  Future<Map<String, String>> fetchFolderFileList(String relativePath) async {
    final entries = await _propfind(relativePath, depth: 1);
    final map = <String, String>{};
    for (final entry in entries.where((e) => !e.isCollection)) {
      final name = p.posix.basename(entry.path);
      if (!name.toLowerCase().endsWith('.json')) {
        continue;
      }
      if (entry.etag != null && entry.etag!.isNotEmpty) {
        map[name] = entry.etag!;
      }
    }
    return map;
  }

  Future<DownloadedRemoteFile> downloadFile(String relativePath) async {
    final uri = _buildUri(relativePath);
    final response = await _client.get(uri, headers: _authHeaders());
    if (response.statusCode >= 400) {
      throw HttpException('下载失败 ${response.statusCode}');
    }
    final etag = response.headers['etag'] ?? response.headers['ETag'];
    return DownloadedRemoteFile(content: utf8.decode(response.bodyBytes), etag: etag?.replaceAll('"', ''));
  }

  Future<String?> uploadFile(String relativePath, String content) async {
    final parent = p.posix.dirname(relativePath);
    if (parent != '.' && parent.isNotEmpty) {
      await ensureDirectory(parent);
    }
    final uri = _buildUri(relativePath);
    final response = await _client.put(
      uri,
      headers: _authHeaders()..['Content-Type'] = 'application/json',
      body: utf8.encode(content),
    );
    if (response.statusCode >= 400) {
      throw HttpException('上传失败 ${response.statusCode}');
    }
    final etag = response.headers['etag'] ?? response.headers['ETag'];
    if (etag != null && etag.isNotEmpty) {
      return etag.replaceAll('"', '');
    }
    return await _fetchEtag(relativePath);
  }

  Future<void> close() async {
    _client.close();
  }

  Future<void> ping() async {
    final uri = _buildUri('');
    final response = await _client.send(
      http.Request('PROPFIND', uri)..headers.addAll(_authHeaders(depth: 0)),
    );
    if (response.statusCode >= 400) {
      throw HttpException('连接失败: ${response.statusCode}');
    }
  }

  Future<String?> _fetchEtag(String relativePath) async {
    final entries = await _propfind(relativePath, depth: 0, includeSelf: true);
    for (final entry in entries) {
      if (entry.isCollection) continue;
      if (entry.etag != null && entry.etag!.isNotEmpty) {
        return entry.etag;
      }
    }
    return null;
  }
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
