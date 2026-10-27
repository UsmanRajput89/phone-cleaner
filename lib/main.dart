import 'package:flutter/material.dart';

import 'app/controller.dart';
import 'app/theme.dart';
import 'ui/gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.create();
  runApp(PhoneCleanerApp(controller: controller));
}

class PhoneCleanerApp extends StatelessWidget {
  final AppController controller;

  const PhoneCleanerApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'Phone Cleaner',
            debugShowCheckedModeBanner: false,
            themeMode: controller.flutterThemeMode,
            theme: buildTheme(lightPalette, Brightness.light),
            darkTheme: buildTheme(darkPalette, Brightness.dark),
            home: const Gate(),
          );
        },
      ),
    );
  }
}
