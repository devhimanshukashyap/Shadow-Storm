// lib/admin/auth/admin_auth_guard.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Auth Guard
// Routes based on admin auth state
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../auth/admin_auth_service.dart';
import '../pages/admin_login_page.dart';
import '../pages/admin_access_denied_page.dart';
import '../layout/admin_shell.dart';

class AdminAuthGuard extends StatelessWidget {
  const AdminAuthGuard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminAuthResult>(
      stream: AdminAuthService.instance.adminAuthStream,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData) {
          return const _AdminLoadingScreen();
        }

        final result = snapshot.data!;

        switch (result.status) {
          case AdminAuthStatus.authenticated:
            return AdminShell(adminUser: result.user!);

          case AdminAuthStatus.notAdmin:
            return AdminAccessDeniedPage(
              user: result.user,
              reason: result.errorMessage,
            );

          case AdminAuthStatus.error:
            return AdminAccessDeniedPage(
              user: result.user,
              reason: result.errorMessage ?? 'An unexpected error occurred.',
              isError: true,
            );

          case AdminAuthStatus.unauthenticated:
          case AdminAuthStatus.loading:
            return const AdminLoginPage();
        }
      },
    );
  }
}

// ─────────────────────────────────────────────
// ADMIN LOADING SCREEN
// ─────────────────────────────────────────────
class _AdminLoadingScreen extends StatefulWidget {
  const _AdminLoadingScreen();

  @override
  State<_AdminLoadingScreen> createState() => _AdminLoadingScreenState();
}

class _AdminLoadingScreenState extends State<_AdminLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06040E),
      body: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing logo mark
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF130F22),
                  border: Border.all(
                    color: Color.fromRGBO(
                      157, 85, 255,
                      0.4 + 0.4 * _pulse.value,
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(
                        157, 85, 255,
                        0.2 + 0.2 * _pulse.value,
                      ),
                      blurRadius: 24 + 12 * _pulse.value,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Color(0xFF9D55FF),
                    size: 36,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Title
              const Text(
                'SHADOW STORM',
                style: TextStyle(
                  color: Color(0xFFEDE0FF),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'ADMIN CONTROL CENTER',
                style: TextStyle(
                  color: Color.fromRGBO(
                    157, 85, 255,
                    0.6 + 0.4 * _pulse.value,
                  ),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 36),

              // Loading indicator
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Color.fromRGBO(
                    157, 85, 255,
                    0.7 + 0.3 * _pulse.value,
                  ),
                  strokeWidth: 2,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Verifying admin access...',
                style: TextStyle(
                  color: const Color(0xFF9B8DC0),
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}