// lib/screens/all_tournaments_screen.dart
// ─────────────────────────────────────────────
// ALL TOURNAMENTS SCREEN
// Reusable screen that shows a filterable list
// of tournaments. Same Shadow Storm design system.
//
// Usage examples:
//   AllTournamentsScreen()                          — all tournaments
//   AllTournamentsScreen(initialStatus: 'live')     — live only
//   AllTournamentsScreen(initialStatus: 'upcoming') — upcoming only
//   AllTournamentsScreen(initialType: 'clash_squad')— type pre-filtered
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tournament_model.dart';
import '../services/tournament_service.dart';
import 'tournament_details_screen.dart';

// ── Design tokens (same values as HomeScreen SSColors) ──
class _C {
  static const background      = Color(0xFF06040E);
  // static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);

  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  // static const purpleDim       = Color(0xFF7B3FE4);
  // static const purpleDark      = Color(0xFF3C2570);
  // static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);

  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);

  static const gold            = Color(0xFFFFCC44);
  static const live            = Color(0xFFFF4466);
  // static const liveGlow        = Color(0x55FF4466);
  static const success         = Color(0xFF44FF99);

  static const border          = Color(0x337B3FE4);
  // static const borderBright    = Color(0x667B3FE4);
}

// ── Filter model ────────────────────────────────
class _StatusOption {
  final String value; // null = all, 'live', 'upcoming', 'completed'
  final String label;
  final IconData icon;
  final Color color;
  const _StatusOption({
    required this.value, required this.label,
    required this.icon,  required this.color,
  });
}

class _TypeOption {
  final String value; // 'all', 'battle_royale', 'clash_squad', 'lone_wolf', 'league'
  final String label;
  final String emoji;
  const _TypeOption({
    required this.value, required this.label, required this.emoji,
  });
}

const _statusOptions = [
  _StatusOption(value: 'all',       label: 'All',       icon: Icons.grid_view_rounded,         color: _C.purpleLight),
  _StatusOption(value: 'live',      label: 'Live',      icon: Icons.radio_button_checked,      color: _C.live),
  _StatusOption(value: 'upcoming',  label: 'Upcoming',  icon: Icons.schedule_rounded,          color: _C.gold),
  _StatusOption(value: 'completed', label: 'Completed', icon: Icons.check_circle_outline_rounded, color: _C.textMuted),
];

const _typeOptions = [
  _TypeOption(value: 'all',          label: 'All Types',   emoji: '⚡'),
  _TypeOption(value: 'battle_royale',label: 'Full Map',    emoji: '🗺️'),
  _TypeOption(value: 'clash_squad',  label: 'Clash Squad', emoji: '⚔️'),
  _TypeOption(value: 'lone_wolf',    label: 'Lone Wolf',   emoji: '🎯'),
  _TypeOption(value: 'league',       label: 'League',      emoji: '🏆'),
];

// ─────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────
class AllTournamentsScreen extends StatefulWidget {
  final String  title;
  final String? initialStatus; // 'live' | 'upcoming' | 'completed' | null → 'all'
  final String? initialType;   // 'battle_royale' | 'clash_squad' | 'lone_wolf' | 'league' | null → 'all'

  const AllTournamentsScreen({
    super.key,
    this.title       = 'All Tournaments',
    this.initialStatus,
    this.initialType,
  });

  @override
  State<AllTournamentsScreen> createState() => _AllTournamentsScreenState();
}

