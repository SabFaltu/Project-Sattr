import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'services/app_config.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await _openWindow();
  }

  final supportDir = await _supportDirectory();
  final config = await AppConfig.load(supportDir);
  final database = AppDatabase.open(_databasePath(config, supportDir));
  final state = AppState(database, config: config, supportDir: supportDir);
  await state.bootstrap();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const SattraApp(),
    ),
  );
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Sizes and shows the main window.
///
/// Every step is best-effort. Sizing depends on the desktop being able to
/// report its geometry, and on some setups — a bare X session, a remote
/// display, a locked-down kiosk — that call can fail or simply never return.
/// A window that is the wrong size is a nuisance; a window that never appears
/// leaves the clinic staring at nothing, so the failure path still ends with
/// the window on screen.
Future<void> _openWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager
        .waitUntilReadyToShow(
          const WindowOptions(
            size: Size(1320, 860),
            minimumSize: Size(1024, 680),
            center: true,
            title: 'Project सत्र — Clinic Management',
            titleBarStyle: TitleBarStyle.normal,
          ),
          () async {
            await windowManager.show();
            await windowManager.focus();
          },
        )
        .timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Window setup did not complete ($error); showing it anyway.');
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // Nothing further to try: the embedder will present its default window.
    }
  }
}

Future<String> _supportDirectory() async =>
    (await getApplicationSupportDirectory()).path;

/// Where the clinic record lives.
///
/// Precedence runs from most to least explicit: an environment override, then
/// a location the administrator chose in Settings, then the platform default.
/// The environment override is what lets two copies run side by side on one
/// machine while testing a hub against a terminal.
String _databasePath(AppConfig config, String supportDir) {
  final override = Platform.environment['SATTRA_DATA_DIR'];
  if (override != null && override.isNotEmpty) {
    return p.join(override, 'sattra.db');
  }
  return config.resolveDatabasePath(supportDir);
}
