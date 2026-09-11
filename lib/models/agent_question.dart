/// Agent 向用户提问的结构化模型（ask_user_question 工具 / 目录权限确认共用）。
/// 与 agent-runtime/src/protocol.ts 的 AgentQuestion 契约对应。
class AgentQuestionOption {
  const AgentQuestionOption({required this.label, this.description});

  final String label;
  final String? description;

  factory AgentQuestionOption.fromJson(dynamic raw) {
    if (raw is Map) {
      return AgentQuestionOption(
        label: (raw['label'] ?? '').toString(),
        description: raw['description']?.toString(),
      );
    }
    // 容错：LLM 偶尔直接给字符串
    return AgentQuestionOption(label: raw.toString());
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        if (description != null) 'description': description,
      };
}

class AgentQuestion {
  const AgentQuestion({
    required this.question,
    this.header,
    required this.type,
    this.options = const [],
    this.multiSelect = false,
  });

  final String question;
  final String? header;
  /// 'choice' = 选项选择，'text' = 自由输入
  final String type;
  final List<AgentQuestionOption> options;
  final bool multiSelect;

  factory AgentQuestion.fromJson(dynamic raw) {
    if (raw is! Map) {
      return AgentQuestion(question: raw?.toString() ?? '', type: 'text');
    }
    final options = (raw['options'] as List?)
            ?.map(AgentQuestionOption.fromJson)
            .where((option) => option.label.isNotEmpty)
            .toList() ??
        const <AgentQuestionOption>[];
    return AgentQuestion(
      question: (raw['question'] ?? '').toString(),
      header: raw['header']?.toString(),
      // type 缺省时按 options 推断
      type: raw['type'] == 'text' || options.isEmpty ? 'text' : 'choice',
      options: options,
      multiSelect: raw['multiSelect'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        if (header != null) 'header': header,
        'type': type,
        'options': [for (final option in options) option.toJson()],
        'multiSelect': multiSelect,
      };
}
