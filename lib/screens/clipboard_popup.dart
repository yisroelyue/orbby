import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/clipboard_service.dart';

/// 剪贴板历史弹窗
/// Shift+Ctrl+V 打开，选择一条后复制到系统剪贴板，用户手动 Ctrl+V 粘贴
class ClipboardPopup extends StatefulWidget {
  const ClipboardPopup({super.key});

  /// 子→父通信通道
  static const popupChannel = WindowMethodChannel(
    'orbby_clipboard_popup_events',
    mode: ChannelMode.unidirectional,
  );

  @override
  State<ClipboardPopup> createState() => _ClipboardPopupState();
}

class _ClipboardPopupState extends State<ClipboardPopup> {
  List<String> _history = [];
  int _selectedIndex = 0;
  int _hoveredIndex = -1;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  // 浅色主题颜色
  static const _bgColor = Color(0xFFFAFAFA);
  static const _surfaceColor = Colors.white;
  static const _primaryColor = Color(0xFF2196F3);
  static const _textPrimary = Colors.black;
  static const _textSecondary = Color(0xFF212121);
  static const _textHint = Color(0xFF616161);
  static const _dividerColor = Color(0xFFE0E0E0);
  static const _hoverColor = Color(0xFFE8E8E8);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _focusNode.requestFocus();
    _setupMethodHandler();
  }

  Future<void> _setupMethodHandler() async {
    final controller = await WindowController.fromCurrentEngine();
    controller.setWindowMethodHandler((call) async {
      if (call.method == 'refresh') {
        _loadHistory();
        _focusNode.requestFocus();
      } else if (call.method == 'reposition') {
        final args = call.arguments as Map;
        final left = (args['left'] as num).toDouble();
        final top = (args['top'] as num).toDouble();
        await windowManager.setPosition(Offset(left, top));
        _loadHistory();
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await ClipboardService.loadHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _selectedIndex = _history.isNotEmpty ? 0 : -1;
      });
    }
  }

  /// 选择一条：复制到系统剪贴板，隐藏弹窗
  void _selectItem(int index) {
    if (index < 0 || index >= _history.length) return;
    Clipboard.setData(ClipboardData(text: _history[index]));
    ClipboardPopup.popupChannel.invokeMethod('close');
    windowManager.hide();
  }

  void _close() {
    ClipboardPopup.popupChannel.invokeMethod('close');
    windowManager.hide();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _history.length - 1);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _history.length - 1);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _selectedIndex >= 0) {
      _selectItem(_selectedIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final offset = _selectedIndex * 52.0;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Microsoft YaHei').copyWith(scaffoldBackgroundColor: Colors.transparent),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          autofocus: true,
          child: Container(
            width: 320,
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _dividerColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(children: [
                    const Icon(Icons.content_paste_rounded, size: 18, color: _primaryColor),
                    const SizedBox(width: 8),
                    const Text('剪贴板',
                        style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${_history.length}/10',
                        style: const TextStyle(color: _textHint, fontSize: 12)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _close,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, size: 16, color: _textHint),
                      ),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: _dividerColor),
                // 列表
                if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无剪贴板记录\n复制文本后自动保存',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _textHint, fontSize: 13)),
                  )
                else
                  Flexible(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          final content = _history[index];
                          final isSelected = index == _selectedIndex;
                          final displayText = content.length > 100
                              ? '${content.substring(0, 100)}...'
                              : content;
                          final singleLine = displayText.replaceAll('\n', ' ').replaceAll('\r', '');

                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => setState(() => _hoveredIndex = index),
                            onExit: (_) => setState(() => _hoveredIndex = -1),
                            child: GestureDetector(
                              onTap: () => _selectItem(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _primaryColor.withAlpha(25)
                                      : _hoveredIndex == index
                                          ? _hoverColor
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _primaryColor.withAlpha(40)
                                          : _hoverColor,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('${index + 1}',
                                        style: TextStyle(
                                            color: isSelected
                                                ? _primaryColor
                                                : _textHint,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(singleLine,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: isSelected
                                                ? _textPrimary
                                                : _textSecondary,
                                            fontSize: 13,
                                            height: 1.4)),
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                // 底部提示
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Row(children: [
                    _keyHint('↑↓'),
                    const SizedBox(width: 4),
                    const Text('选择', style: TextStyle(color: _textHint, fontSize: 11)),
                    const SizedBox(width: 12),
                    _keyHint('Enter'),
                    const SizedBox(width: 4),
                    const Text('确定', style: TextStyle(color: _textHint, fontSize: 11)),
                    const SizedBox(width: 12),
                    _keyHint('Esc'),
                    const SizedBox(width: 4),
                    const Text('关闭', style: TextStyle(color: _textHint, fontSize: 11)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _hoverColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _dividerColor, width: 0.5),
      ),
      child: Text(text,
          style: const TextStyle(color: _textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
