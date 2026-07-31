import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbby/agent/tool_policy.dart';

void main() {
  final root = Directory.current.path;

  test('allows paths inside workspace and rejects paths outside it', () {
    final policy = ToolPolicy(workspaceRoot: root);
    expect(policy.validate('read_file', {'path': '$root/test.txt'}), isNull);
    expect(
      policy.validate('read_file', {'path': Directory(root).parent.path}),
      isNotNull,
    );
  });

  test('rejects dangerous commands', () {
    final policy = ToolPolicy(workspaceRoot: root);
    expect(
      policy.validate('execute_command', {'command': 'shutdown /s'}),
      isNotNull,
    );
    expect(
      policy.validate('execute_command', {
        'command': 'git status',
        'cwd': root,
      }),
      isNull,
    );
  });
}
