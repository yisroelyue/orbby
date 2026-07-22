import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../config/constants.dart';
import '../config/settings.dart';
import '../services/chat_storage_service.dart';
import '../widgets/typing_indicator.dart';

class AgentChatPopup extends StatefulWidget {
  const AgentChatPopup({super.key});

  static const popupChannel = WindowMethodChannel(
    'orbby_agent_chat_popup_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<AgentChatPopup> createState() => _AgentChatPopupState();
}

class _AgentChatPopupState extends State<AgentChatPopup>
    with TickerProviderStateMixin, WindowListener {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _messages = <_ChatMessage>[];
  AgentChatPalette _theme = AgentChatColors.light;
  String _themeName = 'light';
  String _mode = 'accept';
  String? _selectedAction;
  String? _hoveredAction;
  bool _isSending = false;
  bool _isMaximized = false;
  bool _wasFocused = false;

  // 对话管理
  List<ChatConversation> _conversations = [];
  String? _currentConversationId;
  String _currentModel = '';

  // 用户信息
  String _userName = '';
  String _userAvatarPath = '';

  // 侧边栏 hover 状态
  String? _hoveredConvId;
  bool _isHoveredNewChat = false;
  bool _isHoveredClearAll = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    if (_wasFocused) {
      // 窗口已经获得焦点时再次获得焦点（点击任务栏图标）→ 最小化
      windowManager.minimize();
      _wasFocused = false;
    } else {
      _wasFocused = true;
      AgentChatPopup.popupChannel.invokeMethod('popup_focus_changed', {'focused': true});
    }
  }

  @override
  void onWindowBlur() {
    _wasFocused = false;
    AgentChatPopup.popupChannel.invokeMethod('popup_focus_changed', {'focused': false});
  }

  @override
  void onWindowMinimize() {
    AgentChatPopup.popupChannel.invokeMethod('popup_minimized', {'minimized': true});
  }

  @override
  void onWindowRestore() {
    AgentChatPopup.popupChannel.invokeMethod('popup_minimized', {'minimized': false});
  }

