import 'package:flutter/material.dart';

import 'services/window_coordinator.dart';

class OrbbyApp extends StatelessWidget {
  const OrbbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Microsoft YaHei'),
      home: const WindowCoordinator(),
    );
  }
}
