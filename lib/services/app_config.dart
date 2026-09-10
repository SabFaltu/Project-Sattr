import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The handful of settings that cannot live in the database.
///
/// Where the database *is* obviously cannot be stored inside it, so this small
/// JSON file sits beside the application's own support directory and is read
/// before anything is opened.
class AppConfig {
  AppConfig._(this.configFile, this._values);

  final File configFile;
  final Map<String, Object?> _values;

  static const _kDatabasePath = 'database_path';

  static Future<AppConfig> load(String supportDir) async {
    final file = File(p.join(supportDir, 'config.json'));
    var values = <String, Object?>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) values = decoded.cast<String, Object?>();
      } catch (_) {
        // A corrupt config must not stop the clinic from opening; the
        // defaults below are all recoverable from the Settings page.
      }
    }
    return AppConfig._(file, values);
  }

  Future<void> _save() async {
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_values),
    );
  }

  /// Where the clinic record lives, or null to use the default location.
  String? get databasePath => _values[_kDatabasePath] as String?;

  Future<void> setDatabasePath(String? path) async {
    if (path == null || path.isEmpty) {
      _values.remove(_kDatabasePath);
    } else {
      _values[_kDatabasePath] = path;
    }
    await _save();
  }

  /// Resolves the database path, falling back to the default.
  String resolveDatabasePath(String supportDir) =>
      databasePath ?? p.join(supportDir, 'sattra.db');
}
