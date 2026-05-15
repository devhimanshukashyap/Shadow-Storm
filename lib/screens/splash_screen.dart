import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────
//  Entry point (remove if using inside a project)
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ShadowStormTheme.background,
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: ShadowStormTheme.background,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Theme Constants
// ─────────────────────────────────────────────
abstract class ShadowStormTheme {
  static const Color background = Color(0xFF0D0D0D);
  static const Color neonPurple = Color(0xFF8B5CF6);
  static const Color neonPurpleLight = Color(0xFFAB80FF);
  static const Color neonPurpleDark = Color(0xFF5B21B6);
  static const Color neonPurpleGlow = Color(0x558B5CF6);
  static const Color surfaceDark = Color(0xFF1A1A2E);
  static const Color textPrimary = Color(0xFFF8F8FF);
  static const Color textMuted = Color(0xFF6B7280);
}

// ─────────────────────────────────────────────
//  Splash Screen
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────
  late final AnimationController _masterController;
  late final AnimationController _pulseController;
  late final AnimationController _particleController;
  late final AnimationController _exitController;

  // ── Animations ───────────────────────────────
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _dividerWidth;
  late final Animation<double> _glowPulse;
  late final Animation<double> _exitFade;

  // ── Particle System ──────────────────────────
  final List<_Particle> _particles = [];
  final int _particleCount = 30;

  @override
  void initState() {
    super.initState();
    _initParticles();
    _initAnimations();
    _scheduleNavigation();
  }

  void _initParticles() {
    final rng = math.Random();
    for (int i = 0; i < _particleCount; i++) {
      _particles.add(_Particle.random(rng));
    }
  }

  void _initAnimations() {
    // Master intro sequence (0–2 s)
    _masterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _logoSlide = Tween<double>(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
      ),
    );

    _dividerWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _masterController,
        curve: const Interval(0.3, 0.65, curve: Curves.easeOut),
      ),
    );

    // Pulse glow loop
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _glowPulse = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Particle drift loop
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Exit fade
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    _masterController.forward();
  }

  void _scheduleNavigation() {
    Future.delayed(const Duration(milliseconds: 3000), () async {
      if (!mounted) return;
      await _exitController.forward();
      if (!mounted) return;
      final User? user = AuthService().currentUser;
      Navigator.of(context).pushReplacement(
        _FadeRoute(page: user != null ? const HomeScreen() : const LoginScreen()),
      );
    });
  }

  @override
  void dispose() {
    _masterController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: ShadowStormTheme.background,
      body: FadeTransition(
        opacity: _exitFade,
        child: Stack(
          children: [
            // Layer 1 — Radial background gradient
            _BackgroundGradient(glowPulse: _glowPulse),

            // Layer 2 — Floating particles
            _ParticleField(
              particles: _particles,
              controller: _particleController,
              size: size,
            ),

            // Layer 3 — Hexagonal grid overlay
            const _HexGrid(),

            // Layer 4 — Core logo content
            _LogoContent(
              logoFade: _logoFade,
              logoScale: _logoScale,
              logoSlide: _logoSlide,
              taglineFade: _taglineFade,
              dividerWidth: _dividerWidth,
              glowPulse: _glowPulse,
            ),

            // Layer 5 — Bottom badge
            _BottomBadge(taglineFade: _taglineFade),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Background Gradient Widget
// ─────────────────────────────────────────────
class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient({required this.glowPulse});
  final Animation<double> glowPulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowPulse,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.2),
            radius: 1.2,
            colors: [
              ShadowStormTheme.neonPurple
                  .withValues(alpha: 0.18 * glowPulse.value),
              ShadowStormTheme.neonPurpleDark
                  .withValues(alpha: 0.08 * glowPulse.value),
              ShadowStormTheme.background,
              ShadowStormTheme.background,
            ],
            stops: const [0.0, 0.35, 0.65, 1.0],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Particle System
// ─────────────────────────────────────────────
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.angle,
    required this.opacity,
    required this.phase,
  });

  double x, y, size, speed, angle, opacity, phase;

  factory _Particle.random(math.Random rng) => _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: rng.nextDouble() * 2.5 + 0.8,
        speed: rng.nextDouble() * 0.012 + 0.004,
        angle: rng.nextDouble() * math.pi * 2,
        opacity: rng.nextDouble() * 0.5 + 0.15,
        phase: rng.nextDouble() * math.pi * 2,
      );
}

