import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/app_providers.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars and make them transparent so the flat app
  // background blends with the phone's status / navigation bars.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const RemoteApp(),
    ),
  );
}

class RemoteApp extends StatelessWidget {
  const RemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => ColoredBox(
        color: AppColors.bg,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeShell(),
    );
  }
}
