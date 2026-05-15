import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

// ─────────────────────────────────────────────
//  Entry point (remove if integrating into project)
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: SSTheme.background,
    ),
  );
  runApp(const ShadowStormApp());
}

class ShadowStormApp extends StatelessWidget {
  const ShadowStormApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shadow Storm',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SSTheme.background,
      colorScheme: ColorScheme.dark(
        primary: SSTheme.neonPurple,
        secondary: SSTheme.neonPurpleLight,
        surface: SSTheme.surface,
        onPrimary: Colors.white,
        onSurface: SSTheme.textPrimary,
      ),
      fontFamily: 'monospace',
    );
  }
}

// ─────────────────────────────────────────────
//  Design Tokens
// ─────────────────────────────────────────────
abstract class SSTheme {
  static const Color background     = Color(0xFF0D0D0D);
  static const Color surface        = Color(0xFF141420);
  static const Color surfaceElevated= Color(0xFF1C1C2E);
  static const Color border         = Color(0xFF2A2A40);
  static const Color neonPurple     = Color(0xFF8B5CF6);
  static const Color neonPurpleLight= Color(0xFFAB80FF);
  static const Color neonPurpleDim  = Color(0xFF5B21B6);
  static const Color neonPurpleGlow = Color(0x408B5CF6);
  static const Color textPrimary    = Color(0xFFF1F1FF);
  static const Color textSecondary  = Color(0xFF9CA3AF);
  static const Color textMuted      = Color(0xFF4B5563);
  static const Color googleBlue     = Color(0xFF4285F4);
  static const Color googleRed      = Color(0xFFEA4335);
  static const Color googleYellow   = Color(0xFFFBBC05);
  static const Color googleGreen    = Color(0xFF34A853);

  static const double radiusLg      = 20;
  static const double radiusMd      = 14;
  static const double radiusSm      = 10;

  static List<BoxShadow> glowShadow({double intensity = 1.0}) => [
    BoxShadow(
      color: neonPurple.withValues(alpha: 0.35 * intensity),
      blurRadius: 24 * intensity,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: neonPurple.withValues(alpha: 0.15 * intensity),
      blurRadius: 48 * intensity,
      spreadRadius: 0,
    ),
  ];
}

