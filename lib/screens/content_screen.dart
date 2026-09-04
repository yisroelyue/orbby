import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../services/llm_service.dart';
import '../services/translate_service.dart';

class ContentScreen extends StatefulWidget {
  const ContentScreen({super.key});
  static const readyChannel = WindowMethodChannel(
    'orbby_content_events',
    mode: ChannelMode.unidirectional,
  );
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen>
    with WindowListener, WidgetsBindingObserver {
  final _input = TextEditingController();
  TranslateLang _lang = TranslateLang.zhEn;
  String _result = '';
  bool _loading = false;
  bool _showResult = false;
  bool _wasFocused = false;
  bool _hiding = false;
  Timer? _contentClearTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _contentClearTimer = Timer.periodic(const Duration(hours: 1), (_) {
      if (!mounted) return;
      setState(() {
        _input.clear();
        _result = '';
        _showResult = false;
      });
    });
    _initWindowHandler();
  }

  Future<void> _initWindowHandler() async {
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      if (call.method == 'place') {
        final a = call.arguments as Map;
        await windowManager.setBounds(Rect.fromLTWH(
          (a['left'] as num).toDouble(),
          (a['top'] as num).toDouble(),
          (a['width'] as num).toDouble(),
          (a['height'] as num).toDouble(),
        ));
        await windowManager.show();
      } else if (call.method == 'set_text' && call.arguments is String) {
        _input.text = call.arguments as String;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      } else if (call.method == 'clear') {
        _input.clear();
        if (mounted) setState(() { _result = ''; _showResult = false; });
      }
    });
    await ContentScreen.readyChannel.invokeMethod('ready');
  }

  @override
  void dispose() {
    _contentClearTimer?.cancel();
    _input.dispose();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onWindowBlur() async {
    await _hideAndClear();
  }

  @override
  void onWindowFocus() {
    _wasFocused = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wasFocused = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_wasFocused) {
          _wasFocused = false;
          _hideAndClear();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _hideAndClear() async {
    if (_hiding) return;
    _hiding = true;
    if (mounted) {
      setState(() {});
    }
    // 给打开流程留出读取刚复制内容的时间；若窗口重新获得焦点则取消清理。
    ContentScreen.readyChannel.invokeMethod('hidden');
    await windowManager.hide();
    _hiding = false;
  }

  Future<void> _run(Future<String> Function(String) task) async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() { _loading = true; _result = ''; });
    try {
      final value = await task(text);
      if (mounted) {
        setState(() {
          _result = value;
          _showResult = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = e.toString();
          _showResult = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _translate() => _run(
        (text) => TranslateService.translate(text, lang: _lang),
      );

  Future<void> _analyze() => _runStream(
        (text, onToken) => LlmService.askStream(
          '请用简洁清晰的中文回复，解释以下词语或语句的含义，由来，功能等。只保留关键部分，避免无用拓展，输出格式：正常格式，不是markdown或者其他：\n\n $text',
          systemPrompt: '你是实用的 AI 分析助手。',
          onToken: onToken,
        ),
      );

  Future<void> _runStream(
    Future<String> Function(String, void Function(String)) task,
  ) async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() { _loading = true; _result = ''; _showResult = true; });
    try {
      await task(text, (token) {
        if (mounted) setState(() => _result += token);
      });
    } catch (e) {
      if (mounted) setState(() => _result = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _copyResult() async {
    if (_result.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _result));
  }

  Widget _buildResultSection() => Container(
        height: (_loading && _result.isEmpty) ? 80 : null,
        constraints: const BoxConstraints(maxHeight: 400),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            _result.isEmpty && _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _result.isEmpty
            ? Center(
                child: SvgPicture.asset(
                  'assets/svg/暂无数据.svg',
                  width: 64,
                  height: 64,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 30),
                child: Text(
                  _result,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            if (_result.trim().isNotEmpty)
              Positioned(
                right: -6,
                bottom: -6,
                child: IconButton(
                  onPressed: _copyResult,
                  tooltip: '复制结果',
                  icon: const Icon(
                    Icons.copy_outlined,
                    size: 16,
                    color: Color(0xffaeb4ba),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            if (_loading && _result.trim().isNotEmpty)
              const Positioned(
                right: -2,
                top: -2,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: const Color(0xffeef0f3),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, 6))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                TextField(
                controller: _input,
                onChanged: (_) => setState(() {}),
                minLines: 1,
                maxLines: 30,
                style: const TextStyle(fontSize: 12),
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                ),
                if (_input.text.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/svg/暂无数据.svg',
                          width: 56,
                          height: 56,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_showResult || _loading) ...[
              _buildResultSection(),
              if (false) Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _result.trim().isEmpty ? null : _copyResult,
                  tooltip: '复制结果',
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _ActionButton('assets/svg/翻译.svg', _translate, _loading),
                _ActionButton('assets/svg/分析.svg', _analyze, _loading),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton(this.asset, this.onPressed, this.disabled);
  final String asset;
  final VoidCallback onPressed;
  final bool disabled;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _updateLoadingAnimation();
  }

  @override
  void didUpdateWidget(covariant _ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disabled != widget.disabled) _updateLoadingAnimation();
  }

  void _updateLoadingAnimation() {
    // Loading animation is displayed in the result area.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: SizedBox(
          width: 40,
          height: 40,
          child: ElevatedButton(
            onPressed: widget.disabled ? null : widget.onPressed,
            child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  widget.disabled
                      ? const Color(0xffb9bec4)
                      : const Color(0xff494949),
                  BlendMode.srcIn,
                ),
                child: SvgPicture.asset(
                  widget.asset,
                  width: 20,
                  height: 20,
                ),
            ),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
              foregroundColor: WidgetStateProperty.all(Colors.transparent),
              shadowColor: WidgetStateProperty.all(Colors.transparent),
              padding: WidgetStateProperty.all(EdgeInsets.zero),
              minimumSize: WidgetStateProperty.all(Size.zero),
              elevation: WidgetStateProperty.all(0),
              overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.disabled)) {
                  return Colors.transparent;
                }
                if (states.contains(WidgetState.pressed)) {
                  return const Color(0x18000000);
                }
                if (states.contains(WidgetState.hovered)) {
                  return const Color(0x0f000000);
                }
                return Colors.transparent;
              }),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
    );
  }
}
