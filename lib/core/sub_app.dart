import 'package:flutter/material.dart';

/// 每个子应用 package 实现此接口即可被应用中心发现和启动。
abstract class SubApp {
  /// 唯一标识，与 apps_config.json 中的 subAppId 对应
  String get id;

  /// 显示名称
  String get name;

  /// 描述文本
  String get description;

  /// 子应用包内的图标路径，如 'assets/logo.svg'
  String get iconAsset;

  /// pubspec.yaml 中的 name，用于 package: 前缀资源解析
  String get packageName;

  /// 窗口大小，默认 800×600
  Size get preferredWindowSize => const Size(800, 600);

  /// 是否显示窗口标题栏，默认 true。屏幕录制等需要无边框的可覆盖为 false。
  bool get showWindowTitleBar => true;

  /// 构建子应用主界面（在独立窗口中显示）
  Widget buildApp(BuildContext context);
}