class _AllTournamentsScreenState extends State<AllTournamentsScreen>
    with TickerProviderStateMixin {

  late String _statusFilter;
  late String _typeFilter;

  Set<String> _joinedIds = {};

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeIn;

  final TournamentService _service = TournamentService.instance;

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus ?? 'all';
    _typeFilter   = widget.initialType   ?? 'all';

    _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);

    // Load joined IDs
    if (_userId != null) {
      _service.joinedTournamentIdsStream(_userId!).listen((ids) {
        if (mounted) setState(() => _joinedIds = ids);
      });
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // Build the appropriate stream based on current filters
  Stream<List<TournamentModel>> get _stream {
    return _service.filteredTournamentsStream(
      statusFilter: _statusFilter == 'all' ? null : _statusFilter,
      typeFilter:   _typeFilter,
    );
  }

  void _openDetails(TournamentModel t) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, _) => TournamentDetailsScreen(tournament: t),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: FadeTransition(
        opacity: _fadeIn,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── App Bar ────────────────────────
            _buildAppBar(),

            // ── Status Filter ──────────────────
            SliverToBoxAdapter(child: _buildStatusFilter()),

            // ── Type Filter ────────────────────
            SliverToBoxAdapter(child: _buildTypeFilter()),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Tournament List ────────────────
            _buildList(),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: _C.background,
      elevation: 0,
      toolbarHeight: 60,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            shape: BoxShape.circle,
            border: Border.all(color: _C.border),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _C.textPrimary, size: 16),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title.toUpperCase(),
            style: const TextStyle(
              color: _C.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          StreamBuilder<List<TournamentModel>>(
            stream: _stream,
            builder: (_, snap) {
              final count = snap.data?.length ?? 0;
              return Text(
                '$count tournament${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: _C.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _C.border),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STATUS FILTER ROW
  // ─────────────────────────────────────────────
  Widget _buildStatusFilter() {
    return Container(
      color: _C.background,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: _statusOptions.map((opt) {
          final active = _statusFilter == opt.value;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_statusFilter != opt.value) {
                  setState(() => _statusFilter = opt.value);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? opt.color.withValues(alpha: 0.15)
                      : _C.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? opt.color.withValues(alpha: 0.5)
                        : _C.border,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(opt.icon,
                        color: active ? opt.color : _C.textMuted, size: 14),
                    const SizedBox(height: 3),
                    Text(
                      opt.label,
                      style: TextStyle(
                        color: active ? opt.color : _C.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TYPE FILTER ROW
  // ─────────────────────────────────────────────
  Widget _buildTypeFilter() {
    return Container(
      color: _C.background,
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _typeOptions.map((opt) {
            final active = _typeFilter == opt.value;
            return GestureDetector(
              onTap: () {
                if (_typeFilter != opt.value) {
                  setState(() => _typeFilter = opt.value);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? _C.purpleGlowFaint : _C.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? _C.purple.withValues(alpha: 0.6) : _C.border,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(opt.emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      opt.label,
                      style: TextStyle(
                        color: active ? _C.purpleLight : _C.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TOURNAMENT LIST
  // ─────────────────────────────────────────────
  Widget _buildList() {
    return StreamBuilder<List<TournamentModel>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => const _ListCardShimmer(),
              childCount: 5,
            ),
          );
        }

        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: _ErrorState(message: 'Could not load tournaments.\n${snap.error}'),
          );
        }

        final list = snap.data ?? [];

        if (list.isEmpty) {
          return SliverToBoxAdapter(child: _EmptyState(
            statusFilter: _statusFilter,
            typeFilter: _typeFilter,
          ));
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _TournamentListCard(
                tournament:  list[i],
                isJoined:    _joinedIds.contains(list[i].id),
                onTap:       () => _openDetails(list[i]),
                animIndex:   i,
              ),
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// TOURNAMENT LIST CARD
// Vertical card for list-view display
// ─────────────────────────────────────────────
class _TournamentListCard extends StatefulWidget {
  final TournamentModel tournament;
  final bool            isJoined;
  final VoidCallback    onTap;
  final int             animIndex;

  const _TournamentListCard({
    required this.tournament,
    required this.isJoined,
    required this.onTap,
    required this.animIndex,
  });

  @override
  State<_TournamentListCard> createState() => _TournamentListCardState();
}

class _TournamentListCardState extends State<_TournamentListCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset>   _slide;
  late Animation<double>   _fade;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);

    Future.delayed(Duration(milliseconds: 60 * widget.animIndex), () {
      if (mounted) _slideCtrl.forward();
    });
  }

  @override
  void dispose() { _slideCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _C.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: t.status == TournamentStatus.live
                      ? _C.live.withValues(alpha: 0.35)
                      : widget.isJoined
                          ? _C.success.withValues(alpha: 0.3)
                          : _C.border,
                  width: (t.status == TournamentStatus.live || widget.isJoined) ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: t.status == TournamentStatus.live
                        ? _C.live.withValues(alpha: 0.06)
                        : _C.purple.withValues(alpha: 0.06),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    // ── Left accent bar ────────
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: _statusAccentColor(t),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                      ),
                    ),
                    // ── Content ────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: badges
                            Row(
                              children: [
                                _StatusPill(t.status),
                                const SizedBox(width: 6),
                                _TypePill(t.tournamentType),
                                if (widget.isJoined) ...[
                                  const SizedBox(width: 6),
                                  _JoinedPill(),
                                ],
                                const Spacer(),
                                Text(
                                  t.startTimeDisplay,
                                  style: const TextStyle(
                                    color: _C.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Row 2: title
                            Text(
                              t.title,
                              style: const TextStyle(
                                color: _C.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.subtitle,
                              style: const TextStyle(
                                color: _C.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Row 3: stats
                            Row(
                              children: [
                                _Stat(
                                  icon: Icons.emoji_events_rounded,
                                  color: _C.gold,
                                  value: t.prizePoolDisplay,
                                ),
                                const SizedBox(width: 16),
                                _Stat(
                                  icon: Icons.people_rounded,
                                  color: _C.purpleLight,
                                  value: '${t.joinedPlayers}/${t.maxPlayers}',
                                ),
                                const SizedBox(width: 16),
                                _Stat(
                                  icon: Icons.payments_rounded,
                                  color: t.entryFee > 0
                                      ? _C.textSecondary
                                      : _C.success,
                                  value: t.entryFeeDisplay,
                                ),
                                const Spacer(),
                                // Chevron
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _C.purpleGlowFaint,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: _C.purple,
                                    size: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Row 4: progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: t.fillPercent,
                                minHeight: 3,
                                backgroundColor: _C.surfaceElevated,
                                valueColor: AlwaysStoppedAnimation(
                                  t.isAlmostFull ? _C.live : _C.purple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _statusAccentColor(TournamentModel t) {
    switch (t.status) { //error on switch
      case TournamentStatus.live:      return _C.live;
      case TournamentStatus.completed: return _C.textMuted;
      case TournamentStatus.upcoming:  return _C.purple;
      case TournamentStatus.cancelled: return _C.textMuted; 
    }
  }
}

// ── Small badge pills ────────────────────────
class _StatusPill extends StatelessWidget {
  final TournamentStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case TournamentStatus.live:
        color = _C.live; label = '● LIVE'; break;
      case TournamentStatus.completed:
        color = _C.textMuted; label = 'ENDED'; break;
      case TournamentStatus.upcoming:
        color = _C.gold; label = 'UPCOMING'; break;
          case TournamentStatus.cancelled:
    color = _C.textMuted; label = 'CANCELLED';   break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(
        color: color, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8,
      )),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String type;
  const _TypePill(this.type);

  static const _labels = {
    'battle_royale': '🗺️ Full Map',
    'clash_squad':   '⚔️ Clash Squad',
    'lone_wolf':     '🎯 Lone Wolf',
    'league':        '🏆 League',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[type] ?? type;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _C.border),
      ),
      child: Text(label, style: const TextStyle(
        color: _C.textSecondary, fontSize: 9, fontWeight: FontWeight.w700,
      )),
    );
  }
}

class _JoinedPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _C.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _C.success.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: _C.success, size: 9),
          SizedBox(width: 3),
          Text('JOINED', style: TextStyle(
            color: _C.success, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   value;
  const _Stat({required this.icon, required this.color, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700,
        )),
      ],
    );
  }
}

// ── Shimmer loading card ─────────────────────
class _ListCardShimmer extends StatefulWidget {
  const _ListCardShimmer();

  @override
  State<_ListCardShimmer> createState() => _ListCardShimmerState();
}

class _ListCardShimmerState extends State<_ListCardShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        height: 110,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: _C.surfaceCard.withValues(alpha: 0.5 + 0.3 * _anim.value),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.border),
        ),
      ),
    );
  }
}

// ── Error / Empty states ─────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _C.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.live.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: _C.live, size: 32),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String statusFilter;
  final String typeFilter;
  const _EmptyState({required this.statusFilter, required this.typeFilter});

  @override
  Widget build(BuildContext context) {
    final typeLabel = _typeOptions
        .firstWhere((o) => o.value == typeFilter,
            orElse: () => const _TypeOption(value: '', label: 'selected', emoji: ''))
        .label;

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _C.purpleGlowFaint,
              shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: const Icon(Icons.search_off_rounded, color: _C.purple, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('No tournaments found',
            style: TextStyle(
              color: _C.textPrimary, fontSize: 16, fontWeight: FontWeight.w700,
            )),
          const SizedBox(height: 6),
          Text(
            'No $typeLabel tournaments\nmatching "$statusFilter" filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _C.textSecondary, fontSize: 13, height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}