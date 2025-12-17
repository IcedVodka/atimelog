import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'platform.dart';

Future<void> initDesktopWindow() async {
  if (!isDesktop) {
    return;
  }
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    title: 'AtimeLog',
    minimumSize: Size(420, 640),
  );
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
