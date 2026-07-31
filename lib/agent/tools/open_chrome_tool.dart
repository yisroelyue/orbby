// 工具：打开谷歌浏览器并访问指定链接或搜索
// 从 orbby-agent/src/tools/open_chrome.ts 迁移

import 'dart:io';
import '../types.dart';

/// Windows 下 Chrome 常见安装路径
List<String> _chromePathsWin() {
  final programFiles =
      Platform.environment['PROGRAMFILES'] ?? 'C:\\Program Files';
  final programFilesX86 =
      Platform.environment['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';
  final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

  return [
    '$programFiles\\Google\\Chrome\\Application\\chrome.exe',
    '$programFilesX86\\Google\\Chrome\\Application\\chrome.exe',
    '$localAppData\\Google\\Chrome\\Application\\chrome.exe',
  ];
}

/// macOS 路径
const _chromePathsMac = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];

/// Linux 路径
const _chromePathsLinux = [
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
  '/snap/bin/chromium',
];

/// 查找 Chrome 可执行文件路径
String _findChrome() {
  List<String> candidates;

  if (Platform.isWindows) {
    candidates = _chromePathsWin();
  } else if (Platform.isMacOS) {
    candidates = _chromePathsMac;
  } else {
    candidates = _chromePathsLinux;
  }

  for (final chromePath in candidates) {
    if (File(chromePath).existsSync()) {
      return chromePath;
    }
  }

  // 兜底：尝试直接在 PATH 中找
  return Platform.isWindows ? 'chrome' : 'google-chrome';
}

final openChromeTool = ToolDefinition(
  name: 'open_chrome',
  description:
      '打开谷歌浏览器并访问指定网址或搜索关键词。'
      '可以传入 url 直接打开网页，也可以传入 search 关键词进行谷歌搜索，或者同时传入 url 在新标签页打开。'
      '支持用 new_window 参数控制是否打开新窗口（默认在当前窗口新标签页打开）。',
  parameters: {
    'type': 'object',
    'properties': {
      'url': {
        'type': 'string',
        'description':
            '要打开的网页链接，例如 https://www.google.com。如果只传 search 不传 url，会自动打开谷歌搜索。',
      },
      'search': {
        'type': 'string',
        'description':
            '要在谷歌搜索的关键词。会自动拼接为 https://www.google.com/search?q=关键词。如果同时传了 url，会忽略此参数。',
      },
      'new_window': {
        'type': 'boolean',
        'description': '是否打开新窗口（默认 false，即在当前窗口新标签页打开）',
      },
    },
    'required': [],
  },
  execute: (args) async {
    final url = args['url'] as String?;
    final search = args['search'] as String?;
    final newWindow = args['new_window'] == true;

    // 两个都没传
    if ((url == null || url.isEmpty) && (search == null || search.isEmpty)) {
      return '错误：请至少提供 url 或 search 参数之一。\n示例：\n  - url: "https://github.com"\n  - search: "今天天气"';
    }

    // 确定目标 URL
    String targetUrl;
    String actionDesc;

    if (url != null && url.isNotEmpty) {
      // 如果 URL 没有协议前缀，自动添加 https://
      targetUrl = url.startsWith(RegExp(r'https?://')) ? url : 'https://$url';
      actionDesc = '打开链接: $targetUrl';
    } else {
      // 谷歌搜索
      targetUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(search!)}';
      actionDesc = '搜索: $search';
    }

    final chromePath = _findChrome();

    // 构建 Chrome 启动参数
    final newWindowFlag = newWindow ? ' --new-window' : '';

    try {
      if (Platform.isWindows) {
        await Process.start('cmd', [
          '/c',
          'start',
          '',
          '"$chromePath"$newWindowFlag',
          '"$targetUrl"',
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start(chromePath, [
          if (newWindow) '--new-window',
          targetUrl,
        ], mode: ProcessStartMode.detached);
      }
      return '已在 Chrome 中$actionDesc';
    } catch (e) {
      return '打开浏览器失败: $e\n提示：请确认 Chrome 工具已安装，路径: $chromePath';
    }
  },
);
