import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../config/settings.dart';
import '../core/sub_app.dart';
import '../core/sub_app_registry.dart';
import '../widgets/app_square_panel.dart';
import '../widgets/interactive_icon.dart';

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
    setState(() {
      _systemApps = AppConfig.loadSystemApps();
      _customApps = AppConfig.loadCustomApps();
      _panelAppIds = settings.panelAppIds;
      _loading = false;
    });
  }

  List<AppInfo> get _allApps => [..._customApps, ..._systemApps];

  Future<void> _savePanel() async {
    final settings = await SettingsService.load();
    settings.panelAppIds = _panelAppIds;
    await SettingsService.save(settings);
    AppCenterScreen.panelChannel.invokeMethod('panel_changed');
  }

  bool _isInPanel(String id) => _panelAppIds.contains(id);

  void _showContextMenu(BuildContext ctx, Offset position, AppInfo app) {
    final alreadyIn = _isInPanel(app.id);
    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF2E2E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        if (alreadyIn)
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, color: Colors.white54, size: 18),
                SizedBox(width: 8),
                Text('从面板移除', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          )
        else if (_panelAppIds.length < 8)
          const PopupMenuItem(
            value: 'add',
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.white54, size: 18),
                SizedBox(width: 8),
                Text('加入显示面板', style: TextStyle(color: Colors.white70, fontSize: 14)),
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
    final launchType = result['launchType'] ?? 'executable';
    final app = AppInfo(
      id: id,
      name: result['name']!,
      executable: launchType == 'executable' ? result['path'] : null,
      subAppId: launchType == 'plugin' ? result['subAppId'] : null,
      icon: launchType == 'plugin' ? result['icon'] ?? 'assets/svg/应用.svg' : 'assets/svg/应用.svg',
      type: 'custom',
      launchType: launchType,
    );
    _customApps.add(app);
    await AppConfig.saveCustomApps(_customApps);
    setState(() {});
  }

  Future<void> _removeCustomApp(AppInfo app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('确定要删除「${app.name}」吗？',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
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
    if (app.launchType == 'plugin' && app.subAppId != null) {
      AppCenterScreen.panelChannel.invokeMethod('launch_sub_app', {
        'subAppId': app.subAppId!,
      });
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
        debugPrint('Failed to launch "${app.name}": $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A2A2A),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitleBar(),
              if (!_loading) _buildPanelBar(),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      strokeWidth: 2,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 8),
                    children: [
                      _buildSection(
                        title: 'Orbby应用',
                        apps: _systemApps,
                        isSystem: true,
                      ),

                      _buildSection(
                        title: '用户应用',
                        apps: _customApps,
                        isSystem: false,
                      ),
                    ],
                  ),
                ),
            ],
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
            '应用中心',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        InteractiveIcon(
          size: 30,
          onTap: () => windowManager.hide(),
          child: const Icon(Icons.close, color: Colors.white54, size: 18),
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
    const maxSlots = 8;
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
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${filled.length}/$maxSlots)',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filled.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '右键下方应用来添加到显示面板',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                children: [
                  for (int i = 0; i < filled.length; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i > 0 ? 20 : 0),
                      child: _buildSlot(i, filled),
                    ),
                ],
              ),
              ),
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
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: app.type == 'system'
                      ? _buildAppIcon(app)
                      : Text(
                          app.name.isNotEmpty ? app.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                app.name,
                style: const TextStyle(color: Colors.white, fontSize: 12),
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
          color: Colors.white.withValues(alpha: 0.06),
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
    final tileCount = isSystem ? apps.length : apps.length + 1; // +1 for add tile

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${apps.length})',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (tileCount == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                '暂无应用',
                style: TextStyle(color: Colors.white38, fontSize: 13),
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
              if (!isSystem && index == apps.length) {
                return _buildAddTile();
              }
              return _buildAppTile(apps[index], isSystem: isSystem, index: index);
            },
          ),
      ],
    );
  }

  Widget _buildAppTile(AppInfo app, {required bool isSystem, required int index}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _launch(app),
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition, app),
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
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: isSystem
                        ? _buildAppIcon(app)
                        : Text(
                            app.name.isNotEmpty ? app.name[0] : '?',
                            style: const TextStyle(
                              color: Colors.white54,
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
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white38, size: 11),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              app.name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
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
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.add, color: Colors.white38, size: 24),
            ),
            const SizedBox(height: 6),
            const Text(
              '添加',
              style: TextStyle(color: Colors.white38, fontSize: 12),
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
  String _mode = 'executable'; // 'plugin' or 'executable'
  String? _selectedPluginId;
  SubApp? _selectedPlugin;

  List<SubApp> get _plugins => SubAppRegistry.all;

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
      setState(() => _selectedPath = result.files.first.path);
    }
  }

  void _selectPlugin(SubApp plugin) {
    setState(() {
      _selectedPlugin = plugin;
      _selectedPluginId = plugin.id;
      _nameCtrl.text = plugin.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '添加应用',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode toggle
            Row(
              children: [
                _buildModeChip('外部程序', 'executable'),
                const SizedBox(width: 8),
                _buildModeChip('已注册插件', 'plugin'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white70,
              decoration: InputDecoration(
                hintText: '应用名称',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            if (_mode == 'executable')
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_rounded,
                          color: Colors.white54, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedPath ?? '选择应用文件',
                          style: TextStyle(
                            color: _selectedPath != null
                                ? Colors.white70
                                : Colors.white.withValues(alpha: 0.35),
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._plugins.map((p) => GestureDetector(
                    onTap: () => _selectPlugin(p),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _selectedPluginId == p.id
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: _selectedPluginId == p.id
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.2))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ),
                          if (p.description.isNotEmpty)
                            Text(
                              p.description,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            if (_mode == 'executable' && _selectedPath == null) return;
            if (_mode == 'plugin' && _selectedPluginId == null) return;
            Navigator.of(context).pop({
              'name': name,
              'path': _selectedPath,
              'launchType': _mode,
              'subAppId': _selectedPluginId,
              'icon': _selectedPlugin?.iconAsset,
            });
          },
          child: const Text(
            '添加',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip(String label, String value) {
    final active = _mode == value;
    return GestureDetector(
      onTap: () => setState(() => _mode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white38,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
