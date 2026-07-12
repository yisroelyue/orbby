import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/settings.dart';
import '../config/panel_theme.dart';
import '../screens/menu_screen.dart';

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

class AppSquarePanel extends StatefulWidget {
  const AppSquarePanel({super.key});

  @override
  State<AppSquarePanel> createState() => _AppSquarePanelState();
}

class _AppSquarePanelState extends State<AppSquarePanel> with PanelThemeMixin {
  bool _panelEnabled = true;
  bool _loading = true;
  bool _headerHovered = false;
  bool _panelHovered = false;
  List<AppInfo> _apps = [];
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _fetch();
    MenuScreen.refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    MenuScreen.refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);

    final settings = await SettingsService.load();
    _panelEnabled = settings.showAppSquarePanel;

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

  void _openAppCenter() {
    MenuScreen.menuChannel.invokeMethod('open_app_center');
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
    MenuScreen.menuChannel.invokeMethod('launch_sub_app', {
      'subAppId': subAppId,
    });
  }

  Widget _buildAppIcon(AppInfo app) {
    if (app.icon.startsWith('assets/')) {
      if (app.icon.endsWith('.svg')) {
        return SvgPicture.asset(app.icon, width: 22, height: 22);
      }
      return Image.asset(
        app.icon,
        width: 22,
        height: 22,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.apps, color: secondaryText, size: 22),
      );
    }

    final iconPath = AppConfig.resolvePath(app.icon);
    final file = File(iconPath);
    if (!file.existsSync()) {
      return Icon(Icons.apps, color: secondaryText, size: 22);
    }
    if (app.icon.endsWith('.svg')) {
      return SvgPicture.file(file, width: 22, height: 22);
    }
    return Image.file(
      file,
      width: 22,
      height: 22,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.apps, color: secondaryText, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_panelEnabled && !_loading) {
      return const SizedBox.shrink();
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _panelHovered = true),
      onExit: (_) => setState(() => _panelHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          color: panelBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              if (_loading)
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
                )
              else
                _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _headerHovered = true),
      onExit: (_) => setState(() => _headerHovered = false),
      child: GestureDetector(
        onTap: _openAppCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _headerHovered
                ? hoverBg
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/svg/应用.svg',
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '应用中心',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _headerHovered ? 1.0 : 0.0,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: mutedText,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '暂无应用，请编辑 apps_config.json 添加',
            style: TextStyle(color: tertiaryText, fontSize: 13),
          ),
        ),
      );
    }

    final visibleCount = _panelHovered ? _apps.length : (_apps.length > 4 ? 4 : _apps.length);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: visibleCount,
        itemBuilder: (_, index) => _buildAppTile(_apps[index], index),
      ),
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
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          decoration: BoxDecoration(
            color: isHovered
                ? hoverBg
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: elementBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: app.type == 'system'
                      ? _buildAppIcon(app)
                      : Text(
                          app.name.isNotEmpty ? app.name[0] : '?',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                app.name,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
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
      return [];
    }
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
