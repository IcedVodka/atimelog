import 'package:flutter/material.dart';

import '../../models/time_models.dart';
import '../../services/time_tracking_controller.dart';

class CategoryManageTab extends StatefulWidget {
  const CategoryManageTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<CategoryManageTab> createState() => _CategoryManageTabState();
}

class _CategoryManageTabState extends State<CategoryManageTab> {
  final List<Color> _palette = const [
    Color(0xFF1565C0), // 蓝
    Color(0xFF1E88E5),
    Color(0xFF90CAF9),
    Color(0xFF0D47A1),
    Color(0xFF6A1B9A), // 紫
    Color(0xFF8E24AA),
    Color(0xFFBA68C8),
    Color(0xFF9C27B0),
    Color(0xFFC2185B), // 粉
    Color(0xFFE91E63),
    Color(0xFFFF80AB),
    Color(0xFFD81B60),
    Color(0xFF00897B), // 青
    Color(0xFF26A69A),
    Color(0xFF26C6DA),
    Color(0xFF4DD0E1),
    Color(0xFF2E7D32), // 绿
    Color(0xFF43A047),
    Color(0xFF81C784),
    Color(0xFFA5D6A7),
    Color(0xFFFFB300), // 黄/橙
    Color(0xFFFFD54F),
    Color(0xFFFF8F00),
    Color(0xFFFF7043),
    Color(0xFF6D4C41), // 棕
    Color(0xFF8D6E63),
    Color(0xFF455A64), // 深灰
    Color(0xFF607D8B),
    Color(0xFF9E9E9E),
  ];
  final List<IconData> _iconOptions = const [
    Icons.computer,
    Icons.hotel_outlined,
    Icons.movie_filter_outlined,
    Icons.fitness_center,
    Icons.sports_esports,
    Icons.home,
    Icons.people,
    Icons.book_outlined,
    Icons.shopping_cart,
    Icons.work_outline,
    Icons.fastfood,
    Icons.code,
    Icons.brush_outlined,
    Icons.music_note,
    Icons.pets,
    Icons.child_friendly,
    Icons.school,
    Icons.car_rental,
    Icons.self_improvement,
    Icons.travel_explore,
    Icons.coffee,
    Icons.nightlight_round,
    Icons.camera_alt_outlined,
    Icons.flight_takeoff,
    Icons.hiking,
    Icons.public,
    Icons.lightbulb_outline,
    Icons.laptop_mac,
    Icons.directions_bike,
    Icons.local_hospital,
    Icons.mediation,
    Icons.palette_outlined,
    Icons.waves,
    Icons.timer,
    Icons.restaurant_menu,
    Icons.spa,
    Icons.emoji_events,
    Icons.handyman_outlined,
    Icons.build_circle_outlined,
    Icons.cake_outlined,
  ];
  int? _draggingIndex;

  List<IconData> _buildIconOptions(IconData current) {
    final seen = <String>{};
    final result = <IconData>[];
    String keyFor(IconData icon) =>
        '${icon.fontFamily ?? 'MaterialIcons'}-${icon.codePoint}';
    void addIcon(IconData icon) {
      final key = keyFor(icon);
      if (seen.add(key)) {
        result.add(icon);
      }
    }

    addIcon(current);
    for (final icon in _iconOptions) {
      addIcon(icon);
    }
    return result;
  }

