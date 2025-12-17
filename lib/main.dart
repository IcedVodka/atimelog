import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/desktop_window.dart';
import 'services/time_storage_service.dart';
import 'services/time_tracking_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDesktopWindow();
  await initializeDateFormatting('zh_CN', null);
  Intl.defaultLocale = 'zh_CN';
  final controller = TimeTrackingController(TimeStorageService());
  runApp(AtimeLogApp(controller: controller));
}
