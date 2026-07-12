import 'package:flutter/material.dart';

import 'screens/pet_screen.dart';

class OrbbyApp extends StatelessWidget {
  const OrbbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'NotoSansSC'),
      home: const PetScreen(),
    );
  }
}
