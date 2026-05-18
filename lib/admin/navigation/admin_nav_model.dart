// lib/admin/navigation/admin_nav_model.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Navigation Model
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// NAV ITEM MODEL
// ─────────────────────────────────────────────
class AdminNavItem {
  final String     id;
  final String     label;
  final IconData   icon;
  final IconData   iconActive;
  final String     route;
  final Color?     accentColor;
  final String?    badge;
  final bool       isDividerBefore;

  const AdminNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.iconActive,
    required this.route,
    this.accentColor,
    this.badge,
    this.isDividerBefore = false,
  });
}

// ─────────────────────────────────────────────
// NAV ITEMS DEFINITION
// ─────────────────────────────────────────────
const kAdminNavItems = [
  AdminNavItem(
    id:          'dashboard',
    label:       'Dashboard',
    icon:        Icons.dashboard_outlined,
    iconActive:  Icons.dashboard_rounded,
    route:       '/admin/dashboard',
    accentColor: Color(0xFF9D55FF),
  ),
  AdminNavItem(
    id:          'deposits',
    label:       'Deposits',
    icon:        Icons.add_circle_outline_rounded,
    iconActive:  Icons.add_circle_rounded,
    route:       '/admin/deposits',
    accentColor: Color(0xFF44FF99),
    isDividerBefore: true,
  ),
  AdminNavItem(
    id:          'withdrawals',
    label:       'Withdrawals',
    icon:        Icons.remove_circle_outline_rounded,
    iconActive:  Icons.remove_circle_rounded,
    route:       '/admin/withdrawals',
    accentColor: Color(0xFFFF4466),
  ),
  AdminNavItem(
    id:          'tournaments',
    label:       'Tournaments',
    icon:        Icons.emoji_events_outlined,
    iconActive:  Icons.emoji_events_rounded,
    route:       '/admin/tournaments',
    accentColor: Color(0xFFFFCC44),
    isDividerBefore: true,
  ),
  AdminNavItem(
    id:          'users',
    label:       'Users',
    icon:        Icons.people_outline_rounded,
    iconActive:  Icons.people_rounded,
    route:       '/admin/users',
    accentColor: Color(0xFF44CCFF),
  ),
  AdminNavItem(
    id:          'logs',
    label:       'Logs',
    icon:        Icons.receipt_long_outlined,
    iconActive:  Icons.receipt_long_rounded,
    route:       '/admin/logs',
    accentColor: Color(0xFFFF9944),
    isDividerBefore: true,
  ),
  AdminNavItem(
    id:          'settings',
    label:       'Settings',
    icon:        Icons.settings_outlined,
    iconActive:  Icons.settings_rounded,
    route:       '/admin/settings',
    accentColor: Color(0xFF9B8DC0),
  ),
];

// ─────────────────────────────────────────────
// NAV STATE
// ─────────────────────────────────────────────
class AdminNavState extends ChangeNotifier {
  String _activeId = 'dashboard';

  String get activeId => _activeId;

  AdminNavItem get activeItem =>
      kAdminNavItems.firstWhere((item) => item.id == _activeId);

  void setActive(String id) {
    if (_activeId != id) {
      _activeId = id;
      notifyListeners();
    }
  }
}