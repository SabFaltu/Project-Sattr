import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'features/auth/first_run_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/shell/app_shell.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'theme.dart';

class SattraApp extends StatelessWidget {
  const SattraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppState>().themeMode;
    return FluentApp(
      title: 'Project सत्र',
      debugShowCheckedModeBanner: false,
      theme: SattraTheme.light(),
      darkTheme: SattraTheme.dark(),
      themeMode: switch (appTheme) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      localizationsDelegates: const [
        FluentLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

/// Decides which of the three top-level states the application is in.
///
/// Kept deliberately flat: an install either has no accounts yet, has nobody
/// signed in, or is in use. There is no route a signed-out user can reach.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.auth.needsFirstRunSetup) return const FirstRunPage();
    if (!state.isSignedIn) return const SignInPage();
    return const AppShell();
  }
}
