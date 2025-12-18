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
  final exeDir = File(Platform.resolvedExecutable).parent;
  if (Platform.isWindows) {
    final winCandidates = [
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
    for (final path in winCandidates) {
      if (File(path).existsSync()) {
        return path;
      }
    }
    return 'assets/clock.ico';
  }

  final unixCandidates = <String>[
    p.join(
      exeDir.path,
      'data',
      'flutter_assets',
      'assets',
      'clock.png',
    ),
    p.join(
      Directory.current.path,
      'data',
      'flutter_assets',
      'assets',
      'clock.png',
    ),
    p.join(Directory.current.path, 'assets', 'clock.png'),
  ];
  if (Platform.isMacOS) {
    unixCandidates.insert(
      1,
      p.normalize(
        p.join(
          exeDir.path,
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          'assets',
          'clock.png',
        ),
      ),
    );
  }
  for (final path in unixCandidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return 'assets/clock.png';
}
