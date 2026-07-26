import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '设置窗口中可配置各项参数',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );
  }
}
