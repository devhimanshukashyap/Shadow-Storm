// lib/screens/tournament_details_screen.dart
// ─────────────────────────────────────────────
// TOURNAMENT DETAILS SCREEN
// Shows full tournament info with room system,
// join logic, and real-time Firestore updates.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';
import '../services/tournament_service.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS (same as HomeScreen)
// ─────────────────────────────────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);

  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleDim       = Color(0xFF7B3FE4);
  // static const purpleDark      = Color(0xFF3C2570);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);

  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);

  static const gold            = Color(0xFFFFCC44);
  static const live            = Color(0xFFFF4466);
  // static const liveGlow        = Color(0x55FF4466);
  static const success         = Color(0xFF44FF99);
  // static const successGlow     = Color(0x3344FF99);

  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

// ─────────────────────────────────────────────
// TOURNAMENT DETAILS SCREEN
// ─────────────────────────────────────────────
class TournamentDetailsScreen extends StatefulWidget {
  /// Pass the tournament from the card tap.
  /// The screen also subscribes to real-time updates
  /// so joinedPlayers count stays fresh.
  final TournamentModel tournament;

  const TournamentDetailsScreen({super.key, required this.tournament});

  @override
  State<TournamentDetailsScreen> createState() =>
      _TournamentDetailsScreenState();
}

