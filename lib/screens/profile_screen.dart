import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SSColors {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);

  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleDim       = Color(0xFF7B3FE4);
  static const purpleDark      = Color(0xFF3C2570);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);

  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const textOnPurple    = Color(0xFFFFFFFF);

  static const gold            = Color(0xFFFFCC44);
  static const live            = Color(0xFFFF4466);
  static const liveGlow        = Color(0x55FF4466);
  static const successGreen    = Color(0xFF44FFAA);
  static const successGreenGlow= Color(0x3344FFAA);

  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

class SSTextStyles {
  static const _base = TextStyle(fontFamily: 'Roboto', color: SSColors.textPrimary);

  static final displayLarge  = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5);
  static final displayMedium = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.3);
  static final titleLarge    = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2);
  static final titleMedium   = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.15);
  static final titleSmall    = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1);
  static final bodyMedium    = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: SSColors.textSecondary);
  static final labelLarge    = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: SSColors.textSecondary);
  static final labelSmall    = _base.copyWith(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: SSColors.textMuted);
  static final monoPrize     = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: SSColors.gold);
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL  —  maps one Firestore document to a plain Dart object
// ─────────────────────────────────────────────────────────────────────────────
class PlayerProfile {
  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final DateTime? createdAt;
  final double walletBalance;
  final int wins;
  final int tournamentsPlayed;
  final int rankPoints;

