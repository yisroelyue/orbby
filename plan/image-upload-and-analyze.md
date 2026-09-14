# 图片粘贴与 `/image-analyze` 方案

## 目标

支持在聊天输入框直接粘贴图片文件或截图，显示缩略图，最多 4 张，并将图片交给视觉模型分析。

新增 `/image-analyze` 命令：选择命令并回车后不立即发送，而是将 `/image-analyze ` 写入输入框；用户继续粘贴图片、填写说明，再次回车执行分析。只有命令没有图片时提示用户先粘贴图片。

## 总体链路

```text
Windows Clipboard -> Flutter 附件服务 -> 预览组件
-> AgentService -> WebSocket chat.start -> agent-runtime
-> 统一多模态消息 -> provider adapter -> LLM
```

Flutter 负责剪贴板读取、预览、压缩和限制；Node 负责消息组装；LLM client 负责 OpenAI/Anthropic 格式转换。

## 文件规划

Flutter：

```text
lib/models/chat_attachment.dart
lib/services/clipboard_image_service.dart
lib/services/chat_attachment_controller.dart
lib/widgets/chat_attachment_preview.dart
lib/widgets/chat_attachment_viewer.dart
lib/services/agent_service.dart
lib/screens/home_screen/input.dart
lib/screens/home_screen/commands.dart
```

Windows：

```text
windows/runner/clipboard_image_channel.h
windows/runner/clipboard_image_channel.cpp
```

Node：

```text
agent-runtime/src/protocol.ts
agent-runtime/src/server.ts
agent-runtime/src/agent/runtime.ts
agent-runtime/src/llm/client.ts
agent-runtime/src/llm/content-adapter.ts
```

## 剪贴板实现

Flutter 默认文本 Clipboard 不足以稳定读取 Windows 图片，建议增加原生 MethodChannel。Windows 侧支持：

- `CF_HDROP`：资源管理器复制的图片文件。
- `CF_BITMAP`、`CF_DIB`、`CF_DIBV5`：截图或应用复制的图片数据。

位图统一转换为 PNG 临时文件，Dart 层统一得到附件对象。输入框捕获 `Ctrl+V`，优先尝试图片；没有图片时保留普通文本粘贴。可增加 Windows 图片专用快捷键 `Alt+V`。

## 附件模型和状态

`ChatAttachmentController extends ChangeNotifier` 统一负责添加、删除、清空、去重、校验和生成发送 payload。附件包含：

```dart
id, fileName, mimeType, localPath, thumbnailBytes,
width, height, sizeBytes
```

限制建议：最多 4 张；单张原文件最多 10 MB；支持 PNG、JPEG、WebP、GIF（动画取首帧）；最长边超过 4096px 时缩放；照片可转 JPEG，截图尽量保留 PNG；Base64 后单张建议不超过 5～8 MB。

第 5 张不加入列表，只显示本地提示。使用文件信息或 SHA-256 防止重复粘贴同一图片。

## 输入框 UI

输入区域顺序：

```text
CommandPalette
AgentQuestionPanel
ChatAttachmentPreview
TextField
```

预览组件支持缩略图、删除、点击查看大图、读取中、读取失败和图片失效状态。发送成功清空附件；请求失败或取消时保留附件，方便重试。

## `/image-analyze` 命令

命令模型增加：

```dart
enum ChatCommandBehavior { immediate, prepareInput }
```

现有命令使用 `immediate`；`/image-analyze` 使用 `prepareInput`。选择后：

- 不调用 `AgentService`。
- 输入框设置为 `/image-analyze `。
- 光标移动到末尾并请求焦点。
- 进入图片分析准备状态。

发送时将：

```text
/image-analyze 请找出布局问题
```

转换成：

```text
请找出布局问题
```

不把命令前缀发送给模型。若没有补充文字，使用“请分析这些图片，并描述其中的重要内容”。输入为空且无附件时不发送；输入是 `/image-analyze` 但无附件时提示先粘贴图片。

