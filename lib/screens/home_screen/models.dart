part of 'home_screen.dart';

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
  _ChatMessage({required this.text, required this.isUser, this.streaming = false, this.local = false, this.terminated = false, List<ChatAttachment>? attachments})
      : attachments = List<ChatAttachment>.from(attachments ?? const []);
  String text;
  final bool isUser;
  bool streaming;
  final bool local;
  bool terminated;
  final List<_ToolEvent> toolEvents = [];
  final List<FileChangePreview> fileChanges = [];
  /// 用户消息的图片附件（引用元数据 + 本地路径，随会话落盘；不含 Base64）
  final List<ChatAttachment> attachments;
}