class _TournamentDetailsScreenState extends State<TournamentDetailsScreen>
    with TickerProviderStateMixin {
  // ── State ─────────────────────────────────
  bool _isJoined    = false;
  bool _isJoining   = false;
  bool _checkingJoin = true;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  final TournamentService  _service = TournamentService.instance;
  final FirebaseFirestore  _db      = FirebaseFirestore.instance;
  final FirebaseAuth       _auth    = FirebaseAuth.instance;

  User?   get _user        => _auth.currentUser;
  String? get _userId      => _user?.uid;
  String  get _tournamentId => widget.tournament.id;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700),
    )..forward();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _checkIfJoined();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Check if current user has already joined ─
  Future<void> _checkIfJoined() async {
    if (_userId == null) {
      setState(() => _checkingJoin = false);
      return;
    }
    try {
      final doc = await _db
          .collection('tournaments')
          .doc(_tournamentId)
          .collection('participants')
          .doc(_userId)
          .get();
      if (mounted) {
        setState(() {
          _isJoined    = doc.exists;
          _checkingJoin = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingJoin = false);
    }
  }

  // ── Join Tournament ──────────────────────────
  Future<void> _joinTournament(TournamentModel t) async {
    if (_userId == null) {
      _showSnack('Please log in to join tournaments.');
      return;
    }
    if (t.slotsLeft <= 0) {
      _showSnack('Tournament is full!');
      return;
    }

    setState(() => _isJoining = true);

    try {
      // 1. Write participant document
      await _db
          .collection('tournaments')
          .doc(_tournamentId)
          .collection('participants')
          .doc(_userId)
          .set({
        'userId':    _userId,
        'userName':  _user?.displayName ?? 'Unknown',
        'userEmail': _user?.email ?? '',
        'joinedAt':  FieldValue.serverTimestamp(),
        'status':    'registered', // future: 'playing', 'eliminated', 'winner'
      });

      // 2. Increment joinedPlayers atomically
      await _service.joinTournament(_tournamentId);

      if (mounted) {
        setState(() {
          _isJoined  = true;
          _isJoining = false;
        });
        _showSuccessSnack('You\'re in! Good luck, ${_user?.displayName?.split(' ').first ?? 'Striker'}!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        _showSnack('Failed to join. Please try again.');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _C.textPrimary)),
        backgroundColor: _C.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _C.border),
        ),
      ),
    );
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _C.success, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: const TextStyle(color: _C.textPrimary))),
          ],
        ),
        backgroundColor: _C.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _C.success.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  // ── Copy to clipboard helper ─────────────────
  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnack('$label copied!');
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: StreamBuilder<TournamentModel?>(
        stream: _service.tournamentByIdStream(_tournamentId),
        builder: (context, snap) {
          // Use latest data from stream, fall back to passed-in model
          final t = snap.data ?? widget.tournament;

          return FadeTransition(
            opacity: _fadeIn,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Collapsible Banner App Bar ──────
                _buildSliverAppBar(t),

                // ── Body Content ────────────────────
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildInfoRow(t),
                      const SizedBox(height: 20),
                      _buildPrizeSection(t),
                      const SizedBox(height: 16),
                      _buildMatchInfo(t),
                      const SizedBox(height: 16),
                      _buildSlotProgress(t),
                      const SizedBox(height: 16),
                      _buildRoomSection(t),
                      const SizedBox(height: 16),
                      if (t.rules != null && t.rules!.isNotEmpty)
                        _buildRulesSection(t),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      // ── Sticky Join Button ─────────────────────
      bottomNavigationBar: StreamBuilder<TournamentModel?>(
        stream: _service.tournamentByIdStream(_tournamentId),
        builder: (context, snap) {
          final t = snap.data ?? widget.tournament;
          return _buildJoinBar(t);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SLIVER APP BAR (Banner)
  // ─────────────────────────────────────────────
  Widget _buildSliverAppBar(TournamentModel t) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: _C.background,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _C.surfaceCard.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: _C.border),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _C.textPrimary, size: 16),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _BannerHeader(tournament: t, pulse: _pulse),
        collapseMode: CollapseMode.parallax,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // INFO ROW (quick stats)
  // ─────────────────────────────────────────────
  Widget _buildInfoRow(TournamentModel t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _QuickStat(
            icon: Icons.map_rounded,
            label: 'MAP',
            value: t.map,
            color: _C.purpleLight,
          ),
          const SizedBox(width: 10),
          _QuickStat(
            icon: Icons.people_rounded,
            label: 'MODE',
            value: t.mode,
            color: _C.purple,
          ),
          const SizedBox(width: 10),
          _QuickStat(
            icon: Icons.access_time_rounded,
            label: 'STARTS',
            value: t.startTimeDisplay,
            color: _C.gold,
            flex: 2,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PRIZE SECTION
  // ─────────────────────────────────────────────
  Widget _buildPrizeSection(TournamentModel t) {
    return _SectionCard(
      title: 'PRIZE BREAKDOWN',
      icon: Icons.emoji_events_rounded,
      iconColor: _C.gold,
      child: Column(
        children: [
          // Total prize pool highlight
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _C.gold.withValues(alpha: 0.12),
                  _C.gold.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.gold.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: _C.gold, size: 20),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TOTAL PRIZE POOL',
                        style: TextStyle(
                          color: _C.gold.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        )),
                    Text(
                      t.prizePoolDisplay,
                      style: const TextStyle(
                        color: _C.gold,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Position rewards
          if (t.positions.isNotEmpty) ...[
            ...t.positions.map((p) => _PositionRewardRow(reward: p)),
            const SizedBox(height: 10),
          ],

          // Kill / Survival rewards
          if (t.killReward > 0 || t.survivalReward > 0)
            _RewardTypeRow(tournament: t),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MATCH INFO
  // ─────────────────────────────────────────────
  Widget _buildMatchInfo(TournamentModel t) {
    return _SectionCard(
      title: 'MATCH INFO',
      icon: Icons.sports_esports_rounded,
      iconColor: _C.purple,
      child: Column(
        children: [
          _InfoTile(label: 'Tournament Type', value: t.modeDisplay),
          _InfoTile(label: 'Map', value: t.map),
          _InfoTile(label: 'Entry Fee', value: t.entryFeeDisplay,
              valueColor: t.entryFee > 0 ? _C.textPrimary : _C.success),
          _InfoTile(label: 'Reward Type', value: _rewardTypeLabel(t.rewardType)),
        ],
      ),
    );
  }

  String _rewardTypeLabel(String type) {
    switch (type) {
      case 'kill':     return 'Kill Based';
      case 'survival': return 'Survival Based';
      case 'position': return 'Position Based';
      case 'mixed':    return 'Mixed (Kill + Position)';
      default:         return type;
    }
  }

  // ─────────────────────────────────────────────
  // SLOT PROGRESS
  // ─────────────────────────────────────────────
  Widget _buildSlotProgress(TournamentModel t) {
    final pct = t.fillPercent;
    return _SectionCard(
      title: 'SLOTS',
      icon: Icons.grid_view_rounded,
      iconColor: _C.purpleLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${t.joinedPlayers}',
                      style: const TextStyle(
                        color: _C.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${t.maxPlayers}',
                      style: const TextStyle(
                        color: _C.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.isAlmostFull
                      ? _C.live.withValues(alpha: 0.15)
                      : _C.purpleGlowFaint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: t.isAlmostFull
                        ? _C.live.withValues(alpha: 0.4)
                        : _C.border,
                  ),
                ),
                child: Text(
                  t.isAlmostFull ? '🔥 Almost Full' : '${t.slotsLeft} slots left',
                  style: TextStyle(
                    color: t.isAlmostFull ? _C.live : _C.purpleLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: _C.surfaceElevated,
              valueColor: AlwaysStoppedAnimation(
                t.isAlmostFull ? _C.live : _C.purple,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% filled',
            style: const TextStyle(
              color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ROOM SECTION (visibility gated)
  // ─────────────────────────────────────────────
  Widget _buildRoomSection(TournamentModel t) {
    return _SectionCard(
      title: 'ROOM DETAILS',
      icon: Icons.meeting_room_rounded,
      iconColor: _C.purple,
      child: _checkingJoin
          ? const _RoomLoading()
          : _isJoined
              ? _RoomRevealed(tournament: t, onCopy: _copyToClipboard)
              : const _RoomLocked(),
    );
  }

  // ─────────────────────────────────────────────
  // RULES SECTION
  // ─────────────────────────────────────────────
  Widget _buildRulesSection(TournamentModel t) {
    return _SectionCard(
      title: 'RULES',
      icon: Icons.gavel_rounded,
      iconColor: _C.purpleLight,
      child: Text(
        t.rules ?? '',
        style: const TextStyle(
          color: _C.textSecondary,
          fontSize: 13,
          height: 1.6,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // JOIN BAR (sticky bottom)
  // ─────────────────────────────────────────────
  Widget _buildJoinBar(TournamentModel t) {
    final isFull   = t.slotsLeft <= 0;
    final isLive   = t.status == TournamentStatus.live;
    final isCompleted = t.status == TournamentStatus.completed;

    return Container(
      decoration: const BoxDecoration(
        color: _C.surface,
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              // Entry fee info
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ENTRY FEE',
                    style: TextStyle(
                      color: _C.textMuted, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1,
                    )),
                  Text(
                    t.entryFeeDisplay,
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _isJoined
                    ? _JoinedBadge()
                    : isCompleted
                        ? _DisabledButton(label: 'TOURNAMENT ENDED')
                        : isFull
                            ? _DisabledButton(label: 'TOURNAMENT FULL')
                            : isLive
                                ? _DisabledButton(label: 'ALREADY STARTED')
                                : _JoinButton(
                                    isLoading: _isJoining,
                                    onTap: () => _joinTournament(t),
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
// BANNER HEADER WIDGET
// ─────────────────────────────────────────────
class _BannerHeader extends StatelessWidget {
  final TournamentModel   tournament;
  final Animation<double> pulse;
  const _BannerHeader({required this.tournament, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: banner image or geometric pattern
        if (t.bannerUrl != null && t.bannerUrl!.isNotEmpty)
          Image.network(
            t.bannerUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _FallbackBanner(),
          )
        else
          _FallbackBanner(),

        // Dark gradient overlay
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                _C.background.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // Content
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status badge
              _StatusBadge(status: t.status, pulse: pulse),
              const SizedBox(height: 10),
              // Title
              Text(
                t.title,
                style: const TextStyle(
                  color: _C.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  shadows: [Shadow(color: _C.purpleGlow, blurRadius: 16)],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.subtitle,
                style: const TextStyle(
                  color: _C.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.surfaceCard,
      child: CustomPaint(painter: _BannerPatternPainter()),
    );
  }
}

class _BannerPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _C.purple.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    const spacing = 28.0;
    final cols = (size.width  / spacing).ceil() + 2;
    final rows = (size.height / spacing).ceil() + 2;
    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        canvas.drawCircle(Offset(c * spacing.toDouble(), r * spacing.toDouble()), 1.2, paint);
      }
    }
    final linePaint = Paint()
      ..color = _C.purple.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) {
      final x = size.width * (0.5 + i * 0.15);
      canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.5, size.height), linePaint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _StatusBadge extends StatelessWidget {
  final TournamentStatus  status;
  final Animation<double> pulse;
  const _StatusBadge({required this.status, required this.pulse});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case TournamentStatus.live:
        color = _C.live; label = 'LIVE NOW'; break;
      case TournamentStatus.completed:
        color = _C.textMuted; label = 'COMPLETED'; break;
      case TournamentStatus.upcoming:
        color = _C.purple; label = 'UPCOMING'; break;
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: 0.5 + 0.3 * pulse.value),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == TournamentStatus.live) ...[
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.5 + 0.5 * pulse.value),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(
              color: color, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 1.2,
            )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ROOM WIDGETS
// ─────────────────────────────────────────────

class _RoomLoading extends StatelessWidget {
  const _RoomLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: CircularProgressIndicator(
          color: _C.purple, strokeWidth: 2,
        ),
      ),
    );
  }
}

class _RoomLocked extends StatelessWidget {
  const _RoomLocked();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: _C.purpleGlowFaint,
              shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: const Icon(Icons.lock_rounded, color: _C.purple, size: 24),
          ),
          const SizedBox(height: 12),
          const Text(
            'Room Details Locked',
            style: TextStyle(
              color: _C.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Join the tournament to unlock\nRoom ID and Password',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _C.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomRevealed extends StatelessWidget {
  final TournamentModel             tournament;
  final void Function(String, String) onCopy;
  const _RoomRevealed({required this.tournament, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final t         = tournament;
    final hasRoomId = t.roomId != null && t.roomId!.isNotEmpty;
    final hasPw     = t.roomPassword != null && t.roomPassword!.isNotEmpty;

    if (!hasRoomId && !hasPw) {
      return _RoomPending();
    }

    return Column(
      children: [
        // Joined badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _C.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _C.success.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: _C.success, size: 15),
              SizedBox(width: 6),
              Text('You\'re registered for this tournament',
                style: TextStyle(
                  color: _C.success, fontSize: 12, fontWeight: FontWeight.w600,
                )),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (hasRoomId)
          _RoomField(
            label: 'ROOM ID',
            value: t.roomId!,
            icon: Icons.meeting_room_rounded,
            onCopy: () => onCopy(t.roomId!, 'Room ID'),
          ),
        if (hasRoomId && hasPw) const SizedBox(height: 10),
        if (hasPw)
          _RoomField(
            label: 'PASSWORD',
            value: t.roomPassword!,
            icon: Icons.vpn_key_rounded,
            onCopy: () => onCopy(t.roomPassword!, 'Password'),
          ),
      ],
    );
  }
}

class _RoomPending extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: _C.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Room details coming soon',
                  style: TextStyle(
                    color: _C.gold, fontSize: 13, fontWeight: FontWeight.w700,
                  )),
                const SizedBox(height: 2),
                const Text(
                  'Room ID & Password will be revealed 30 min before the match.',
                  style: TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomField extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final VoidCallback onCopy;
  const _RoomField({
    required this.label, required this.value,
    required this.icon,  required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.borderBright),
      ),
      child: Row(
        children: [
          Icon(icon, color: _C.purple, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(
                  color: _C.textMuted, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1,
                )),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(
                  color: _C.textPrimary, fontSize: 16,
                  fontWeight: FontWeight.w800, letterSpacing: 1.5,
                )),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _C.purpleGlowFaint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.border),
              ),
              child: const Icon(Icons.copy_rounded, color: _C.purple, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PRIZE BREAKDOWN ROWS
// ─────────────────────────────────────────────
class _PositionRewardRow extends StatelessWidget {
  final PositionReward reward;
  const _PositionRewardRow({required this.reward});

  static const _medals = ['🥇', '🥈', '🥉'];
  static const _rankColors = [_C.gold, Color(0xFFC0C0C0), Color(0xFFCD7F32)];

  @override
  Widget build(BuildContext context) {
    final r     = reward.rank;
    final emoji = r <= 3 ? _medals[r - 1] : '#$r';
    final color = r <= 3 ? _rankColors[r - 1] : _C.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          Text(
            r <= 3 ? ['1st Place', '2nd Place', '3rd Place'][r - 1] : 'Rank $r',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            '₹${_fmt(reward.amount)}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double a) {
    if (a >= 100000) {
      final l = (a ~/ 100000);
      final t = ((a % 100000) ~/ 1000);
      final r = (a % 1000).toInt();
      if (r == 0 && t == 0) return '$l,00,000';
      if (r == 0) return '$l,${t.toString().padLeft(2,'0')},000';
      return '$l,${t.toString().padLeft(2,'0')},${r.toString().padLeft(3,'0')}';
    } else if (a >= 1000) {
      final t = a ~/ 1000;
      final r = (a % 1000).toInt();
      return r == 0 ? '$t,000' : '$t,${r.toString().padLeft(3,'0')}';
    }
    return a.toInt().toString();
  }
}

class _RewardTypeRow extends StatelessWidget {
  final TournamentModel tournament;
  const _RewardTypeRow({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          if (t.killReward > 0) ...[
            const Icon(Icons.sports_kabaddi_rounded, color: _C.live, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text('₹${t.killReward.toInt()} per kill',
              style: const TextStyle(
                color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w600,
              ))),
          ],
          if (t.killReward > 0 && t.survivalReward > 0)
            Container(width: 1, height: 20, color: _C.border,
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          if (t.survivalReward > 0) ...[
            const Icon(Icons.shield_rounded, color: _C.purpleLight, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text('₹${t.survivalReward.toInt()} survival',
              style: const TextStyle(
                color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w600,
              ))),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// REUSABLE SECTION WIDGETS
// ─────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String    title;
  final IconData  icon;
  final Color     iconColor;
  final Widget    child;
  const _SectionCard({
    required this.title, required this.icon,
    required this.iconColor, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 7),
                Text(title, style: const TextStyle(
                  color: _C.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                )),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String  label;
  final String  value;
  final Color?  valueColor;
  const _InfoTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(
              color: _C.textMuted, fontSize: 12,
            )),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? _C.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final int      flex;
  const _QuickStat({
    required this.icon, required this.label,
    required this.value, required this.color, this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _C.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(
                    color: _C.textMuted, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8,
                  )),
                  const SizedBox(height: 1),
                  Text(value,
                    style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
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

// ─────────────────────────────────────────────
// JOIN BAR WIDGETS
// ─────────────────────────────────────────────
class _JoinButton extends StatefulWidget {
  final bool       isLoading;
  final VoidCallback onTap;
  const _JoinButton({required this.isLoading, required this.onTap});

  @override
  State<_JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends State<_JoinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _ctrl.forward(),
      onTapUp:     (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_C.purple, _C.purpleDim],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _C.purple.withValues(alpha: 0.45),
                blurRadius: 14, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2,
                    ),
                  )
                : const Text('JOIN TOURNAMENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    )),
          ),
        ),
      ),
    );
  }
}

class _JoinedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: _C.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.success.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: _C.success, size: 18),
          SizedBox(width: 8),
          Text('REGISTERED',
            style: TextStyle(
              color: _C.success,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            )),
        ],
      ),
    );
  }
}

class _DisabledButton extends StatelessWidget {
  final String label;
  const _DisabledButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Center(
        child: Text(label, style: const TextStyle(
          color: _C.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        )),
      ),
    );
  }
}