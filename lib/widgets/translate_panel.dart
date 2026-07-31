import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/translate_service.dart';
import 'base_panel.dart';
import 'interactive_icon.dart';

class TranslatePanel extends BasePanel {
  const TranslatePanel({super.key});

  @override
  PanelSize get panelSize => PanelSize.full;

  @override
  String get panelName => 'translate';

  @override
  State<TranslatePanel> createState() => _TranslatePanelState();
}

class _TranslatePanelState extends BasePanelState<TranslatePanel> {
  bool _isTranslating = false;
  bool _isError = false;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  String _resultText = '';
  Timer? _clearTimer;
  TranslateLang _selectedLang = TranslateLang.zhEn;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _startClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) setState(() => _resultText = '');
    });
  }

  Future<void> _performTranslation() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _resultText = '请输入要翻译的文本';
        _isError = true;
      });
      return;
    }
    _clearTimer?.cancel();
    setState(() => _isTranslating = true);
    try {
      final result = await TranslateService.translate(
        text,
        lang: _selectedLang,
      );
      if (!mounted) return;
      setState(() {
        _resultText = result;
        _isError = false;
        _inputController.clear();
      });
      _startClearTimer();
    } on TranslateException catch (e) {
      if (!mounted) return;
      setState(() {
        _resultText = e.message;
        _isError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultText = '翻译失败: $e';
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  @override
Widget buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题 + 输入框同一行
        _buildInputRow(),
        const SizedBox(height: 8),
        _buildLangSelector(),
        _buildAnswerArea(),
      ],
    );
  }

  Widget _buildInputRow() {
    return Container(
      decoration: BoxDecoration(
        color: hoverBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.only(left: 8, right: 4, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(Icons.translate_rounded, color: primaryText, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              cursorColor: primaryText,
              style: TextStyle(color: primaryText, fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (!_isTranslating) _performTranslation();
              },
              decoration: InputDecoration(
                hintText: '粘贴要翻译的文本...',
                hintStyle: TextStyle(color: hintColor, fontSize: 14, fontWeight: FontWeight.w600),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          InteractiveIcon(
            size: 32,
            onTap: () {
              if (_isTranslating) return;
              _performTranslation();
            },
            child: _isTranslating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tertiaryText,
                    ),
                  )
                : SvgPicture.asset(
                    'assets/svg/翻译.svg',
                    width: 22,
                    height: 22,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLangSelector() {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TranslateLang.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final lang = TranslateLang.values[index];
          final isSelected = lang == _selectedLang;
          return GestureDetector(
            onTap: () {
              if (isSelected) return;
              setState(() {
                _selectedLang = lang;
                _resultText = '';
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : hoverBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? accentColor : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  lang.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : secondaryText,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnswerArea() {
    if (_resultText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isError ? '错误' : '翻译结果',
                  style: TextStyle(
                    color: _isError ? Colors.redAccent : tertiaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                InteractiveIcon(
                  size: 24,
                  onTap: () => setState(() => _resultText = ''),
                  child: Icon(Icons.close, color: mutedText, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              _resultText,
              style: TextStyle(
                color: _isError ? Colors.redAccent : primaryText,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
