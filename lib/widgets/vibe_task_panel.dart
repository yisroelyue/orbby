import 'package:flutter/material.dart';

import '../config/panel_theme.dart';
import '../services/vibe_task_service.dart';

class VibeTaskPanel extends StatefulWidget {
  const VibeTaskPanel({super.key});

  @override
  State<VibeTaskPanel> createState() => _VibeTaskPanelState();
}

class _VibeTaskPanelState extends State<VibeTaskPanel>
    with SingleTickerProviderStateMixin, PanelThemeMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    VibeTaskService.instance.notifier.addListener(_onTasksChanged);
    VibeTaskService.instance.start();
  }

  @override
  void dispose() {
    VibeTaskService.instance.notifier.removeListener(_onTasksChanged);
    VibeTaskService.instance.stop();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTasksChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tasks = VibeTaskService.instance.tasks;
    final activeCount = tasks
        .where((t) =>
            t.status == VibeTaskStatus.working ||
            t.status == VibeTaskStatus.needsApproval ||
            t.status == VibeTaskStatus.needsInput)
        .length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(activeCount),
            const SizedBox(height: 12),
            if (tasks.isEmpty) _buildEmptyState() else _buildTaskList(tasks),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int activeCount) {
    return Row(
      children: [
        Icon(Icons.sensors, color: secondaryText, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Vibe Coding 任务监控',
            style: TextStyle(
              color: primaryText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (activeCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF64FFDA),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$activeCount 活跃',
            style: TextStyle(color: tertiaryText, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty_rounded, color: mutedText, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '等待 Claude Code hook 事件...',
              style: TextStyle(color: mutedText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(VibeTaskList tasks) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _buildTaskCard(tasks[index]),
    );
  }

  Widget _buildTaskCard(VibeTask task) {
    final (color, label) = _statusAppearance(task.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildStatusDot(task.status, color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.projectName,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(color: color, fontSize: 11),
                    ),
                  ],
                ),
                if (task.actionLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.actionLabel,
                    style: TextStyle(color: mutedText, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(VibeTaskStatus status, Color color) {
    if (status == VibeTaskStatus.working ||
        status == VibeTaskStatus.needsApproval) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (_, child) {
          return Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _pulseAnimation.value),
              shape: BoxShape.circle,
            ),
          );
        },
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  (Color, String) _statusAppearance(VibeTaskStatus status) {
    switch (status) {
      case VibeTaskStatus.working:
        return (const Color(0xFF64FFDA), status.label);
      case VibeTaskStatus.needsApproval:
        return (Colors.redAccent, status.label);
      case VibeTaskStatus.needsInput:
        return (Colors.amber, status.label);
      case VibeTaskStatus.idle:
        return (mutedText, status.label);
      case VibeTaskStatus.completed:
        return (Colors.greenAccent, status.label);
      case VibeTaskStatus.failed:
        return (Colors.redAccent, status.label);
      case VibeTaskStatus.stopped:
        return (Colors.grey, status.label);
    }
  }
}
