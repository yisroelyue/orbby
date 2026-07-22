import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/sub_app_registry.dart';

/// 通用子应用窗口，根据 subAppId 从注册表中查找 SubApp 并渲染其 buildApp()。
class SubAppWindowScreen extends StatelessWidget {
  const SubAppWindowScreen({super.key, required this.subAppId});

  final String subAppId;

  @override
  Widget build(BuildContext context) {
    final subApp = SubAppRegistry.byId(subAppId);
    if (subApp == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Microsoft YaHei'),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Text(
              'Sub-app not found: $subAppId',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Microsoft YaHei'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            if (subApp.showWindowTitleBar) _buildTitleBar(subApp.name),
            Expanded(child: subApp.buildApp(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(String title) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _windowButton(
              icon: Icons.minimize_rounded,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 4),
            _windowButton(
              icon: Icons.close_rounded,
              onTap: () => windowManager.hide(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.white54, size: 16),
      ),
    );
  }
}
