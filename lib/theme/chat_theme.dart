import 'package:flutter/material.dart';

/// 聊天主界面（menu 窗口）的主题 token，浅 / 深两套同构。
/// 对照《对话示例-UI重设计参考图》（plan/）：三层底色（surface / raised / sunken）
/// + 三级文字（ink / body / ink2-3）+ 琥珀强调色；浅色使用中性灰底和文字。
///
/// 使用方式：
/// - HomeScreen（part 文件）直接读 State 的 `_themeData` 字段（弹窗等
///   navigator 层 context 在 scope 之外，不能走 [ChatTheme.of]）。
/// - lib/widgets/ 下的展示组件（CommandPalette / 提问卡片 / diff 面板等）
///   经 [ChatTheme.of] 取 token，由 HomeScreen 在 body 外包 [ChatThemeScope]。
@immutable
class ChatThemeData {
  const ChatThemeData({
    required this.isDark,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.barBg,
    required this.line,
    required this.lineSoft,
    required this.ink,
    required this.body,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
    required this.tagBg,
    required this.tagFg,
    required this.codeInlineBg,
    required this.hover,
    required this.userMessageBg,
    required this.danger,
    required this.dangerSoft,
    required this.ok,
    required this.okSoft,
    required this.info,
    required this.infoSoft,
    required this.run,
    required this.done,
    required this.term,
    required this.markBg,
    required this.markFg,
    required this.markLine,
    required this.windowShadows,
    required this.cardShadows,
    required this.popShadows,
    required this.selectionColor,
  });

  /// 是否深色（MaterialApp brightness 与个别反色逻辑用）
  final bool isDark;

  /// 窗口底 = 内容区底（两者同色，靠 tab 栏 hairline 分隔）
  final Color surface;

  /// 「浮起来」的东西：激活 tab、输入框、命令面板、提问卡片、diff 面板
  final Color raised;

  /// 「沉下去」的东西：diff 正文底、卡片内输入框
  final Color sunken;

  /// 两段式卡片的顶部条底色（提问记录卡 / 代码块标题条）。
  /// 与 [sunken] 分开维护，顶栏使用更轻的中性灰。
  final Color barBg;

  final Color line;
  final Color lineSoft;

  /// 最强文字：用户消息、标题、路径
  final Color ink;

  /// 次强：Agent 正文、代码正文
  final Color body;

  /// 元信息：工具行标题、问题文案
  final Color ink2;

  /// 最弱：参数、占位、提示、时间
  final Color ink3;

  final Color accent;
  final Color accentDeep;
  final Color accentSoft;

  /// 中性灰标签（底/字）：留痕卡（QuestionRecordCard）的「?」徽标与
  /// header 标签。刻意不用琥珀——留痕是历史记录，不与进行中提问卡片的
  /// accentSoft 标签抢注意；底色须在 [barBg] 顶栏上有可辨区分度。
  final Color tagBg;
  final Color tagFg;

  /// 行内代码（正文 `code` 片段）底色：中性灰，不承琥珀调。
  /// 刻意独立于 [accentSoft]——后者还是 header 标签 / 聚焦光环的品牌色。
  final Color codeInlineBg;

  final Color hover;
  /// 用户消息气泡底色，独立于控件悬停态。
  final Color userMessageBg;
  final Color danger;
  final Color dangerSoft;
  final Color ok;
  final Color okSoft;
  final Color info;
  final Color infoSoft;

  /// 状态圆点：运行橙（工具组概览）/ 完成绿（ORBBY 标签）/ 终止红（ORBBY 标签）
  final Color run;
  final Color done;
  final Color term;

  /// 空态品牌块（墨底圆角方块 + 三条横线）
  final Color markBg;
  final Color markFg;
  final Color markLine;

  /// 窗口本体投影（浅色柔和、深色重）
  final List<BoxShadow> windowShadows;

  /// 卡片级微影
  final List<BoxShadow> cardShadows;

  /// 浮层（命令面板 / 提问卡片 / 浮钮）投影
  final List<BoxShadow> popShadows;

  /// 聊天区文字选中高亮
  final Color selectionColor;

