import 'package:flutter/material.dart';

import '../../config/settings.dart';
import '../home_screen.dart';
import '../../widgets/app_square_panel.dart';
import '../../widgets/balance_panel.dart';
import '../../widgets/base_panel.dart';
import '../../widgets/carousel_panel.dart';
import '../../widgets/control_panel.dart';
import '../../widgets/daily_quote_panel.dart';
import '../../widgets/favorites_panel.dart';
import '../../widgets/news_panel.dart';
import '../../widgets/photo_wall_panel.dart';
import '../../widgets/schedule_panel.dart';
import '../../widgets/script_panel.dart';
import '../../widgets/todo_panel.dart';
import '../../widgets/translate_panel.dart';
import '../../widgets/weather_panel.dart';

/// 面板注册项
class PanelDef {
  const PanelDef(this.builder, {this.order = 0});
  final BasePanel Function() builder;
  final int order;
}

/// 面板注册表（默认顺序）
final List<PanelDef> panelDefs = [
  PanelDef(() => const DailyQuotePanel(), order: 0),
  PanelDef(() => const PhotoWallPanel(), order: 1),
  PanelDef(() => const BalancePanel(), order: 2),
  PanelDef(() => const TranslatePanel(), order: 3),
  PanelDef(() => const WeatherPanel(), order: 4),
  PanelDef(() => const NewsPanel(), order: 5),
  PanelDef(() => const SchedulePanel(), order: 6),
  PanelDef(() => const TodoPanel(), order: 7),
  PanelDef(() => const FavoritesPanel(), order: 8),
  PanelDef(() => const AppSquarePanel(), order: 9),
  PanelDef(() => const ControlPanel(), order: 10),
  PanelDef(() => const ScriptPanel(), order: 11),
];

/// 默认面板顺序
final List<String> defaultPanelOrder =
    panelDefs.map((d) => d.builder().panelName).toList();

/// 面板名称到中文名的映射
final Map<String, String> panelNameMap = {
  'daily_quote': '每日一言',
  'photo_wall': '照片墙',
  'balance': '余额',
  'translate': '翻译',
  'weather': '天气',
  'news': '新闻',
  'schedule': '日程',
  'todo': '待办',
  'favorites': '收藏',
  'app_square': '应用',
  'control': '控制',
  'script': '脚本',
};


/// 按顺序构建面板列表
List<BasePanel> buildOrderedPanels(List<String> order) {
  final defMap = {for (final d in panelDefs) d.builder().panelName: d};
  final panels = <BasePanel>[];
  for (final name in order) {
    final def = defMap[name];
    if (def != null) {
      panels.add(def.builder());
    }
  }
  // 补充新增的面板（settings 中没有的）
  for (final def in panelDefs) {
    final name = def.builder().panelName;
    if (!order.contains(name)) {
      panels.add(def.builder());
    }
  }
  return panels;
}

/// 将面板列表按尺寸自动排版：small 面板两两并排，落单占 50%
List<Widget> buildPanelRows(List<BasePanel> panels) {
  final rows = <Widget>[];
  final buffer = <BasePanel>[];

  void flush() {
    while (buffer.isNotEmpty) {
      if (buffer.length >= 2) {
        rows.add(Row(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1.0, child: buffer.removeAt(0))),
            const SizedBox(width: 8),
            Expanded(child: AspectRatio(aspectRatio: 1.0, child: buffer.removeAt(0))),
          ],
        ));
      } else {
        rows.add(Row(
          children: [
            Expanded(child: AspectRatio(aspectRatio: 1.0, child: buffer.removeAt(0))),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ));
      }
    }
  }

  for (final panel in panels) {
    if (panel.panelSize == PanelSize.small) {
      buffer.add(panel);
      if (buffer.length >= 2) flush();
    } else {
      flush();
      rows.add(panel);
    }
  }
  flush();

  return rows;
}

