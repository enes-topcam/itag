import 'package:flutter/material.dart';

/// TPCM Find tasarım sistemi renkleri (tasarım dokümanı §3).
class AppColors {
  static const bg = Color(0xFF0C0E16); // Ana zemin
  static const card = Color(0xFF191C29); // Kart zemin
  static const raised = Color(0xFF232638); // Yükseltilmiş yüzey
  static const accent = Color(0xFF8067F7); // Mor vurgu
  static const accentLight = Color(0xFFA798FF); // Açık mor
  static const text = Color(0xFFF7F7FA); // Ana yazı
  static const text2 = Color(0xFF9DA4B8); // İkincil yazı
  static const ok = Color(0xFF33CE91); // Bağlı
  static const warn = Color(0xFFF0B75E); // Bağlanıyor / düşük sinyal
  static const err = Color(0xFFF36B78); // Hata / silme
  static const line = Color(0xFF2C3142); // Çizgi
}

class AppDims {
  static const pad = 20.0; // standart kenar boşluğu
  static const gap = 12.0; // kart arası
  static const cardRadius = 20.0;
  static const buttonRadius = 18.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentLight,
    onSecondary: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.raised,
    error: AppColors.err,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );
  final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDims.buttonRadius));
  const buttonSize = Size.fromHeight(56);
  const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    dividerColor: AppColors.line,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text),
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
      titleMedium: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyLarge: TextStyle(fontSize: 16, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 13, color: AppColors.text2),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDims.cardRadius)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.raised,
        disabledForegroundColor: AppColors.text2,
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        minimumSize: buttonSize,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accentLight),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: const TextStyle(color: AppColors.text2),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accentLight),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Colors.white : AppColors.text2),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accent : AppColors.raised),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accent.withValues(alpha: 0.22),
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? AppColors.accentLight
              : AppColors.text2)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? AppColors.accentLight
              : AppColors.text2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.raised,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.accent),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.accent.withValues(alpha: 0.25),
      side: const BorderSide(color: AppColors.line),
      labelStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
