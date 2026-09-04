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
  static const _githubUrl = 'https://github.com/yisroelyue/orbby';
  static const _features = [
    _Feature(Icons.track_changes_rounded, '悬浮球状态栏', '随时唤起 Orbby', Color(0xFF9B8AFB)),
    _Feature(Icons.api_rounded, 'API 状态', '余额用量一目了然', Color(0xFF73A7FF)),
    _Feature(Icons.note_alt_rounded, '我的笔记', '快速记下灵感', Color(0xFFFF7E9D)),
    _Feature(Icons.folder_special_rounded, '文件收藏', '好东西从不丢失', Color(0xFF2C9C81)),
    _Feature(Icons.smart_toy_rounded, 'Orbby agent', '快速解决你的烦恼问题', Color(0xFF425EE1)),
    _Feature(Icons.apps_rounded, '应用中心', '扩展你的工作方式', Color(0xFFB28CFF)),
    _Feature(Icons.translate_rounded, '翻译助手', '快速理解每句话', Color(0xFFFFB86B)),
    _Feature(Icons.content_paste_rounded, '快速剪切板', '加速工作效率', Color(0xFFB8879E)),
    _Feature(Icons.more_horiz_rounded, '更多功能', '更多能力开发中', Color(0xFF367340)),
  ];

  @override
  void initState() { super.initState(); windowManager.addListener(this); }

  @override
  void dispose() { windowManager.removeListener(this); super.dispose(); }

  @override
  void onWindowClose() => windowManager.hide();

  Future<void> _openUrl(String url) async {
    try { await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Microsoft YaHei'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: FrostedPanel(
          color: const Color(0xFF11121B),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            child: Column(children: [
              _buildTitleBar(),
              Expanded(child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _buildHero(),
                    const SizedBox(height: 22),
                    const Text('Orbby 能为你做什么', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _buildFeatureGrid(),
                    const SizedBox(height: 22),
                    _buildSummaryCard(),
                    const SizedBox(height: 22),
                    _buildDeveloperInfo(),
                    const SizedBox(height: 22),
                    _buildFooter(),
                  ]),
                ),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFF9B8AFB).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.info_outline_rounded, color: Color(0xFFB9ABFF), size: 16)),
      const SizedBox(width: 9),
      const Expanded(child: Text('关于 Orbby', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
      InteractiveIcon(onTap: () => windowManager.hide(), child: const Icon(Icons.close_rounded, color: Colors.white54, size: 19)),
    ]),
  );

  Widget _buildHero() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF292344), Color(0xFF1A2635)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.09))),
    child: Row(children: [
      Container(width: 64, height: 64, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)), child: Image.asset('assets/png/logo.png')),
      const SizedBox(width: 15),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Orbby', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('你的桌面智能助手', style: TextStyle(color: Colors.white70, fontSize: 13)), SizedBox(height: 9), Row(children: [_StatusDot(), SizedBox(width: 6), Text('已就绪', style: TextStyle(color: Color(0xFF8FE4C8), fontSize: 11, fontWeight: FontWeight.w600))])])),
      const Text('v2.4.0', style: TextStyle(color: Colors.white38, fontSize: 11)),
    ]),
  );

  Widget _buildFeatureGrid() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _features.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 2.0),
    itemBuilder: (_, index) {
      final feature = _features[index];
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.055), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: feature.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)), child: Icon(feature.icon, color: feature.color, size: 19)),
          const SizedBox(width: 9),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(feature.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 3), Text(feature.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 10))])),
        ]),
      );
    },
  );

  Widget _buildSummaryCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(color: const Color(0xFF8F82E8).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
    child: const Row(children: [Icon(Icons.bolt_rounded, color: Color(0xFFC1B7FF), size: 20), SizedBox(width: 10), Expanded(child: Text('从灵感记录到 AI 协作，把常用能力放在桌面触手可及的位置。', style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 12)))]),
  );

  Widget _buildDeveloperInfo() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.055), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF73A7FF).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.person_rounded, color: Color(0xFF73A7FF), size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('开发者', style: TextStyle(color: Colors.white54, fontSize: 10)),
        const SizedBox(height: 2),
        const Text('Yisroel', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        GestureDetector(onTap: () => _openUrl('mailto:Yisroel.yue@gmail.com'), child: const Text('Yisroel.yue@gmail.com', style: TextStyle(color: Color(0xFF73A7FF), fontSize: 11))),
      ])),
    ]),
  );

  Widget _buildFooter() => Row(children: [
    const Expanded(child: Text('开源项目 · 专注于效率', style: TextStyle(color: Colors.white30, fontSize: 10))),
    OutlinedButton.icon(onPressed: () => _openUrl(_githubUrl), icon: const Icon(Icons.open_in_new_rounded, size: 14), label: const Text('GitHub', style: TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: BorderSide(color: Colors.white.withValues(alpha: 0.16)), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
  ]);
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) => Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF8FE4C8), shape: BoxShape.circle));
}

class _Feature {
  const _Feature(this.icon, this.title, this.subtitle, this.color);
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}
