/// '/' 命令与 '@' 技能两个面板 controller 共用的关键词匹配规则。
/// 抽成顶层纯函数避免两处各复制一份排序语义（改一处漏一处）。

/// 是否匹配（rank < 3，见 [paletteMatchRank]）；空关键词匹配一切
bool paletteMatches(String name, String keyword) =>
    paletteMatchRank(name, keyword) < 3;

/// 匹配优先级：名称前缀(0) > 分隔词首字母缩写(1) > 字符顺序匹配(2) > 不匹配(3)。
/// 例如 `cs` -> `clear-session`（前缀），`st` -> `setting`（顺序匹配）。
int paletteMatchRank(String name, String keyword) {
  if (keyword.isEmpty) return 0;
  final normalized = name.toLowerCase();
  if (normalized.startsWith(keyword)) return 0;

  final initials = normalized
      .split(RegExp(r'[-_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .join();
  if (initials.startsWith(keyword)) return 1;

  // 允许输入的字符按顺序出现在名称中，例如 `st` -> `setting`。
  var keywordIndex = 0;
  for (final character in normalized.split('')) {
    if (character == keyword[keywordIndex]) {
      keywordIndex++;
      if (keywordIndex == keyword.length) return 2;
    }
  }
  return 3;
}
