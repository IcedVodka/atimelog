import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/desktop_window.dart';
import 'services/time_storage_service.dart';
import 'services/time_tracking_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    runApp(const _WebUnsupportedApp());
    return;
  }
  await initDesktopWindow();
  await initializeDateFormatting('zh_CN', null);
  Intl.defaultLocale = 'zh_CN';
  final controller = TimeTrackingController(TimeStorageService());
  runApp(AtimeLogApp(controller: controller));
}

class _WebUnsupportedApp extends StatelessWidget {
  const _WebUnsupportedApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            '当前工程依赖本地文件系统和托盘等桌面能力，暂不支持 Web 端运行。\n请使用 Windows/macOS/Linux/Android/iOS 设备启动。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