class _ParticleField extends StatelessWidget {
  const _ParticleField({
    required this.particles,
    required this.controller,
    required this.size,
  });

  final List<_Particle> particles;
  final AnimationController controller;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => CustomPaint(
        size: size,
        painter: _ParticlePainter(
          particles: particles,
          progress: controller.value,
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.progress});

  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final drift = progress * p.speed * 2 * math.pi;
      final px =
          (p.x + math.cos(p.angle + drift) * 0.05 + 1.05) % 1.0 * size.width;
      final py =
          (p.y + math.sin(p.angle * 0.7 + drift + p.phase) * 0.04 + 1.04) %
              1.0 *
              size.height;

      final glow = math.sin(progress * 2 * math.pi + p.phase);
      final alpha = (p.opacity * (0.7 + glow * 0.3)).clamp(0.0, 1.0);

      // Outer glow
      paint.color = ShadowStormTheme.neonPurple.withValues(alpha: alpha * 0.3);
      canvas.drawCircle(Offset(px, py), p.size * 2.2, paint);

      // Core dot
      paint.color = ShadowStormTheme.neonPurpleLight.withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────
//  Hex Grid Overlay
// ─────────────────────────────────────────────
class _HexGrid extends StatelessWidget {
  const _HexGrid();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.04,
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _HexGridPainter(),
      ),
    );
  }
}

class _HexGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ShadowStormTheme.neonPurple
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    const r = 28.0;
    const h = r * 0.866; // sqrt(3)/2

    int col = 0;
    for (double x = 0; x < size.width + r; x += r * 1.5) {
      final yOffset = col.isOdd ? h : 0.0;
      for (double y = yOffset; y < size.height + h; y += h * 2) {
        _drawHex(canvas, paint, Offset(x, y), r);
      }
      col++;
    }
  }

  void _drawHex(Canvas canvas, Paint paint, Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 180 * (60 * i - 30);
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HexGridPainter _) => false;
}

// ─────────────────────────────────────────────
//  Logo Content Widget
// ─────────────────────────────────────────────
class _LogoContent extends StatelessWidget {
  const _LogoContent({
    required this.logoFade,
    required this.logoScale,
    required this.logoSlide,
    required this.taglineFade,
    required this.dividerWidth,
    required this.glowPulse,
  });

