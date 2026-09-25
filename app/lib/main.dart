// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.load();
  runApp(BikeAssessorApp(services));
}

class BikeAssessorApp extends StatelessWidget {
  final AppServices services;
  const BikeAssessorApp(this.services, {super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B6E53);
    return MaterialApp(
      title: 'Virtual Bike Assessor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomeScreen(services),
    );
  }
}