命令行为应通过 `ChatCommandBehavior` 扩展，不要在 UI 中硬编码单独判断 `/image-analyze`。

## AgentService 和 WebSocket

扩展：

```dart
AgentService.chatStream(String text, {
  List<ChatAttachment> attachments = const [],
  ...
})
```

`chat.start` payload：

```json
{
  "message": "请分析这些图片",
  "attachments": [{
    "id": "att-1",
    "fileName": "screen.png",
    "mimeType": "image/png",
    "data": "base64-data",
    "width": 1920,
    "height": 1080
  }]
}
```

`history.content` 从 `string` 扩展为 `unknown`，兼容文本和多模态 content。Node 侧必须再次校验附件数量、MIME 和大小。

## Agent Runtime 和 provider

Agent Runtime 使用统一内部格式：

```ts
type LlmContent = string | Array<
  {type: 'text'; text: string} |
  {type: 'image'; mediaType: string; data: string}
>;
```

AgentRuntime 只构造统一用户消息，不判断 provider。`content-adapter.ts` 转换为：

OpenAI-compatible：

```json
{"type":"image_url","image_url":{"url":"data:image/png;base64,...","detail":"auto"}}
```

Anthropic：

```json
{"type":"image","source":{"type":"base64","media_type":"image/png","data":"..."}}
```

图片应放在文字之前。不要复制 HTTP、重试和流式处理逻辑。

## 模型能力

发送前增加 `supportsVision(platform, model)` 判断。不支持视觉的模型本地提示“当前模型不支持图片分析，请切换到视觉模型”，不要等 API 返回模糊的 400 错误。不能假设所有 OpenAI-compatible 接口都支持图片。

## 会话持久化

不要把 Base64 写进会话 JSON。附件保存到：

```text
~/.orbby/attachments/{conversationId}/{attachmentId}.png
```

会话只保存 id、文件名、MIME、路径和尺寸等引用。UI 历史消息可以显示缩略图；LLM history 默认只发送当前轮完整图片，历史轮保留图片说明或引用，避免每轮重复消耗视觉 token。

`/retry` 恢复上一条用户消息的附件；文件不存在时提示重新粘贴。`/copy` 保存附件元数据而非 Base64；`/copy-txt` 只复制文字。

## 生命周期和异常

- `/clear`：清空会话、输入框、附件和图片分析模式，旧会话保留。
- 切换会话：先保存当前会话，再清理当前输入附件。
- 取消、断连、请求失败：保留附件，允许重试。
- 第一版请求进行中禁止追加附件。
- 图片读取失败只影响对应图片，并显示错误状态。

## 实施阶段

1. 剪贴板原生通道、图片读取、附件 controller、预览和限制。
2. 扩展 `AgentService`、WebSocket 协议和 Node 接收逻辑。
3. 接入 OpenAI-compatible 多模态格式。
4. 增加 `prepareInput` 命令行为和 `/image-analyze` 发送流程。
5. 接入 Anthropic adapter 和视觉模型判断。
6. 增加附件本地存储、会话显示、`/retry`、`/copy` 和旧会话兼容。
7. 完成后更新 `AGENTS.md`，记录剪贴板协议、附件限制、provider 转换、持久化和命令行为。

## 验收标准

- 复制图片文件或截图后粘贴，输入框能显示缩略图。
- 最多 4 张，第 5 张有明确提示。
- 可删除图片、查看大图并发送普通图片消息。
- `/image-analyze` 选择后不会立即发送，命令会留在输入框。
- 粘贴图片并回车后能执行分析；无图片时不会调用 AI。
- 命令前缀不会传给模型。
- OpenAI-compatible 和 Anthropic 格式转换正确。
- 取消、断连、失败和 `/retry` 不静默丢失附件。
- 旧会话仍能打开。
- 不执行 Flutter analyze 或 Flutter test，只进行代码级检查和必要的构建外检查。
