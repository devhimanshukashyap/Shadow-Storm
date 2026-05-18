// lib/admin/theme/admin_theme.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Theme System
// Premium esports control center aesthetic
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// ADMIN COLOR PALETTE
// ─────────────────────────────────────────────
abstract class AdminColors {
  // ── Backgrounds ──────────────────────────────
  static const background       = Color(0xFF06040E);
  static const surface          = Color(0xFF0E0A1A);
  static const surfaceCard      = Color(0xFF130F22);
  static const surfaceElevated  = Color(0xFF1A1430);
  static const surfaceOverlay   = Color(0xFF211A38);

  // ── Purple brand ─────────────────────────────
  static const purple           = Color(0xFF9D55FF);
  static const purpleLight      = Color(0xFFB07EF8);
  static const purpleDim        = Color(0xFF7B3FE4);
  static const purpleDark       = Color(0xFF3C2570);
  static const purpleGlow       = Color(0x559D55FF);
  static const purpleGlowFaint  = Color(0x229D55FF);
  static const purpleGlowStrong = Color(0x889D55FF);

  // ── Accent colors ─────────────────────────────
  static const gold             = Color(0xFFFFCC44);
  static const goldGlow         = Color(0x55FFCC44);
  static const danger           = Color(0xFFFF4466);
  static const dangerGlow       = Color(0x55FF4466);
  static const success          = Color(0xFF44FF99);
  static const successGlow      = Color(0x5544FF99);
  static const warning          = Color(0xFFFF9944);
  static const warningGlow      = Color(0x55FF9944);
  static const info             = Color(0xFF44CCFF);
  static const infoGlow         = Color(0x5544CCFF);

  // ── Text ─────────────────────────────────────
  static const textPrimary      = Color(0xFFEDE0FF);
  static const textSecondary    = Color(0xFF9B8DC0);
  static const textMuted        = Color(0xFF5A4E80);
  static const textOnPurple     = Color(0xFFFFFFFF);

  // ── Borders ───────────────────────────────────
  static const border           = Color(0x337B3FE4);
  static const borderBright     = Color(0x667B3FE4);
  static const borderActive     = Color(0xFF7B3FE4);

  // ── Sidebar specific ──────────────────────────
  static const sidebarBg       = Color(0xFF08051A);
  static const sidebarActive   = Color(0xFF1E1040);
  static const sidebarHover    = Color(0xFF130C2A);

  // ── Header specific ───────────────────────────
  static const headerBg        = Color(0xFF0A071A);
}

// ─────────────────────────────────────────────
// ADMIN TEXT STYLES
// ─────────────────────────────────────────────
abstract class AdminTextStyles {
  static const _base = TextStyle(
    color: AdminColors.textPrimary,
    fontFamily: 'Roboto',
  );

  static final displayLarge = _base.copyWith(
    fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5,
  );
  static final displayMedium = _base.copyWith(
    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.3,
  );
  static final titleLarge = _base.copyWith(
    fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2,
  );
  static final titleMedium = _base.copyWith(
    fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.15,
  );
  static final titleSmall = _base.copyWith(
    fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1,
  );
  static final bodyLarge = _base.copyWith(
    fontSize: 15, fontWeight: FontWeight.w400, color: AdminColors.textSecondary,
  );
  static final bodyMedium = _base.copyWith(
    fontSize: 13, fontWeight: FontWeight.w400, color: AdminColors.textSecondary,
  );
  static final bodySmall = _base.copyWith(
    fontSize: 11, fontWeight: FontWeight.w400, color: AdminColors.textMuted,
  );
  static final labelLarge = _base.copyWith(
    fontSize: 12, fontWeight: FontWeight.w700,
    letterSpacing: 0.8, color: AdminColors.textSecondary,
  );
  static final labelMedium = _base.copyWith(
    fontSize: 10, fontWeight: FontWeight.w700,
    letterSpacing: 1.0, color: AdminColors.textMuted,
  );
  static final labelSmall = _base.copyWith(
    fontSize: 9, fontWeight: FontWeight.w700,
    letterSpacing: 1.2, color: AdminColors.textMuted,
  );
  static final monoLarge = _base.copyWith(
    fontSize: 20, fontWeight: FontWeight.w900,
    letterSpacing: 0.5, fontFamily: 'monospace',
  );
  static final sidebarItem = _base.copyWith(
    fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2,
  );
}

