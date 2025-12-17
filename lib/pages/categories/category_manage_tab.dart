import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/common_icons.dart';
import '../../models/time_models.dart';
import '../../services/time_tracking_controller.dart';

class CategoryManageTab extends StatefulWidget {
  const CategoryManageTab({super.key, required this.controller});

  final TimeTrackingController controller;

  @override
  State<CategoryManageTab> createState() => _CategoryManageTabState();
}

class _CategoryManageTabState extends State<CategoryManageTab> {
  final List<MaterialColor> _colorFamilies = const [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.blueGrey,
    Colors.grey,
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
    for (final icon in commonIcons) {
      addIcon(icon);
    }
    return result;
  }

  List<Color> _shadeCandidates(MaterialColor family) {
    const shadeKeys = [300, 500, 700, 900];
    return shadeKeys
        .map((key) => family[key] ?? family.shade500)
        .toList(growable: false);
  }

  MaterialColor _matchColorFamily(Color target) {
    MaterialColor? bestFamily;
    var bestScore = 1 << 30;

    for (final family in _colorFamilies) {
      for (final shade in _shadeCandidates(family)) {
        final score = (target.red - shade.red).abs() +
            (target.green - shade.green).abs() +
            (target.blue - shade.blue).abs();
        if (score < bestScore) {
          bestScore = score;
          bestFamily = family;
        }
      }
    }

    return bestFamily ?? Colors.blue;
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
    final count = (width / 100).floor();
    return max(4, min(8, count));
  }

  Future<void> _handleGridReorder({
    required String fromId,
    required int to,
    required List<CategoryModel> categories,
  }) async {
    final from = categories.indexWhere((element) => element.id == fromId);
    if (from == -1 || from == to) {
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
    required double itemHeight,
  }) {
    final cat = categories[index];
    final groupLabel = _deriveGroupFromName(cat.name);
    Widget buildTile({required bool ghost, required bool isTargeted}) {
      return _categoryTile(
        cat,
        groupLabel: groupLabel,
        ghost: ghost,
        isTargeted: isTargeted,
        dragging: _draggingIndex == index,
      );
    }

    return LongPressDraggable<String>(
      data: cat.id,
      maxSimultaneousDrags: 1,
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: itemWidth,
          height: itemHeight,
          child: buildTile(ghost: false, isTargeted: true),
        ),
      ),
      onDragStarted: () => setState(() => _draggingIndex = index),
      onDraggableCanceled: (_, __) => setState(() => _draggingIndex = null),
      onDragEnd: (_) => setState(() => _draggingIndex = null),
      childWhenDragging: Opacity(
        opacity: 0.22,
        child: IgnorePointer(
          child: buildTile(ghost: true, isTargeted: false),
        ),
      ),
      child: DragTarget<String>(
        onWillAccept: (from) => from != null && from != cat.id,
        onAccept: (fromId) => _handleGridReorder(
          fromId: fromId,
          to: index,
          categories: categories,
        ),
        builder: (context, candidate, rejected) {
          final isTargeted = candidate.isNotEmpty;
          return buildTile(ghost: false, isTargeted: isTargeted);
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
                    '长按卡片即可拖动排序 · 布局与分类网格一致，依然支持新增和编辑',
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
                    const spacing = 10.0;
                    const tileAspectRatio = 0.78;
                    final itemWidth =
                        (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                        crossAxisCount;
                    final itemHeight = itemWidth / tileAspectRatio;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                        childAspectRatio: tileAspectRatio,
                      ),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        return _buildDraggableCategoryTile(
                          categories: categories,
                          index: index,
                          itemWidth: itemWidth,
                          itemHeight: itemHeight,
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

  Widget _categoryTile(
    CategoryModel cat, {
    required String groupLabel,
    bool isTargeted = false,
    bool dragging = false,
    bool ghost = false,
  }) {
    final resolvedGroup = groupLabel.isEmpty ? cat.name : groupLabel;
    final theme = Theme.of(context);
    final isDeleted = cat.deleted;
    final isDisabled = !cat.enabled;
    final baseColor = cat.color;
    final displayColor =
        (isDisabled || isDeleted) ? baseColor.withOpacity(0.45) : baseColor;
    final borderColor = isTargeted
        ? theme.colorScheme.primary
        : displayColor.withOpacity(0.55);
    final background = ghost
        ? theme.colorScheme.surfaceVariant.withOpacity(0.18)
        : theme.colorScheme.surfaceVariant.withOpacity(
            theme.brightness == Brightness.dark ? 0.36 : 0.52,
          );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isTargeted ? 1.6 : 1),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                Icons.drag_indicator,
                size: 18,
                color: theme.textTheme.bodySmall?.color,
              ),
              const Spacer(),
              IconButton(
                tooltip: cat.enabled ? '停用该分类' : '启用该分类',
                icon: Icon(
                  cat.enabled ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color:
                      cat.enabled ? theme.colorScheme.primary : theme.disabledColor,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: isDeleted
                    ? null
                    : () => widget.controller.toggleCategory(
                          cat.id,
                          !cat.enabled,
                        ),
              ),
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: () => _showCategoryEditor(existing: cat),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CircleAvatar(
            backgroundColor: displayColor.withOpacity(0.12),
            child: Icon(cat.iconData, color: displayColor),
          ),
          const SizedBox(height: 6),
          Text(
            cat.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (resolvedGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                resolvedGroup,
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (isDisabled || isDeleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                isDeleted ? '已删除（配置文件）' : '已停用',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDeleted ? Colors.redAccent : theme.disabledColor,
                ),
              ),
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '删除（从配置移除，不影响历史数据）',
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
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
    final defaultColor = _colorFamilies.first.shade500;
    Color color = existing?.color ?? defaultColor;
    MaterialColor selectedFamily = _matchColorFamily(color);
    IconData icon = existing?.iconData ??
        (commonIcons.isNotEmpty ? commonIcons.first : Icons.category);
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '颜色（先选色系，再选梯度）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _colorFamilies.map((family) {
                      final baseShade = family.shade500;
                      final isActiveFamily = selectedFamily == family;
                      return GestureDetector(
                        onTap: () => setDialogState(() {
                          selectedFamily = family;
                          color = family.shade500;
                        }),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: baseShade,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isActiveFamily
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: isActiveFamily
                                ? [
                                    BoxShadow(
                                      color: baseShade.withOpacity(0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: isActiveFamily
                              ? const Icon(
                                  Icons.expand_more,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      key: ValueKey<int>(selectedFamily.value),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant
                            .withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.32
                              : 0.48,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selectedFamily.shade500.withOpacity(0.85),
                        ),
                      ),
                      child: Wrap(
                        spacing: 10,
                        children: _shadeCandidates(selectedFamily)
                            .map(
                              (shade) => GestureDetector(
                                onTap: () => setDialogState(() {
                                  color = shade;
                                }),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: shade,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: color.value == shade.value
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: color.value == shade.value
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 18,
                                        )
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前色阶：${colorToHex(color)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
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
