// lib/admin/pages/admin_access_denied_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Access Denied Page
// Professional access denied screen
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/admin_auth_service.dart';
import '../theme/admin_theme.dart';

class AdminAccessDeniedPage extends StatefulWidget {
  final User?   user;
  final String? reason;
  final bool    isError;

  const AdminAccessDeniedPage({
    super.key,
    this.user,
    this.reason,
    this.isError = false,
  });

  @override
  State<AdminAccessDeniedPage> createState() => _AdminAccessDeniedPageState();
}

class _AdminAccessDeniedPageState extends State<AdminAccessDeniedPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    await AdminAuthService.instance.signOut();
    // Auth stream handles navigation
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Stack(
        children: [
          // Grid background
          Positioned.fill(
            child: CustomPaint(painter: _DeniedGridPainter()),
          ),

          // Red ambient glow
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) {
              final size = MediaQuery.of(context).size;
              return Positioned(
                top: size.height * 0.2,
                left: size.width * 0.1,
                child: Container(
                  width: size.width * 0.8,
                  height: size.width * 0.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AdminColors.danger.withValues(
                            alpha: 0.06 + 0.04 * _pulse.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Content
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildShield(),
                    const SizedBox(height: 32),
                    _buildTitle(),
                    const SizedBox(height: 16),
                    _buildDetails(),
                    const SizedBox(height: 36),
                    _buildActions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShield() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AdminColors.surfaceCard,
          border: Border.all(
            color: AdminColors.danger.withValues(
                alpha: 0.4 + 0.3 * _pulse.value),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AdminColors.danger.withValues(
                  alpha: 0.15 + 0.10 * _pulse.value),
              blurRadius: 28 + 12 * _pulse.value,
            ),
          ],
        ),
        child: Center(
          child: Icon(
            widget.isError
                ? Icons.error_outline_rounded
                : Icons.shield_outlined,
            color: AdminColors.danger,
            size: 44,
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          widget.isError ? 'AUTHENTICATION ERROR' : 'ACCESS DENIED',
          style: AdminTextStyles.displayLarge.copyWith(
            color: AdminColors.danger,
            letterSpacing: 3,
            fontSize: 24,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          height: 2,
          width: 80,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AdminColors.danger,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AdminColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Reason
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AdminColors.danger,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.reason ??
                      'You do not have permission to access the admin control center.',
                  style: AdminTextStyles.bodyMedium.copyWith(
                    color: AdminColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          if (widget.user != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 1,
              color: AdminColors.danger.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),

            // Signed-in account info
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.surfaceElevated,
                    border: Border.all(color: AdminColors.border),
                  ),
                  child: widget.user!.photoURL != null
                      ? ClipOval(
                          child: Image.network(
                            widget.user!.photoURL!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.person_rounded,
                              color: AdminColors.textMuted,
                              size: 18,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: AdminColors.textMuted,
                          size: 18,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user!.displayName ?? 'Unknown User',
                        style: AdminTextStyles.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.user!.email ?? '',
                        style: AdminTextStyles.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AdminColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'NO ACCESS',
                    style: AdminTextStyles.labelSmall.copyWith(
                      color: AdminColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Instruction
          Row(
            children: [
              const Icon(
                Icons.contact_support_outlined,
                color: AdminColors.textMuted,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contact the system administrator to request admin access.',
                  style: AdminTextStyles.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        // Sign out button
        GestureDetector(
          onTap: _signingOut ? null : _signOut,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AdminColors.danger, Color(0xFFCC2244)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AdminColors.danger.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _signingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                const SizedBox(width: 10),
                Text(
                  _signingOut ? 'Signing out...' : 'Sign Out & Try Different Account',
                  style: AdminTextStyles.titleSmall.copyWith(
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Warning footer
        Text(
          '⚠ Unauthorized access attempts are logged and reported.',
          style: AdminTextStyles.labelSmall.copyWith(
            color: AdminColors.textMuted.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DeniedGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AdminColors.danger.withValues(alpha: 0.02)
      ..strokeWidth = 0.6;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DeniedGridPainter _) => false;
}