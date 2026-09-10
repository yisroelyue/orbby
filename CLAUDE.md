# 项目规范
- 不进行flutter分析，测试，会卡住，改完代码告诉我就可以。
- 影响当前架构的改动需要告诉我，改动完了之后更新规范文件。

## 架构

- Flutter Windows 多窗口应用，**每个窗口是独立 Flutter engine，静态变量/单例不跨窗口共享**——跨窗口必须走 channel 或 AppEvents。
- 入口 `lib/main.dart` 按启动参数 `type` 分发各窗口 UI 与窗口配置。主窗口（pet）常驻隐藏，跑 `WindowCoordinator`（`lib/services/window_coordinator.dart`，即 hub）：全局快捷键 + 所有子窗口的创建/定位/显示。
- 子窗口：`menu`（聊天 HomeScreen）、`settings`、`app_bar`、`content`、`app_center`、`about`。menu/settings 启动时预创建（hiddenAtLaunch），常驻窗口用 hide/show 切换；app_center/about 每次新建。
- 窗口通信（本地 fork 的 `packages/desktop_multi_window`）两条路：
  - `WindowMethodChannel(..., ChannelMode.unidirectional)`：全局仅 hub 注册 handler，任何 engine 都能 invoke → **子→hub**（ready、hidden、open_settings 等）。
  - `window.invokeMethod(...)` 定向调用子窗口的 `setWindowMethodHandler` → **hub→子**（place、app_event 等）。
- **ready 握手**：子窗口 engine 就绪后发 `'ready'`，hub 等 Completer（5s 超时兜底）再 place/show；不等的话首次 place 会丢。

## 组件通信（AppEvents）

跨窗口/组件的状态变更通知统一用 `AppEvents`（`lib/services/app_events.dart`），事件名集中定义在该类，禁止魔法字符串：

```
// 发出：本窗口立即生效，并自动扩散到所有窗口
AppEvents.emit(AppEvents.panelAppsChanged);

// 组件监听（参照 lib/widgets/app_square_panel.dart）
AppEvents.addListener(AppEvents.panelAppsChanged, _loadApps);
```

initState 注册、dispose 必须 removeListener；`_load` 中先 `if (!mounted) return` 再 `setState`。窗口控制类指令（place、switch_tab、open_app_center 等）不走总线，仍用定向 channel。
