import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get supportsTrayPopup => isDesktop && !Platform.isLinux;

String? trayIconPath() {
  if (!isDesktop) {
    return null;
  }
  if (Platform.isWindows) {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      p.join(
        exeDir.path,
        'data',
        'flutter_assets',
        'assets',
        'clock.ico',
      ),
      p.join(
        Directory.current.path,
        'data',
        'flutter_assets',
        'assets',
        'clock.ico',
      ),
      p.join(Directory.current.path, 'assets', 'clock.ico'),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
  }
  return Platform.isWindows ? 'assets/clock.ico' : 'assets/clock.png';
}
