import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orbby/core/sub_app.dart';
import 'package:orbby/core/sub_app_registry.dart';
import 'package:orbby_plugin_image_processer/orbby_plugin_image_processer.dart';
import 'package:window_manager/window_manager.dart';

class ImageHandlerApp extends SubApp {
  @override
  String get id => 'image_handler';

  @override
  String get name => '图像处理器';

  @override
  String get description => '裁剪旋转、格式转换、扩图、背景填充、水印';

  @override
  String get iconAsset => 'assets/svg/图像处理.svg';

  @override
  String get packageName => 'orbby';

  @override
  Size get preferredWindowSize => const Size(960, 720);

  @override
  bool get showWindowTitleBar => false;

  @override
  Widget buildApp(BuildContext context) {
    return const _ImageHandlerWrapper();
  }
}

class _ImageHandlerWrapper extends StatelessWidget {
  const _ImageHandlerWrapper();

  static const _textPrimary = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orbby 图像处理器',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
      ),
      home: Column(
        children: [
          _buildTitleBar(),
          const Expanded(child: HomeScreen()),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF252525),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            SvgPicture.asset('assets/svg/图像处理.svg', width: 18, height: 18),
            const SizedBox(width: 8),
            Text('图像处理器',
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none)),
            const Spacer(),
            _TitleBarBtn(
                icon: Icons.minimize_rounded,
                onTap: () => windowManager.minimize()),
            const SizedBox(width: 4),
            _TitleBarBtn(
                icon: Icons.close_rounded, onTap: () => windowManager.hide()),
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

void registerImageHandlerApp() {
  SubAppRegistry.register(() => ImageHandlerApp());
}
