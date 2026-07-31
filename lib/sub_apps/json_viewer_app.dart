import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orbby/core/sub_app.dart';
import 'package:orbby/core/sub_app_registry.dart';
import 'package:orbby_plugin_json_viewer/orbby_plugin_json_viewer.dart';
import 'package:window_manager/window_manager.dart';

class JsonViewerApp extends SubApp {
  @override
  String get id => 'json_viewer';

  @override
  String get name => 'JSON 查看器';

  @override
  String get description => '编辑、格式化、树形预览 JSON 数据';

  @override
  String get iconAsset => 'assets/svg/JSON查看.svg';

  @override
  String get packageName => 'orbby';

  @override
  Size get preferredWindowSize => const Size(1800, 1200);

  @override
  bool get showWindowTitleBar => false;

  @override
  Widget buildApp(BuildContext context) {
    return const _JsonViewerWrapper();
  }
}

class _JsonViewerWrapper extends StatefulWidget {
  const _JsonViewerWrapper();

  @override
  State<_JsonViewerWrapper> createState() => _JsonViewerWrapperState();
}

class _JsonViewerWrapperState extends State<_JsonViewerWrapper> {
  static const _textPrimary = Color(0xFFE0E0E0);

  bool _isMaximized = false;

  Future<void> _toggleMaximize() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (!mounted) return;
    setState(() => _isMaximized = !maximized);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orbby JSON 查看器',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        body: Column(
          children: [
            _buildTitleBar(),
            const Expanded(child: JsonViewerScreen()),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(color: Color(0xFF252525)),
        child: Row(
          children: [
            const SizedBox(width: 4),
            SvgPicture.asset('assets/svg/JSON查看.svg', width: 18, height: 18),
            const SizedBox(width: 8),
            Text(
              'JSON 查看器',
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
            const Spacer(),
            _TitleBarBtn(
              icon: Icons.minimize_rounded,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 4),
            _TitleBarBtn(
              icon: _isMaximized ? Icons.filter : Icons.filter_none,
              onTap: _toggleMaximize,
            ),
            const SizedBox(width: 4),
            _TitleBarBtn(
              icon: Icons.close_rounded,
              onTap: () => windowManager.hide(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TitleBarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white60, size: 16),
      ),
    );
  }
}

void registerJsonViewerApp() {
  SubAppRegistry.register(() => JsonViewerApp());
}