// ─────────────────────────────────────────────
//  Login Screen (Root)
// ─────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ─────────────────
  late final AnimationController _introCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _floatCtrl;

  // ── Intro animations ──────────────────────
  late final Animation<double> _bgFade;
  late final Animation<double> _logoSlide;
  late final Animation<double> _logoFade;
  late final Animation<double> _taglineSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _cardSlide;
  late final Animation<double> _cardFade;

  // ── Ambient animations ────────────────────
  late final Animation<double> _glowPulse;
  late final Animation<double> _floatY;

  // ── State ─────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _introCtrl.forward();
  }

  void _initAnimations() {
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _bgFade = _curved(0.0, 0.4, Curves.easeOut);
    _logoSlide = _tween(40.0, 0.0, 0.0, 0.55, Curves.easeOut);
    _logoFade = _curved(0.0, 0.55, Curves.easeOut);
    _taglineSlide = _tween(24.0, 0.0, 0.25, 0.65, Curves.easeOut);
    _taglineFade = _curved(0.25, 0.65, Curves.easeOut);
    _cardSlide = _tween(50.0, 0.0, 0.45, 1.0, Curves.easeOut);
    _cardFade = _curved(0.45, 1.0, Curves.easeOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _glowPulse = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    _floatY = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  Animation<double> _curved(double start, double end, Curve curve) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _introCtrl,
          curve: Interval(start, end, curve: curve),
        ),
      );

  Animation<double> _tween(
    double from,
    double to,
    double start,
    double end,
    Curve curve,
  ) =>
      Tween<double>(begin: from, end: to).animate(
        CurvedAnimation(
          parent: _introCtrl,
          curve: Interval(start, end, curve: curve),
        ),
      );

  @override
  void dispose() {
    _introCtrl.dispose();
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await AuthService().signInWithGoogle();
      if (!mounted) return;

      if (user != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign-in cancelled.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign-in failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: SSTheme.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _introCtrl,
          _pulseCtrl,
          _floatCtrl,
        ]),
        builder: (context, _) => Stack(
          children: [
            // ── Ambient background ──────────
            _AmbientBackground(
              fade: _bgFade.value,
              glowPulse: _glowPulse.value,
              screenSize: size,
            ),

            // ── Scan-line texture ───────────
            const _ScanLineOverlay(),

            // ── Scrollable body ─────────────
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: size.height -
                        MediaQuery.of(context).padding.top -
                        bottomPadding,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 12),

                        // ── Top corner label
                        _TopCornerLabel(fade: _bgFade.value),

                        SizedBox(height: size.height * 0.06),

                        // ── Floating logo section
                        Transform.translate(
                          offset: Offset(0, _floatY.value),
                          child: _LogoSection(
                            logoFade: _logoFade.value,
                            logoSlide: _logoSlide.value,
                            taglineFade: _taglineFade.value,
                            taglineSlide: _taglineSlide.value,
                            glowPulse: _glowPulse.value,
                          ),
                        ),

                        SizedBox(height: size.height * 0.06),

                        // ── Login card
                        _LoginCard(
                          cardFade: _cardFade.value,
                          cardSlide: _cardSlide.value,
                          isLoading: _isLoading,
                          onGoogleSignIn: _handleGoogleSignIn,
                          glowPulse: _glowPulse.value,
                          errorMessage: _errorMessage,
                        ),

                        SizedBox(height: size.height * 0.04),

                        // ── Footer
                        _Footer(fade: _cardFade.value),

                        SizedBox(height: bottomPadding + 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Ambient Background
// ─────────────────────────────────────────────
class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({
    required this.fade,
    required this.glowPulse,
    required this.screenSize,
  });

  final double fade, glowPulse;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: fade,
      child: Stack(
        children: [
          // Top radial
          Positioned(
            top: -screenSize.height * 0.15,
            left: -screenSize.width * 0.2,
            child: Container(
              width: screenSize.width * 1.4,
              height: screenSize.width * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SSTheme.neonPurple.withValues(alpha: 0.14 * glowPulse),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom radial
          Positioned(
            bottom: -screenSize.height * 0.1,
            right: -screenSize.width * 0.3,
            child: Container(
              width: screenSize.width * 1.2,
              height: screenSize.width * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SSTheme.neonPurpleDim.withValues(alpha: 0.10 * glowPulse),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Subtle grid
          CustomPaint(
            size: screenSize,
            painter: _GridPainter(),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SSTheme.neonPurple.withValues(alpha: 0.025)
      ..strokeWidth = 0.6;

    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}

// ─────────────────────────────────────────────
//  Scan-line Overlay
// ─────────────────────────────────────────────
class _ScanLineOverlay extends StatelessWidget {
  const _ScanLineOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _ScanLinePainter(),
      ),
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanLinePainter _) => false;
}

// ─────────────────────────────────────────────
//  Top Corner Label
// ─────────────────────────────────────────────
class _TopCornerLabel extends StatelessWidget {
  const _TopCornerLabel({required this.fade});
  final double fade;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: fade,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: SSTheme.neonPurple,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'SS_v3.0.1',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: SSTheme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: SSTheme.border, width: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'SEASON III',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 2.5,
                color: SSTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Logo Section
// ─────────────────────────────────────────────
class _LogoSection extends StatelessWidget {
  const _LogoSection({
    required this.logoFade,
    required this.logoSlide,
    required this.taglineFade,
    required this.taglineSlide,
    required this.glowPulse,
  });

  final double logoFade, logoSlide, taglineFade, taglineSlide, glowPulse;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Storm emblem ─────────────────────
        Opacity(
          opacity: logoFade,
          child: Transform.translate(
            offset: Offset(0, -logoSlide),
            child: _StormEmblem(glowPulse: glowPulse),
          ),
        ),

        const SizedBox(height: 26),

        // ── Title ────────────────────────────
        Opacity(
          opacity: logoFade,
          child: Transform.translate(
            offset: Offset(0, -logoSlide * 0.6),
            child: _TitleText(glowPulse: glowPulse),
          ),
        ),

        const SizedBox(height: 14),

        // ── Tagline ──────────────────────────
        Opacity(
          opacity: taglineFade,
          child: Transform.translate(
            offset: Offset(0, taglineSlide),
            child: const _TaglineRow(),
          ),
        ),
      ],
    );
  }
}

class _StormEmblem extends StatelessWidget {
  const _StormEmblem({required this.glowPulse});
  final double glowPulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SSTheme.surface,
        border: Border.all(
          color: SSTheme.neonPurple.withValues(alpha: 0.5 + 0.3 * glowPulse),
          width: 1.5,
        ),
        boxShadow: SSTheme.glowShadow(intensity: glowPulse),
      ),
      child: CustomPaint(painter: _EmblemPainter(glowPulse: glowPulse)),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter({required this.glowPulse});
  final double glowPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Bolt glow
    canvas.drawCircle(
      Offset(cx, cy),
      20,
      Paint()
        ..color = SSTheme.neonPurple.withValues(alpha: 0.18 * glowPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Lightning bolt
    final bolt = Path()
      ..moveTo(cx + 8,  cy - 22)
      ..lineTo(cx - 10, cy - 2)
      ..lineTo(cx + 3,  cy - 2)
      ..lineTo(cx - 8,  cy + 22)
      ..lineTo(cx + 10, cy + 2)
      ..lineTo(cx - 3,  cy + 2)
      ..close();

    canvas.drawPath(
      bolt,
      Paint()
        ..color = SSTheme.neonPurple.withValues(alpha: 0.45 * glowPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawPath(
      bolt,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SSTheme.neonPurpleLight, SSTheme.neonPurple],
        ).createShader(
          Rect.fromCenter(center: Offset(cx, cy), width: 30, height: 50),
        ),
    );

    // Tick ring
    final tickPaint = Paint()
      ..color = SSTheme.neonPurple.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 12; i++) {
      final a = i * 30 * math.pi / 180;
      final r1 = i % 3 == 0 ? 36.0 : 38.0;
      canvas.drawLine(
        Offset(cx + r1 * math.cos(a), cy + r1 * math.sin(a)),
        Offset(cx + 41 * math.cos(a), cy + 41 * math.sin(a)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => old.glowPulse != glowPulse;
}

class _TitleText extends StatelessWidget {
  const _TitleText({required this.glowPulse});
  final double glowPulse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          'SHADOW STORM',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            foreground: Paint()
              ..color = SSTheme.neonPurple.withValues(alpha: 0.45 * glowPulse)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              SSTheme.neonPurpleLight,
              SSTheme.neonPurple,
              Color(0xFFE0D4FF),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: const Text(
            'SHADOW STORM',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _TaglineRow extends StatelessWidget {
  const _TaglineRow();

  @override
  Widget build(BuildContext context) {
    const words = ['Compete', 'Win', 'Dominate'];
    const divider = '  ·  ';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: words.asMap().entries.map((entry) {
        final last = entry.key == words.length - 1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.5,
                color: entry.key == 2
                    ? SSTheme.neonPurpleLight
                    : SSTheme.textSecondary,
              ),
            ),
            if (!last)
              Text(
                divider,
                style: TextStyle(
                  fontSize: 13,
                  color: SSTheme.textMuted,
                  letterSpacing: 0,
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
//  Login Card
// ─────────────────────────────────────────────
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.cardFade,
    required this.cardSlide,
    required this.isLoading,
    required this.onGoogleSignIn,
    required this.glowPulse,
    this.errorMessage,             // ← ADD THIS
  });

  final double cardFade, cardSlide, glowPulse;
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final String? errorMessage;      // ← ADD THIS

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: cardFade,
      child: Transform.translate(
        offset: Offset(0, cardSlide),
        child: Container(
          decoration: BoxDecoration(
            color: SSTheme.surface,
            borderRadius: BorderRadius.circular(SSTheme.radiusLg),
            border: Border.all(
              color: SSTheme.border,
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: SSTheme.neonPurple.withValues(alpha: 0.08 * glowPulse),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SSTheme.radiusLg),
            child: Column(
              children: [
                _CardAccentBar(glowPulse: glowPulse),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardHeader(),
                      const SizedBox(height: 28),
                      _Divider(),
                      const SizedBox(height: 28),
                      _GoogleSignInButton(
                        isLoading: isLoading,
                        onPressed: onGoogleSignIn,
                        glowPulse: glowPulse,
                      ),
                      const SizedBox(height: 20),
                      _SecurityNote(),

                      // ── Error message block ──
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 13,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  letterSpacing: 0.3,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardAccentBar extends StatelessWidget {
  const _CardAccentBar({required this.glowPulse});
  final double glowPulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            SSTheme.neonPurpleDim.withValues(alpha: 0.7),
            SSTheme.neonPurple,
            SSTheme.neonPurpleLight,
            SSTheme.neonPurple,
            SSTheme.neonPurpleDim.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: SSTheme.neonPurple.withValues(alpha: 0.5 * glowPulse),
            blurRadius: 12,
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: SSTheme.neonPurple,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: SSTheme.neonPurple.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'PLAYER AUTH',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: SSTheme.neonPurpleLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter the Arena',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: SSTheme.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to join tournaments, track\nyour stats, and climb the leaderboard.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.55,
            color: SSTheme.textSecondary.withValues(alpha: 0.85),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(height: 0.8, color: SSTheme.border),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'CONTINUE WITH',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 3,
              color: SSTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(height: 0.8, color: SSTheme.border),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Google Sign-In Button
// ─────────────────────────────────────────────
class _GoogleSignInButton extends StatefulWidget {
  const _GoogleSignInButton({
    required this.isLoading,
    required this.onPressed,
    required this.glowPulse,
  });

  final bool isLoading;
  final VoidCallback onPressed;
  final double glowPulse;

  @override
  State<_GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<_GoogleSignInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;
  late final Animation<double> _hoverScale;
  late final Animation<double> _hoverGlow;

  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _hoverScale = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOut),
    );
    _hoverGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
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
    return AnimatedBuilder(
      animation: _hoverCtrl,
      builder: (_, _) => GestureDetector(
        onTapDown: (_) {
          if (!widget.isLoading) {
            setState(() => _isHovered = true);
            _hoverCtrl.forward();
          }
        },
        onTapUp: (_) {
          setState(() => _isHovered = false);
          _hoverCtrl.reverse();
          widget.onPressed();
        },
        onTapCancel: () {
          setState(() => _isHovered = false);
          _hoverCtrl.reverse();
        },
        child: Transform.scale(
          scale: _hoverScale.value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: SSTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(SSTheme.radiusMd),
              border: Border.all(
                color: _isHovered
                    ? SSTheme.neonPurple.withValues(alpha: 0.8)
                    : SSTheme.border,
                width: _isHovered ? 1.2 : 0.8,
              ),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: SSTheme.neonPurple
                        .withValues(alpha: 0.3 * _hoverGlow.value),
                    blurRadius: 20,
                    spreadRadius: 0,
                  ),
              ],
            ),
            child: widget.isLoading
                ? const _LoadingIndicator()
                : const _GoogleButtonContent(),
          ),
        ),
      ),
    );
  }
}

class _GoogleButtonContent extends StatelessWidget {
  const _GoogleButtonContent();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _GoogleLogo(),
        const SizedBox(width: 14),
        const Text(
          'Continue with Google',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: SSTheme.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // G circle segments (simplified Google G)
    final colors = [
      SSTheme.googleBlue,
      SSTheme.googleRed,
      SSTheme.googleYellow,
      SSTheme.googleGreen,
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        (i * math.pi / 2) - math.pi / 4,
        math.pi / 2,
        false,
        Paint()
          ..color = colors[i]
          ..strokeWidth = 3.2
          ..style = PaintingStyle.stroke,
      );
    }

    // White center
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.55,
      Paint()..color = SSTheme.surfaceElevated,
    );

    // G bar (right extension)
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - 2.2, r * 0.85, 4.4),
      Paint()..color = SSTheme.googleBlue,
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter _) => false;
}

class _LoadingIndicator extends StatefulWidget {
  const _LoadingIndicator();

  @override
  State<_LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<_LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: _SpinnerPainter(progress: _ctrl.value),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'Authenticating...',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: SSTheme.neonPurpleLight,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        _DotPulse(ctrl: _ctrl),
      ],
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    // Track
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = SSTheme.neonPurple.withValues(alpha: 0.15)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2 + progress * 2 * math.pi,
      math.pi * 0.8,
      false,
      Paint()
        ..color = SSTheme.neonPurple
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.progress != progress;
}

class _DotPulse extends StatelessWidget {
  const _DotPulse({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, _) => Row(
        children: List.generate(3, (i) {
          final phase = (ctrl.value - i * 0.2).clamp(0.0, 1.0);
          final opacity =
              (math.sin(phase * math.pi * 2) * 0.5 + 0.5).clamp(0.2, 1.0);
          return Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color:
                    SSTheme.neonPurpleLight.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Security Note
// ─────────────────────────────────────────────
class _SecurityNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 12,
          color: SSTheme.textMuted.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          'Secured with OAuth 2.0 · End-to-end encrypted',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.4,
            color: SSTheme.textMuted.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Footer
// ─────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer({required this.fade});
  final double fade;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: fade,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(label: 'Privacy Policy'),
              _FooterSep(),
              _FooterLink(label: 'Terms of Service'),
              _FooterSep(),
              _FooterLink(label: 'Support'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '© 2024 Shadow Storm Esports. All rights reserved.',
            style: TextStyle(
              fontSize: 10,
              color: SSTheme.textMuted.withValues(alpha: 0.4),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: SSTheme.textMuted.withValues(alpha: 0.55),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _FooterSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 10,
          color: SSTheme.textMuted.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}