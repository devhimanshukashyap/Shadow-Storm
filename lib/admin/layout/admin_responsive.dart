// lib/admin/layout/admin_responsive.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Responsive Wrapper
// Breakpoint-based layout switching
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// BREAKPOINTS
// ─────────────────────────────────────────────
abstract class AdminBreakpoints {
  static const double mobile  = 768;
  static const double tablet  = 1024;
  static const double desktop = 1280;
  static const double wide    = 1440;
}

// ─────────────────────────────────────────────
// LAYOUT TYPE
// ─────────────────────────────────────────────
enum AdminLayoutType {
  mobile,   // < 768
  tablet,   // 768 – 1024
  desktop,  // > 1024
}

// ─────────────────────────────────────────────
// RESPONSIVE HELPER
// ─────────────────────────────────────────────
class AdminResponsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const AdminResponsive({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  static AdminLayoutType layoutOf(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < AdminBreakpoints.mobile) return AdminLayoutType.mobile;
    if (width < AdminBreakpoints.tablet) return AdminLayoutType.tablet;
    return AdminLayoutType.desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= AdminBreakpoints.tablet;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < AdminBreakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= AdminBreakpoints.mobile && w < AdminBreakpoints.tablet;
  }

  @override
  Widget build(BuildContext context) {
    final layout = layoutOf(context);
    switch (layout) {
      case AdminLayoutType.mobile:
        return mobile;
      case AdminLayoutType.tablet:
        return tablet ?? desktop;
      case AdminLayoutType.desktop:
        return desktop;
    }
  }
}

// ─────────────────────────────────────────────
// RESPONSIVE GRID
// ─────────────────────────────────────────────
class AdminGrid extends StatelessWidget {
  final List<Widget> children;
  final int          mobileColumns;
  final int          tabletColumns;
  final int          desktopColumns;
  final double       spacing;
  final double       runSpacing;

  const AdminGrid({
    super.key,
    required this.children,
    this.mobileColumns  = 1,
    this.tabletColumns  = 2,
    this.desktopColumns = 3,
    this.spacing        = 16,
    this.runSpacing     = 16,
  });

  @override
  Widget build(BuildContext context) {
    final layout  = AdminResponsive.layoutOf(context);
    final columns = switch (layout) {
      AdminLayoutType.mobile  => mobileColumns,
      AdminLayoutType.tablet  => tabletColumns,
      AdminLayoutType.desktop => desktopColumns,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}