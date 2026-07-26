import 'package:flutter/material.dart';

import '../config/settings.dart';
import '../screens/home_screen.dart';
import 'base_panel.dart';

class ScriptPanel extends BasePanel {
  const ScriptPanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.small;

  @override
  String get panelName => 'script';

  @override
  State<ScriptPanel> createState() => _ScriptPanelState();
}

class _ScriptPanelState extends BasePanelState<ScriptPanel> {
  bool _panelEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
    HomeScreen.refreshNotifier.addListener(_onRefresh);
    registerPanelEnabled((v) => _panelEnabled = v, (s) => s.showScriptPanel);
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
    _panelEnabled = settings.showScriptPanel;
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  bool get panelEnabled => _panelEnabled || _loading;

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题栏
        Row(
          children: [
            Icon(Icons.code_rounded, color: primaryText, size: 22),
            const SizedBox(width: 8),
            Text(
              '脚本库',
              style: TextStyle(
                color: primaryText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 内容区域
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction_rounded,
                color: mutedText,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                '功能开发中',
                style: TextStyle(
                  color: mutedText,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