  static const ChatThemeData light = ChatThemeData(
    isDark: false,
    surface: Color(0xFFFCFCFC),
    raised: Color(0xFFFFFFFF),
    sunken: Color(0xFFF2F2F2),
    // 中性灰（不带黄调），比 raised 白略深一档
    barBg: Color(0xFFF5F5F5),
    line: Color(0xFFE3E3E3),
    lineSoft: Color(0xFFECECEC),
    ink: Color(0xFF202020),
    body: Color(0xFF676B70),
    ink2: Color(0xFF626262),
    ink3: Color(0xFF858585),
    accent: Color(0xFFFFC145),
    accentDeep: Color(0xFF9C6E14),
    accentSoft: Color(0xFFFFF6E2),
    // 灰标签：在 barBg(#F5F5F5) 顶栏上可辨的一档灰底（值近 lineSoft，语义分开维护）
    tagBg: Color(0xFFE9E9E9),
    tagFg: Color(0xFF626262),
    codeInlineBg: Color(0xFFF5F5F5),
    hover: Color(0xFFEAEAEA),
    userMessageBg: Color(0xFFF2F3F4),
    danger: Color(0xFFC0483C),
    dangerSoft: Color(0xFFFBEDEA),
    ok: Color(0xFF3E9E63),
    okSoft: Color(0xFFEAF6EF),
    info: Color(0xFF3E7BC4),
    infoSoft: Color(0xFFEAF1FA),
    run: Color(0xFFE08A2B),
    done: Color(0xFF4FB477),
    term: Color(0xFFD9534F),
    markBg: Color(0xFF1F2A44),
    markFg: Color(0xFFFFFFFF),
    markLine: Colors.transparent,
    // 阴影只在窗口内的呼吸区（_windowMargin）里能渲染，超出窗口边界的部分
    // 会被系统裁掉，故 blur/spread 按呼吸区宽度收敛，避免"看不见的投影"
    windowShadows: [
      BoxShadow(color: Color(0x121F2A44), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x4D1F2A44), blurRadius: 20, offset: Offset(0, 8), spreadRadius: -6),
    ],
    cardShadows: [
      BoxShadow(color: Color(0x0A1F2A44), blurRadius: 2, offset: Offset(0, 1)),
    ],
    popShadows: [
      BoxShadow(color: Color(0x0F1F2A44), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x331F2A44), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -12),
    ],
    selectionColor: Color(0x339C6E14),
  );

  static const ChatThemeData dark = ChatThemeData(
    isDark: true,
    // 色板对齐参考稿（plan/对话示例-UI重设计参考图.html）.dark 变量：
    // 炭灰窗口底 / 卡片 / 沉底、更亮的描边与 hover；正文提亮为柔和灰白。
    // ink2/ink3 刻意高于参考的 secondary/muted——工具行小字按可读性要求提亮过。
    surface: Color(0xFF1B1C1E),
    raised: Color(0xFF222326),
    sunken: Color(0xFF202123),
    // 冷灰，比 raised(#222326) 深一档（代码块标题条 / 留痕卡头）
    barBg: Color(0xFF1D2023),
    line: Color(0xFF383A3E),
    lineSoft: Color(0xFF2E3034),
    ink: Color(0xFFE9E9EB),
    body: Color(0xFFD8DADF),
    ink2: Color(0xFFACB4C2),
    ink3: Color(0xFF838B99),
    accent: Color(0xFFFFC145),
    accentDeep: Color(0xFFF0B93C),
    accentSoft: Color(0x24FFC145),
    // 灰标签：在 barBg(#1D2023) 顶栏上可辨的一档灰底（值同 lineSoft，语义分开维护）
    tagBg: Color(0xFF2E3034),
    tagFg: Color(0xFFACB4C2),
    codeInlineBg: Color(0x0DFFFFFF),
    hover: Color(0xFF2C2E31),
    userMessageBg: Color(0xFF2C2E31),
    danger: Color(0xFFE4705F),
    dangerSoft: Color(0x24E4705F),
    ok: Color(0xFF5CC98A),
    okSoft: Color(0x215CC98A),
    info: Color(0xFF75A9E6),
    infoSoft: Color(0x2475A9E6),
    run: Color(0xFFF0A94B),
    done: Color(0xFF57C88A),
    term: Color(0xFFE4685C),
    markBg: Color(0xFF2C313A),
    markFg: Color(0xFFF2F4F8),
    markLine: Color(0x1AFFFFFF),
    // 同浅色：收敛到窗口内呼吸区可承载的范围
    windowShadows: [
      BoxShadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0xBF000000), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -6),
    ],
    cardShadows: [
      BoxShadow(color: Color(0x59000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
    popShadows: [
      BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0xB3000000), blurRadius: 34, offset: Offset(0, 16), spreadRadius: -14),
    ],
    selectionColor: Color(0xFF4A4A4A),
  );
}

/// 把 [ChatThemeData] 注入子树；widgets 组件经 [ChatTheme.of] 读取。
/// Scope 只包在 HomeScreen 的 body 内（弹窗走 navigator 层 context，
/// 在 scope 之外，请直接用宿主 State 的主题字段）。
class ChatThemeScope extends InheritedWidget {
  const ChatThemeScope({
    super.key,
    required this.data,
    required super.child,
  });

  final ChatThemeData data;

  static ChatThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChatThemeScope>();
    return scope?.data ?? ChatThemeData.dark;
  }

  @override
  bool updateShouldNotify(ChatThemeScope oldWidget) => data != oldWidget.data;
}

/// 展示组件的取用门面：`ChatTheme.of(context)`。
/// 内部即 [ChatThemeScope] 查找，单独暴露一层是为了让组件不必知道 Scope
/// 的存在（将来换注入方式只改这里）。
///
/// 字体也收在这里：字体与明暗主题无关，所以不做成 [ChatThemeData] 的字段，
/// 但同样要求**组件不得硬编码字体名**——换字体只改这两个常量。
abstract final class ChatTheme {
  static ChatThemeData of(BuildContext context) => ChatThemeScope.of(context);

  /// 正文与 UI 文案字体（Windows 系统字体，无需内嵌）。
  static const String fontFamily = 'Microsoft YaHei';

  /// 等宽字体：代码块、工具 diff、文件路径。无中文字形，
  /// 中文由系统字体兜底（Flutter 不会自动回退到 [fontFamily]）。
  static const String codeFont = 'JetBrains Mono';
}
