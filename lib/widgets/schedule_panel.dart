import 'package:flutter/material.dart';

import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import '../services/schedule_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

export '../services/schedule_service.dart' show ScheduleItem;

class SchedulePanel extends BasePanel {
  const SchedulePanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'schedule';

  @override
  State<SchedulePanel> createState() => _SchedulePanelState();
}

class _SchedulePanelState extends BasePanelState<SchedulePanel>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<ScheduleItem> _items = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // 科技感色调
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _electricBlue = Color(0xFF2979FF);
  static const Color _neonOrange = Color(0xFFFF9100);
  static const Color _softWhite = Color(0xFFE0E6ED);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final cached = PanelCache.get<List<ScheduleItem>>('schedule_items');
    if (cached != null) {
      _items = cached;
      _loading = false;
    }
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('schedule_items')) {
      setState(() => _loading = true);
      PanelDataService.refreshSchedule();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    PanelCache.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<List<ScheduleItem>>('schedule_items');
    if (cached != null && mounted) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    }
  }

  @override
  BoxDecoration? get panelDecoration => null;

  void _openAddDialog() {
    _showScheduleDialog(
      id: '',
      title: '',
      time: '',
      iconCodePoint: Icons.event_rounded.codePoint,
      date: DateTime.now(),
    );
  }

  void _openEditDialog(ScheduleItem item) {
    _showScheduleDialog(
      id: item.id,
      title: item.title,
      time: item.time,
      iconCodePoint: item.iconCodePoint,
      date: item.date,
    );
  }

  // 日程类型定义
  static const _scheduleTypes = [
    {'name': '会议', 'icon': Icons.groups_rounded},
    {'name': '工作', 'icon': Icons.work_rounded},
    {'name': '学习', 'icon': Icons.school_rounded},
    {'name': '运动', 'icon': Icons.fitness_center_rounded},
    {'name': '餐饮', 'icon': Icons.restaurant_rounded},
    {'name': '出行', 'icon': Icons.flight_rounded},
    {'name': '购物', 'icon': Icons.shopping_cart_rounded},
    {'name': '娱乐', 'icon': Icons.movie_rounded},
    {'name': '医疗', 'icon': Icons.local_hospital_rounded},
    {'name': '其他', 'icon': Icons.event_rounded},
  ];

  void _showScheduleDialog({
    required String id,
    required String title,
    required String time,
    required int iconCodePoint,
    required DateTime date,
  }) {
    final titleController = TextEditingController(text: title);
    String selectedTime = time;
    // 根据iconCodePoint找到对应的类型，如果没有则默认"其他"
    String selectedType = _scheduleTypes.firstWhere(
      (t) => (t['icon'] as IconData).codePoint == iconCodePoint,
      orElse: () => _scheduleTypes.last,
    )['name'] as String;
    final isCreate = id.isEmpty;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCreate ? Icons.add_rounded : Icons.edit_rounded,
                            color: const Color(0xFF2196F3),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isCreate ? '添加日程' : '编辑日程',
                          style: const TextStyle(
                            color: Color(0xFF1F1F1F),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: 22, color: Colors.grey.shade500),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 标题输入
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      style: const TextStyle(
                        color: Color(0xFF1F1F1F),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        hintText: '输入日程标题...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF2196F3),
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 时间和日期选择
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final parts = selectedTime.split(':');
                              TimeOfDay initialTime;
                              if (parts.length == 2) {
                                initialTime = TimeOfDay(
                                  hour: int.tryParse(parts[0]) ?? 9,
                                  minute: int.tryParse(parts[1]) ?? 0,
                                );
                              } else {
                                initialTime = const TimeOfDay(hour: 9, minute: 0);
                              }
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  selectedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.access_time_rounded, size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 10),
                                  Text(
                                    selectedTime.isEmpty ? '选择时间' : selectedTime,
                                    style: TextStyle(
                                      color: selectedTime.isEmpty ? Colors.grey.shade400 : const Color(0xFF1F1F1F),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  date = picked;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today_rounded, size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Color(0xFF1F1F1F),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 类型选择
                    Text(
                      '类型',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _scheduleTypes.map((type) {
                        final isSelected = selectedType == type['name'];
                        final icon = type['icon'] as IconData;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              selectedType = type['name'] as String;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF2196F3) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 16,
                                  color: isSelected ? Colors.white : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  type['name'] as String,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : const Color(0xFF1F1F1F),
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    // 按钮
                    Row(
                      children: [
                        if (!isCreate) ...[
                          TextButton.icon(
                            onPressed: () async {
                              await ScheduleService.remove(id);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                              PanelDataService.refreshSchedule();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade400,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: const Text('删除'),
                          ),
                        ],
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade600,
                          ),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final titleText = titleController.text.trim();
                            if (titleText.isEmpty || selectedTime.isEmpty) return;

                            // 根据类型获取对应的图标
                            final selectedTypeData = _scheduleTypes.firstWhere(
                              (t) => t['name'] == selectedType,
                              orElse: () => _scheduleTypes.last,
                            );
                            final icon = selectedTypeData['icon'] as IconData;

                            if (isCreate) {
                              await ScheduleService.add(titleText, selectedTime, icon, date);
                            } else {
                              await ScheduleService.update(id, titleText, selectedTime, icon);
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                            PanelDataService.refreshSchedule();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleDone(ScheduleItem item) async {
    await ScheduleService.toggleDone(item.id);
    PanelDataService.refreshSchedule();
  }

  @override
  Widget buildContent(BuildContext context) {
    final accent = isDark ? _cyan : _electricBlue;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A237E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部标题栏
        Row(
          children: [
            // 脉冲指示灯 — 橙色表示进行中
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _neonOrange.withValues(alpha: _pulseAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: _neonOrange
                            .withValues(alpha: _pulseAnimation.value * 0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              'TODAY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _neonOrange,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            // 时间戳
            Text(
              _formatTimestamp(),
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white30 : Colors.black26,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            // 添加按钮
            InteractiveIcon(
              size: 28,
              onTap: _openAddDialog,
              child: Icon(Icons.add_rounded, color: tertiaryText, size: 18),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // 日程列表
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tertiaryText,
                ),
              ),
            ),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: Text(
                '暂无日程，点击 + 添加',
                style: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
                  fontSize: 12,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                return _buildScheduleCard(
                  item: _items[index],
                  accent: accent,
                  titleColor: titleColor,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildScheduleCard({
    required ScheduleItem item,
    required Color accent,
    required Color titleColor,
  }) {
    // 颜色区分：未处理用亮色，已处理用暗色
    final timeColor =
        item.isDone ? (isDark ? Colors.white24 : Colors.black26) : accent;
    final labelColor = item.isDone
        ? (isDark ? Colors.white30 : Colors.black38)
        : (isDark ? _softWhite : const Color(0xFF37474F));
    final iconColor =
        item.isDone ? (isDark ? Colors.white24 : Colors.black26) : tertiaryText;

    // 判断是否是今天
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(item.date.year, item.date.month, item.date.day);
    final isToday = itemDate.isAtSameMomentAs(today);

    return GestureDetector(
      onTap: () => _openEditDialog(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // 时间标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.isDone
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.04))
                    : accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 日期（如果不是今天）
                  if (!isToday)
                    Text(
                      '${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  // 时间
                  Text(
                    item.time,
                    style: TextStyle(
                      color: timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 图标
            Icon(item.icon, size: 16, color: iconColor),
            const SizedBox(width: 10),
            // 标题
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 13,
                  fontWeight: item.isDone ? FontWeight.w400 : FontWeight.w500,
                  decoration:
                      item.isDone ? TextDecoration.lineThrough : null,
                  decorationColor: isDark ? Colors.white24 : Colors.black26,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 完成状态切换
            GestureDetector(
              onTap: () => _toggleDone(item),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  item.isDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: item.isDone
                      ? (isDark ? Colors.white24 : Colors.black26)
                      : _neonOrange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
