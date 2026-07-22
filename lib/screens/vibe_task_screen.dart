import 'package:flutter/material.dart';

import '../services/vibe_task_service.dart';

class VibeTaskScreen extends StatefulWidget {
  const VibeTaskScreen({super.key});

  @override
  State<VibeTaskScreen> createState() => _VibeTaskScreenState();
}

class _VibeTaskScreenState extends State<VibeTaskScreen> {
  @override
  void initState() {
    super.initState();
    VibeTaskService.instance.notifier.addListener(_onTasksChanged);
    VibeTaskService.instance.start();
  }

  @override
  void dispose() {
    VibeTaskService.instance.notifier.removeListener(_onTasksChanged);
    VibeTaskService.instance.stop();
    super.dispose();
  }

  void _onTasksChanged() {
    if (mounted) setState(() {});
  }

  (String, Color) _activeDisplay() {
    final tasks = VibeTaskService.instance.tasks;
    if (tasks.isEmpty) {
      return ('Vibe 监控中...', Colors.white24);
    }

    // Pick the most relevant active task — show status only, no project name
    for (final task in tasks) {
      switch (task.status) {
        case VibeTaskStatus.working:
          return (task.status.label, const Color(0xFF64FFDA));
        case VibeTaskStatus.needsApproval:
          return (task.status.label, Colors.redAccent);
        case VibeTaskStatus.needsInput:
          return (task.status.label, Colors.amber);
        default:
          continue;
      }
    }

    final latest = tasks.first;
    return (latest.status.label, Colors.white30);
  }

  @override
  Widget build(BuildContext context) {
    final (text, color) = _activeDisplay();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Microsoft YaHei'),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
