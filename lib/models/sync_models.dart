class SyncConfig {
  const SyncConfig({
    required this.enabled,
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
    required this.autoIntervalMinutes,
  });

  final bool enabled;
  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final int autoIntervalMinutes;

  SyncConfig copyWith({
    bool? enabled,
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
    int? autoIntervalMinutes,
  }) {
    return SyncConfig(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      autoIntervalMinutes: autoIntervalMinutes ?? this.autoIntervalMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'remotePath': remotePath,
      'autoIntervalMinutes': autoIntervalMinutes,
    };
  }

  factory SyncConfig.fromJson(Map<String, dynamic> json) {
    return SyncConfig(
      enabled: json['enabled'] as bool? ?? false,
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/atimelog_data',
      autoIntervalMinutes: json['autoIntervalMinutes'] as int? ?? 30,
    );
  }

  static SyncConfig defaults() {
    return const SyncConfig(
      enabled: false,
      serverUrl: '',
      username: '',
      password: '',
      remotePath: '/atimelog_data',
      autoIntervalMinutes: 30,
    );
  }

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty && remotePath.trim().isNotEmpty;

  bool get shouldAutoSync =>
      enabled && isConfigured && autoIntervalMinutes > 0;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class SyncProgress {
  const SyncProgress({
    required this.stage,
    this.detail,
    this.uploaded = 0,
    this.downloaded = 0,
    this.totalUpload = 0,
    this.totalDownload = 0,
  });

  final String stage;
  final String? detail;
  final int uploaded;
  final int downloaded;
  final int totalUpload;
  final int totalDownload;
}

class SyncStatus {
  const SyncStatus({
    required this.syncing,
    required this.verifying,
    this.lastSyncTime,
    this.lastSyncSucceeded,
    this.lastSyncMessage,
    this.lastDuration,
    this.lastUploadCount = 0,
    this.lastDownloadCount = 0,
    this.progress,
  });

  final bool syncing;
  final bool verifying;
  final DateTime? lastSyncTime;
  final bool? lastSyncSucceeded;
  final String? lastSyncMessage;
  final Duration? lastDuration;
  final int lastUploadCount;
  final int lastDownloadCount;
  final SyncProgress? progress;

  SyncStatus copyWith({
    bool? syncing,
    bool? verifying,
    DateTime? lastSyncTime,
    bool? lastSyncSucceeded,
    String? lastSyncMessage,
    Duration? lastDuration,
    int? lastUploadCount,
    int? lastDownloadCount,
    SyncProgress? progress,
    bool clearProgress = false,
  }) {
    return SyncStatus(
      syncing: syncing ?? this.syncing,
      verifying: verifying ?? this.verifying,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSyncSucceeded: lastSyncSucceeded ?? this.lastSyncSucceeded,
      lastSyncMessage: lastSyncMessage ?? this.lastSyncMessage,
      lastDuration: lastDuration ?? this.lastDuration,
      lastUploadCount: lastUploadCount ?? this.lastUploadCount,
      lastDownloadCount: lastDownloadCount ?? this.lastDownloadCount,
      progress: clearProgress ? null : (progress ?? this.progress),
    );
  }

  factory SyncStatus.initial() {
    return const SyncStatus(
      syncing: false,
      verifying: false,
      lastUploadCount: 0,
      lastDownloadCount: 0,
      progress: null,
    );
  }
}

class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    required this.uploaded,
    required this.downloaded,
    required this.duration,
  });

  final bool success;
  final String message;
  final int uploaded;
  final int downloaded;
  final Duration duration;
}
