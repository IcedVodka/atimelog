import 'dart:io';

import 'package:flutter/foundation.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool get supportsTrayPopup => isDesktop && !Platform.isLinux;

String? trayIconPath() {
  if (!isDesktop) {
    return null;
  }
  return Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';
}
