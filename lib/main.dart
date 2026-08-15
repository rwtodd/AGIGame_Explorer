import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/screens/launcher_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SierraAgiApp(),
    ),
  );
}

class SierraAgiApp extends StatelessWidget {
  const SierraAgiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sierra AGI Engine & Debug Workbench',
      debugShowCheckedModeBanner: false,
      theme: AgiTheme.darkTheme,
      home: const LauncherScreen(),
    );
  }
}
