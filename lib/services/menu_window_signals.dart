import 'package:flutter/foundation.dart';

/// menu 窗口本地信号：每次窗口被 place 显示时自增。
/// 仅在 menu engine 内有效；窗口控制指令不走 AppEvents 总线（见项目规范），
/// 这里只是把"已显示"转达给窗口内的组件（用于输入框自动聚焦）。
final menuWindowShown = ValueNotifier(0);

/// hub 定向下发 open_settings（托盘菜单 / Ctrl+Alt+` 快捷键，设置已并入
/// menu 窗口的 /setting 弹窗）时自增，由 HomeScreen 监听打开设置弹窗。
/// 同样仅 menu engine 内有效，转达机制同上。
final menuSettingsRequested = ValueNotifier(0);