  Future<void> _init() async {
    final c = await WindowController.fromCurrentEngine();
    c.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'set_data':
          final args = call.arguments as Map;
          final w = (args['width'] as num?)?.toDouble() ?? 400;
          final h = (args['height'] as num?)?.toDouble() ?? 500;
          final l = (args['left'] as num?)?.toDouble() ?? 0;
          final t = (args['top'] as num?)?.toDouble() ?? 0;
          final theme = args['theme'] as String? ?? 'light';
          final model = args['model'] as String? ?? '';
          await windowManager.setMinimumSize(const Size(600, 500));
          await windowManager.setMaximumSize(const Size(3840, 2160));
          await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
          await windowManager.show();
          if (mounted) {
            setState(() {
              _theme = AgentChatColors.of(theme);
              _themeName = theme;
              _currentModel = model;
            });
          }
          // 加载对话列表
          await _loadConversations();
          return;
        case 'set_model':
          final args = call.arguments as Map;
          if (mounted) {
            setState(() {
              _currentModel = args['model'] as String? ?? '';
            });
          }
          return;
        case 'conversation_created':
          final args = call.arguments as Map;
          final id = args['id'] as String? ?? '';
          final title = args['title'] as String? ?? '';
          if (mounted && id.isNotEmpty) {
            setState(() {
              _currentConversationId = id;
              _messages.clear();
              // 添加到列表顶部
              _conversations.insert(
                0,
                ChatConversation(id: id, title: title, model: _currentModel, mode: _mode),
              );
            });
          }
          return;
        case 'conversation_loaded':
          final args = call.arguments as Map;
          final messages = (args['messages'] as List<dynamic>?)
                  ?.map((e) => Map<String, String>.from(e as Map))
                  .toList() ??
              [];
          if (mounted) {
            setState(() {
              _messages.clear();
              for (final msg in messages) {
                _messages.add(_ChatMessage(
                  text: msg['content'] ?? '',
                  isUser: msg['role'] == 'user',
                ));
              }
            });
            _scrollToBottom();
          }
          return;
        case 'conversation_deleted':
          final args = call.arguments as Map;
          final id = args['id'] as String? ?? '';
          if (mounted && id.isNotEmpty) {
            setState(() {
              _conversations.removeWhere((c) => c.id == id);
              if (_currentConversationId == id) {
                _currentConversationId = null;
                _messages.clear();
              }
            });
          }
          return;
        case 'all_conversations_cleared':
          if (mounted) {
            setState(() {
              _conversations.clear();
              _currentConversationId = null;
              _messages.clear();
            });
          }
          return;
        case 'clear_messages':
          setState(() => _messages.clear());
          return;
        case 'remove_last_message':
          if (_messages.isNotEmpty) {
            setState(() => _messages.removeLast());
          }
          return;
        case 'focus_window':
          await windowManager.show();
          await windowManager.focus();
          return;
        case 'minimize_window':
          await windowManager.minimize();
          return;
        case 'restore_window':
          await windowManager.restore();
          await windowManager.show();
          await windowManager.focus();
          return;
        case 'add_message':
          final args = call.arguments as Map;
          final text = args['text'] as String? ?? '';
          final isUser = args['isUser'] as bool? ?? true;
          final streaming = args['streaming'] as bool? ?? false;
          if (text.isNotEmpty || streaming) {
            setState(() {
              _messages.add(_ChatMessage(
                text: text,
                isUser: isUser,
                streaming: streaming,
              ));
              if (streaming) {
                _isSending = false;
              } else {
                _isSending = isUser;
              }
            });
            _scrollToBottom();
          }
          return;
        case 'append_stream_chunk':
          final args = call.arguments as Map;
          final chunk = args['text'] as String? ?? '';
          if (chunk.isNotEmpty && _messages.isNotEmpty) {
            setState(() {
              _messages.last.text += chunk;
            });
            _scrollToBottom();
          }
          return;
        case 'stream_end':
          if (_messages.isNotEmpty) {
            setState(() {
              _messages.last.streaming = false;
            });
          }
          return;
        case 'stream_error':
          final args = call.arguments as Map;
          final error = args['error'] as String? ?? '请求失败';
          if (_messages.isNotEmpty && _messages.last.streaming) {
            setState(() {
              _messages.removeLast();
              _messages.add(_ChatMessage(text: error, isUser: false));
              _isSending = false;
            });
          }
          return;
        case 'update_conversation_title':
          final args = call.arguments as Map;
          final id = args['id'] as String? ?? '';
          final title = args['title'] as String? ?? '';
          if (mounted && id.isNotEmpty) {
            setState(() {
              final idx = _conversations.indexWhere((c) => c.id == id);
              if (idx >= 0) {
                _conversations[idx].title = title;
              }
            });
          }
          return;
        default:
          throw UnimplementedError('Not implemented: ${call.method}');
      }
    });

    final args = _parseArgs(c.arguments);
    final w = (args['width'] as num?)?.toDouble() ?? 400;
    final h = (args['height'] as num?)?.toDouble() ?? 500;
    final l = (args['left'] as num?)?.toDouble() ?? 0;
    final t = (args['top'] as num?)?.toDouble() ?? 0;
    final theme = args['theme'] as String? ?? 'light';
    final model = args['model'] as String? ?? '';
    await windowManager.setMinimumSize(const Size(600, 500));
    await windowManager.setMaximumSize(const Size(3840, 2160));
    await windowManager.setBounds(Rect.fromLTWH(l, t, w, h));
    if (args['hidden'] != true) {
      await windowManager.show();
    }
    if (mounted) {
      setState(() {
        _theme = AgentChatColors.of(theme);
        _themeName = theme;
        _currentModel = model;
      });
    }
    await _loadConversations();
    await _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final s = await SettingsService.load();
    if (mounted) {
      setState(() {
        _userName = s.userName;
        _userAvatarPath = s.userAvatarPath;
      });
    }
  }

  Future<void> _loadConversations() async {
    final convs = await ChatStorageService.loadAll();
    if (mounted) {
      setState(() {
        _conversations = convs;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Map<String, dynamic> _parseArgs(String raw) {
    if (raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  // ─── 对话操作 ────────────────────────────────────────────────────────────

  void _createNewConversation() {
    // 当前对话无内容时，不创建新对话
    if (_currentConversationId != null && _messages.isEmpty) return;
    AgentChatPopup.popupChannel.invokeMethod('popup_new_conversation');
  }

  void _switchConversation(String id) {
    if (id == _currentConversationId) return;
    setState(() {
      _currentConversationId = id;
    });
    AgentChatPopup.popupChannel.invokeMethod('popup_switch_conversation', {
      'id': id,
    });
  }

  void _deleteConversation(String id) {
    AgentChatPopup.popupChannel.invokeMethod('popup_delete_conversation', {
      'id': id,
    });
  }

  void _clearAllConversations() {
    AgentChatPopup.popupChannel.invokeMethod('popup_clear_all_conversations');
  }

  // ─── 发送消息 ────────────────────────────────────────────────────────────

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    AgentChatPopup.popupChannel.invokeMethod('popup_send_message', {
      'text': text,
      'mode': _mode,
    });
    _inputController.clear();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _sendMessage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _closePopup() {
    AgentChatPopup.popupChannel.invokeMethod('popup_close');
  }

  // ─── 构建 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = _themeName == 'dark';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        fontFamily: 'Microsoft YaHei',
      ),
      home: Scaffold(
        backgroundColor: _theme.scaffoldBg,
        body: DragToResizeArea(
          child: Container(
            color: _theme.scaffoldBg,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Row(
                    children: [
                      _buildSidebar(),
                      Container(width: 1, color: _theme.dividerColor),
                      Expanded(child: _buildChatArea()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final isDark = _themeName == 'dark';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Image.asset(PetConfig.logoSprite, width: 22, height: 22),
            const SizedBox(width: 8),
            Text(
              'Orbby Agent',
              style: TextStyle(
                color: _theme.headerText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _buildHeaderButton(
              tooltip: isDark ? '明亮模式' : '暗黑模式',
              icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              onTap: () async {
                final newTheme = isDark ? 'light' : 'dark';
                setState(() {
                  _themeName = newTheme;
                  _theme = AgentChatColors.of(newTheme);
                });
                final s = await SettingsService.load();
                s.agentChatPopupTheme = newTheme;
                await SettingsService.save(s);
              },
            ),
            const SizedBox(width: 4),
            _buildHeaderButton(
              tooltip: '最小化',
              icon: Icons.minimize_rounded,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 4),
            _buildHeaderButton(
              tooltip: _isMaximized ? '还原' : '最大化',
              icon: _isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              onTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                setState(() => _isMaximized = !_isMaximized);
              },
            ),
            const SizedBox(width: 4),
            _buildHeaderButton(
              tooltip: '关闭',
              icon: Icons.close_rounded,
              onTap: _closePopup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: _theme.statusText),
          ),
        ),
      ),
    );
  }

  // ─── 左侧边栏 ────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: _theme.sidebarBg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // 用户信息
          if (_userName.isNotEmpty ||
              (_userAvatarPath.isNotEmpty &&
                  File(_userAvatarPath).existsSync()))
            _buildUserInfo(),
          // 功能按钮
          _buildSidebarFeatureButtons(),
          const SizedBox(height: 8),
          // 新建对话按钮
          _buildNewChatButton(),
          const SizedBox(height: 8),
          // 对话列表
          Expanded(child: _buildConversationList()),
          // 底部按钮
          _buildClearAllButton(),
        ],
      ),
    );
  }

  Widget _buildUserInfo() {
    final hasAvatar =
        _userAvatarPath.isNotEmpty && File(_userAvatarPath).existsSync();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _theme.chipActiveBg,
            backgroundImage:
                hasAvatar ? FileImage(File(_userAvatarPath)) : null,
            child: hasAvatar
                ? null
                : Icon(Icons.person, size: 18, color: _theme.chipInactiveText),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _userName,
              style: TextStyle(
                color: _theme.headerText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarFeatureButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          _buildFeatureButton('assets/svg/个性化.svg', '个性设置'),
          _buildFeatureButton('assets/svg/技能点.svg', '技能'),
          _buildFeatureButton('assets/svg/记忆 (1).svg', '知识库'),
        ],
      ),
    );
  }

  Widget _buildFeatureButton(String svgPath, String label) {
    final isHovered = _hoveredConvId == label;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredConvId = label),
      onExit: (_) => setState(() => _hoveredConvId = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // TODO: 打开对应功能
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isHovered
                ? _theme.chipActiveBg.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                svgPath,
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  _theme.chipActiveText,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: _theme.headerText,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewChatButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHoveredNewChat = true),
        onExit: (_) => setState(() => _isHoveredNewChat = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _createNewConversation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _isHoveredNewChat
                  ? _theme.chipActiveBg.withValues(alpha: 0.3)
                  : _theme.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: _theme.chipActiveText),
                const SizedBox(width: 8),
                Text(
                  '新对话',
                  style: TextStyle(
                    color: _theme.chipActiveText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    if (_conversations.isEmpty) {
      return Center(
        child: Text(
          '暂无对话',
          style: TextStyle(color: _theme.emptyText, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _conversations.length,
      itemBuilder: (_, index) {
        final conv = _conversations[index];
        final isSelected = conv.id == _currentConversationId;
        final isHovered = conv.id == _hoveredConvId;
        return _buildConversationItem(conv, isSelected, isHovered);
      },
    );
  }

  Widget _buildConversationItem(
    ChatConversation conv,
    bool isSelected,
    bool isHovered,
  ) {
    final bgColor = isSelected
        ? _theme.chipActiveBg
        : isHovered
            ? _theme.chipActiveBg.withValues(alpha: 0.15)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredConvId = conv.id),
        onExit: (_) => setState(() => _hoveredConvId = null),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _switchConversation(conv.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: isSelected ? _theme.chipActiveText : _theme.statusText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conv.title.isEmpty ? '新对话' : conv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? _theme.chipActiveText : _theme.headerText,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(conv.updatedAt),
                        style: TextStyle(
                          color: _theme.emptyText,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isHovered)
                  GestureDetector(
                    onTap: () => _deleteConversation(conv.id),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _theme.emptyText,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }

  Widget _buildClearAllButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHoveredClearAll = true),
        onExit: (_) => setState(() => _isHoveredClearAll = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _conversations.isEmpty ? null : _clearAllConversations,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isHoveredClearAll && _conversations.isNotEmpty
                  ? _theme.chipActiveBg.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: _conversations.isNotEmpty
                      ? _theme.chipInactiveText
                      : _theme.chipInactiveText.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  '清除所有对话',
                  style: TextStyle(
                    color: _conversations.isNotEmpty
                        ? _theme.chipInactiveText
                        : _theme.chipInactiveText.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 右侧聊天区域 ──────────────────────────────────────────────────────────

  Widget _buildChatArea() {
    final isEmpty = _messages.isEmpty && !_isSending;
    return Container(
      padding: const EdgeInsets.all(12),
      child: isEmpty ? _buildWelcomeScreen() : _buildNormalChatArea(),
    );
  }

  Widget _buildNormalChatArea() {
    final showTyping = _isSending && !_hasActiveStream;
    return Column(
      children: [
        _buildModelLabel(),
        const SizedBox(height: 4),
        Expanded(child: _buildChatList()),
        if (showTyping) ...[
          const SizedBox(height: 8),
          const TypingIndicator(),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        _buildInputArea(),
        const SizedBox(height: 6),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    return Column(
      children: [
        _buildModelLabel(),
        const Spacer(flex: 2),
        Text(
          '我可以为你做些什么？',
          style: TextStyle(
            color: _theme.headerText,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        // 输入框与建议左对齐
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeInputArea(),
              const SizedBox(height: 20),
              _buildSuggestionItem(
                'assets/png/agentHint/1.png',
                '开始使用 Orbby 助手，查看常用功能',
                '你好，请介绍你的功能。',
              ),
              const SizedBox(height: 12),
              _buildSuggestionItem(
                'assets/png/agentHint/2.svg',
                '探索创意灵感',
                '给我一些创意灵感和建议。',
              ),
              const SizedBox(height: 12),
              _buildSuggestionItem(
                'assets/png/agentHint/3.svg',
                '编写代码，测试用例，执行脚本',
                '请帮我修改代码',
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildSuggestionItem(String iconPath, String title, String prompt) {
    final isHovered = _hoveredAction == title;
    final isSvg = iconPath.endsWith('.svg');
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = title),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _sendPresetMessage(prompt),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isHovered
                ? _theme.chipActiveBg.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isSvg
                  ? SvgPicture.asset(iconPath, width: 22, height: 22)
                  : Image.asset(iconPath, width: 22, height: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: _theme.chipInactiveText,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendPresetMessage(String text) {
    if (_isSending) return;
    _inputController.text = text;
    _sendMessage();
  }

  Widget _buildModelLabel() {
    final modelStr = _currentModel.isEmpty ? '未配置模型' : _currentModel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _theme.chipActiveBg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            modelStr,
            style: TextStyle(
              color: _theme.statusText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _inputController,
        minLines: 1,
        maxLines: 4,
        enabled: !_isSending,
        style: TextStyle(color: _theme.inputText, fontSize: 15),
        decoration: InputDecoration(
          hintText: _isSending ? '' : '描述你的需求或想法',
          hintStyle: TextStyle(color: _theme.inputHint),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          filled: true,
          fillColor: _theme.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: TypingIndicator(),
                )
              : IconButton(
                  icon: Icon(Icons.send_rounded,
                      size: 18, color: _theme.chipActiveText),
                  onPressed: _sendMessage,
                ),
        ),
      ),
    );
  }

  Widget _buildWelcomeInputArea() {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: _inputController,
        minLines: 3,
        maxLines: 6,
        enabled: !_isSending,
        style: TextStyle(color: _theme.inputText, fontSize: 15),
        decoration: InputDecoration(
          hintText: _isSending ? '' : '描述你的需求或想法',
          hintStyle: TextStyle(color: _theme.inputHint,fontSize: 18),
          isDense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 30,
            vertical: 30,
          ),
          filled: true,
          fillColor: _theme.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSending
              ? const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: TypingIndicator(),
                )
              : IconButton(
                  icon: Icon(Icons.send_rounded,
                      size: 18, color: _theme.chipActiveText),
                  onPressed: _sendMessage,
                ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final chars = _messages.fold<int>(0, (sum, m) => sum + m.text.length);
    final sizeStr = chars >= 1024
        ? '${(chars / 1024).toStringAsFixed(chars >= 10240 ? 0 : 1)}k'
        : '${chars}b';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          _buildModeChip('accept', '审核模式'),
          const SizedBox(width: 6),
          _buildModeChip('plan', '计划模式'),
          const SizedBox(width: 6),
          _buildModeChip('auto', '自动模式'),
          const Spacer(),
          Text(
            'context: $sizeStr',
            style: TextStyle(color: _theme.chipInactiveText, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(String value, String label) {
    final isActive = _mode == value;
    return GestureDetector(
      onTap: () => setState(() => _mode = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? _theme.chipActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _theme.chipActiveText : _theme.chipInactiveText,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Color get _chipHoverBg {
    return _theme.chipActiveBg.withValues(
      alpha: _themeName == 'dark' ? 0.45 : 0.20,
    );
  }

  // ─── 消息列表 ────────────────────────────────────────────────────────────

  bool get _hasActiveStream {
    return _messages.isNotEmpty && _messages.last.streaming;
  }

  Widget _buildChatList() {
    if (_messages.isEmpty && !_isSending) {
      return Center(
        child: Text(
          '暂无消息',
          style: TextStyle(color: _theme.emptyText, fontSize: 13),
        ),
      );
    }
    return Theme(
      data: ThemeData(
        brightness:
            _themeName == 'dark' ? Brightness.dark : Brightness.light,
        scrollbarTheme: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _messages.length,
        itemBuilder: (_, index) {
          return _buildMessageBubble(_messages[index]);
        },
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: _theme.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(color: _theme.bubbleText, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: MarkdownBody(
            data: msg.streaming ? '${msg.text}▌' : msg.text,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: _theme.bubbleText, fontSize: 16, fontWeight: FontWeight.w400, fontFamily: 'Microsoft YaHei'),
              h1: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Microsoft YaHei'),
              h2: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Microsoft YaHei'),
              h3: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Microsoft YaHei'),
              h4: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Microsoft YaHei'),
              h5: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Microsoft YaHei'),
              h6: TextStyle(
                  color: _theme.bubbleText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Microsoft YaHei'),
              code: TextStyle(
                color: _theme.bubbleText,
                fontSize: 15,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: _theme.bubbleText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              a: TextStyle(color: _theme.bubbleText, fontFamily: 'Microsoft YaHei'),
              blockquoteDecoration: BoxDecoration(
                color: _theme.bubbleText.withValues(alpha: 0.05),
                border: Border(
                  left: BorderSide(
                    color: _theme.dividerColor,
                    width: 3,
                  ),
                ),
              ),
              blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 8),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: _theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildActionButton('assets/svg/复制.svg', '复制', () {
                Clipboard.setData(ClipboardData(text: msg.text));
              }),
              const SizedBox(width: 14),
              _buildActionButton('assets/svg/重新.svg', '重新生成', () {
                AgentChatPopup.popupChannel.invokeMethod('agent_regenerate');
              }),
              const SizedBox(width: 14),
              _buildActionButton('assets/svg/more.svg', '更多', () {
                // TODO: 更多操作
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
      String svgAsset, String label, VoidCallback onTap) {
    final isHovered = _hoveredAction == label;
    final isSelected = _selectedAction == label;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredAction = label),
      onExit: (_) => setState(() => _hoveredAction = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedAction = label);
          onTap();
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) setState(() => _selectedAction = null);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected
                ? _theme.chipActiveBg
                : isHovered
                    ? _theme.chipActiveBg.withValues(alpha: 0.4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SvgPicture.asset(
            svgAsset,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              isSelected || isHovered
                  ? _theme.chipActiveText
                  : _theme.statusText.withValues(alpha: 1),
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser, this.streaming = false});

  String text;
  final bool isUser;
  bool streaming;
}

// ─── Agent Chat 颜色定义 ──────────────────────────────────────────────────

class AgentChatColors {
  const AgentChatColors._();

  static const light = AgentChatPalette(
    bg: Color(0xFFFFFFFF),
    inputBg: Color(0x0D000000),
    inputText: Color(0xFF333333),
    inputHint: Color(0xFF888888),
    chipActiveBg: Color(0x14000000),
    chipActiveText: Color(0xFF333333),
    chipInactiveText: Color(0xFF999999),
    headerText: Color(0xFF333333),
    userBubble: Color(0xFFE0E0E0),
    agentBubble: Color(0xFFD5D5D5),
    bubbleText: Color(0xFF333333),
    emptyText: Color(0xFF999999),
    statusText: Color(0xFF000000),
    scaffoldBg: Color(0xFFFFFFFF),
    sidebarBg: Color(0xFFF5F5F5),
    dividerColor: Color(0xFFE0E0E0),
  );

  static const dark = AgentChatPalette(
    bg: Color(0xFF1E1E1E),
    inputBg: Color(0xFF2A2A2A),
    inputText: Color(0xB3FFFFFF),
    inputHint: Color(0x4DFFFFFF),
    chipActiveBg: Color(0x26FFFFFF),
    chipActiveText: Color(0xB3FFFFFF),
    chipInactiveText: Color(0x4DFFFFFF),
    headerText: Colors.white,
    userBubble: Color(0xFF3A3A3A),
    agentBubble: Color(0xFF2A2A2A),
    bubbleText: Colors.white,
    emptyText: Color(0x4DFFFFFF),
    statusText: Color(0xFFFFFFFF),
    scaffoldBg: Color(0xFF1E1E1E),
    sidebarBg: Color(0xFF252525),
    dividerColor: Color(0xFF3A3A3A),
  );

  static AgentChatPalette of(String theme) => theme == 'dark' ? dark : light;
}

class AgentChatPalette {
  const AgentChatPalette({
    required this.bg,
    required this.inputBg,
    required this.inputText,
    required this.inputHint,
    required this.chipActiveBg,
    required this.chipActiveText,
    required this.chipInactiveText,
    required this.headerText,
    required this.userBubble,
    required this.agentBubble,
    required this.bubbleText,
    required this.emptyText,
    required this.statusText,
    required this.scaffoldBg,
    required this.sidebarBg,
    required this.dividerColor,
  });

  final Color bg;
  final Color inputBg;
  final Color inputText;
  final Color inputHint;
  final Color chipActiveBg;
  final Color chipActiveText;
  final Color chipInactiveText;
  final Color headerText;
  final Color userBubble;
  final Color agentBubble;
  final Color bubbleText;
  final Color emptyText;
  final Color statusText;
  final Color scaffoldBg;
  final Color sidebarBg;
  final Color dividerColor;
}
