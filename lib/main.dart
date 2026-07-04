import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/app_providers.dart';
import 'state/preferences_provider.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

/// Single sink for every error the app can't otherwise handle. Kept as one place
/// on purpose: it's the hook a crash reporter (Sentry/Crashlytics) would plug
/// into later. For now it just logs — there's no remote reporting.
void _logError(Object error, StackTrace? stack) {
  FlutterError.dumpErrorToConsole(
    FlutterErrorDetails(exception: error, stack: stack),
  );
}

Future<void> main() async {
  // Run everything inside a guarded zone so uncaught async errors are contained
  // instead of taking the app down.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Build/layout/paint errors -> our logger (and the usual console dump in
      // debug). Without this they'd be silently swallowed in release.
      FlutterError.onError = (details) {
        _logError(details.exception, details.stack);
        if (kDebugMode) FlutterError.presentError(details);
      };
      // Uncaught errors that reach the platform dispatcher: log + mark handled.
      PlatformDispatcher.instance.onError = (error, stack) {
        _logError(error, stack);
        return true;
      };
      // Never show users Flutter's red/grey crash box — a calm fallback instead.
      ErrorWidget.builder = (details) => const _FatalErrorScreen();

      // Draw behind the system bars and make them transparent so the flat app
      // background blends with the phone's status / navigation bars. (The
      // icon brightness is set per-mode in RemoteApp.)
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // A failure here must not white-screen launch; show the calm fallback
      // instead of a blank screen (prefs failing is rare but possible on a
      // locked-down or corrupt device store).
      final SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (error, stack) {
        _logError(error, stack);
        runApp(
          const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _FatalErrorScreen(),
          ),
        );
        return;
      }

      runApp(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const RemoteApp(),
        ),
      );
    },
    _logError,
  );
}

class RemoteApp extends ConsumerWidget {
  const RemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(effectiveDarkModeProvider);
    // Swap the token palette *before* anything below reads it; every widget
    // that uses AppColors rebuilds under this watch.
    AppColors.setDark(dark);
    // Keep the transparent system bars readable in either mode.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    return MaterialApp(
      title: 'Omnix',
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => ColoredBox(
        color: AppColors.bg,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeShell(),
    );
  }
}

/// Calm replacement for Flutter's default error box, shown if a widget fails to
/// build. Self-contained (no theme/inherited-widget dependencies) so it renders
/// even when something upstream is broken.
class _FatalErrorScreen extends StatelessWidget {
  const _FatalErrorScreen();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Something went wrong.\nPlease reopen the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textMuted,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
