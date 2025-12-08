// 引入 Flutter 的 UI 库 (Material Design 风格)
import 'package:flutter/material.dart';

// 程序入口，类似 Python 的 if __name__ == "__main__":
void main() {
  runApp(const MyApp());
}

// 1. 定义 App 的根组件
// StatelessWidget 意味着这个组件自己没有“状态”变化（比如数字加减）
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp 是整个 APP 的最外层包装，提供主题、导航等
    return MaterialApp(
      title: 'AtimeLog Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue, // 定义主题色
      ),
      home: const HomePage(), // 指定 App 打开后显示的第一个页面
    );
  }
}

// 2. 定义主页面
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Scaffold (脚手架) 提供了标准的页面结构：顶栏、内容区、悬浮按钮等
    return Scaffold(
      // AppBar: 顶部的标题栏
      appBar: AppBar(
        title: const Text('我的时间记录'),
        backgroundColor: Colors.blue,
      ),
      // Body: 页面中间的内容
      body: Center( // Center 组件把子元素居中
        child: Column( // Column 组件让子元素垂直排列
          mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
          children: <Widget>[
            const Text(
              '你好，未来的 Atimelog!', 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20), // 也就是加个空行
            const Text('这是你在 Linux 上跑起来的第一个 Flutter 页面'),
          ],
        ),
      ),
      // FloatingActionButton: 右下角的悬浮按钮
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          print("你点击了按钮！看终端输出！"); // 类似 Python print
        },
        child: const Icon(Icons.timer), // 一个闹钟图标
      ),
    );
  }
}