// lib/admin/pages/admin_login_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Login Page
// Premium esports control center sign-in
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../auth/admin_auth_service.dart';
import '../theme/admin_theme.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage>
    with TickerProviderStateMixin {
  late AnimationController _introCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;

  late Animation<double> _fadeIn;
  late Animation<double> _slideIn;
  late Animation<double> _pulse;
  late Animation<double> _scan;

  bool    _isLoading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();

    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _fadeIn = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideIn = Tween<double>(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _introCtrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _scan  = CurvedAnimation(parent: _scanCtrl,  curve: Curves.linear);
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    final result = await AdminAuthService.instance.signInWithGoogle();

    if (!mounted) return;

    if (result.isAdmin) {
      // Auth guard stream handles navigation automatically
      return;
    } else if (result.isNotAdmin) {
      setState(() {
        _isLoading = false;
        _errorMsg  = 'Access denied. This account does not have admin privileges.';
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMsg  = result.errorMessage ?? 'Sign-in failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Stack(
        children: [
          // Background grid
          Positioned.fill(
            child: CustomPaint(painter: _AdminGridPainter()),
          ),

          // Ambient glow
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Positioned(
              top: -size.height * 0.2,
              left: -size.width * 0.2,
              child: Container(
                width: size.width * 1.4,
                height: size.width * 1.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AdminColors.purple.withValues(
                          alpha: 0.08 + 0.06 * _pulse.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Scan line
          AnimatedBuilder(
            animation: _scan,
            builder: (_, _) => Positioned(
              top: size.height * _scan.value,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AdminColors.purple.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Main content
          Center(
            child: FadeTransition(
              opacity: _fadeIn,
              child: AnimatedBuilder(
                animation: _slideIn,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _slideIn.value),
                  child: child,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 40),
                        _buildLoginCard(),
                        const SizedBox(height: 24),
                        _buildSecurityNote(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Column(
        children: [
          // Admin emblem
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AdminColors.surfaceCard,
              border: Border.all(
                color: AdminColors.purple.withValues(
                    alpha: 0.4 + 0.3 * _pulse.value),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AdminColors.purple.withValues(
                      alpha: 0.15 + 0.10 * _pulse.value),
                  blurRadius: 28 + 12 * _pulse.value,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.admin_panel_settings_rounded,
                color: AdminColors.purple,
                size: 40,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Title
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AdminColors.purpleLight, AdminColors.purple],
            ).createShader(bounds),
            child: const Text(
              'SHADOW STORM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
              ),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'ADMIN CONTROL CENTER',
            style: TextStyle(
              color: AdminColors.purple.withValues(
                  alpha: 0.6 + 0.3 * _pulse.value),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          color: AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AdminColors.borderBright),
          boxShadow: [
            BoxShadow(
              color: AdminColors.purple.withValues(
                  alpha: 0.08 + 0.04 * _pulse.value),
              blurRadius: 40,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // Accent bar
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AdminColors.purpleDim,
                      AdminColors.purple,
                      AdminColors.purpleLight,
                      AdminColors.purple,
                      AdminColors.purpleDim,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AdminColors.purple,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AdminColors.purpleGlow,
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'ADMIN AUTHENTICATION',
                          style: AdminTextStyles.labelLarge.copyWith(
                            color: AdminColors.purpleLight,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Control Center Access',
                      style: AdminTextStyles.titleLarge.copyWith(fontSize: 22),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Authorized personnel only. All access attempts are logged and monitored.',
                      style: AdminTextStyles.bodyMedium,
                    ),

                    const SizedBox(height: 28),

                    // Divider
                    Row(
                      children: [
                        Expanded(child: Container(
                          height: 1,
                          color: AdminColors.border,
                        )),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'SIGN IN WITH',
                            style: AdminTextStyles.labelSmall,
                          ),
                        ),
                        Expanded(child: Container(
                          height: 1,
                          color: AdminColors.border,
                        )),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Google sign-in button
                    _AdminSignInButton(
                      isLoading: _isLoading,
                      pulse: _pulse,
                      onTap: _handleSignIn,
                    ),

                    // Error message
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AdminColors.danger.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AdminColors.danger,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMsg!,
                                style: AdminTextStyles.bodySmall.copyWith(
                                  color: AdminColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 12,
          color: AdminColors.textMuted.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          'Secured with OAuth 2.0  ·  Access logged  ·  Admin only',
          style: AdminTextStyles.labelSmall.copyWith(
            color: AdminColors.textMuted.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SIGN IN BUTTON
// ─────────────────────────────────────────────
class _AdminSignInButton extends StatefulWidget {
  final bool             isLoading;
  final Animation<double> pulse;
  final VoidCallback     onTap;

  const _AdminSignInButton({
    required this.isLoading,
    required this.pulse,
    required this.onTap,
  });

  @override
  State<_AdminSignInButton> createState() => _AdminSignInButtonState();
}

class _AdminSignInButtonState extends State<_AdminSignInButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverCtrl;
  late Animation<double>   _hoverScale;
  final bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _hoverScale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) { if (!widget.isLoading) _hoverCtrl.forward(); },
      onTapUp:     (_) { _hoverCtrl.reverse(); widget.onTap(); },
      onTapCancel: () => _hoverCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _hoverScale,
        builder: (_, child) => Transform.scale(
          scale: _hoverScale.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            color: AdminColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _pressed
                  ? AdminColors.purple.withValues(alpha: 0.7)
                  : AdminColors.borderBright,
              width: _pressed ? 1.5 : 1,
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: AdminColors.purple.withValues(alpha: 0.25),
                      blurRadius: 20,
                    ),
                  ]
                : [],
          ),
          child: widget.isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: AdminColors.purple,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Verifying admin access...',
                      style: AdminTextStyles.titleSmall.copyWith(
                        color: AdminColors.purpleLight,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Google G icon
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CustomPaint(painter: _GoogleGPainter()),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Continue with Google',
                      style: AdminTextStyles.titleSmall.copyWith(
                        color: AdminColors.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAINTERS
// ─────────────────────────────────────────────
class _AdminGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AdminColors.purple.withValues(alpha: 0.025)
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
  bool shouldRepaint(_AdminGridPainter _) => false;
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFFEA4335),
      const Color(0xFFFBBC05),
      const Color(0xFF34A853),
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        (i * math.pi / 2) - math.pi / 4,
        math.pi / 2,
        false,
        Paint()
          ..color       = colors[i]
          ..strokeWidth = 3.2
          ..style       = PaintingStyle.stroke,
      );
    }

    canvas.drawCircle(
      Offset(cx, cy), r * 0.55,
      Paint()..color = AdminColors.surfaceElevated,
    );

    canvas.drawRect(
      Rect.fromLTWH(cx, cy - 2.2, r * 0.85, 4.4),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter _) => false;
}