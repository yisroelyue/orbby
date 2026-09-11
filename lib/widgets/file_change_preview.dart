import 'package:flutter/material.dart';
import '../models/file_change_preview.dart';

class FileChangesPanel extends StatelessWidget {
  const FileChangesPanel({super.key, required this.changes});
  final List<FileChangePreview> changes;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF202328),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final change in changes) _FileDiff(change: change),
        ],
      ),
    );
  }
}

class _FileDiff extends StatelessWidget {
  const _FileDiff({required this.change});
  final FileChangePreview change;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${change.path}  ${change.operation}  +${change.additions} -${change.deletions}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'JetBrains Mono')),
          const SizedBox(height: 3),
          Padding(padding: const EdgeInsets.only(left: 12), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final line in change.diff.split('\n')) _DiffLine(line)]))),
        ]),
      );
}

Widget _DiffLine(String line) {
  if (line.startsWith('--- ') || line.startsWith('+++ ')) {
    return const SizedBox.shrink();
  }
  final added = line.startsWith('+') && !line.startsWith('+++');
  final removed = line.startsWith('-') && !line.startsWith('---');
  final hunk = line.startsWith('@@');
  if (hunk) return const SizedBox.shrink();
  return Container(width: 700, color: added ? const Color(0x263B914A) : removed ? const Color(0x264D2226) : Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: Text(line, style: TextStyle(color: added ? const Color(0xFF8BD49A) : removed ? const Color(0xFFF28B96) : Colors.white54, fontSize: 11, fontFamily: 'JetBrains Mono')));
}
