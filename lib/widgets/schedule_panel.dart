import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

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
  bool _panelEnabled = true;
  bool _loading = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // 科技感色调
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _electricBlue = Color(0xFF2979FF);
  static const Color _deepNavy = Color(0xFF0A1628);
  static const Color _darkPanel = Color(0xFF0D1F3C);
  static const Color _gridLine = Color(0xFF1A3A5C);
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

    _fetchSettings();
    registerPanelEnabled((v) => _panelEnabled = v, (s) => s.showSchedulePanel);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchSettings() async {
    setState(() => _loading = true);
    final settings = await SettingsService.load();
    _panelEnabled = settings.showSchedulePanel;
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  static final _fakeItems = [
    _ScheduleItem('09:00', '团队站会', Icons.groups_rounded),
    _ScheduleItem('10:30', '产品需求评审', Icons.description_rounded),
    _ScheduleItem('12:00', '午餐 · 和小王约了', Icons.restaurant_rounded),
    _ScheduleItem('14:00', '代码 Review', Icons.code_rounded),
    _ScheduleItem('15:30', '客户演示', Icons.present_to_all_rounded),
    _ScheduleItem('17:00', '健身 · 胸肌日', Icons.fitness_center_rounded),
  ];

  @override
  BoxDecoration? get panelDecoration {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [_deepNavy, _darkPanel]
            : [
                const Color(0xFFEAF2FB),
                const Color(0xFFF0F4FA),
              ],
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final accent = isDark ? _cyan : _electricBlue;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A237E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部 HUD 标题栏
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
                    color: _neonOrange.withOpacity(_pulseAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: _neonOrange.withOpacity(_pulseAnimation.value * 0.4),
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
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '日程',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  letterSpacing: 1,
                ),
              ),
            ),
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
            InteractiveIcon(
              size: 28,
              onTap: () => setState(() {}),
              child: Icon(Icons.refresh_rounded, color: tertiaryText, size: 18),
            ),
          ],
        ),

        // 扫描线装饰
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  accent.withOpacity(0.4),
                  accent.withOpacity(0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ),
            ),
          ),
        ),

        // 日程列表
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: _fakeItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              return _buildScheduleCard(
                item: _fakeItems[index],
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
    required _ScheduleItem item,
    required Color accent,
    required Color titleColor,
  }) {
    final now = DateTime.now();
    final parts = item.time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final isPast = now.hour > hour || (now.hour == hour && now.minute >= minute);
    final isCurrent = now.hour == hour &&
        now.minute >= minute &&
        now.minute < minute + 30;

    final glowColor = isDark ? _cyan.withOpacity(0.08) : _electricBlue.withOpacity(0.06);
    final borderColor = isDark ? _cyan.withOpacity(0.15) : _electricBlue.withOpacity(0.12);
    final currentGlow = isDark ? _neonOrange.withOpacity(0.12) : _neonOrange.withOpacity(0.08);
    final currentBorder = isDark ? _neonOrange.withOpacity(0.3) : _neonOrange.withOpacity(0.2);
    final pastGlow = isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02);
    final pastBorder = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);

    final bgColor = isPast ? pastGlow : (isCurrent ? currentGlow : glowColor);
    final bdColor = isPast ? pastBorder : (isCurrent ? currentBorder : borderColor);
    final timeColor = isPast
        ? (isDark ? Colors.white24 : Colors.black26)
        : (isCurrent ? _neonOrange : accent);
    final labelColor = isPast
        ? (isDark ? Colors.white30 : Colors.black38)
        : (isDark ? _softWhite : const Color(0xFF37474F));
    final iconColor = isPast
        ? (isDark ? Colors.white24 : Colors.black26)
        : (isCurrent ? _neonOrange : tertiaryText);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bdColor, width: 0.5),
      ),
      child: Row(
        children: [
          // 时间标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isPast
                  ? (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04))
                  : (isCurrent
                      ? _neonOrange.withOpacity(0.12)
                      : accent.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPast
                    ? Colors.transparent
                    : (isCurrent
                        ? _neonOrange.withOpacity(0.25)
                        : accent.withOpacity(0.2)),
                width: 0.5,
              ),
            ),
            child: Text(
              item.time,
              style: TextStyle(
                color: timeColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                decoration: isPast ? TextDecoration.lineThrough : null,
                decorationColor: isDark ? Colors.white24 : Colors.black26,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 当前进行中标记
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _neonOrange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'NOW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _neonOrange,
                  letterSpacing: 1,
                ),
              ),
            ),
        ],
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

class _ScheduleItem {
  const _ScheduleItem(this.time, this.title, this.icon);
  final String time;
  final String title;
  final IconData icon;
}
