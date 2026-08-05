# 项目规范

#### 更新到本文将中的内容要精简，参考已有内容格式

## 日志打印规范

日志打印必须使用 `LogService` 的对应方法，通过 `category` 参数区分模块：

```
LogService.info('━━━ LLM 请求 ━━━', category: 'llm');

```

可用 category 值：`system`、`weixin`、`llm`

## 设置实时生效

组件需响应设置变更时，监听 `HomeScreen.settingsChangeNotifier`，参照 `lib/widgets/control_panel.dart`：

```
// initState
_loadSettings();
HomeScreen.settingsChangeNotifier.addListener(_onRefresh);

void _onRefresh() => _loadSettings();  // 同步 tear-off，内部调异步

// dispose 必须 removeListener
```

`_loadSettings` 中先 `if (!mounted) return` 再 `setState`。




