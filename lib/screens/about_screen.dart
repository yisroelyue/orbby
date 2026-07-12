import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/frosted_panel.dart';
import '../widgets/interactive_icon.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  Future<void> _openUrl(String url) async {
    try {
      await Process.start('cmd', ['/c', 'start', url],
          mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  static const _features = [
    (_Icon.ball, '悬浮球'),
    (_Icon.balance, 'AI流量'),
    (_Icon.vibe, 'Vibe任务'),
    (_Icon.translate, '翻译'),
    (_Icon.todo, '待办事项'),
    (_Icon.favorites, '文件收藏'),
    (_Icon.apps, '应用中心'),
    (_Icon.more, '更多功能'),
  ];

  static const _githubUrl = 'https://github.com/yisroelyue/orbby';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSansSC'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: FrostedPanel(
          color: Colors.white12.withValues(alpha: 0.0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTitleBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // App icon
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/png/logo.png',
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // App name
                        const Text(
                          'Orbby',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Tagline
                        const Text(
                          '悬浮球 · 桌面助手',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Version
                        const Text(
                          'v2.4.0',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white30,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Divider
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 16),
                        // Feature cards grid
                        _buildFeatureGrid(),
                        const SizedBox(height: 20),
                        // GitHub button
                        _buildGitHubButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '关于',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InteractiveIcon(
            onTap: () => windowManager.hide(),
            child: const Icon(Icons.close, color: Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _features.map((f) => _buildFeatureCard(f.$1, f.$2)).toList(),
    );
  }

  Widget _buildFeatureCard(_Icon icon, String label) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon.emoji,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitHubButton() {
    return OutlinedButton.icon(
      onPressed: () => _openUrl(_githubUrl),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text(
        'GitHub',
        style: TextStyle(fontSize: 13),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white60,
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.15),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

enum _Icon {
  ball('🐾'),
  balance('💰'),
  vibe('🤖'),
  translate('🌐'),
  todo('📋'),
  favorites('📁'),
  apps('🧩'),
  more('✨');

  const _Icon(this.emoji);
  final String emoji;
}