  String _deriveGroupFromName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parts = trimmed.split('.');
    if (parts.length >= 2 && parts.first.trim().isNotEmpty) {
      return parts.first.trim();
    }
    return trimmed;
  }

  int _resolveCrossAxisCount(double width) {
    if (width >= 1080) return 4;
    if (width >= 860) return 3;
    return 2;
  }

  Future<void> _handleGridReorder(
    int from,
    int to,
    List<CategoryModel> categories,
  ) async {
    if (from == to) {
      return;
    }
    final updated = [...categories];
    final item = updated.removeAt(from);
    updated.insert(to, item);
    await widget.controller.reorderCategories(updated);
    setState(() {});
  }

  Widget _buildDraggableCategoryTile({
    required List<CategoryModel> categories,
    required int index,
    required double itemWidth,
  }) {
    final cat = categories[index];
    final groupLabel = _deriveGroupFromName(cat.name);
    Widget buildCard({required bool ghost, required bool isTargeted}) {
      return _categoryCard(
        cat,
        groupLabel: groupLabel,
        ghost: ghost,
        isTargeted: isTargeted,
        dragging: _draggingIndex == index,
      );
    }

    final placeholder = buildCard(ghost: true, isTargeted: false);

    return Draggable<int>(
      data: index,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: itemWidth, minWidth: itemWidth),
          child: buildCard(ghost: false, isTargeted: true),
        ),
      ),
      onDragStarted: () => setState(() => _draggingIndex = index),
      onDraggableCanceled: (_, unusedVelocity) =>
          setState(() => _draggingIndex = null),
      onDragEnd: (_) => setState(() => _draggingIndex = null),
      childWhenDragging: Opacity(
        opacity: 0.25,
        child: IgnorePointer(child: placeholder),
      ),
      child: DragTarget<int>(
        onWillAccept: (from) => from != null && from != index,
        onAccept: (from) => _handleGridReorder(from, index, categories),
        builder: (context, candidate, rejected) {
          final isTargeted = candidate.isNotEmpty;
          return buildCard(ghost: false, isTargeted: isTargeted);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final categories = [...widget.controller.allCategories]
          ..sort((a, b) => a.order.compareTo(b.order));
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '分类管理',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCategoryEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('新增'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '按住卡片或右上角拖拽图标即可排序 · 栅格自适应宽度填充屏幕',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = _resolveCrossAxisCount(
                      constraints.maxWidth,
                    );
                    final itemWidth =
                        (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                        crossAxisCount;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.55,
                      ),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        return _buildDraggableCategoryTile(
                          categories: categories,
                          index: index,
                          itemWidth: itemWidth,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryCard(
    CategoryModel cat, {
    required String groupLabel,
    bool isTargeted = false,
    bool dragging = false,
    bool ghost = false,
  }) {
    final resolvedGroup = groupLabel.isEmpty ? cat.name : groupLabel;
    final theme = Theme.of(context);
    final isDeleted = cat.deleted;
    final borderColor = isTargeted
        ? theme.colorScheme.primary
        : cat.color.withOpacity(0.25);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: ghost
            ? theme.colorScheme.surfaceVariant.withOpacity(0.2)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isTargeted ? 1.6 : 1),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: cat.color.withOpacity(0.12),
                child: Icon(cat.iconData, color: cat.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cat.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (isDeleted)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '已删除（仅配置文件）',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    Text(
                      resolvedGroup,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: cat.enabled,
                onChanged: isDeleted
                    ? null
                    : (val) => widget.controller.toggleCategory(cat.id, val),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('顺序 ${cat.order}', style: theme.textTheme.bodySmall),
              const Spacer(),
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit),
                onPressed: () => _showCategoryEditor(existing: cat),
              ),
              IconButton(
                tooltip: '删除（从配置移除，不影响历史数据）',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _deleteCategory(cat),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryEditor({CategoryModel? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    Color color = existing?.color ?? _palette.first;
    IconData icon = existing?.iconData ?? _iconOptions.first;
    String derivedGroup = _deriveGroupFromName(nameController.text);
    bool enabled = existing?.enabled ?? true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? '新增分类' : '编辑分类'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      helperText: '使用“群组.子类”自动分组，例如：睡眠.午睡',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        derivedGroup = _deriveGroupFromName(value);
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '当前群组: ${derivedGroup.isEmpty ? '填写名称后自动生成' : derivedGroup}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _palette
                        .map(
                          (c) => GestureDetector(
                            onTap: () => setDialogState(() => color = c),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: color == c
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '图标',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _buildIconOptions(icon)
                        .map(
                          (opt) => ChoiceChip(
                            label: Icon(
                              opt,
                              color: opt == icon
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                            ),
                            selected: opt == icon,
                            selectedColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onSelected: (_) => setDialogState(() => icon = opt),
                          ),
                        )
                        .toList(),
                  ),
                  SwitchListTile(
                    title: const Text('启用'),
                    value: enabled,
                    onChanged: (val) => setDialogState(() => enabled = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      return;
    }
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('名称不能为空');
      return;
    }
    final parsedGroup = _deriveGroupFromName(name);
    final id = existing?.id ?? _buildCategoryId(name);
    final updated = CategoryModel(
      id: id,
      name: name,
      iconCode: icon.codePoint,
      colorHex: colorToHex(color),
      order: existing?.order ?? widget.controller.allCategories.length,
      enabled: enabled,
      group: parsedGroup,
    );
    await widget.controller.addOrUpdateCategory(updated);
  }

  String _buildCategoryId(String name) {
    final base = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final exists = widget.controller.allCategories.any(
      (element) => element.id == base,
    );
    if (!exists) {
      return base;
    }
    return '${base}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: const Text('将从 categories.json 中移除该分类，历史数据不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.controller.removeCategory(cat.id);
    if (!mounted) return;
    _showSnack('已删除 ${cat.name}');
  }
}
