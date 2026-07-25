import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/menu_screen.dart';
import 'base_panel.dart';

class ScriptPanel extends BasePanel {
  const ScriptPanel({super.key});

  @override
  State<ScriptPanel> createState() => _ScriptPanelState();
}

class _ScriptPanelState extends BasePanelState<ScriptPanel> {
  bool _panelEnabled = true;
  bool _loading = true;

  @override
  String get panelTitle => '脚本库';

  @override
  PanelIcon get panelIcon => const PanelIcon.icon(Icons.code_rounded);

  @override
  VoidCallback? get onHeaderTap => null;

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
    _panelEnabled = settings.showScriptPanel;
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  Widget buildContent(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.construction_rounded,
            color: mutedText,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            '功能开发中...',
            style: TextStyle(
              color: mutedText,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '用于管理和运行 Python 脚本',
            style: TextStyle(
              color: mutedText.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
