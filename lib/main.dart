import 'package:flutter/material.dart';

import 'models.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding.dart';
import 'tag_connection.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  tagManager.init();
  runApp(const TpcmFindApp());
}

class TpcmFindApp extends StatelessWidget {
  const TpcmFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPCM Find',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      // İlk açılışta karşılama + izinler; sonra doğrudan Cihazlarım.
      home: appSettings.onboarded ? const HomeShell() : const WelcomeScreen(),
    );
  }
}
