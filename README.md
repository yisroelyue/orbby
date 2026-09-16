<div align="center">
  <img src="introduce/logo.png" alt="Orbby Logo" width="120">
  <h1>Orbby Assistant（奥比助手）</h1>
  <p>一款常驻桌面的电脑助手，帮你把日常琐事办了</p>

![Platform](https://img.shields.io/badge/platform-Windows-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.12%2B-02569B)
![Node.js](https://img.shields.io/badge/Node.js-18%2B-339933)

</div>

---

## 📦 版本发布

| 版本     | 日期         | 主要功能                                                                          | 下载                                                                                                   |
| ------ | ---------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| v3.0.0 | 2026-09-14 | 架构重构：Agent 引擎重写为 Node.js 运行时；移除插件化 sub-app 架构；多窗口聊天与附件系统                       | 开发中                                                                                                  |
| v1.0.0 | 2026-07-13 | 初始版本                                                                          | [Windows x64](https://github.com/yisroelyue/orbby/releases/download/v1.0.0/orbby-windows-x64.tar.gz) |

> v3.0.0 是当前开发分支（`feature-3.0.0`）。与 v1.0.0 相比是一次架构重构：Agent 核心从 Dart 迁到 Node.js 子进程，跨窗口通信与附件链路随之重做。

---

## ✨ 功能介绍

### 🎨 主题与外观

窗口无边框、透明背景，配合半透明磨砂面板（`FrostedPanel`）呈现；各窗口在自身 `MaterialApp` 中独立配置主题。

<div align="center">
  <img src="introduce/主题页面 (1).png" alt="主题页面1">
  <img src="introduce/主题页面 (2).png" alt="主题页面2">
</div>

### 🤖 Orbby Agent

聊天窗口里的 AI 助手，Agent 核心跑在独立的 Node.js 运行时中，通过 localhost WebSocket 与 Flutter 通信。ReAct 工具循环最多 30 步，可读写文件、执行命令、管理终端会话、调用技能，过程与结果流式输出。需要你拍板时会弹出提问卡片（单选 / 多选 / 填空），改过的文件支持一键回滚。

### 💡 核心功能

- **🎛️ Orbby Agent 对话** — 多轮任务执行，流式输出，工具调用过程可见
- **⌨️ 斜杠命令** — 共 16 条：`/help`、`/session`、`/new`、`/clear`、`/clear-session`、`/compact`、`/retry`、`/rollback`、`/copy`、`/copy-txt`、`/apps`、`/sys_setting`、`/setting`、`/permission-off`、`/permission-all`、`/permission-read`
- **📎 附件支持** — 图片 / 文本 / PDF 拖入或粘贴进输入框，图片可直接交给视觉模型分析
- **↩️ 文件改动回滚** — Agent 写入的文件留有备份，`/rollback` 还原最近一次改动
- **💰 API 状态** — 实时显示 API 余额 / 用量（支持 DeepSeek / OpenAI / Anthropic 等多平台），可切换平台，为 Agent 和翻译提供 LLM 支持
- **📝 我的笔记** — 待办 / 笔记列表，快速记下灵感
- **🚀 应用中心** — 快速启动常用应用的面板，支持添加自定义程序（自动提取 exe 图标），也可启动 Orbby 自带功能
- **🌐 翻译助手** — 支持 LLM 翻译与腾讯云翻译两种后端
- **📋 快速剪切板** — 剪贴板里的图片 / 图片文件可直接粘贴进对话
- **🗂️ 系统托盘** — 设置 / 关于 / 退出，常驻后台不碍事

<div align="center">
  <img src="introduce/功能 (1).png" alt="功能展示1" >
  <img src="introduce/功能 (2).png" alt="功能展示2" >
  <img src="introduce/功能 (3).png" alt="功能展示3">
</div>

---

## 🏗️ 架构一览

每个窗口是一个独立的 Flutter engine，静态变量 / 单例不跨窗口共享，跨窗口通信走 channel 或 AppEvents：

- **pet 主窗口** — 常驻隐藏，运行 `WindowCoordinator`（hub）：全局快捷键 + 所有子窗口的创建 / 定位 / 显示
- **子窗口** — `menu`（聊天）、`settings`、`app_bar`、`content`、`app_center`、`about`；menu / settings 常驻复用，其余按需新建

---

## 🚀 快速开始

### 环境要求

- Flutter SDK 3.12+
- Node.js 18+
- Windows 10+

### 运行

```bash
# 克隆仓库
git clone https://github.com/yisroelyue/orbby.git
cd orbby

# 安装 Flutter 依赖
flutter pub get

# 构建 Agent 运行时
cd agent-runtime
npm install
npm run build
cd ..

# 运行
flutter run -d windows
```

### 构建

```bash
flutter build windows --release
```

### 可选配置

- `ORBBY_WORKSPACE` — 指定 Agent 的初始工作区；不设置时默认为当前用户桌面目录
- 会话数据、附件与文件回滚备份存放在 `~/.orbby/` 下

---

## 🛠️ 技术栈

- **Flutter** — UI 框架，Windows 桌面多窗口
- **Node.js / TypeScript** — Agent 运行时（ReAct 工具循环、LLM 协议适配、PDF / 文本提取）
- **C++ 原生通道** — 剪贴板读取、窗口形状、全局热键、文件拖放
- **自维护 fork** — `desktop_multi_window` 多窗口通信

---

## 📄 许可

MIT License