/// Dashboard tab — 面板列表
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<String> _panelOrder = [];
  List<String> _hiddenPanels = [];
  bool _editing = false;


  /// 按面板名缓存实例，移动顺序时只重排引用，不重建
  final Map<String, BasePanel> _panelCache = {};

  @override
  void initState() {
    super.initState();
    _loadOrder();
    HomeScreen.panelOrderNotifier.addListener(_onOrderChanged);
    HomeScreen.editModeNotifier.addListener(_onEditModeChanged);
    HomeScreen.settingsChangeNotifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    HomeScreen.panelOrderNotifier.removeListener(_onOrderChanged);
    HomeScreen.editModeNotifier.removeListener(_onEditModeChanged);
    HomeScreen.settingsChangeNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onOrderChanged() {
    _loadOrder();
  }

  void _onEditModeChanged() {
    setState(() {
      _editing = HomeScreen.editModeNotifier.value;
    });
  }

  void _onSettingsChanged() {
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final settings = await SettingsService.load();
    final order = settings.panelOrder.isNotEmpty
        ? settings.panelOrder
        : defaultPanelOrder;
    if (!mounted) return;

    setState(() {
      _panelOrder = order;
      _hiddenPanels = List.from(settings.hiddenPanels);
    });
  }

  Future<void> _saveLayout() async {
    final settings = await SettingsService.load();
    settings.panelOrder = _panelOrder;
    settings.hiddenPanels = _hiddenPanels;
    await SettingsService.save(settings);
  }

  /// 获取面板实例，按名字缓存，顺序变化时只重排引用
  List<BasePanel> _getPanels() {
    // 先确保所有面板都已创建
    for (final def in panelDefs) {
      final panel = def.builder();
      _panelCache.putIfAbsent(panel.panelName, () => panel);
    }
    // 按当前顺序返回引用
    return _panelOrder
        .where((name) => _panelCache.containsKey(name))
        .map((name) => _panelCache[name]!)
        .toList();
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _panelOrder.removeAt(index);
      _panelOrder.insert(index - 1, item);
    });
    _saveLayout();
  }

  void _moveDown(int index) {
    if (index >= _panelOrder.length - 1) return;
    setState(() {
      final item = _panelOrder.removeAt(index);
      _panelOrder.insert(index + 1, item);
    });
    _saveLayout();
  }

  void _hidePanel(String name) {
    setState(() {
      if (!_hiddenPanels.contains(name)) {
        _hiddenPanels.add(name);
      }
    });
    _saveLayout();
  }

  void _showPanel(String name) {
    setState(() {
      _hiddenPanels.remove(name);
    });
    _saveLayout();
  }

  /// 获取可见面板的有序列表（排除隐藏的）
  List<String> _getVisibleOrder() {
    return _panelOrder.where((name) {
      if (_hiddenPanels.contains(name)) return false;
      return true;
    }).toList();
  }

  /// 构建带编辑蒙版的面板
  Widget _buildEditablePanel(BasePanel panel, int visibleIndex, List<String> visibleOrder) {
    final name = panel.panelName;
    final isFirst = visibleIndex == 0;
    final isLast = visibleIndex == visibleOrder.length - 1;

    return Stack(
      children: [
        panel,
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              children: [
                // 轮播标记（左上角）
                if (panel.isCarousel)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '轮播',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 操作按钮（居中）
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _editButton(
                        icon: Icons.keyboard_arrow_up,
                        onTap: isFirst ? null : () {
                          final realIndex = _panelOrder.indexOf(name);
                          _moveUp(realIndex);
                        },
                      ),
                      const SizedBox(width: 12),
                      _editButton(
                        icon: Icons.visibility_off_rounded,
                        onTap: () => _hidePanel(name),
                      ),
                      const SizedBox(width: 12),
                      _editButton(
                        icon: Icons.keyboard_arrow_down,
                        onTap: isLast ? null : () {
                          final realIndex = _panelOrder.indexOf(name);
                          _moveDown(realIndex);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _editButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.white.withValues(alpha:0.25)
              : Colors.white.withValues(alpha:0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: onTap != null ? Colors.white : Colors.white38,
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_panelOrder.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final visibleOrder = _getVisibleOrder();
    final allPanels = _getPanels();
    final visiblePanels = allPanels
        .where((p) => visibleOrder.contains(p.panelName))
        .toList()
      ..sort((a, b) =>
          visibleOrder.indexOf(a.panelName) - visibleOrder.indexOf(b.panelName));

    if (_editing) {
      return _buildEditingLayout(visiblePanels, visibleOrder);
    }

    // 分离应用中心面板、轮播面板和普通面板
    final appSquarePanel = visiblePanels.where((p) => p.panelName == 'app_square').toList();
    final carouselPanels = visiblePanels.where((p) => p.isCarousel).toList();
    final normalPanels = visiblePanels.where((p) => !p.isCarousel && p.panelName != 'app_square').toList();

    final rows = <Widget>[];

    // 非编辑模式下，轮播面板组合为 CarouselPanel
    if (carouselPanels.isNotEmpty) {
      rows.add(CarouselPanel(panels: carouselPanels));
    }

    // 普通面板按原有逻辑排列
    rows.addAll(buildPanelRows(normalPanels));

    return Theme(
      data: ThemeData(
        scrollbarTheme:
            const ScrollbarThemeData(thickness: WidgetStatePropertyAll(0)),
      ),
      child: Column(
        children: [
          // 主内容区域（可滚动）
          Expanded(
            child: ListView.separated(
              primary: true,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => rows[index],
            ),
          ),
          // 应用中心固定在底部
          if (appSquarePanel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 0, right: 0),
              child: appSquarePanel.first,
            ),
        ],
      ),
    );
  }

  Widget _buildEditingLayout(List<BasePanel> visiblePanels, List<String> visibleOrder) {
    // 编辑模式下小面板也两两配对，和正常布局一致
    final editablePanels = <BasePanel>[];
    for (int i = 0; i < visiblePanels.length; i++) {
      editablePanels.add(visiblePanels[i]);
    }
    final items = _buildEditableRows(editablePanels, visibleOrder);

    // 如果有隐藏的面板，底部显示恢复按钮
    if (_hiddenPanels.isNotEmpty) {
      items.add(const SizedBox(height: 12));
      items.add(_buildHiddenPanelsBar());
    }

    return Theme(
      data: ThemeData(
        scrollbarTheme:
            const ScrollbarThemeData(thickness: WidgetStatePropertyAll(0)),
      ),
      child: ListView.separated(
        primary: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, index) => items[index],
      ),
    );
  }

  /// 和 buildPanelRows 逻辑一致，但每个面板加编辑蒙版
  List<Widget> _buildEditableRows(List<BasePanel> panels, List<String> visibleOrder) {
    final rows = <Widget>[];
    final buffer = <BasePanel>[];

    void flush() {
      while (buffer.isNotEmpty) {
        if (buffer.length >= 2) {
          final a = buffer.removeAt(0);
          final b = buffer.removeAt(0);
          rows.add(Row(
            children: [
              Expanded(child: AspectRatio(aspectRatio: 1.0, child: _buildEditablePanel(a, visibleOrder.indexOf(a.panelName), visibleOrder))),
              const SizedBox(width: 8),
              Expanded(child: AspectRatio(aspectRatio: 1.0, child: _buildEditablePanel(b, visibleOrder.indexOf(b.panelName), visibleOrder))),
            ],
          ));
        } else {
          final panel = buffer.removeAt(0);
          rows.add(Row(
            children: [
              Expanded(child: AspectRatio(aspectRatio: 1.0, child: _buildEditablePanel(panel, visibleOrder.indexOf(panel.panelName), visibleOrder))),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox.shrink()),
            ],
          ));
        }
      }
    }

    for (final panel in panels) {
      // 轮播面板在编辑模式下展开为独立卡片
      if (panel.isCarousel) {
        flush();
        rows.add(_buildEditablePanel(panel, visibleOrder.indexOf(panel.panelName), visibleOrder));
      } else if (panel.panelSize == PanelSize.small) {
        buffer.add(panel);
        if (buffer.length >= 2) flush();
      } else {
        flush();
        rows.add(_buildEditablePanel(panel, visibleOrder.indexOf(panel.panelName), visibleOrder));
      }
    }
    flush();

    return rows;
  }

  Widget _buildHiddenPanelsBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已隐藏的面板',
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hiddenPanels.map((name) {
              final displayName = panelNameMap[name] ?? name;
              return GestureDetector(
                onTap: () => _showPanel(name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252540),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_rounded,
                          size: 14, color: Colors.white.withValues(alpha:0.7)),
                      const SizedBox(width: 4),
                      Text(
                        displayName,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha:0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.add_rounded,
                          size: 14, color: Colors.white.withValues(alpha:0.5)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
