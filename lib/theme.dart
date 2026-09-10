import 'package:fluent_ui/fluent_ui.dart';

/// Visual language for the application.
///
/// Fluent's own palette does most of the work; what is defined here are the
/// few clinical accents the interface needs to be able to say something at a
/// glance — a stock line that is short, a symptom that is not baseline, a
/// terminal that is working offline.
class SattraTheme {
  static const Color brand = Color(0xFF0F6CBD);
  static const Color brandDeep = Color(0xFF115EA3);

  static const Color ok = Color(0xFF0E7A0B);
  static const Color warn = Color(0xFFB86A00);
  static const Color danger = Color(0xFFC4314B);
  static const Color info = Color(0xFF0F6CBD);

  static FluentThemeData light() => _build(Brightness.light);
  static FluentThemeData dark() => _build(Brightness.dark);

  static FluentThemeData _build(Brightness brightness) {
    final base = FluentThemeData(
      brightness: brightness,
      accentColor: _accent,
      fontFamily: _uiFontFamily,
      visualDensity: VisualDensity.standard,
    );
    return base.copyWith(
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF6F7F9)
          : const Color(0xFF1F1F1F),
      cardColor: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF2B2B2B),
    );
  }

  /// The interface font is left to the platform.
  ///
  /// Windows resolves this to Segoe UI, which is the look the project
  /// specifies; other platforms fall back to their own UI face rather than
  /// shipping a font the project has no licence to redistribute.
  static const String? _uiFontFamily = null;

  static final AccentColor _accent = AccentColor.swatch(const {
    'darkest': Color(0xFF06355C),
    'darker': Color(0xFF0A4479),
    'dark': brandDeep,
    'normal': brand,
    'light': Color(0xFF3A8FD4),
    'lighter': Color(0xFF7FB6E5),
    'lightest': Color(0xFFCCE3F5),
  });

  /// Colour for a symptom grade: baseline reads calm, anything else is
  /// something the clinician should notice.
  static Color symptomColor(bool notable, Brightness brightness) => notable
      ? warn
      : (brightness == Brightness.light
          ? const Color(0xFF5C6470)
          : const Color(0xFFA9B1BC));

  static Color stockColor(bool out, bool low) =>
      out ? danger : (low ? warn : ok);
}
