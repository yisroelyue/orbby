import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
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
  PanelSize get panelSize => PanelSize.small;

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

  @override
  bool get panelHovered => _panelHovered;

  @override
  void initState() {
    super.initState();
    _fetch();
    HomeScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    HomeScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);

    final settings = await SettingsService.load();

    final custom = AppConfig.loadCustomApps();
    final system = AppConfig.loadSystemApps();
    final allApps = [...custom, ...system];

    if (settings.panelAppIds.isNotEmpty) {
      _apps = settings.panelAppIds
          .map((id) => allApps.where((a) => a.id == id))
          .expand((m) => m)
          .take(8)
          .toList();
    } else {
      _apps = allApps.take(8).toList();
    }

    if (!mounted) return;
    setState(() => _loading = false);
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
  EdgeInsetsGeometry get panelPadding => const EdgeInsets.all(12);

  @override
  Widget buildContent(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: _loading
          ? Padding(
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
            )
          : _buildContent(),
    );
  }

  Widget _buildAppIcon(AppInfo app) {
    if (app.icon.startsWith('assets/')) {
      if (app.icon.endsWith('.svg')) {
        return SvgPicture.asset(app.icon, width: 28, height: 28);
      }
      return Image.asset(
        app.icon,
        width: 28,
        height: 28,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.apps_rounded, color: secondaryText, size: 28),
      );
    }

    final iconPath = AppConfig.resolvePath(app.icon);
    final file = File(iconPath);
    if (!file.existsSync()) {
      return Icon(Icons.apps_rounded, color: secondaryText, size: 28);
    }
    if (app.icon.endsWith('.svg')) {
      return SvgPicture.file(file, width: 28, height: 28);
    }
    return Image.file(
      file,
      width: 28,
      height: 28,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.apps_rounded, color: secondaryText, size: 28),
    );
  }


  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题栏
        GestureDetector(
          onTap: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
          child: Row(
            children: [
              SvgPicture.asset('assets/svg/应用.svg', width: 22, height: 22),
              const SizedBox(width: 8),
              Text(
                '应用中心',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // 内容区域
        if (_loading) ...[
          Padding(
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
          ),
        ] else if (_apps.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '暂无应用',
                style: TextStyle(color: tertiaryText, fontSize: 12),
              ),
            ),
          ),
        ] else ...[
          Builder(
            builder: (context) {
              final visibleCount = _panelHovered ? _apps.length : (_apps.length > 6 ? 6 : _apps.length);
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: visibleCount,
                      itemBuilder: (_, index) => _buildAppTile(_apps[index], index),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildAppTile(AppInfo app, int index) {
    final isHovered = _hoveredIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
        onTap: () => _launchApp(app),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: isHovered ? hoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              app.type == 'system'
                  ? _buildAppIcon(app)
                  : Text(
                      app.name.isNotEmpty ? app.name[0] : '?',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              const SizedBox(height: 6),
              Text(
                app.name,
                style: TextStyle(
                  color: isHovered ? primaryText : tertiaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ],
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
      "id": "screen_record",
      "name": "屏幕录制",
      "launchType": "plugin",
      "subAppId": "screen_record",
      "executable": null,
      "icon": "assets/png/录制.png",
      "description": "录制全屏视频",
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
