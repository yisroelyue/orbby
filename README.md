# 🐾 Orbby

桌面助手 — 一只常驻桌面的办公助手，集成 AI 余额监控、笔记管理、应用快速启动和 Claude Code 工作区。

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.12%2B-02569B)

Orbby

## ✨ 功能

- **🪟 桌面助手** — 可拖拽的，自动吸附到屏幕边缘，旋转适配贴边方向
- **💰 AI 流量管理** — 实时显示 API 余额（支持 DeepSeek / OpenAI / Anthropic 等多平台），可配置刷新间隔和货币符号
- **📝 笔记管理** — 待办 / 笔记列表，支持增删改查、勾选完成、导入导出 JSON，待处理与已完成 Tab 分类管理
- **🚀 应用中心** — 快速启动常用应用的面板
- **⚙️ 系统设置** — API Key 配置、面板显隐、语言切换、开机自启
- **🖥️ Claude Code 工作区** — 一键打开终端进入 Claude Code 交互环境
- **🎨 毛玻璃效果** — Windows Acrylic / macOS 半透明背景，圆角无边框窗口

## 📸 预览

```
┌──────────────┐
│  🐱 Pet      │  ← 贴边助手（拖拽切换吸附边）
└──────────────┘
     │ 悬停展开
     ▼
┌──────────────────────┐
│ 🏷 账户余额   ● 可用  │
│ ¥ 49.20       🔄 📺  │  ← 菜单面板
│ 📝 我的笔记      [3]  │
│ 🚀 应用中心           │
│ >_ 终端          🚪  │
└──────────────────────┘
```

## 🚀 快速开始

### 环境要求
- Flutter SDK 3.12+
- Windows 10+ / macOS 11+ / Linux

### 运行

```bash
# 克隆仓库
git clone https://github.com/yisroelyue/orbby.git
cd orbby

# 安装依赖
flutter pub get

# 运行
flutter run -d windows   # Windows
flutter run -d macos     # macOS
flutter run -d linux     # Linux
```

### 构建

```bash
flutter build windows --release
```

## 🏗️ 技术栈

- **Flutter** — 跨平台 UI 框架
- **desktop_multi_window** — 多窗口管理（助手窗口 + 菜单窗口 + 设置窗口）
- **window_manager** — 无边框窗口、置顶、毛玻璃效果
- **flutter_acrylic** — Windows Acrylic 半透明背景
- **system_tray** — 系统托盘图标

## 📁 项目结构

```
lib/
├── main.dart              # 入口，多窗口路由
├── app.dart               # 主助手窗口
├── config/                # 配置常量、平台定义、设置
├── screens/               # 各窗口页面
│   ├── pet_screen.dart    # 助手窗口
│   ├── menu_screen.dart   # 菜单窗口
│   ├── settings_screen.dart   # 设置窗口
│   ├── todo_edit_screen.dart  # 笔记管理窗口
│   └── vibe_task_screen.dart  # Vibe 任务窗口
├── services/              # 业务逻辑
│   ├── balance_service.dart
│   ├── todo_service.dart
│   ├── vibe_task_service.dart
│   └── claude_hook_installer.dart
└── widgets/               # 复用组件
    ├── balance_panel.dart
    ├── todo_panel.dart
    ├── app_square_panel.dart
    ├── frosted_panel.dart
    └── interactive_icon.dart
```

## 📄 许可

MIT License
