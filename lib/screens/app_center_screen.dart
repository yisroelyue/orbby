import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../config/settings.dart';
import '../services/windows_app_icon.dart';
import '../services/log_service.dart';
import '../widgets/app_square_panel.dart';
import '../widgets/interactive_icon.dart';
import 'home_screen.dart';

class AppCenterScreen extends StatefulWidget {
  const AppCenterScreen({super.key});

  static const panelChannel = WindowMethodChannel(
    'orbby_app_center_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<AppCenterScreen> createState() => _AppCenterScreenState();
}

class _AppCenterScreenState extends State<AppCenterScreen> {
  List<AppInfo> _systemApps = [];
  List<AppInfo> _customApps = [];
  List<String> _panelAppIds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await SettingsService.load();
    final systemApps = AppConfig.loadSystemApps();
    final customApps = AppConfig.loadCustomApps();
    setState(() {
      _systemApps = systemApps;
      _customApps = customApps;
      // 过滤掉已失效的面板 id（如旧架构残留），避免计数虚高导致右键菜单异常
      _panelAppIds = settings.panelAppIds
          .where((id) => [...customApps, ...systemApps].any((a) => a.id == id))
          .toList();
      _loading = false;
    });
    // 有失效 id 被过滤时写回，持久化清理脏数据
    if (_panelAppIds.length != settings.panelAppIds.length) {
      await _savePanel();
    }
  }

  List<AppInfo> get _allApps => [..._customApps, ..._systemApps];

  Future<void> _savePanel() async {
    final settings = await SettingsService.load();
    settings.panelAppIds = _panelAppIds;
    await SettingsService.save(settings);
    AppCenterScreen.panelChannel.invokeMethod('panel_changed');
  }

  bool _isInPanel(String id) => _panelAppIds.contains(id);