  final Animation<double> logoFade;
  final Animation<double> logoScale;
  final Animation<double> logoSlide;
  final Animation<double> taglineFade;
  final Animation<double> dividerWidth;
  final Animation<double> glowPulse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          logoFade,
          logoScale,
          logoSlide,
          taglineFade,
          dividerWidth,
          glowPulse,
        ]),
        builder: (_, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Storm Icon ───────────────────
            Opacity(
              opacity: logoFade.value,
              child: Transform.translate(
                offset: Offset(0, -logoSlide.value),
                child: Transform.scale(
                  scale: logoScale.value,
                  child: _StormIcon(glowPulse: glowPulse.value),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── "SHADOW STORM" Title ─────────
            Opacity(
              opacity: logoFade.value,
              child: Transform.translate(
                offset: Offset(0, logoSlide.value * 0.5),
                child: Transform.scale(
                  scale: logoScale.value,
                  child: _GlowText(glowPulse: glowPulse.value),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Divider ──────────────────────
            SizedBox(
              width: 260,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: dividerWidth.value,
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          ShadowStormTheme.neonPurple,
                          ShadowStormTheme.neonPurpleLight,
                          ShadowStormTheme.neonPurple,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Sub-tagline ──────────────────
            Opacity(
              opacity: taglineFade.value,
              child: const _TaglineText(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Storm Icon (custom SVG-style painter)
// ─────────────────────────────────────────────
class _StormIcon extends StatelessWidget {
  const _StormIcon({required this.glowPulse});
  final double glowPulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: CustomPaint(
        painter: _StormIconPainter(glowPulse: glowPulse),
      ),
    );
  }
}

class _StormIconPainter extends CustomPainter {
  const _StormIconPainter({required this.glowPulse});
  final double glowPulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // ── Outer ring glow
    final outerGlow = Paint()
      ..color =
          ShadowStormTheme.neonPurple.withValues(alpha: 0.25 * glowPulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(Offset(cx, cy), 48, outerGlow);

    // ── Outer ring
    final ring = Paint()
      ..color = ShadowStormTheme.neonPurple.withValues(alpha: 0.6 * glowPulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), 48, ring);

    // ── Inner ring
    final innerRing = Paint()
      ..color = ShadowStormTheme.neonPurple.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(cx, cy), 38, innerRing);

    // ── Lightning bolt body (stylised "S" / storm bolt)
    final boltPath = Path();
    // Top-right to center-left to bottom-right
    boltPath.moveTo(cx + 10, cy - 28);
    boltPath.lineTo(cx - 12, cy - 4);
    boltPath.lineTo(cx + 4, cy - 4);
    boltPath.lineTo(cx - 10, cy + 28);
    boltPath.lineTo(cx + 12, cy + 4);
    boltPath.lineTo(cx - 4, cy + 4);
    boltPath.close();

    // Glow layer
    canvas.drawPath(
      boltPath,
      Paint()
        ..color =
            ShadowStormTheme.neonPurple.withValues(alpha: 0.5 * glowPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Fill layer
    canvas.drawPath(
      boltPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ShadowStormTheme.neonPurpleLight,
            ShadowStormTheme.neonPurple,
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: size.width,
            height: size.height,
          ),
        ),
    );

    // Tick marks on ring
    final tickPaint = Paint()
      ..color = ShadowStormTheme.neonPurple.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * math.pi / 180;
      final inner = i % 3 == 0 ? 42.0 : 44.0;
      canvas.drawLine(
        Offset(cx + inner * math.cos(angle), cy + inner * math.sin(angle)),
        Offset(cx + 48 * math.cos(angle), cy + 48 * math.sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_StormIconPainter old) => old.glowPulse != glowPulse;
}

// ─────────────────────────────────────────────
//  Glow Text
// ─────────────────────────────────────────────
class _GlowText extends StatelessWidget {
  const _GlowText({required this.glowPulse});
  final double glowPulse;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow layer (blurred)
        Text(
          'SHADOW\nSTORM',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 42,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: 10,
            foreground: Paint()
              ..color = ShadowStormTheme.neonPurple
                  .withValues(alpha: 0.55 * glowPulse)
              ..maskFilter =
                  const MaskFilter.blur(BlurStyle.normal, 18),
          ),
        ),
        // Sharp layer
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ShadowStormTheme.neonPurpleLight,
              ShadowStormTheme.neonPurple,
              ShadowStormTheme.textPrimary,
            ],
            stops: [0.0, 0.45, 1.0],
          ).createShader(bounds),
          child: const Text(
            'SHADOW\nSTORM',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 42,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Tagline
// ─────────────────────────────────────────────
class _TaglineText extends StatelessWidget {
  const _TaglineText();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'FREE FIRE ESPORTS TOURNAMENT',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 4.5,
            color: ShadowStormTheme.neonPurpleLight.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '⚡  DOMINATE THE STORM  ⚡',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 3,
            color: ShadowStormTheme.textMuted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Bottom Badge
// ─────────────────────────────────────────────
class _BottomBadge extends StatelessWidget {
  const _BottomBadge({required this.taglineFade});
  final Animation<double> taglineFade;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 36;
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: taglineFade,
        builder: (_, _) => Opacity(
          opacity: taglineFade.value,
          child: Column(
            children: [
              // Loading bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: _PulseBar(progress: taglineFade.value),
              ),
              const SizedBox(height: 14),
              Text(
                'SEASON III  •  2024',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3.5,
                  color: ShadowStormTheme.textMuted.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w500,
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
//  Pulse Loading Bar
// ─────────────────────────────────────────────
class _PulseBar extends StatefulWidget {
  const _PulseBar({required this.progress});
  final double progress;

  @override
  State<_PulseBar> createState() => _PulseBarState();
}

class _PulseBarState extends State<_PulseBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) => Container(
        height: 2,
        decoration: BoxDecoration(
          color: ShadowStormTheme.neonPurple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          widthFactor: 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                begin: Alignment(_shimmer.value - 0.6, 0),
                end: Alignment(_shimmer.value + 0.6, 0),
                colors: [
                  ShadowStormTheme.neonPurple.withValues(alpha: 0.0),
                  ShadowStormTheme.neonPurpleLight.withValues(alpha: 0.9),
                  ShadowStormTheme.neonPurple.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Custom Page Transition
// ─────────────────────────────────────────────
class _FadeRoute extends PageRouteBuilder {
  _FadeRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 800),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          ),
        );
}