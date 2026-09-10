import '../data/db/app_database.dart';
import 'crypto_service.dart';

/// How this install participates in a clinic network.
enum DeploymentMode {
  /// Runs alone. No network listener, no outbound sync.
  standalone,

  /// Holds the authoritative database and answers other terminals.
  hub,

  /// Keeps a full local copy and syncs it against a hub.
  terminal;

  static DeploymentMode fromName(String? v) => DeploymentMode.values
      .firstWhere((m) => m.name == v, orElse: () => DeploymentMode.standalone);

  String get label => switch (this) {
        DeploymentMode.standalone => 'Standalone',
        DeploymentMode.hub => 'Clinic hub',
        DeploymentMode.terminal => 'Terminal',
      };

  String get description => switch (this) {
        DeploymentMode.standalone =>
          'This machine keeps its own records and does not talk to any other.',
        DeploymentMode.hub =>
          'This machine holds the clinic record and serves the other terminals '
              'on the network. Staff passwords are kept here.',
        DeploymentMode.terminal =>
          'This machine keeps a full working copy and syncs it with the clinic '
              'hub.',
      };
}

/// Typed accessors over the local `app_settings` table.
///
/// Nothing here replicates: each install has its own identity, its own idea of
/// where the hub is, and its own sync watermarks.
class SettingsService {
  SettingsService(this._db);

  final AppDatabase _db;

  static const _kClinicName = 'clinic_name';
  static const _kMode = 'deployment_mode';
  static const _kHubHost = 'hub_host';
  static const _kHubPort = 'hub_port';
  static const _kListenPort = 'listen_port';
  static const _kClinicKey = 'clinic_key';
  static const _kLastSyncAt = 'last_sync_at';
  static const _kSeeded = 'seeded';
  static const _kAutoSync = 'auto_sync';
  static const _kThemeMode = 'theme_mode';

  static const int defaultPort = 7343;

  String get clinicName => _db.setting(_kClinicName) ?? 'Sattra Clinic';
  set clinicName(String v) => _db.setSetting(_kClinicName, v);

  DeploymentMode get mode => DeploymentMode.fromName(_db.setting(_kMode));
  set mode(DeploymentMode v) => _db.setSetting(_kMode, v.name);

  String get hubHost => _db.setting(_kHubHost) ?? '';
  set hubHost(String v) => _db.setSetting(_kHubHost, v.trim());

  int get hubPort => int.tryParse(_db.setting(_kHubPort) ?? '') ?? defaultPort;
  set hubPort(int v) => _db.setSetting(_kHubPort, '$v');

  int get listenPort =>
      int.tryParse(_db.setting(_kListenPort) ?? '') ?? defaultPort;
  set listenPort(int v) => _db.setSetting(_kListenPort, '$v');

  /// Shared secret for this clinic's network. Absent until an administrator
  /// generates or enters one.
  String? get clinicKey {
    final v = _db.setting(_kClinicKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  set clinicKey(String? v) {
    if (v == null || v.isEmpty) {
      _db.removeSetting(_kClinicKey);
    } else {
      _db.setSetting(_kClinicKey, v.trim().toUpperCase());
    }
  }

  Future<String?> get clinicKeyFingerprint async {
    final key = clinicKey;
    return key == null ? null : CryptoService.fingerprint(key);
  }

  /// Light, dark, or follow the desktop. Stored per install, because one
  /// clinic terminal may sit in a bright reception and another in a back room.
  AppThemeMode get themeMode =>
      AppThemeMode.fromName(_db.setting(_kThemeMode));
  set themeMode(AppThemeMode v) => _db.setSetting(_kThemeMode, v.name);

  bool get autoSync => (_db.setting(_kAutoSync) ?? '1') == '1';
  set autoSync(bool v) => _db.setSetting(_kAutoSync, v ? '1' : '0');

  DateTime? get lastSyncAt {
    final v = _db.setting(_kLastSyncAt);
    return v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0);
  }

  set lastSyncAt(DateTime? v) => v == null
      ? _db.removeSetting(_kLastSyncAt)
      : _db.setSetting(_kLastSyncAt, '${v.millisecondsSinceEpoch}');

  bool get isSeeded => _db.setting(_kSeeded) == '1';
  void markSeeded() => _db.setSetting(_kSeeded, '1');

  /// Watermark of the last successful pull for [table].
  int watermark(String table) =>
      int.tryParse(_db.setting('wm_$table') ?? '') ?? 0;

  void setWatermark(String table, int value) =>
      _db.setSetting('wm_$table', '$value');

  void resetWatermarks(Iterable<String> tables) {
    for (final t in tables) {
      _db.removeSetting('wm_$t');
    }
  }

  String get baseUrl => 'http://$hubHost:$hubPort';

  /// True once this install has everything it needs to reach a hub.
  bool get canSync =>
      mode == DeploymentMode.terminal &&
      hubHost.isNotEmpty &&
      clinicKey != null;
}


/// Appearance preference.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromName(String? v) => AppThemeMode.values
      .firstWhere((m) => m.name == v, orElse: () => AppThemeMode.system);

  String get label => switch (this) {
        AppThemeMode.system => 'Match the desktop',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
      };
}