  Future<void> _showOrderMenu(BuildContext ctx, Offset position, AppInfo app) async {
    final action = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: const [
        PopupMenuItem(value: 'first', child: Text('移到最前')),
        PopupMenuItem(value: 'up', child: Text('上移')),
        PopupMenuItem(value: 'down', child: Text('下移')),
        PopupMenuItem(value: 'last', child: Text('移到最后')),
      ],
    );
    if (action == null) return;
    final apps = [..._allApps];
    final index = apps.indexWhere((item) => item.id == app.id);
    if (index < 0) return;
    final target = switch (action) {
      'first' => 0,
      'up' => index - 1,
      'down' => index + 1,
      'last' => apps.length - 1,
      _ => index,
    }.clamp(0, apps.length - 1);
    if (target == index) return;
    final moved = apps.removeAt(index);
    apps.insert(target, moved);
    setState(() {
      _customApps = apps.where((item) => item.type == 'custom').toList();
      _systemApps = apps.where((item) => item.type != 'custom').toList();
      _panelAppIds = apps.map((item) => item.id).toList();
    });
    await _savePanel();
  }

  void _showContextMenu(BuildContext ctx, Offset position, AppInfo app) {
    final alreadyIn = _isInPanel(app.id);
    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        if (alreadyIn)
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, color: Colors.black54, size: 18),
                SizedBox(width: 8),
                Text('从面板移除', style: TextStyle(color: Colors.black54, fontSize: 14)),
              ],
            ),
          )
        else if (!alreadyIn)
          const PopupMenuItem(
            value: 'add',
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.black54, size: 18),
                SizedBox(width: 8),
                Text('加入显示面板', style: TextStyle(color: Colors.black54, fontSize: 14)),
              ],
            ),
          )
        else if (false)
          const PopupMenuItem(
            enabled: false,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.black26, size: 18),
                SizedBox(width: 8),
                Text('显示面板已满', style: TextStyle(color: Colors.black38, fontSize: 14)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'add') {
        setState(() => _panelAppIds.add(app.id));
        _savePanel();
      } else if (value == 'remove') {
        setState(() => _panelAppIds.remove(app.id));
        _savePanel();
      }
    });
  }

  Future<void> _addCustomApp() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => const _AddAppDialog(),
    );
    if (result == null) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    var icon = result['icon'] ?? 'assets/svg/应用.svg';
    if (icon.toLowerCase().endsWith('.ico')) {
      icon = AppConfig.convertIcoToPng(icon, id) ?? 'assets/svg/应用.svg';
    }
    final executable = result['path'];
    LogService.info('添加应用：${result['name']}，可执行文件：$executable', category: 'system');
    if (executable != null && Platform.isWindows) {
      try {
        final iconBytes = await WindowsAppIcon.fromExecutable(executable);
        if (iconBytes != null) {
          final iconFile = File('${AppConfig.iconsDir}/$id.png');
          await iconFile.parent.create(recursive: true);
          await iconFile.writeAsBytes(iconBytes);
          icon = iconFile.path;
        }
      } catch (e, stack) {
        // 图标读取失败时保留已选择的图标或默认图标。
      }
    }
    final name = (result['name']?.trim().isNotEmpty == true)
        ? result['name']!.trim()
        : File(executable ?? '').uri.pathSegments.last
            .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final app = AppInfo(
      id: id,
      name: name,
      executable: executable,
      icon: icon,
      type: 'custom',
    );
    _customApps.add(app);
    await AppConfig.saveCustomApps(_customApps);
    HomeScreen.triggerSettingsChange();
    await AppCenterScreen.panelChannel.invokeMethod('panel_changed');
    setState(() {});
  }

  Future<void> _removeCustomApp(AppInfo app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF5F5F5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除',
            style: TextStyle(color: Colors.black87, fontSize: 16)),
        content: Text('确定要删除「${app.name}」吗？',
            style: const TextStyle(color: Colors.black54, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: Colors.black38, fontSize: 14)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除',
                style: TextStyle(color: Colors.redAccent, fontSize: 14)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _customApps.removeWhere((a) => a.id == app.id);
    _panelAppIds.remove(app.id);
    await AppConfig.saveCustomApps(_customApps);
    await _savePanel();
    setState(() {});
  }

  void _launch(AppInfo app) async {
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
        
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.black26,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8),
                        children: [
                          _buildTitleBar(),
                          const SizedBox(height: 16),
                          if (false) _buildSection(
                            title: 'Orbby应用',
                            apps: _systemApps,
                            isSystem: true,
                          ),
                          _buildSection(
                            title: '',
                            apps: _allApps,
                            isSystem: true,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
      children: [
        SvgPicture.asset('assets/svg/应用.svg', width: 22, height: 22),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '应用',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        InteractiveIcon(
          size: 30,
          onTap: () => windowManager.hide(),
          child: const Icon(Icons.close, color: Colors.black38, size: 18),
        ),
      ],
      ),
    );
  }

  List<AppInfo> get _panelApps {
    return _panelAppIds
        .map((id) => _allApps.where((a) => a.id == id))
        .expand((m) => m)
        .toList();
  }

  Widget _buildPanelBar() {
    final filled = _panelApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              '面板中显示',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${filled.length})',
              style: const TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filled.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '右键下方应用来添加到显示面板',
                  style: TextStyle(color: Colors.black38, fontSize: 13),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
              ),
              itemCount: filled.length,
              itemBuilder: (_, index) => _buildSlot(index, filled),
            ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSlot(int index, List<AppInfo> filled) {
    if (index < filled.length) {
      final app = filled[index];
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _launch(app),
          onSecondaryTapUp: (_) {
            setState(() => _panelAppIds.remove(app.id));
            _savePanel();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: app.hasIcon
                      ? _buildAppIcon(app)
                      : Text(
                          app.name.isNotEmpty ? app.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                app.name,
                style: const TextStyle(color: Colors.black87, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<AppInfo> apps,
    required bool isSystem,
  }) {
    final tileCount = apps.length + 1; // 最后一格为添加应用

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (title.isNotEmpty) Text(
              title,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (title.isNotEmpty) const SizedBox(width: 6),
            if (title.isNotEmpty) Text(
              '(${apps.length})',
              style: const TextStyle(color: Colors.black38, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (tileCount == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                '暂无应用',
                style: TextStyle(color: Colors.black38, fontSize: 13),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.9,
            ),
            itemCount: tileCount,
            itemBuilder: (_, index) {
              if (index == apps.length) {
                return _buildAddTile();
              }
              final app = apps[index];
              return _buildAppTile(
                app,
                isSystem: app.type != 'custom',
                index: index,
              );
            },
          ),
      ],
    );
  }

  Widget _buildAppTile(AppInfo app, {required bool isSystem, required int index}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (app.type == 'custom') _removeCustomApp(app);
        },
        onSecondaryTapUp: (details) => _showOrderMenu(context, details.globalPosition, app),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _isInPanel(app.id)
                        ? Colors.black.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: app.hasIcon
                        ? _buildAppIcon(app)
                        : Text(
                            app.name.isNotEmpty ? app.name[0] : '?',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                if (!isSystem)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: GestureDetector(
                      onTap: () => _removeCustomApp(app),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.black38, size: 11),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              app.name,
              style: const TextStyle(color: Colors.black87, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTile() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _addCustomApp,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.1),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.add, color: Colors.black38, size: 24),
            ),
            const SizedBox(height: 6),
            const Text(
              '添加',
              style: TextStyle(color: Colors.black38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon(AppInfo app) {
    if (app.icon.startsWith('assets/')) {
      if (app.icon.endsWith('.svg')) {
        return SvgPicture.asset(app.icon, width: 24, height: 24);
      }
      return Image.asset(
        app.icon,
        width: 24,
        height: 24,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.apps, color: Colors.white54, size: 24),
      );
    }

    final path = AppConfig.resolvePath(app.icon);
    final file = File(path);
    if (!file.existsSync()) {
      return const Icon(Icons.apps, color: Colors.white54, size: 24);
    }
    if (app.icon.endsWith('.svg')) {
      return SvgPicture.file(file, width: 24, height: 24);
    }
    return Image.file(
      file,
      width: 24,
      height: 24,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.apps, color: Colors.white54, size: 24),
    );
  }
}

class _AddAppDialog extends StatefulWidget {
  const _AddAppDialog();

  @override
  State<_AddAppDialog> createState() => _AddAppDialogState();
}

class _AddAppDialogState extends State<_AddAppDialog> {
  final _nameCtrl = TextEditingController();
  String? _selectedPath;
  String? _selectedIcon;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe', 'bat', 'cmd', 'msi', 'lnk'],
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path == null) return;
      setState(() {
        _selectedPath = path;
        _selectedIcon = _findIco(path);
      });
    }
  }

  /// 在选中程序的同目录查找 .ico 图标（优先与程序同名，其次第一个）。
  String? _findIco(String exePath) {
    try {
      final dir = Directory(File(exePath).parent.path);
      if (!dir.existsSync()) return null;
      final icos = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.ico'))
          .toList();
      if (icos.isEmpty) return null;
      final base = File(exePath)
          .uri
          .pathSegments
          .last
          .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
      for (final f in icos) {
        if (f.uri.pathSegments.last.toLowerCase() == '$base.ico') {
          return f.path;
        }
      }
      return icos.first.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '添加应用',
        style: TextStyle(color: Colors.black87, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (false) TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.black87, fontSize: 14),
              cursorColor: Colors.black54,
              decoration: InputDecoration(
                hintText: '应用名称',
                hintStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.35), fontSize: 14),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open_rounded,
                        color: Colors.black54, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedPath ?? '选择应用文件',
                        style: TextStyle(
                          color: _selectedPath != null
                              ? Colors.black54
                              : Colors.black.withValues(alpha: 0.35),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Colors.black38, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (_selectedPath == null) return;
            Navigator.of(context).pop({
              'name': name,
              'path': _selectedPath,
              'icon': _selectedIcon ?? 'assets/svg/应用.svg',
            });
          },
          child: const Text(
            '添加',
            style: TextStyle(color: Colors.black87, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
