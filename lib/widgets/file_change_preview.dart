import 'package:flutter/material.dart';

import '../models/file_change_preview.dart';
import '../theme/chat_theme.dart';

/// Agent 文件改动留痕面板（嵌在 AI 气泡内，随会话落盘）。
/// 视觉与参考稿 .diff 同源：raised 卡 + 12px 圆角 + line 描边 + 卡片微影，
/// 每条改动 = 头部（操作标签 + 路径 + 增删计数）+ sunken 底 diff 正文，
/// 行体 = 老行号/新行号双槽 + +/- 符号 + 间隙 + 代码文本，
/// 增删语义由行底软色与符号色表达，代码正文一律墨色。
class FileChangesPanel extends StatelessWidget {
  const FileChangesPanel({super.key, required this.changes});
  final List<FileChangePreview> changes;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.line),
        boxShadow: theme.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < changes.length; i++) ...[
            // 多条改动之间的 hairline 分隔（Column 的 cross 轴是 start，
            // 无宽高的 Container 会塌缩成 0，必须显式给高度与满宽）
            if (i > 0)
              Container(height: 1, width: double.infinity, color: theme.lineSoft),
            _FileDiff(change: changes[i]),
          ],
        ],
      ),
    );
  }
}

class _FileDiff extends StatelessWidget {
  const _FileDiff({required this.change});
  final FileChangePreview change;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final rows = _parseDiffRows(change.diff);
    // 行号槽宽度按最大行号位数算：JetBrains Mono 数字定宽 0.6em（11.5px
    // 字号 ≈ 6.9px/位），槽宽不足会把行号截断成另一个错误数字
    var maxNo = 0;
    for (final row in rows) {
      final no = row.oldNo ?? row.newNo ?? 0;
      if (no > maxNo) maxNo = no;
    }
    final gutterWidth = maxNo.toString().length * 6.9 + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部：操作标签 + 路径（mono）+ 增删计数。
        // 顶栏灰底（barBg，与代码块标题条 / 提问留痕卡同一 token），
        // 与正文 sunken 的分隔沿用正文容器自带的顶部 hairline
        Container(
          color: theme.barBg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Row(
              children: [
                _OpTag(operation: change.operation),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.ink,
                      fontSize: 12.5,
                      fontFamily: ChatTheme.codeFont,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+${change.additions}',
                  style: TextStyle(
                    color: theme.ok,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: ChatTheme.codeFont,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '-${change.deletions}',
                  style: TextStyle(
                    color: theme.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: ChatTheme.codeFont,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 正文：sunken 底 + 顶部 hairline。行宽 = max(容器宽, 700)：容器比
        // 700 宽时行底铺满整卡（写死 700 会在右侧留一段未染色的空条），
        // 比 700 窄时保底 700 并横向滚动
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.sunken,
            border: Border(top: BorderSide(color: theme.lineSoft)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowWidth = constraints.maxWidth < _minDiffRowWidth
                  ? _minDiffRowWidth
                  : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in rows)
                      _DiffLine(
                        row: row,
                        width: rowWidth,
                        gutterWidth: gutterWidth,
                        theme: theme,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 操作标签：create 绿 / edit 蓝 / delete 红，软底 + 前景同系
class _OpTag extends StatelessWidget {
  const _OpTag({required this.operation});
  final String operation;

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    final (bg, fg, label) = switch (operation) {
      'create' => (theme.okSoft, theme.ok, '新建'),
      'delete' => (theme.dangerSoft, theme.danger, '删除'),
      _ => (theme.infoSoft, theme.info, '编辑'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          fontFamily: ChatTheme.codeFont,
        ),
      ),
    );
  }
}

/// 行体最小宽度：卡片窄于该值时行体保底此宽并横向滚动
const double _minDiffRowWidth = 700;

/// 一行 diff 的解析结果：符号（+/−）+ 去符号正文 + 老/新行号。
/// 删除行只带老行号、新增行只带新行号（另一侧为 null）。
class _DiffRow {
  const _DiffRow(this.sign, this.text, this.oldNo, this.newNo);
  final String sign;
  final String text;
  final int? oldNo;
  final int? newNo;
}

/// 解析 agent-runtime fs-tools 生成的简化 unified diff（---/+++ 头 +
/// @@ hunk 头 + 先全部删除行后全部新增行，无上下文行）。
/// 行号从 @@ 头起算、按侧独立推进；@@ 再次出现时重置游标（容错多 hunk）。
/// ---/+++ 头只认前两行位置：被删行内容以 `-- ` 开头时拼上前缀也是
/// `--- xxx`，按内容匹配会把它误当文件头吞掉。
List<_DiffRow> _parseDiffRows(String diff) {
  final lines = diff.split('\n');
  final hunkHeader = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)?');
  var oldNo = 0;
  var newNo = 0;
  final rows = <_DiffRow>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final hunk = hunkHeader.firstMatch(line);
    if (hunk != null) {
      oldNo = int.parse(hunk.group(1)!);
      newNo = int.parse(hunk.group(2)!);
      continue;
    }
    if (i < 2 && (line.startsWith('--- ') || line.startsWith('+++ '))) continue;
    final sign = line.isEmpty ? ' ' : line[0];
    int? o;
    int? n;
    if (sign == '-') {
      o = oldNo++;
    } else if (sign == '+') {
      n = newNo++;
    } else {
      o = oldNo++;
      n = newNo++;
    }
    rows.add(_DiffRow(sign, line.isEmpty ? '' : line.substring(1), o, n));
  }
  return rows;
}

/// 行体：老/新行号双槽（GitHub 同款：删除行占左槽、新增行占右槽）+
/// +/- 符号 + 一格间隙 + 代码文本；增删染行底软色与符号色，正文墨色。
class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.row,
    required this.width,
    required this.gutterWidth,
    required this.theme,
  });

  final _DiffRow row;
  final double width;
  final double gutterWidth;
  final ChatThemeData theme;

  @override
  Widget build(BuildContext context) {
    final added = row.sign == '+';
    final removed = row.sign == '-';
    // GitHub 式：行底与 +/- 符号染增删色，代码正文一律墨色（ink，
    // 深色主题下自动反为近白），彩色文字大面积铺开可读性差
    final signColor = added ? theme.ok : removed ? theme.danger : theme.ink3;
    final gutterStyle = TextStyle(
      color: theme.ink3,
      fontSize: 11.5,
      fontFamily: ChatTheme.codeFont,
    );
    return Container(
      width: width,
      color: added
          ? theme.okSoft
          : removed
              ? theme.dangerSoft
              : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: gutterWidth,
            child: Text(
              row.oldNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: gutterStyle,
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: gutterWidth,
            child: Text(
              row.newNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: gutterStyle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            row.sign,
            style: TextStyle(
              color: signColor,
              fontSize: 12.5,
              fontFamily: ChatTheme.codeFont,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.text,
              style: TextStyle(
                color: theme.ink,
                fontSize: 12.5,
                height: 1.7,
                fontFamily: ChatTheme.codeFont,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
