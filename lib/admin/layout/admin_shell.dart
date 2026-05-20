// lib/admin/layout/admin_shell.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Shell
// Phase 5: Added 'logs', 'settings', 'tools' routes
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../navigation/admin_nav_model.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/admin_header.dart';
import '../layout/admin_responsive.dart';
import '../pages/admin_pages.dart';
import '../theme/admin_theme.dart';

class AdminShell extends StatefulWidget {
  final User adminUser;
  const AdminShell({super.key, required this.adminUser});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell>
    with SingleTickerProviderStateMixin {
  final AdminNavState _navState = AdminNavState();

  bool _sidebarCollapsed    = false;
  bool _mobileSidebarOpen   = false;

  late AnimationController _pageCtrl;
  late Animation<double>   _pageFade;

  @override
  void initState() {
    super.initState();
    _pageCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300),
    )..forward();
    _pageFade = CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOutCubic);
    _navState.addListener(_onNavChanged);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _navState.removeListener(_onNavChanged);
    _navState.dispose();
    super.dispose();
  }

  void _onNavChanged() {
    _pageCtrl.reset();
    _pageCtrl.forward();
    if (_mobileSidebarOpen) setState(() => _mobileSidebarOpen = false);
  }

  void _toggleSidebar()       => setState(() => _sidebarCollapsed   = !_sidebarCollapsed);
  void _toggleMobileSidebar() => setState(() => _mobileSidebarOpen  = !_mobileSidebarOpen);

  @override
  Widget build(BuildContext context) {
    return AdminResponsive.isDesktop(context)
        ? _buildDesktopLayout()
        : _buildMobileLayout();
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Row(
        children: [
          AdminSidebar(
            navState:         _navState,
            adminUser:        widget.adminUser,
            isCollapsed:      _sidebarCollapsed,
            onToggleCollapse: _toggleSidebar,
          ),
          Expanded(
            child: Column(
              children: [
                AdminHeader(
                  navState:         _navState,
                  adminUser:        widget.adminUser,
                  sidebarCollapsed: _sidebarCollapsed,
                  onToggleSidebar:  _toggleSidebar,
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _pageFade,
                    child: ListenableBuilder(
                      listenable: _navState,
                      builder: (_, _) => _buildPage(_navState.activeId),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              AdminHeader(
                navState:         _navState,
                adminUser:        widget.adminUser,
                sidebarCollapsed: true,
                onToggleSidebar:  _toggleMobileSidebar,
              ),
              Expanded(
                child: FadeTransition(
                  opacity: _pageFade,
                  child: ListenableBuilder(
                    listenable: _navState,
                    builder: (_, _) => _buildPage(_navState.activeId),
                  ),
                ),
              ),
            ],
          ),
          if (_mobileSidebarOpen) ...[
            GestureDetector(
              onTap: _toggleMobileSidebar,
              child: Container(color: Colors.black.withOpacity(0.6)),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve:    Curves.easeInOutCubic,
              left: 0, top: 0, bottom: 0,
              child: AdminSidebar(
                navState:         _navState,
                adminUser:        widget.adminUser,
                isCollapsed:      false,
                onToggleCollapse: _toggleMobileSidebar,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // PAGE ROUTER — Phase 5 complete
  // ──────────────────────────────────────────
  Widget _buildPage(String id) {
    return switch (id) {
      'dashboard'   => const AdminDashboardPage(),
      'deposits'    => const AdminDepositsPage(),
      'withdrawals' => const AdminWithdrawalsPage(),
      'tournaments' => const AdminTournamentsPage(),
      'users'       => const AdminUsersPage(),
      'logs'        => const AdminLogsPage(),        // Phase 5 ✓
      'settings'    => const AdminSettingsPage(),    // Phase 5 ✓
      'tools'       => const AdminSystemToolsPage(), // Phase 5 ✓
      _             => const AdminDashboardPage(),
    };
  }
}