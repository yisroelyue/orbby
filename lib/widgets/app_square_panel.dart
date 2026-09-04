import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../config/settings.dart';
import '../screens/home_screen.dart';

class AppInfo {
  const AppInfo({required this.id, required this.name, required this.icon, this.executable, this.description = '', this.type = 'system'});
  final String id;
  final String name;
  final String icon;
  final String? executable;
  final String description;
  final String type;
  bool get hasIcon => icon.isNotEmpty && icon != 'assets/svg/应用.svg';

  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        executable: json['executable'] as String?,
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'system',
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'icon': icon, 'executable': executable,
        'description': description, 'type': type,
      };
}

class AppSquarePanel extends StatefulWidget {
  const AppSquarePanel({super.key});
  @override
  State<AppSquarePanel> createState() => _AppSquarePanelState();
}

class _AppSquarePanelState extends State<AppSquarePanel> {
  static const _buttonSize = 56.0;
  static const _iconSize = 36.0;
  static const _textColor = Color(0xFFDDDDDD);
  static const _hoverColor = Color(0x22333333);
  static const _borderColor = Color(0x55888888);

  final _scrollController = ScrollController();
  List<AppInfo> _apps = [];
  int? _hoveredIndex;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadApps();
    HomeScreen.settingsChangeNotifier.addListener(_loadApps);
  }

  @override
  void dispose() {
    HomeScreen.settingsChangeNotifier.removeListener(_loadApps);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final settings = await SettingsService.load();
    final all = [...AppConfig.loadCustomApps(), ...AppConfig.loadSystemApps()];
    final byId = {for (final app in all) app.id: app};
    final apps = [
      ...settings.panelAppIds.map((id) => byId[id]).whereType<AppInfo>(),
      ...all.where((app) => !settings.panelAppIds.contains(app.id)),
    ];
    if (mounted) setState(() { _apps = apps; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: _loading ? const SizedBox(height: _buttonSize) : _buildList(),
    );
  }

  Widget _buildList() {
    return SizedBox(
      height: _buttonSize,
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
          final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
          if (delta == 0) return;
          final position = _scrollController.position;
          _scrollController.animateTo(
            (position.pixels + delta).clamp(0.0, position.maxScrollExtent).toDouble(),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        },
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          itemCount: _apps.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, index) => index == 0 ? _appCenterButton() : _appButton(_apps[index - 1], index - 1),
        ),
      ),
    );
  }

  Widget _button({required Widget child, required VoidCallback onTap, required bool hovered, required ValueChanged<bool> onHover}) {
    const size = _buttonSize;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: size,
      height: _buttonSize,
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.transparent),
            ),
            child: Center(
              child: Transform.scale(
                scale: hovered ? 1.5 : 1.0,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _appCenterButton() => _button(
        hovered: _hoveredIndex == -1,
        onHover: (v) => setState(() => _hoveredIndex = v ? -1 : null),
        onTap: () => HomeScreen.menuChannel.invokeMethod('open_app_center'),
        child: SvgPicture.asset('assets/svg/应用.svg', width: _iconSize, height: _iconSize),
      );

  Widget _appButton(AppInfo app, int index) => _button(
        hovered: _hoveredIndex == index,
        onHover: (v) => setState(() => _hoveredIndex = v ? index : null),
        onTap: () => _launchApp(app),
        child: app.hasIcon
            ? _buildIcon(app)
            : SizedBox(
                width: _iconSize,
                height: _iconSize,
                child: Container(
                  decoration: BoxDecoration(
                    color: _appColor(app.name),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    app.name.isEmpty ? '?' : app.name[0],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
      );

  Widget _buildIcon(AppInfo app) {
    if (app.icon.startsWith('assets/')) {
      return app.icon.endsWith('.svg') ? SvgPicture.asset(app.icon, width: _iconSize, height: _iconSize) : Image.asset(app.icon, width: _iconSize, height: _iconSize);
    }
    final file = File(AppConfig.resolvePath(app.icon));
    if (!file.existsSync()) return const Icon(Icons.apps_rounded, color: _textColor, size: _iconSize);
    return app.icon.endsWith('.svg') ? SvgPicture.file(file, width: _iconSize, height: _iconSize) : Image.file(file, width: _iconSize, height: _iconSize);
  }

  Color _appColor(String name) {
    const colors = [
      Color(0xFF3949AB), // indigo
      Color(0xFF00897B), // teal
      Color(0xFF7E57C2), // purple
      Color(0xFFEC407A), // pink
      Color(0xFFFB8C00), // orange
      Color(0xFF43A047), // green
      Color(0xFF039BE5), // light blue
      Color(0xFFF4511E), // deep orange
      Color(0xFF6D4C41), // brown
      Color(0xFF546E7A), // blue grey
      Color(0xFF7CB342), // light green
      Color(0xFFE53935), // red
      Color(0xFFFFB300), // amber
      Color(0xFF8E24AA), // deep purple
      Color(0xFF00ACC1), // cyan
      Color(0xFF5C6BC0), // periwinkle
    ];
    var hash = 0;
    for (final codeUnit in name.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }

  Future<void> _launchApp(AppInfo app) async {
    if (app.executable == null) return;
    final path = AppConfig.resolvePath(app.executable!);
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path], runInShell: false);
    } else {
      await Process.start(path, [], runInShell: true, workingDirectory: File(path).parent.path);
    }
  }
}

class AppConfig {
  AppConfig._();
  static String get projectRoot => Directory.current.path;
  static String get systemConfigPath => '$projectRoot/lib/config/apps_config.json';
  static String get _customPath => '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}/.orbby/custom_apps.json';
  static String resolvePath(String raw) => Platform.isWindows && raw.length > 1 && raw[1] == ':' || raw.startsWith('/') ? raw : '$projectRoot/$raw';
  static List<AppInfo> _load(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return [];
      final list = (jsonDecode(file.readAsStringSync()) as Map)['apps'] as List?;
      return list?.map((e) => AppInfo.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    } catch (_) { return []; }
  }
  static List<AppInfo> loadSystemApps() => _load(systemConfigPath);
  static List<AppInfo> loadCustomApps() => _load(_customPath);
  static Future<void> saveCustomApps(List<AppInfo> apps) async {
    final file = File(_customPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({'apps': apps.map((a) => a.toJson()).toList()}));
  }
  static String get iconsDir => '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}/.orbby/icons';
  static String? convertIcoToPng(String path, String id) {
    try {
      final decoded = img.decodeImage(File(path).readAsBytesSync());
      if (decoded == null) return null;
      final dir = Directory(iconsDir)..createSync(recursive: true);
      final output = '${dir.path}/$id.png';
      File(output).writeAsBytesSync(img.encodePng(decoded));
      return output;
    } catch (_) { return null; }
  }
}