// ─────────────────────────────────────────────
// ADMIN SHADOWS & GLOWS
// ─────────────────────────────────────────────
abstract class AdminShadows {
  static List<BoxShadow> purpleGlow({double intensity = 1.0}) => [
    BoxShadow(
      color: AdminColors.purple.withValues(alpha: 0.25 * intensity),
      blurRadius: 20 * intensity,
    ),
    BoxShadow(
      color: AdminColors.purple.withValues(alpha: 0.10 * intensity),
      blurRadius: 40 * intensity,
    ),
  ];

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: AdminColors.purple.withValues(alpha: 0.05),
      blurRadius: 30,
    ),
  ];

  static List<BoxShadow> sidebarShadow = [
    BoxShadow(
      color: AdminColors.purple.withValues(alpha: 0.15),
      blurRadius: 30,
      offset: const Offset(4, 0),
    ),
  ];

  static List<BoxShadow> headerShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────
// ADMIN GRADIENTS
// ─────────────────────────────────────────────
abstract class AdminGradients {
  static const primaryGradient = LinearGradient(
    colors: [AdminColors.purple, AdminColors.purpleDim],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A071A), Color(0xFF06040E)],
  );

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A1430), Color(0xFF0E0A1A)],
  );

  static const sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A071A), Color(0xFF06040E)],
  );

  static const dangerGradient = LinearGradient(
    colors: [AdminColors.danger, Color(0xFFCC2244)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const successGradient = LinearGradient(
    colors: [AdminColors.success, Color(0xFF22CC66)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [AdminColors.gold, Color(0xFFCC9922)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ─────────────────────────────────────────────
// ADMIN DECORATIONS
// ─────────────────────────────────────────────
abstract class AdminDecorations {
  static BoxDecoration card({
    Color? color,
    bool glowing = false,
    double radius = 16,
  }) =>
      BoxDecoration(
        color: color ?? AdminColors.surfaceCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: glowing ? AdminColors.borderBright : AdminColors.border,
        ),
        boxShadow: glowing ? AdminShadows.purpleGlow() : AdminShadows.cardShadow,
      );

  static BoxDecoration statsCard = BoxDecoration(
    color: AdminColors.surfaceCard,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AdminColors.border),
    boxShadow: AdminShadows.cardShadow,
  );

  static BoxDecoration tableHeader = const BoxDecoration(
    color: AdminColors.surfaceElevated,
    border: Border(
      bottom: BorderSide(color: AdminColors.border),
    ),
  );

  static BoxDecoration tableRow({bool isEven = true}) => BoxDecoration(
    color: isEven ? AdminColors.surfaceCard : AdminColors.surface,
    border: const Border(
      bottom: BorderSide(color: AdminColors.border, width: 0.5),
    ),
  );

  static BoxDecoration sidebar = BoxDecoration(
    gradient: AdminGradients.sidebarGradient,
    border: const Border(
      right: BorderSide(color: AdminColors.border),
    ),
    boxShadow: AdminShadows.sidebarShadow,
  );

  static BoxDecoration header = BoxDecoration(
    color: AdminColors.headerBg,
    border: const Border(
      bottom: BorderSide(color: AdminColors.border),
    ),
    boxShadow: AdminShadows.headerShadow,
  );

  static BoxDecoration activeNavItem = BoxDecoration(
    color: AdminColors.sidebarActive,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AdminColors.border),
    boxShadow: [
      BoxShadow(
        color: AdminColors.purple.withValues(alpha: 0.2),
        blurRadius: 12,
      ),
    ],
  );

  static BoxDecoration badge({required Color color}) => BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: color.withValues(alpha: 0.4)),
  );
}

// ─────────────────────────────────────────────
// FLUTTER THEME DATA
// ─────────────────────────────────────────────
ThemeData buildAdminTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AdminColors.background,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.dark(
      primary: AdminColors.purple,
      secondary: AdminColors.purpleLight,
      surface: AdminColors.surface,
      error: AdminColors.danger,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: AdminColors.textPrimary,
      onError: Colors.white,
    ),
    dividerColor: AdminColors.border,
    dividerTheme: const DividerThemeData(
      color: AdminColors.border,
      thickness: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        AdminColors.purple.withValues(alpha: 0.4),
      ),
      trackColor: WidgetStateProperty.all(
        AdminColors.surfaceElevated,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminColors.border),
      ),
      textStyle: AdminTextStyles.bodySmall.copyWith(
        color: AdminColors.textPrimary,
      ),
    ),
  );
}