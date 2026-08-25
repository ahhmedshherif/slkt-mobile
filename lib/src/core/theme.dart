import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const burgundy = Color(0xFF541627);
  static const oxblood = Color(0xFF260A11);
  static const charcoal = Color(0xFF181416);
  static const ivory = Color(0xFFF4EFE8);
  static const gold = Color(0xFFB89A6A);

  // Compatibility aliases keep feature screens consistent while the complete
  // interface inherits the new TKTS brand system from a single source.
  static const yellow = gold;
  static const lavender = gold;
  static const black = charcoal;
  static const coral = burgundy;
  static const coralDark = oxblood;
  static const ink = charcoal;
  static const navy = oxblood;
  static const canvas = ivory;
  static const paper = ivory;
  static const muted = Color(0xFF6E6265);
  static const line = Color(0x55B89A6A);
  static const success = Color(0xFF087F5B);
}

abstract final class AppSystemUi {
  static const light = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );

  static const dark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  final body = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
  return base.copyWith(
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.coral,
      primary: AppColors.coral,
      secondary: AppColors.navy,
      surface: AppColors.paper,
    ),
    textTheme: body.copyWith(
      displaySmall: GoogleFonts.epilogue(
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineLarge: GoogleFonts.epilogue(
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineMedium: GoogleFonts.epilogue(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleLarge: GoogleFonts.epilogue(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.paper,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.gold.withValues(alpha: .10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.coral, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.ivory,
        disabledBackgroundColor: AppColors.black.withValues(alpha: .35),
        disabledForegroundColor: AppColors.ivory.withValues(alpha: .65),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      indicatorColor: AppColors.yellow,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SlktPageTransitionsBuilder(),
        TargetPlatform.iOS: SlktPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: AppSystemUi.dark,
    ),
  );
}

class SlktPageTransitionsBuilder extends PageTransitionsBuilder {
  const SlktPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == Navigator.defaultRouteName) return child;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) return child;

    final curved = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.05, 0.7, 0.1, 1),
      reverseCurve: const Cubic(0.3, 0, 1, 1),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.055, .018),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
