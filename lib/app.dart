import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/platform.dart';
import 'pages/home/home_shell.dart';
import 'services/time_tracking_controller.dart';

class AtimeLogApp extends StatefulWidget {
  const AtimeLogApp({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<AtimeLogApp> createState() => _AtimeLogAppState();
}

class _AtimeLogAppState extends State<AtimeLogApp>
    with WindowListener, TrayListener {
  late Future<void> _initFuture;
  bool _trayReady = false;
  bool get _supportsTrayPopup => supportsTrayPopup;

  @override
  void initState() {
    super.initState();
    _initFuture = widget.controller.init();
    if (isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      unawaited(_initSystemTray());
    }
  }

  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      trayManager.destroy();
    }
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    final iconPath = trayIconPath();
    if (iconPath == null) {
      return;
    }
    try {
      await trayManager.setIcon(iconPath);
      if (!Platform.isLinux) {
        await trayManager.setToolTip('AtimeLog');
      }
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open-panel', label: '打开面板'),
            MenuItem.separator(),
            MenuItem(key: 'exit-app', label: '退出'),
          ],
        ),
      );
      _trayReady = true;
    } catch (error) {
      debugPrint('初始化托盘失败: $error');
    }
  }

  Future<void> _hideToTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> _restoreFromTray() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exitFromTray() async {
    if (!isDesktop) {
      return;
    }
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onTrayIconMouseDown() {
    if (_trayReady && _supportsTrayPopup) {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_trayReady && _supportsTrayPopup) {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (!_trayReady) {
      return;
    }
    switch (menuItem.key) {
      case 'open-panel':
        unawaited(_restoreFromTray());
        break;
      case 'exit-app':
        unawaited(_exitFromTray());
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (!isDesktop) {
      return;
    }
    final preventClose = await windowManager.isPreventClose();
    if (preventClose) {
      if (_trayReady) {
        await _hideToTray();
      } else {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      }
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            theme: _buildTheme(Brightness.light),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            theme: _buildTheme(Brightness.light),
            home: Scaffold(
              body: Center(child: Text('初始化失败: ${snapshot.error}')),
            ),
          );
        }
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final darkMode = widget.controller.settings.darkMode;
            return MaterialApp(
              title: 'AtimeLog',
              theme: _buildTheme(Brightness.light),
              darkTheme: _buildTheme(Brightness.dark),
              themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
              home: HomeShell(controller: widget.controller),
            );
          },
        );
      },
    );
  }
}
