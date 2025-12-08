import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/time_models.dart';
import 'services/time_storage_service.dart';
import 'services/time_tracking_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AtimeLog Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class CategoryDefinition {
  const CategoryDefinition(this.id, this.name, this.icon);

  final String id;
  final String name;
  final IconData icon;
}

const _categories = <CategoryDefinition>[
  CategoryDefinition('work', '工作', Icons.work_outline),
  CategoryDefinition('study', '学习', Icons.school_outlined),
  CategoryDefinition('life', '生活', Icons.self_improvement),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TimeTrackingController _controller;
  late final Future<void> _initFuture;
  final TextEditingController _noteController = TextEditingController();
  String _selectedCategory = _categories.first.id;

  @override
  void initState() {
    super.initState();
    _controller = TimeTrackingController(TimeStorageService());
    _initFuture = _controller.init().then((_) {
      if (!mounted) {
        return;
      }
      if (_controller.currentNote.isNotEmpty) {
        _noteController.text = _controller.currentNote;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人时间记录 P1 Demo'),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('初始化失败: ${snapshot.error}'));
          }
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTimerCard(),
                  const SizedBox(height: 16),
                  _buildNoteInput(),
                  const SizedBox(height: 16),
                  _buildCategorySelector(),
                  const SizedBox(height: 16),
                  _buildRecentContexts(),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTimerCard() {
    final isRunning = _controller.isRunning;
    final duration = _controller.currentDuration;
    final colorScheme = Theme.of(context).colorScheme;
    final title = isRunning ? '计时进行中' : '尚未开始';
    final note = _controller.currentNote.isEmpty ? '请先输入想做的事情' : _controller.currentNote;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              note,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              _formatDuration(duration),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 24),
            if (isRunning)
              FilledButton.icon(
                icon: const Icon(Icons.stop_circle_outlined),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
                onPressed: _controller.isRunning ? _stopTimer : null,
                label: const Text('停止并归档'),
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: _noteController.text.trim().isEmpty ? null : _startNew,
                label: const Text('开始全新计时'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteInput() {
    return TextField(
      controller: _noteController,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: '记录内容',
        hintText: '例如：编写需求文档',
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _categories
              .map(
                (category) => ChoiceChip(
                  label: Text(category.name),
                  avatar: Icon(category.icon, size: 18),
                  selected: _selectedCategory == category.id,
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = category.id;
                    });
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRecentContexts() {
    final contexts = _controller.recentContexts;
    if (contexts.isEmpty) {
      return const Text(
        '最近没有上下文记录，完成一次计时后就会出现快捷续记入口。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近做过', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: contexts
              .map(
                (contextItem) => ActionChip(
                  label: Text('${contextItem.note} · ${_formatLastActive(contextItem.lastActiveTime)}'),
                  avatar: const Icon(Icons.refresh),
                  onPressed: () => _resumeContext(contextItem),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Future<void> _startNew() async {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      _showSnack('请先输入内容');
      return;
    }
    try {
      await _controller.startNewActivity(
        categoryId: _selectedCategory,
        note: note,
      );
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _stopTimer() async {
    try {
      await _controller.stopCurrentActivity();
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _resumeContext(RecentContext contextItem) async {
    _noteController.text = contextItem.note;
    try {
      await _controller.resumeFromContext(contextItem);
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write(hours.toString().padLeft(2, '0'));
    buffer.write(':');
  }
  buffer.write(minutes.toString().padLeft(2, '0'));
  buffer.write(':');
  buffer.write(seconds.toString().padLeft(2, '0'));
  return buffer.toString();
}

String _formatLastActive(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  return DateFormat('MM-dd HH:mm').format(time);
}
