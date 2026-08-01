import 'dart:async';

import 'package:flutter/material.dart';

import 'base_panel.dart';

/// 轮播面板组件
/// 支持自动轮播、手动滑动、无限循环
class CarouselPanel extends StatefulWidget {
  final List<BasePanel> panels;

  /// 自动切换间隔（秒），默认 12
  final int switchInterval;

  const CarouselPanel({super.key, required this.panels, this.switchInterval = 12});

  @override
  State<CarouselPanel> createState() => _CarouselPanelState();
}

class _CarouselPanelState extends State<CarouselPanel> {
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(Duration(seconds: widget.switchInterval), (timer) {
      if (!mounted || _isHovered) return; // 鼠标悬停时暂停轮播
      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.panels.length;
      });
    });
  }

  @override
  void didUpdateWidget(CarouselPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换间隔改变时重启定时器
    if (oldWidget.switchInterval != widget.switchInterval) {
      _startAutoPlay();
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  void _goToPrevious() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + widget.panels.length) % widget.panels.length;
    });
    _startAutoPlay();
  }

  void _goToNext() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.panels.length;
    });
    _startAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 轮播内容区域 + 左右切换按钮
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: 150,
            child: Stack(
              children: [
                // 使用 Stack 保持所有面板状态，通过可见性切换
                for (int i = 0; i < widget.panels.length; i++)
                  Visibility(
                    visible: i == _currentIndex,
                    maintainState: true, // 关键：保持状态不销毁
                    child: widget.panels[i],
                  ),
                // 左切换按钮（鼠标悬停时显示）
                if (_isHovered)
                  Positioned(
                    left: 4,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _goToPrevious,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 右切换按钮（鼠标悬停时显示）
                if (_isHovered)
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _goToNext,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 指示器
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.panels.length,
            (index) => GestureDetector(
              onTap: () {
                setState(() => _currentIndex = index);
                _startAutoPlay();
              },
              child: Container(
                width: _currentIndex == index ? 16 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _currentIndex == index
                      ? Theme.of(context).primaryColor
                      : Colors.grey.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
