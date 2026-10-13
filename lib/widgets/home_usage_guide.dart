import '../services/chat_command.dart';

/// 首页使用说明内容生成器，作为本地 assistant 消息插入聊天记录。
/// 命令清单从 HomeScreen 注册表生成，避免说明和实际功能脱节。
class HomeUsageGuide {
  const HomeUsageGuide._();

  static String asConversationRecord(List<ChatCommand> commands) {
    final buffer = StringBuffer()
      ..writeln('## 应用介绍')
      ..writeln()
      ..writeln('Orbby 是一个由多个独立窗口组成的桌面助手。可以在对话面板中输入任务，也可以通过应用条和内容面板访问常用功能。输入 `/` 浏览命令，输入 `@` 选择技能。')
      ..writeln()
      ..writeln('## 窗口说明')
      ..writeln()
      ..writeln('### 应用条')
      ..writeln('桌面快捷入口栏，用于打开常用应用或功能。按 `Win+\`` 显示或隐藏。')
      ..writeln()
      ..writeln('### 内容面板')
      ..writeln('展示应用与相关内容的面板。按 `Ctrl+\`` 显示或隐藏。')
      ..writeln()
      ..writeln('### 对话面板')
      ..writeln('与 Agent 对话、发送任务、查看回复和工具执行过程的主窗口。按 `Alt+\`` 呼出或收起；按 Esc 可收起。')
      ..writeln()
      ..writeln('## 命令列表');
    for (final command in commands) {
      buffer.writeln('- `/${command.name}` — ${command.description}');
    }
    return buffer.toString();
  }
}
