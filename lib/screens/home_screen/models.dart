part of 'home_screen.dart';

/// 一个会话标签页的完整视图状态（多会话并发的 UI 侧载体）。
/// 消息列表、流式状态、排队消息、挂起提问、附件、输入草稿全部按 tab 隔离。
///
/// 关键纪律：**流式写入必须持有 view 引用**（_sendText 开头捕获），
/// 绝不能经 `_current` 间接访问——流式期间用户可能切走 tab，
/// 经 `_current` 写会串到错误的会话；渲染/命令层（只作用于前台）不受此限。
class ChatSessionView {
  ChatSessionView({required this.agentSessionId});

  /// Node 侧会话隔离 key：agent-runtime 按 sessionId 隔离上下文/工作区/锁，
  /// tab 生命周期内不变（/cd 等只影响本 tab 对应的 Node 会话）
  final String agentSessionId;

  /// 会话持久化句柄；null = 新对话尚未落盘，首轮发送时创建
  ChatConversation? conversation;

  final messages = <_ChatMessage>[];

  /// 本会话排队等待的后续任务（当前回复结束后按序续发）
  final queuedTexts = <String>[];

  /// 本会话是否有流式请求进行中
  bool isSending = false;

  /// Agent 提问卡片（输入框上方）；null = 无挂起提问。
  /// 后台会话挂起提问时用户看不到卡片，tab 上以"待回答"标记提醒
  AgentQuestionPanelController? questionCtrl;

  /// 当前提问的 questionId（与 [questionCtrl] 同生命周期）
  String? questionId;

  /// 输入框草稿：切换 tab 时存回/恢复，各会话互不覆盖
  String inputDraft = '';

  /// 本会话输入框附件（粘贴的图片/文件）
  final attachmentCtrl = ChatAttachmentController();
}

/// 聊天消息数据模型：随会话 JSON 落盘（ChatStorageService），
/// toJson/fromJson 需与既有会话文件格式保持兼容，勿改动字段名。

class _ToolEvent {
  _ToolEvent(this.id, this.name, {required this.running, this.error = false, this.parameters, this.result, this.errorMessage, List<FileChangePreview>? changes}) : changes = List<FileChangePreview>.from(changes ?? const []);
  final String id;
  final String name;
  bool running;
  bool error;
  final dynamic parameters;
  dynamic result;
  String? errorMessage;
  final List<FileChangePreview> changes;
  /// ask_user_question 的问答留痕（挂在对应工具行下面展示）
  final List<_QuestionPanel> questionPanels = [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'running': running,
        'error': error,
        if (parameters != null) 'parameters': parameters,
        if (result != null) 'result': result,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (changes.isNotEmpty) 'changes': changes.map((e) => e.toJson()).toList(),
        if (questionPanels.isNotEmpty) 'questionPanels': questionPanels.map((e) => e.toJson()).toList(),
      };

  factory _ToolEvent.fromJson(Map<String, dynamic> json) => _ToolEvent(
        json['id']?.toString() ?? '',
        json['name']?.toString() ?? 'tool',
        running: json['running'] == true,
        error: json['error'] == true,
        parameters: json['parameters'],
        result: json['result'],
        errorMessage: json['errorMessage']?.toString(),
        changes: (json['changes'] as List? ?? []).whereType<Map>().map((e) => FileChangePreview.fromJson(Map<String, dynamic>.from(e))).toList(),
      )..questionPanels.addAll((json['questionPanels'] as List? ?? []).whereType<Map>().map((e) => _QuestionPanel.fromJson(Map<String, dynamic>.from(e))));
}

/// 一次 Agent 提问的问答留痕（questions + 用户 answers / 跳过标记），随会话落盘。
class _QuestionPanel {
  _QuestionPanel({required this.questions, required this.answers, this.skipped = false});
  final List<AgentQuestion> questions;
  final List<List<String>> answers;
  final bool skipped;

  Map<String, dynamic> toJson() => {
        'questions': questions.map((e) => e.toJson()).toList(),
        'answers': answers,
        'skipped': skipped,
      };

  factory _QuestionPanel.fromJson(Map<String, dynamic> json) => _QuestionPanel(
        questions: (json['questions'] as List? ?? []).map(AgentQuestion.fromJson).toList(),
        answers: (json['answers'] as List? ?? []).map((e) => (e as List? ?? []).map((v) => v.toString()).toList()).toList(),
        skipped: json['skipped'] == true,
      );
}

class _ChatMessage {
  _ChatMessage({required this.text, required this.isUser, this.streaming = false, this.local = false, this.terminated = false, this.pending = false, List<ChatAttachment>? attachments})
      : attachments = List<ChatAttachment>.from(attachments ?? const []);
  String text;
  final bool isUser;
  bool streaming;
  final bool local;
  bool terminated;
  bool pending;
  /// 工具步骤组（≥2 个工具调用）是否展开；瞬态 UI 状态，不落盘，重载会话后默认折叠。
  /// 一条消息内的工具行始终连续位于正文之前（agent.dart 切泡逻辑保证），至多一个组。
  bool toolsExpanded = false;
  final List<_ToolEvent> toolEvents = [];
  final List<FileChangePreview> fileChanges = [];
  /// 用户消息的图片附件（引用元数据 + 本地路径，随会话落盘；不含 Base64）
  final List<ChatAttachment> attachments;
}