  const PlayerProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    this.createdAt,
    required this.walletBalance,
    required this.wins,
    required this.tournamentsPlayed,
    required this.rankPoints,
  });

  /// Safely parse a Firestore DocumentSnapshot into a [PlayerProfile].
  factory PlayerProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PlayerProfile(
      uid:               data['uid']               as String?  ?? doc.id,
      name:              data['name']              as String?  ?? 'Player',
      email:             data['email']             as String?  ?? '',
      photoUrl:          data['photoUrl']          as String?  ?? '',
      createdAt:         (data['createdAt'] as Timestamp?)?.toDate(),
      walletBalance:     (data['walletBalance']    as num?     ?? 0).toDouble(),
      wins:              (data['wins']             as num?     ?? 0).toInt(),
      tournamentsPlayed: (data['tournamentsPlayed'] as num?    ?? 0).toInt(),
      rankPoints:        (data['rankPoints']       as num?     ?? 0).toInt(),
    );
  }

  /// Generate a short readable player ID (last 6 chars of uid, uppercased).
  String get playerID => '#${uid.substring(math.max(0, uid.length - 6)).toUpperCase()}';

  /// Human-friendly join date.
  String get joinedDate {
    if (createdAt == null) return '—';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[createdAt!.month - 1]} ${createdAt!.year}';
  }

  /// Tier name based on rank points.
  String get rankTier {
    if (rankPoints >= 10000) return 'GRANDMASTER';
    if (rankPoints >= 7500)  return 'MASTER';
    if (rankPoints >= 5000)  return 'DIAMOND';
    if (rankPoints >= 3000)  return 'PLATINUM';
    if (rankPoints >= 1500)  return 'GOLD';
    if (rankPoints >= 500)   return 'SILVER';
    return 'BRONZE';
  }

  Color get rankColor {
    switch (rankTier) {
      case 'GRANDMASTER': return const Color(0xFFFF4466);
      case 'MASTER':      return const Color(0xFFFF66AA);
      case 'DIAMOND':     return const Color(0xFF66DDFF);
      case 'PLATINUM':    return const Color(0xFF44FFAA);
      case 'GOLD':        return SSColors.gold;
      case 'SILVER':      return const Color(0xFFCCCCDD);
      default:            return const Color(0xFFCD7F32); // bronze
    }
  }

  /// Win-rate percentage string.
  String get winRate {
    if (tournamentsPlayed == 0) return '0%';
    return '${((wins / tournamentsPlayed) * 100).toStringAsFixed(1)}%';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  // ── Auth & Firestore ─────────────────────────────────────────────────────
  final User? _firebaseUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Animation controllers ────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _rotateCtrl;

  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  late Animation<double> _pulse;
  late Animation<double> _rotate;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..repeat();

    _fadeIn  = CurvedAnimation(parent: _fadeCtrl,  curve: Curves.easeOutCubic);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _pulse   = CurvedAnimation(parent: _pulseCtrl,  curve: Curves.easeInOut);
    _rotate  = _rotateCtrl;
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    _rotateCtrl.dispose();
    super.dispose();
  }

  // ── Firestore stream ─────────────────────────────────────────────────────
  Stream<PlayerProfile?> get _profileStream {
    if (_firebaseUser == null) return Stream.value(null);
    return _db
        .collection('users')
        .doc(_firebaseUser.uid)
        .snapshots()
        .map((snap) => snap.exists ? PlayerProfile.fromFirestore(snap) : null);
  }

  // ── Sign out ─────────────────────────────────────────────────────────────
  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SignOutDialog(),
    );
    if (confirm == true && mounted) {
      await FirebaseAuth.instance.signOut();
      // Pop back to login. Adjust route name to match your app's routing.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  // ── Copy player ID to clipboard ──────────────────────────────────────────
  void _copyPlayerID(String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SSColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: SSColors.successGreen, size: 16),
          const SizedBox(width: 8),
          Text('Player ID copied!', style: SSTextStyles.bodyMedium.copyWith(color: SSColors.textPrimary)),
        ]),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SSColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: StreamBuilder<PlayerProfile?>(
        stream: _profileStream,
        builder: (context, snapshot) {
          // ── Loading state ──────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingState();
          }
          // ── Error state ────────────────────────────────────────────────
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error.toString());
          }
          // ── No data (user doc missing) ─────────────────────────────────
          final profile = snapshot.data;
          if (profile == null) {
            return const _EmptyState();
          }
          // ── Main content ───────────────────────────────────────────────
          return FadeTransition(
            opacity: _fadeIn,
            child: SlideTransition(
              position: _slideUp,
              child: _buildContent(profile),
            ),
          );
        },
      ),
    );
  }

  // ── APP BAR ──────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 64,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xDD06040E), Colors.transparent],
          ),
        ),
      ),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SSColors.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SSColors.border),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: SSColors.textPrimary, size: 16),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text('PROFILE', style: SSTextStyles.labelLarge.copyWith(
        fontSize: 13, letterSpacing: 2, color: SSColors.textPrimary,
      )),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SSColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: SSColors.border),
              ),
              child: const Icon(Icons.edit_rounded, color: SSColors.purple, size: 16),
            ),
            onPressed: () {
              // TODO: Navigate to edit profile screen
            },
          ),
        ),
      ],
    );
  }

  // ── SCROLLABLE CONTENT ───────────────────────────────────────────────────
  Widget _buildContent(PlayerProfile profile) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 80)),

        // ── 1. Profile Header ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _ProfileHeader(
            profile: profile,
            pulse: _pulse,
            rotate: _rotate,
            onCopyID: () => _copyPlayerID(profile.playerID),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── 2. Wallet + Quick Stats ───────────────────────────────────────
        SliverToBoxAdapter(child: _WalletRow(profile: profile)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── 3. Player Stats ───────────────────────────────────────────────
        const SliverToBoxAdapter(child: _SectionLabel(title: 'PLAYER', accent: 'STATS')),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: _PlayerStatsGrid(profile: profile)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── 4. Rank & Achievement Card ────────────────────────────────────
        const SliverToBoxAdapter(child: _SectionLabel(title: 'RANK &', accent: 'ACHIEVEMENTS')),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: _RankCard(profile: profile, pulse: _pulse)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── 5. Settings & Actions ─────────────────────────────────────────
        const SliverToBoxAdapter(child: _SectionLabel(title: 'SETTINGS', accent: '& MORE')),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: _SettingsSection()),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // ── 6. Logout Button ──────────────────────────────────────────────
        SliverToBoxAdapter(child: _LogoutButton(onTap: _handleSignOut)),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 ── PROFILE HEADER
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final PlayerProfile profile;
  final Animation<double> pulse;
  final Animation<double> rotate;
  final VoidCallback onCopyID;

  const _ProfileHeader({
    required this.profile,
    required this.pulse,
    required this.rotate,
    required this.onCopyID,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SSColors.surfaceCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: SSColors.borderBright, width: 1),
            boxShadow: [
              BoxShadow(
                color: SSColors.purple.withValues(alpha: 0.12 + 0.08 * pulse.value),
                blurRadius: 28 + 8 * pulse.value,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
        child: Column(
          children: [
            // Rotating ring + avatar
            _AnimatedAvatar(profile: profile, rotate: rotate, pulse: pulse),
            const SizedBox(height: 16),

            // Name
            Text(
              profile.name,
              style: SSTextStyles.displayMedium.copyWith(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // Email
            Text(profile.email, style: SSTextStyles.bodyMedium.copyWith(fontSize: 12)),
            const SizedBox(height: 12),

            // Player ID chip
            GestureDetector(
              onTap: onCopyID,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: SSColors.purpleGlowFaint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SSColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tag_rounded, color: SSColors.purple, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      profile.playerID,
                      style: SSTextStyles.titleSmall.copyWith(
                        color: SSColors.purpleLight, fontSize: 13, letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, color: SSColors.textMuted, size: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Divider
            Container(height: 1, color: SSColors.border),
            const SizedBox(height: 14),

            // Joined date & rank tier
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_rounded, color: SSColors.textMuted, size: 12),
                const SizedBox(width: 5),
                Text(
                  'Joined ${profile.joinedDate}',
                  style: SSTextStyles.labelSmall.copyWith(fontSize: 11),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: profile.rankColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: profile.rankColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.military_tech_rounded, color: profile.rankColor, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        profile.rankTier,
                        style: SSTextStyles.labelSmall.copyWith(
                          color: profile.rankColor, fontWeight: FontWeight.w800, letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Rotating ring avatar widget
class _AnimatedAvatar extends StatelessWidget {
  final PlayerProfile profile;
  final Animation<double> rotate;
  final Animation<double> pulse;

  const _AnimatedAvatar({
    required this.profile,
    required this.rotate,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Slow-rotating dashed ring
          AnimatedBuilder(
            animation: rotate,
            builder: (_, _) => Transform.rotate(
              angle: rotate.value * 2 * math.pi,
              child: CustomPaint(
                size: const Size(110, 110),
                painter: _DashedRingPainter(
                  color: profile.rankColor.withValues(alpha: 0.5),
                  strokeWidth: 1.5,
                  dashCount: 24,
                ),
              ),
            ),
          ),
          // Glow ring
          AnimatedBuilder(
            animation: pulse,
            builder: (_, _) => Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: SSColors.purple.withValues(alpha: 0.25 + 0.15 * pulse.value),
                    blurRadius: 18 + 8 * pulse.value,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // Avatar circle
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [SSColors.purpleDim, SSColors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: SSColors.purpleLight, width: 2),
            ),
            child: ClipOval(
              child: profile.photoUrl.isNotEmpty
                  ? Image.network(
                      profile.photoUrl,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _AvatarFallback(name: profile.name),
                    )
                  : _AvatarFallback(name: profile.name),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'P';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 ── WALLET ROW
// ─────────────────────────────────────────────────────────────────────────────
class _WalletRow extends StatelessWidget {
  final PlayerProfile profile;
  const _WalletRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Wallet balance card
          Expanded(
            flex: 3,
            child: _GlowCard(
              glowColor: SSColors.gold.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SSColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: SSColors.gold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WALLET', style: SSTextStyles.labelSmall),
                      Text(
                        '₹${_formatNumber(profile.walletBalance)}',
                        style: SSTextStyles.monoPrize.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [SSColors.gold, Color(0xFFFFAA22)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ADD',
                      style: SSTextStyles.labelSmall.copyWith(
                        color: SSColors.background,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Rank points chip
          Expanded(
            flex: 2,
            child: _GlowCard(
              glowColor: SSColors.purpleGlow.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: SSColors.purple, size: 16),
                      const SizedBox(width: 6),
                      Text('POINTS', style: SSTextStyles.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatNumber(profile.rankPoints.toDouble()),
                    style: SSTextStyles.titleLarge.copyWith(
                      color: SSColors.purpleLight, fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return n.toStringAsFixed(n == n.truncate() ? 0 : 2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 ── PLAYER STATS GRID
// ─────────────────────────────────────────────────────────────────────────────
class _PlayerStatsGrid extends StatelessWidget {
  final PlayerProfile profile;
  const _PlayerStatsGrid({required this.profile});

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatData(
        icon: Icons.emoji_events_rounded,
        label: 'Tournaments',
        value: '${profile.tournamentsPlayed}',
        color: SSColors.purpleLight,
      ),
      _StatData(
        icon: Icons.military_tech_rounded,
        label: 'Total Wins',
        value: '${profile.wins}',
        color: SSColors.gold,
      ),
      _StatData(
        icon: Icons.percent_rounded,
        label: 'Win Rate',
        value: profile.winRate,
        color: SSColors.successGreen,
      ),
      _StatData(
        icon: Icons.local_fire_department_rounded,
        label: 'Best Streak',
        value: '5W',       // TODO: fetch from Firestore if tracked
        color: SSColors.live,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: stats.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.0,
        ),
        itemBuilder: (_, i) => _StatGridCell(stat: stats[i]),
      ),
    );
  }
}

class _StatData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatData({required this.icon, required this.label, required this.value, required this.color});
}

class _StatGridCell extends StatelessWidget {
  final _StatData stat;
  const _StatGridCell({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SSColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SSColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: stat.color.withValues(alpha: 0.08),
            blurRadius: 12, spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: stat.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, color: stat.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(stat.value, style: SSTextStyles.titleMedium.copyWith(
                  color: stat.color, fontSize: 18,
                )),
                Text(stat.label, style: SSTextStyles.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 ── RANK CARD
// ─────────────────────────────────────────────────────────────────────────────
class _RankCard extends StatelessWidget {
  final PlayerProfile profile;
  final Animation<double> pulse;

  const _RankCard({required this.profile, required this.pulse});

  @override
  Widget build(BuildContext context) {
    // Progress to next tier
    final tiers = [0, 500, 1500, 3000, 5000, 7500, 10000];
    final tierNames = ['BRONZE', 'SILVER', 'GOLD', 'PLATINUM', 'DIAMOND', 'MASTER', 'GRANDMASTER'];
    final currentIdx = tiers.lastIndexWhere((t) => profile.rankPoints >= t);
    final isMaxTier = currentIdx >= tiers.length - 1;
    final currentFloor = tiers[currentIdx];
    final nextFloor = isMaxTier ? tiers.last : tiers[currentIdx + 1];
    final progress = isMaxTier ? 1.0 : (profile.rankPoints - currentFloor) / (nextFloor - currentFloor);
    final nextTierName = isMaxTier ? '—' : tierNames[currentIdx + 1];
    final pointsLeft = isMaxTier ? 0 : nextFloor - profile.rankPoints;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            color: SSColors.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: profile.rankColor.withValues(alpha: 0.3 + 0.1 * pulse.value),
            ),
            boxShadow: [
              BoxShadow(
                color: profile.rankColor.withValues(alpha: 0.10 + 0.06 * pulse.value),
                blurRadius: 20 + 6 * pulse.value,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
        child: Stack(
          children: [
            // Background geometric
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CustomPaint(
                  painter: _GeometricPainter(
                    color: profile.rankColor.withValues(alpha: 0.03),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: profile.rankColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: profile.rankColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(Icons.shield_rounded, color: profile.rankColor, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.rankTier, style: SSTextStyles.titleLarge.copyWith(
                            color: profile.rankColor, letterSpacing: 1.5,
                          )),
                          Text('${profile.rankPoints} RP', style: SSTextStyles.bodyMedium),
                        ],
                      ),
                      const Spacer(),
                      // Achievements badge row
                      Row(
                        children: [
                          _AchievementBadge(icon: Icons.emoji_events_rounded, color: SSColors.gold, tooltip: 'Top Finisher'),
                          const SizedBox(width: 6),
                          _AchievementBadge(icon: Icons.flash_on_rounded, color: SSColors.purple, tooltip: 'Quick Striker'),
                          const SizedBox(width: 6),
                          _AchievementBadge(icon: Icons.local_fire_department_rounded, color: SSColors.live, tooltip: 'Hot Streak'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Progress to next tier
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Progress to $nextTierName',
                          style: SSTextStyles.labelSmall.copyWith(fontSize: 11)),
                      if (!isMaxTier)
                        Text('$pointsLeft RP to go',
                            style: SSTextStyles.labelSmall.copyWith(
                              color: profile.rankColor, fontSize: 11,
                            )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: SSColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation(profile.rankColor),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Milestone row
                  Row(
                    children: [
                      _MilestonePill(icon: Icons.emoji_events_rounded, label: '${profile.wins} Wins'),
                      const SizedBox(width: 8),
                      _MilestonePill(icon: Icons.gamepad_rounded, label: '${profile.tournamentsPlayed} Played'),
                      const SizedBox(width: 8),
                      _MilestonePill(icon: Icons.trending_up_rounded, label: profile.winRate),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  const _AchievementBadge({required this.icon, required this.color, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
    );
  }
}

class _MilestonePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MilestonePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: SSColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SSColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SSColors.textSecondary, size: 11),
          const SizedBox(width: 4),
          Text(label, style: SSTextStyles.labelSmall.copyWith(
            color: SSColors.textSecondary, fontSize: 10,
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 ── SETTINGS
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context) {
    final items = [
      _SettingItem(icon: Icons.notifications_rounded, label: 'Notifications', trailing: _Switch()),
      _SettingItem(icon: Icons.lock_rounded,           label: 'Privacy & Security'),
      _SettingItem(icon: Icons.help_outline_rounded,   label: 'Help & Support'),
      _SettingItem(icon: Icons.info_outline_rounded,   label: 'About Shadow Storm'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: SSColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SSColors.border),
        ),
        child: Column(
          children: List.generate(items.length, (i) {
            final isLast = i == items.length - 1;
            return Column(
              children: [
                _SettingRow(item: items[i]),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(height: 1, color: SSColors.border),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _SettingItem({required this.icon, required this.label, this.trailing});
}

class _SettingRow extends StatelessWidget {
  final _SettingItem item;
  const _SettingRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: item.trailing == null ? () {} : null,
      splashColor: SSColors.purpleGlow,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SSColors.purpleGlowFaint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: SSColors.purple, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(item.label, style: SSTextStyles.titleSmall)),
            item.trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: SSColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Simple toggle switch styled to match the app theme.
class _Switch extends StatefulWidget {
  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  bool _on = true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _on = !_on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          color: _on ? SSColors.purple : SSColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _on ? SSColors.purpleLight : SSColors.border),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _on ? Colors.white : SSColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _LogoutButton extends StatefulWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: SSColors.live.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SSColors.live.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, color: SSColors.live, size: 18),
                const SizedBox(width: 8),
                Text(
                  'SIGN OUT',
                  style: SSTextStyles.labelLarge.copyWith(
                    color: SSColors.live, fontSize: 13, letterSpacing: 1.5,
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

// ─────────────────────────────────────────────────────────────────────────────
// SIGN OUT DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _SignOutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SSColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: SSColors.border),
      ),
      title: Text('Sign Out', style: SSTextStyles.titleMedium),
      content: Text('Are you sure you want to sign out?', style: SSTextStyles.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: SSColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Sign Out', style: TextStyle(color: SSColors.live)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING / ERROR / EMPTY STATES
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40, height: 40,
            child: CircularProgressIndicator(
              valueColor: const AlwaysStoppedAnimation(SSColors.purple),
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: 16),
          Text('Loading profile…', style: SSTextStyles.bodyMedium),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: SSColors.live, size: 48),
            const SizedBox(height: 12),
            Text('Something went wrong', style: SSTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(error, style: SSTextStyles.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_off_rounded, color: SSColors.textMuted, size: 48),
          const SizedBox(height: 12),
          Text('Profile not found', style: SSTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text('Your account data could not be loaded.', style: SSTextStyles.bodyMedium),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Glowing surface card used for wallet row items.
class _GlowCard extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  const _GlowCard({required this.child, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SSColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SSColors.border),
        boxShadow: [BoxShadow(color: glowColor, blurRadius: 16, spreadRadius: 0)],
      ),
      child: child,
    );
  }
}

/// Section label (matches HomeScreen style).
class _SectionLabel extends StatelessWidget {
  final String title;
  final String accent;
  const _SectionLabel({required this.title, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 3, height: 18,
            decoration: BoxDecoration(
              color: SSColors.purple, borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title, style: SSTextStyles.labelLarge.copyWith(fontSize: 12, letterSpacing: 1.5)),
          const SizedBox(width: 5),
          Text(accent, style: SSTextStyles.labelLarge.copyWith(
            fontSize: 12, letterSpacing: 1.5, color: SSColors.purple,
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTER  —  rotating dashed ring around avatar
// ─────────────────────────────────────────────────────────────────────────────
class _DashedRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;

  const _DashedRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - strokeWidth;
    final dashAngle = (2 * math.pi) / dashCount;
    final gapRatio = 0.45;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = dashAngle * i;
      final sweepAngle = dashAngle * (1 - gapRatio);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ─────────────────────────────────────────────────────────────────────────────
// GEOMETRIC BACKGROUND PATTERN (same as HomeScreen)
// ─────────────────────────────────────────────────────────────────────────────
class _GeometricPainter extends CustomPainter {
  final Color color;
  const _GeometricPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    final cols = (size.width / spacing).ceil() + 2;
    final rows = (size.height / spacing).ceil() + 2;

    for (int c = 0; c < cols; c++) {
      for (int r = 0; r < rows; r++) {
        canvas.drawCircle(Offset(c * spacing, r * spacing), 1.2, dotPaint);
      }
    }
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 6; i++) {
      final x = size.width * (0.5 + i * 0.15);
      canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.5, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}