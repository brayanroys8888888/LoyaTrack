import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const blue         = Color(0xFF1565C0);
  static const blue2        = Color(0xFF1976D2);
  static const blue3Light   = Color(0xFFE3F2FD);
  static const blue3Dark    = Color(0xFF0D2A4A);
  static const green        = Color(0xFF2E7D32);
  static const green2       = Color(0xFF388E3C);
  static const green3Light  = Color(0xFFE8F5E9);
  static const green3Dark   = Color(0xFF0A2E0D);
  static const success      = Color(0xFF2E7D32);
  static const successLight = Color(0xFFE8F5E9);
  static const successDark  = Color(0xFF0A2E0D);
  static const danger       = Color(0xFFD32F2F);
  static const dangerLight  = Color(0xFFFFEBEE);
  static const dangerDark   = Color(0xFF3E0A0A);
  static const warning      = Color(0xFFF57C00);
  static const warningLight = Color(0xFFFFF3E0);
  static const warningDark  = Color(0xFF3E2200);
  static const penalty      = Color(0xFFC62828);
  static const penaltyLight = Color(0xFFFCE4EC);
  static const penaltyDark  = Color(0xFF3E0A1A);
  static const bgLight      = Color(0xFFF8F9FA);
  static const surfaceLight = Color(0xFFF0F2F5);
  static const cardLight    = Color(0xFFFFFFFF);
  static const borderLight  = Color(0xFFE0E0E0);
  static const textPrimaryLight    = Color(0xFF1A1A2E);
  static const textSecondaryLight  = Color(0xFF5F6368);
  static const textHintLight       = Color(0xFF9E9E9E);
  static const bgDark       = Color(0xFF0F1117);
  static const surfaceDark  = Color(0xFF1A1D27);
  static const cardDark     = Color(0xFF1E2230);
  static const borderDark   = Color(0xFF2A2D3E);
  static const textPrimaryDark    = Color(0xFFEEF0F5);
  static const textSecondaryDark  = Color(0xFF9AA0B4);
  static const textHintDark       = Color(0xFF5A5F74);
}

class ThemeProvider extends ChangeNotifier {
  // Par défaut : on suit le thème du système (clair/sombre selon le téléphone).
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get themeMode => _mode;

  /// Vrai uniquement si l'utilisateur a explicitement forcé le mode sombre.
  /// (Pour le mode « système », l'état réel est résolu par MaterialApp.)
  bool get isDark => _mode == ThemeMode.dark;

  ThemeProvider() { _load(); }

  void _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('theme_mode');
    if (s == 'light') {
      _mode = ThemeMode.light;
    } else if (s == 'dark') {
      _mode = ThemeMode.dark;
    } else if (s == null && p.containsKey('dark_mode')) {
      // Migration depuis l'ancien réglage booléen 'dark_mode'.
      _mode = (p.getBool('dark_mode') ?? false) ? ThemeMode.dark : ThemeMode.light;
    } else {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'theme_mode',
        m == ThemeMode.light
            ? 'light'
            : m == ThemeMode.dark
                ? 'dark'
                : 'system');
  }
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final bg      = isDark ? AppColors.bgDark      : AppColors.bgLight;
    final card    = isDark ? AppColors.cardDark    : AppColors.cardLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border  = isDark ? AppColors.borderDark  : AppColors.borderLight;
    final textP   = isDark ? AppColors.textPrimaryDark    : AppColors.textPrimaryLight;
    final textS   = isDark ? AppColors.textSecondaryDark  : AppColors.textSecondaryLight;
    final textH   = isDark ? AppColors.textHintDark       : AppColors.textHintLight;

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: bg,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: ColorScheme(
        brightness: b,
        primary: AppColors.blue,
        onPrimary: Colors.white,
        secondary: AppColors.green,
        onSecondary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        background: bg,
        onBackground: textP,
        surface: card,
        onSurface: textP,
      ),
      cardColor: card,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF141828) : AppColors.blue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
        // L'AppBar est bleue → icônes de statut claires, MAIS la barre de
        // navigation (téléphones à 3 boutons) doit suivre le fond du thème.
        // SystemUiOverlayStyle.light forçait un fond noir : on le remplace.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: bg,
          systemNavigationBarDividerColor: bg,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
        hintStyle: TextStyle(color: textH, fontSize: 14),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: textP),
        titleLarge:   TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: textP),
        titleMedium:  TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textP),
        bodyLarge:    TextStyle(fontSize: 15, color: textP),
        bodyMedium:   TextStyle(fontSize: 13, color: textS),
        labelSmall:   TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: textS, letterSpacing: 0.8),
      ),
    );
  }
}

extension ThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg        => isDark ? AppColors.bgDark      : AppColors.bgLight;
  Color get cCard     => isDark ? AppColors.cardDark    : AppColors.cardLight;
  Color get cSurface  => isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
  Color get cBorder   => isDark ? AppColors.borderDark  : AppColors.borderLight;
  Color get cText     => isDark ? AppColors.textPrimaryDark    : AppColors.textPrimaryLight;
  Color get cTextSub  => isDark ? AppColors.textSecondaryDark  : AppColors.textSecondaryLight;
  Color get cHint     => isDark ? AppColors.textHintDark       : AppColors.textHintLight;
  Color get cBlue3    => isDark ? AppColors.blue3Dark    : AppColors.blue3Light;
  Color get cGreen3   => isDark ? AppColors.green3Dark   : AppColors.green3Light;
  Color get cSuccessBg => isDark ? AppColors.successDark : AppColors.successLight;
  Color get cDangerBg  => isDark ? AppColors.dangerDark  : AppColors.dangerLight;
  Color get cWarningBg => isDark ? AppColors.warningDark : AppColors.warningLight;
  Color get cPenaltyBg => isDark ? AppColors.penaltyDark : AppColors.penaltyLight;
}
