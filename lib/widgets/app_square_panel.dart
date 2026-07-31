import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../screens/home_screen.dart';
import '../services/panel_cache.dart';
import '../services/panel_data_service.dart';
import 'base_panel.dart';

class AppInfo {
  const AppInfo({
    required this.id,
    required this.name,
    this.executable,
    this.subAppId,
    required this.icon,
    this.description = '',
    this.type = 'system',
    this.launchType = 'executable',
  });

  final String id;
  final String name;
  final String? executable;
  final String? subAppId;
  final String icon;
  final String description;
  final String type;
  final String launchType;

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      executable: json['executable'] as String?,
      subAppId: json['subAppId'] as String?,
      icon: json['icon'] as String,
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'system',
      launchType: json['launchType'] as String? ?? 'executable',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'executable': executable,
        'subAppId': subAppId,
        'icon': icon,
        'description': description,
        'type': type,
        'launchType': launchType,
      };
}

class AppSquarePanel extends BasePanel {
  const AppSquarePanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.full;

  @override
  String get panelName => 'app_square';

  @override
  State<AppSquarePanel> createState() => _AppSquarePanelState();
}

class _AppSquarePanelState extends BasePanelState<AppSquarePanel> {
  bool _loading = true;
  bool _panelHovered = false;
  List<AppInfo> _apps = [];
  int? _hoveredIndex;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get panelHovered => _panelHovered;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    PanelCache.addListener(_onCacheChanged);
    if (!PanelCache.has('app_square_apps')) {
      setState(() => _loading = true);
      PanelDataService.refreshApps();
    }
  }

  @override
  void dispose() {
    PanelCache.removeListener(_onCacheChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onCacheChanged() => _loadFromCache();

  void _loadFromCache() {
    final cached = PanelCache.get<List<AppInfo>>('app_square_apps');
    if (cached != null && mounted) {
      setState(() {
        _apps = cached;
        _loading = false;
      });
    }
  }

  Future<void> _launchApp(AppInfo app) async {
    if (app.launchType == 'plugin' && app.subAppId != null) {
      await _launchPluginApp(app.subAppId!);
      return;
    }
    if (app.executable != null) {
      final exePath = AppConfig.resolvePath(app.executable!);
      try {
        if (Platform.isWindows) {
          await Process.start('cmd', ['/c', 'start', '', exePath],
              runInShell: false);
        } else {
          await Process.start(
            exePath,
            [],
            runInShell: true,
            workingDirectory: File(exePath).parent.path,
          );
        }
      } catch (e) {
        debugPrint('Failed to launch app "${app.name}": $e');
      }
    }
  }

  Future<void> _launchPluginApp(String subAppId) async {
    HomeScreen.menuChannel.invokeMethod('launch_sub_app', {
      'subAppId': subAppId,
    });
  }

  @override
  EdgeInsetsGeometry get panelPadding => const EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  @override
  double get panelBorderRadius => 8;

  @override
  BoxDecoration? get panelDecoration => BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.0) : Colors.white.withValues(alpha: 0.0),
      );

  @override
  Widget buildContent(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
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
      );
    }

    if (_apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '暂无应用',
            style: TextStyle(color: tertiaryText, fontSize: 12),
          ),
        ),
      );
    }

    return _buildHorizontalList();
  }

  Widget _buildAppIcon(AppInfo app, {double size = 28}) {
    // 资源图标
    if (app.icon.startsWith('assets/')) {
      if (app.icon.endsWith('.svg')) {
        return SvgPicture.asset(app.icon, width: size, height: size);
      }
      return Image.asset(
        app.icon,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.apps_rounded, color: secondaryText, size: size),
      );
    }

    // 文件图标
    final iconPath = AppConfig.resolvePath(app.icon);
    final file = File(iconPath);
    if (!file.existsSync()) {
      return Icon(Icons.apps_rounded, color: secondaryText, size: size);
    }
    if (app.icon.endsWith('.svg')) {
      return SvgPicture.file(file, width: size, height: size);
    }
    return Image.file(
      file,
      width: size,
      height: size,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.apps_rounded, color: secondaryText, size: size),
    );
  }

  Widget _buildHorizontalList() {
    return SizedBox(
      height: 56,
      child: Listener(
        onPointerSignal: (event) {
          try {
            final delta = (event as dynamic).scrollDelta as Offset;
            _scrollController.jumpTo(
              (_scrollController.offset + delta.dy)
                  .clamp(0.0, _scrollController.position.maxScrollExtent),
            );
          } catch (_) {
            // 非滚轮事件，忽略
          }
        },
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: _apps.length + 1, // +1 for app center button
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildAppCenterButton();
            }
            return _buildAppCard(_apps[index - 1], index - 1);
          },
        ),
      ),
    );
  }

  Widget _buildAppCenterButton() {
    final isHovered = _hoveredIndex == -1;
    return Tooltip(
      message: '应用中心',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredIndex = -1),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isHovered ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHovered ? borderColor : Colors.transparent,
                width: 1,
              ),
            ),
            child: SvgPicture.asset(
              'assets/svg/应用.svg',
              width: 36,
              height: 36,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppCard(AppInfo app, int index) {
    final isHovered = _hoveredIndex == index;
    final hasIcon = app.icon.isNotEmpty && app.icon != 'assets/svg/应用.svg';
    return Tooltip(
      message: app.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: GestureDetector(
          onTap: () => _launchApp(app),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isHovered ? hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHovered ? borderColor : Colors.transparent,
                width: 1,
              ),
            ),
            child: hasIcon
                ? _buildAppIcon(app, size: 36)
                : Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: secondaryText.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        app.name.isNotEmpty ? app.name[0] : '?',
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Shared path/config helpers used by both the panel and the app-center screen.
class AppConfig {
  AppConfig._();

  static String get projectRoot {
    try {
      var dir = Directory(Platform.resolvedExecutable).parent;
      while (dir.path != dir.parent.path) {
        if (Directory('${dir.path}/sub_app').existsSync() ||
            Directory('${dir.path}/sub_apps').existsSync()) {
          return dir.path;
        }
        dir = dir.parent;
      }
    } catch (_) {}
    return Directory.current.path;
  }

  static String get systemConfigPath =>
      '$projectRoot/lib/config/apps_config.json';

  static String get _customConfigPath {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return '$home/.orbby/custom_apps.json';
  }

  static String resolvePath(String raw) {
    if (Platform.isWindows && raw.length >= 2 && raw[1] == ':') return raw;
    if (raw.startsWith('/')) return raw;
    return '$projectRoot/$raw';
  }

  static const _systemAppsJson = '''
{
  "apps": [
    {
      "id": "image_handler",
      "name": "图像处理器",
      "launchType": "plugin",
      "subAppId": "image_handler",
      "executable": null,
      "icon": "assets/svg/图像处理.svg",
      "description": "图片格式转换与处理",
      "type": "system"
    },
    {
      "id": "markdown_viewer",
      "name": "Markdown 查看器",
      "launchType": "plugin",
      "subAppId": "markdown_viewer",
      "executable": null,
      "icon": "assets/svg/markdown.svg",
      "description": "编辑与预览 Markdown 报文",
      "type": "system"
    },
    {
      "id": "screen_record",
      "name": "屏幕录制",
      "launchType": "plugin",
      "subAppId": "screen_record",
      "executable": null,
      "icon": "assets/png/录制.png",
      "description": "录制全屏视频",
      "type": "system"
    },
    {
      "id": "json_viewer",
      "name": "JSON 查看器",
      "launchType": "plugin",
      "subAppId": "json_viewer",
      "executable": null,
      "icon": "assets/svg/JSON查看.svg",
      "description": "编辑、格式化、树形预览 JSON 数据",
      "type": "system"
    }
  ]
}
''';

  static List<AppInfo> loadSystemApps() {
    try {
      final file = File(systemConfigPath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final list = json['apps'] as List<dynamic>?;
        if (list != null) {
          return list
              .map((e) => AppInfo.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    try {
      final json = jsonDecode(_systemAppsJson) as Map<String, dynamic>;
      final list = json['apps'] as List<dynamic>?;
      if (list != null) {
        return list
            .map((e) => AppInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Failed to load embedded system apps: $e');
    }
    return [];
  }

  static List<AppInfo> loadCustomApps() {
    try {
      final file = File(_customConfigPath);
      if (!file.existsSync()) return [];
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final list = json['apps'] as List<dynamic>?;
      if (list == null) return [];
      return list
          .map((e) => AppInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Failed to load custom apps: $e');
    }
    return [];
  }

  static Future<void> saveCustomApps(List<AppInfo> apps) async {
    try {
      final dir = Directory(_customConfigPath).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(_customConfigPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'apps': apps.map((a) => a.toJson()).toList(),
        }),
      );
    } catch (e) {
      debugPrint('Failed to save custom apps: $e');
    }
  }
}
