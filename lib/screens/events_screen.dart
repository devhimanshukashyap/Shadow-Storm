// lib/screens/events_screen.dart
// ─────────────────────────────────────────────
// EVENTS SCREEN  (v1)
// Player tournament dashboard — shows only tournaments
// the logged-in user has joined, split into:
//   • Upcoming  — registered, not started
//   • Ongoing   — currently live
//   • Completed — match finished
//
// Architecture:
//   • Single Firestore collectionGroup query on 'participants'
//   • Joins tournament docs in batches of 30
//   • Real-time stream via joinedTournamentsStream
//   • Participant data fetched per-card for placement/kills/winnings
// ─────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';
import '../services/tournament_service.dart';
import 'tournament_details_screen.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS  (mirrors Shadow Storm palette)
// ─────────────────────────────────────────────
class _C {
  static const background = Color(0xFF06040E);
  static const surfaceCard = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);

  static const purple = Color(0xFF9D55FF);
  static const purpleLight = Color(0xFFB07EF8);
  static const purpleGlowFaint = Color(0x229D55FF);

  static const textPrimary = Color(0xFFEDE0FF);
  static const textSecondary = Color(0xFF9B8DC0);
  static const textMuted = Color(0xFF5A4E80);

  static const gold = Color(0xFFFFCC44);
  static const live = Color(0xFFFF4466);
  static const liveGlow = Color(0x55FF4466);
  static const success = Color(0xFF44FF99);
  static const border = Color(0x337B3FE4);
}

// ─────────────────────────────────────────────
// PARTICIPANT MODEL
// Firestore: tournaments/{id}/participants/{uid}
// ─────────────────────────────────────────────
class ParticipantData {
  final String userId;
  final DateTime? joinedAt;
  final int? placement;
  final int? kills;
  final double? winnings;
  final String
  status; // 'registered' | 'playing' | 'completed' | 'disqualified'

  const ParticipantData({
    required this.userId,
    this.joinedAt,
    this.placement,
    this.kills,
    this.winnings,
    required this.status,
  });

  factory ParticipantData.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ParticipantData(
      userId: d['userId'] as String? ?? doc.id,
      joinedAt: (d['joinedAt'] as Timestamp?)?.toDate(),
      placement: (d['placement'] as num?)?.toInt(),
      kills: (d['kills'] as num?)?.toInt(),
      winnings: (d['winnings'] as num?)?.toDouble(),
      status: d['status'] as String? ?? 'registered',
    );
  }
}

// ─────────────────────────────────────────────
// EVENTS SCREEN
// ─────────────────────────────────────────────
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeIn;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  final TournamentService _service = TournamentService.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get _user => FirebaseAuth.instance.currentUser;
  String? get _userId => _user?.uid;

  // Cache of participant data keyed by tournamentId
  final Map<String, ParticipantData> _participantCache = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Fetch participant data for a tournament ──
  Future<ParticipantData?> _getParticipant(String tournamentId) async {
    if (_userId == null) return null;
    if (_participantCache.containsKey(tournamentId)) {
      return _participantCache[tournamentId];
    }
    try {
      final doc = await _db
          .collection('tournaments')
          .doc(tournamentId)
          .collection('participants')
          .doc(_userId)
          .get();
      if (!doc.exists) return null;
      final p = ParticipantData.fromDoc(doc);
      _participantCache[tournamentId] = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  // ── Navigate to details ──────────────────────
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

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: FadeTransition(
        opacity: _fadeIn,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (_, _) => [_buildAppBar()],
          body: TabBarView(
            controller: _tabCtrl,
            children: [
              _EventsTab(
                userId: _userId,
                statusFilter: TournamentStatus.upcoming,
                service: _service,
                pulse: _pulse,
                onTap: _openDetails,
                getParticipant: _getParticipant,
              ),
              _EventsTab(
                userId: _userId,
                statusFilter: TournamentStatus.live,
                service: _service,
                pulse: _pulse,
                onTap: _openDetails,
                getParticipant: _getParticipant,
              ),
              _EventsTab(
                userId: _userId,
                statusFilter: TournamentStatus.completed,
                service: _service,
                pulse: _pulse,
                onTap: _openDetails,
                getParticipant: _getParticipant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // APP BAR + TAB BAR
  // ─────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: _C.background,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _C.purple,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'MY EVENTS',
                  style: TextStyle(
                    color: _C.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'DASHBOARD',
                  style: TextStyle(
                    color: _C.purple,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _user?.displayName ?? 'Player',
              style: const TextStyle(
                color: _C.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Column(
          children: [
            Container(height: 1, color: _C.border),
            TabBar(
              controller: _tabCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicator: const BoxDecoration(),
              dividerColor: Colors.transparent,
              tabs: [
                _EventTab(
                  label: 'UPCOMING',
                  icon: Icons.schedule_rounded,
                  color: _C.gold,
                  tabCtrl: _tabCtrl,
                ),
                _EventTab(
                  label: 'ONGOING',
                  icon: Icons.radio_button_checked,
                  color: _C.live,
                  tabCtrl: _tabCtrl,
                ),
                _EventTab(
                  label: 'COMPLETED',
                  icon: Icons.check_circle_outline_rounded,
                  color: _C.success,
                  tabCtrl: _tabCtrl,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CUSTOM TAB WIDGET
// Passes TabController explicitly — avoids the
// DefaultTabController.of() crash that occurs because
// EventsScreen owns its own TabController and never
// wraps children in a DefaultTabController.
// ─────────────────────────────────────────────
class _EventTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final TabController tabCtrl;

  const _EventTab({
    required this.label,
    required this.icon,
    required this.color,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: _TabChip(label: label, icon: icon, color: color, tabCtrl: tabCtrl),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final TabController tabCtrl;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    const tabs = ['UPCOMING', 'ONGOING', 'COMPLETED'];
    final idx = tabs.indexOf(label);

    return AnimatedBuilder(
      animation: tabCtrl,
      builder: (_, _) {
        final selected = tabCtrl.index == idx;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : _C.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.5) : _C.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? color : _C.textMuted, size: 12),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : _C.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// EVENTS TAB  (one per status)
// ─────────────────────────────────────────────
class _EventsTab extends StatelessWidget {
  final String? userId;
  final TournamentStatus statusFilter;
  final TournamentService service;
  final Animation<double> pulse;
  final void Function(TournamentModel) onTap;
  final Future<ParticipantData?> Function(String) getParticipant;

  const _EventsTab({
    required this.userId,
    required this.statusFilter,
    required this.service,
    required this.pulse,
    required this.onTap,
    required this.getParticipant,
  });

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const _NotLoggedIn();
    }

    return RefreshIndicator(
      color: _C.purple,
      backgroundColor: _C.surfaceCard,
      onRefresh: () async {
        // Stream auto-refreshes; just add a small delay for UX feel
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: StreamBuilder<List<TournamentModel>>(
        stream: service.joinedTournamentsStream(userId!),
        builder: (context, snap) {
          // Loading
          if (snap.connectionState == ConnectionState.waiting) {
            return _LoadingList();
          }
          // Error
          if (snap.hasError) {
            return _ErrorState(message: snap.error.toString());
          }

          // Filter by status
          final all = snap.data ?? [];
          final filtered = all.where((t) => t.status == statusFilter).toList();

          if (filtered.isEmpty) {
            return _EmptyState(status: statusFilter);
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final tournament = filtered[i];
              return _EventCardWrapper(
                tournament: tournament,
                statusFilter: statusFilter,
                pulse: pulse,
                onTap: onTap,
                getParticipant: getParticipant,
                animIndex: i,
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// EVENT CARD WRAPPER
// Fetches participant data then renders correct card type
// ─────────────────────────────────────────────
class _EventCardWrapper extends StatefulWidget {
  final TournamentModel tournament;
  final TournamentStatus statusFilter;
  final Animation<double> pulse;
  final void Function(TournamentModel) onTap;
  final Future<ParticipantData?> Function(String) getParticipant;
  final int animIndex;

  const _EventCardWrapper({
    required this.tournament,
    required this.statusFilter,
    required this.pulse,
    required this.onTap,
    required this.getParticipant,
    required this.animIndex,
  });

  @override
  State<_EventCardWrapper> createState() => _EventCardWrapperState();
}

class _EventCardWrapperState extends State<_EventCardWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  ParticipantData? _participant;
  bool _loadingP = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut);

    Future.delayed(Duration(milliseconds: 60 * widget.animIndex), () {
      if (mounted) _slideCtrl.forward();
    });

    _loadParticipant();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadParticipant() async {
    final p = await widget.getParticipant(widget.tournament.id);
    if (mounted) {
      setState(() {
        _participant = p;
        _loadingP = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    switch (widget.statusFilter) {
      //error on switch
      case TournamentStatus.upcoming:
        return UpcomingEventCard(
          tournament: widget.tournament,
          participant: _participant,
          onTap: widget.onTap,
        );
      case TournamentStatus.live:
        return OngoingEventCard(
          tournament: widget.tournament,
          participant: _participant,
          pulse: widget.pulse,
          onTap: widget.onTap,
        );
      case TournamentStatus.completed:
        return CompletedEventCard(
          tournament: widget.tournament,
          participant: _participant,
          onTap: widget.onTap,
        );
      case TournamentStatus.cancelled:
        return CompletedEventCard(
          tournament: widget.tournament,
          participant: _participant,
          onTap: widget.onTap,
        );
    }
  }
}

// ═════════════════════════════════════════════
// ── UPCOMING EVENT CARD ───────────────────────
// ═════════════════════════════════════════════
class UpcomingEventCard extends StatefulWidget {
  final TournamentModel tournament;
  final ParticipantData? participant;
  final void Function(TournamentModel) onTap;

  const UpcomingEventCard({
    super.key,
    required this.tournament,
    required this.participant,
    required this.onTap,
  });

  @override
  State<UpcomingEventCard> createState() => _UpcomingEventCardState();
}

class _UpcomingEventCardState extends State<UpcomingEventCard> {
  Timer? _timer;
  Duration _matchCountdown = Duration.zero;
  Duration _revealCountdown = Duration.zero;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateCountdowns();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdowns();
    });
  }

  void _updateCountdowns() {
    final now = DateTime.now();
    final startTime = widget.tournament.startTime;
    if (startTime == null) return;

    final matchDiff = startTime.difference(now);
    // Room reveal is 30 min before match
    final revealTime = startTime.subtract(const Duration(minutes: 30));
    final revealDiff = revealTime.difference(now);

    setState(() {
      _matchCountdown = matchDiff.isNegative ? Duration.zero : matchDiff;
      _revealCountdown = revealDiff.isNegative ? Duration.zero : revealDiff;
    });
  }

  bool get _roomRevealed =>
      widget.tournament.startTime != null &&
      DateTime.now().isAfter(
        widget.tournament.startTime!.subtract(const Duration(minutes: 30)),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return GestureDetector(
      onTap: () => widget.onTap(t),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _C.gold.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(color: _C.gold.withValues(alpha: 0.04), blurRadius: 16),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner ────────────────────────
              _BannerImage(
                bannerUrl: t.bannerUrl,
                tournamentType: t.tournamentType,
              ),

              // ── Body ──────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.title,
                            style: const TextStyle(
                              color: _C.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _JoinedPill(),
                      ],
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

                    const SizedBox(height: 14),

                    // Stats row
                    Row(
                      children: [
                        _MiniStat(
                          icon: Icons.emoji_events_rounded,
                          label: 'PRIZE',
                          value: t.prizePoolDisplay,
                          color: _C.gold,
                        ),
                        const SizedBox(width: 12),
                        _MiniStat(
                          icon: Icons.payments_rounded,
                          label: 'ENTRY',
                          value: t.entryFeeDisplay,
                          color: t.entryFee > 0 ? _C.textSecondary : _C.success,
                        ),
                        const SizedBox(width: 12),
                        _MiniStat(
                          icon: Icons.people_rounded,
                          label: 'SLOTS',
                          value: '${t.joinedPlayers}/${t.maxPlayers}',
                          color: _C.purpleLight,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Container(height: 1, color: _C.border),
                    const SizedBox(height: 14),

                    // Countdown row
                    Row(
                      children: [
                        Expanded(
                          child: _CountdownBlock(
                            label: 'MATCH STARTS IN',
                            duration: _matchCountdown,
                            color: _C.gold,
                            icon: Icons.schedule_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _roomRevealed
                              ? _RoomReadyBlock()
                              : _CountdownBlock(
                                  label: 'ROOM REVEAL IN',
                                  duration: _revealCountdown,
                                  color: _C.purple,
                                  icon: Icons.lock_clock_rounded,
                                ),
                        ),
                      ],
                    ),

                    // Room reveal state
                    if (_roomRevealed) ...[
                      const SizedBox(height: 14),
                      _RoomRevealedSection(tournament: t),
                    ],

                    const SizedBox(height: 14),

                    // Quick access button
                    _QuickAccessButton(
                      label: 'VIEW TOURNAMENT',
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: () => widget.onTap(t),
                      color: _C.gold,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ── ONGOING EVENT CARD ────────────────────────
// ═════════════════════════════════════════════
class OngoingEventCard extends StatefulWidget {
  final TournamentModel tournament;
  final ParticipantData? participant;
  final Animation<double> pulse;
  final void Function(TournamentModel) onTap;

  const OngoingEventCard({
    super.key,
    required this.tournament,
    required this.participant,
    required this.pulse,
    required this.onTap,
  });

  @override
  State<OngoingEventCard> createState() => _OngoingEventCardState();
}

class _OngoingEventCardState extends State<OngoingEventCard> {
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _C.success, size: 16),
            const SizedBox(width: 8),
            Text(
              '$label copied!',
              style: const TextStyle(color: _C.textPrimary),
            ),
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

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return GestureDetector(
      onTap: () => widget.onTap(t),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedBuilder(
          animation: widget.pulse,
          builder: (_, child) => Container(
            decoration: BoxDecoration(
              color: _C.surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _C.live.withValues(
                  alpha: 0.25 + 0.15 * widget.pulse.value,
                ),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _C.live.withValues(
                    alpha: 0.05 + 0.04 * widget.pulse.value,
                  ),
                  blurRadius: 20,
                ),
              ],
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Live header strip ─────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _C.live.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(
                    bottom: BorderSide(color: _C.live.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    _LiveDot(),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE NOW',
                      style: TextStyle(
                        color: _C.live,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    _JoinedPill(),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tournament title
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: _C.textPrimary,
                        fontSize: 17,
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

                    const SizedBox(height: 14),

                    // Player count + prize
                    Row(
                      children: [
                        _MiniStat(
                          icon: Icons.people_rounded,
                          label: 'IN MATCH',
                          value: '${t.joinedPlayers}/${t.maxPlayers}',
                          color: _C.purpleLight,
                        ),
                        const SizedBox(width: 12),
                        _MiniStat(
                          icon: Icons.emoji_events_rounded,
                          label: 'PRIZE',
                          value: t.prizePoolDisplay,
                          color: _C.gold,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Container(height: 1, color: _C.border),
                    const SizedBox(height: 14),

                    // Room Details
                    _OngoingRoomSection(
                      tournament: t,
                      onCopy: _copyToClipboard,
                    ),

                    const SizedBox(height: 14),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: _QuickAccessButton(
                            label: 'TOURNAMENT DETAILS',
                            icon: Icons.info_outline_rounded,
                            onTap: () => widget.onTap(t),
                            color: _C.purple,
                            outline: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ── COMPLETED EVENT CARD ──────────────────────
// ═════════════════════════════════════════════
class CompletedEventCard extends StatefulWidget {
  final TournamentModel tournament;
  final ParticipantData? participant;
  final void Function(TournamentModel) onTap;

  const CompletedEventCard({
    super.key,
    required this.tournament,
    required this.participant,
    required this.onTap,
  });

  @override
  State<CompletedEventCard> createState() => _CompletedEventCardState();
}

class _CompletedEventCardState extends State<CompletedEventCard> {
  bool _pressed = false;

  Color get _resultColor {
    final placement = widget.participant?.placement;
    if (placement == null) return _C.textMuted;
    if (placement == 1) return _C.gold;
    if (placement <= 3) return const Color(0xFFC0C0C0);
    if (placement <= 10) return _C.success;
    return _C.textSecondary;
  }

  String get _resultLabel {
    final placement = widget.participant?.placement;
    if (placement == null) return 'N/A';
    if (placement == 1) return '🥇 WINNER';
    if (placement == 2) return '🥈 2nd';
    if (placement == 3) return '🥉 3rd';
    return '#$placement';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final p = widget.participant;
    final color = _resultColor;

    return GestureDetector(
      onTap: () => widget.onTap(t),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.04), blurRadius: 16),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Completed strip ───────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _C.surfaceElevated,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: Border(bottom: BorderSide(color: _C.border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: _C.textMuted,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'COMPLETED',
                      style: TextStyle(
                        color: _C.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (t.startTime != null)
                      Text(
                        _formatDate(t.startTime!),
                        style: const TextStyle(
                          color: _C.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                style: const TextStyle(
                                  color: _C.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t.modeDisplay,
                                style: const TextStyle(
                                  color: _C.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Placement badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            _resultLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Container(height: 1, color: _C.border),
                    const SizedBox(height: 16),

                    // Result summary row
                    Row(
                      children: [
                        _ResultStat(
                          icon: Icons.leaderboard_rounded,
                          label: 'PLACEMENT',
                          value: p?.placement != null
                              ? '#${p!.placement}'
                              : '—',
                          color: color,
                        ),
                        _VertDivider(),
                        _ResultStat(
                          icon: Icons.sports_kabaddi_rounded,
                          label: 'KILLS',
                          value: p?.kills?.toString() ?? '—',
                          color: _C.live,
                        ),
                        _VertDivider(),
                        _ResultStat(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'WINNINGS',
                          value: p?.winnings != null
                              ? '₹${p!.winnings!.toInt()}'
                              : '—',
                          color: p?.winnings != null && p!.winnings! > 0
                              ? _C.success
                              : _C.textMuted,
                        ),
                      ],
                    ),

                    // Winnings earned banner
                    if (p?.winnings != null && p!.winnings! > 0) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _C.success.withValues(alpha: 0.12),
                              _C.success.withValues(alpha: 0.04),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _C.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: _C.success,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'WINNINGS EARNED',
                                  style: TextStyle(
                                    color: _C.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  '₹${p.winnings!.toInt()}',
                                  style: const TextStyle(
                                    color: _C.success,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.check_circle_rounded,
                              color: _C.success,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    _QuickAccessButton(
                      label: 'VIEW DETAILS',
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: () => widget.onTap(t),
                      color: _C.textSecondary,
                      outline: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ─────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────

/// Banner image with graceful fallback
class _BannerImage extends StatelessWidget {
  final String? bannerUrl;
  final String tournamentType;
  const _BannerImage({this.bannerUrl, required this.tournamentType});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: SizedBox(
        height: 120,
        width: double.infinity,
        child: (bannerUrl != null && bannerUrl!.isNotEmpty)
            ? Image.network(
                bannerUrl!,
                fit: BoxFit.cover,
                color: Colors.black38,
                colorBlendMode: BlendMode.darken,
                errorBuilder: (_, _, _) =>
                    _FallbackBanner(tournamentType: tournamentType),
              )
            : _FallbackBanner(tournamentType: tournamentType),
      ),
    );
  }
}

class _FallbackBanner extends StatelessWidget {
  final String tournamentType;
  const _FallbackBanner({required this.tournamentType});

  static Color _accent(String type) {
    switch (type) {
      case 'clash_squad':
        return const Color(0xFFFF6B35);
      case 'lone_wolf':
        return const Color(0xFF00D4FF);
      case 'league':
        return _C.gold;
      default:
        return _C.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(tournamentType);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D0820),
            accent.withValues(alpha: 0.15),
            const Color(0xFF06040E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(painter: _MiniEsportsPainter(accent: accent)),
    );
  }
}

class _MiniEsportsPainter extends CustomPainter {
  final Color accent;
  const _MiniEsportsPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = accent.withValues(alpha: 0.07);
    for (var c = 0; c < 20; c++) {
      for (var r = 0; r < 8; r++) {
        canvas.drawCircle(Offset(c * 28.0, r * 28.0), 1.2, dot);
      }
    }
    final line = Paint()
      ..color = accent.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(size.width * 0.6 + i * 14, 0),
        Offset(size.width, size.height * 0.6 + i * 14),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniEsportsPainter old) => old.accent != accent;
}

/// Countdown block widget
class _CountdownBlock extends StatelessWidget {
  final String label;
  final Duration duration;
  final Color color;
  final IconData icon;
  const _CountdownBlock({
    required this.label,
    required this.duration,
    required this.color,
    required this.icon,
  });

  String _fmt(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays}d ${d.inHours.remainder(24)}h ${d.inMinutes.remainder(60)}m';
    }
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withValues(alpha: 0.7), size: 11),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            duration.inSeconds <= 0 ? 'NOW' : _fmt(duration),
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Room is ready to reveal indicator
class _RoomReadyBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.success.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.success.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open_rounded, color: _C.success, size: 11),
              const SizedBox(width: 4),
              Text(
                'ROOM REVEALED',
                style: TextStyle(
                  color: _C.success.withValues(alpha: 0.7),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'UNLOCKED',
            style: TextStyle(
              color: _C.success,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Room revealed section for Upcoming card (30min before)
class _RoomRevealedSection extends StatelessWidget {
  final TournamentModel tournament;
  const _RoomRevealedSection({required this.tournament});

  void _copy(BuildContext ctx, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied!',
          style: const TextStyle(color: _C.textPrimary),
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

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final hasRoom = t.roomId != null && t.roomId!.isNotEmpty;
    final hasPw = t.roomPassword != null && t.roomPassword!.isNotEmpty;

    if (!hasRoom && !hasPw) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _C.gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.gold.withValues(alpha: 0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: _C.gold, size: 16),
            SizedBox(width: 8),
            Text(
              'Room details loading soon…',
              style: TextStyle(
                color: _C.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (hasRoom)
          _CopyField(
            label: 'ROOM ID',
            value: t.roomId!,
            icon: Icons.meeting_room_rounded,
            onCopy: () => _copy(context, t.roomId!, 'Room ID'),
          ),
        if (hasRoom && hasPw) const SizedBox(height: 8),
        if (hasPw)
          _CopyField(
            label: 'PASSWORD',
            value: t.roomPassword!,
            icon: Icons.vpn_key_rounded,
            onCopy: () => _copy(context, t.roomPassword!, 'Password'),
          ),
      ],
    );
  }
}

/// Room section for Ongoing card
class _OngoingRoomSection extends StatelessWidget {
  final TournamentModel tournament;
  final void Function(String, String) onCopy;
  const _OngoingRoomSection({required this.tournament, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final hasRoom = t.roomId != null && t.roomId!.isNotEmpty;
    final hasPw = t.roomPassword != null && t.roomPassword!.isNotEmpty;

    if (!hasRoom && !hasPw) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _C.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_rounded, color: _C.purple, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room Details',
                    style: TextStyle(
                      color: _C.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Waiting for organiser to post room details.',
                    style: TextStyle(
                      color: _C.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ROOM ACCESS',
          style: TextStyle(
            color: _C.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        if (hasRoom)
          _CopyField(
            label: 'ROOM ID',
            value: t.roomId!,
            icon: Icons.meeting_room_rounded,
            onCopy: () => onCopy(t.roomId!, 'Room ID'),
            accentColor: _C.live,
          ),
        if (hasRoom && hasPw) const SizedBox(height: 8),
        if (hasPw)
          _CopyField(
            label: 'PASSWORD',
            value: t.roomPassword!,
            icon: Icons.vpn_key_rounded,
            onCopy: () => onCopy(t.roomPassword!, 'Password'),
            accentColor: _C.live,
          ),
      ],
    );
  }
}

/// Copyable field widget
class _CopyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onCopy;
  final Color accentColor;

  const _CopyField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onCopy,
    this.accentColor = _C.purple,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _C.textMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    color: _C.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Icon(Icons.copy_rounded, color: accentColor, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini stat chip
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _C.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Result stat (for completed card)
class _ResultStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _ResultStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: _C.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical divider
class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: _C.border,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

/// Joined pill badge
class _JoinedPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          Text(
            'JOINED',
            style: TextStyle(
              color: _C.success,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated Live Dot
class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _C.live.withValues(alpha: 0.5 + 0.5 * _anim.value),
          boxShadow: [
            BoxShadow(color: _C.liveGlow, blurRadius: 6 * _anim.value),
          ],
        ),
      ),
    );
  }
}

/// Quick access button
class _QuickAccessButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool outline;
  const _QuickAccessButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
    this.outline = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: outline ? Colors.transparent : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: outline ? 0.3 : 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, color: color, size: 12),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATE SCREENS
// ─────────────────────────────────────────────

class _NotLoggedIn extends StatelessWidget {
  const _NotLoggedIn();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _C.purpleGlowFaint,
              shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: const Icon(
              Icons.person_off_rounded,
              color: _C.purple,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Not Logged In',
            style: TextStyle(
              color: _C.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Login to see your tournaments.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      itemCount: 3,
      itemBuilder: (_, i) => _ShimmerCard(index: i),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  final int index;
  const _ShimmerCard({required this.index});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        height: 220,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: _C.surfaceCard.withValues(alpha: 0.4 + 0.3 * _anim.value),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.border),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _C.live.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: _C.live, size: 30),
              const SizedBox(height: 10),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: _C.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _C.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final TournamentStatus status;
  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    String emoji, title, subtitle;
    switch (status) {
      //error on switch
      case TournamentStatus.upcoming:
        emoji = '📅';
        title = 'No Upcoming Events';
        subtitle = 'Join a tournament from the Home screen\nto see it here.';
        break;
      case TournamentStatus.live:
        emoji = '🎮';
        title = 'No Ongoing Matches';
        subtitle =
            'You don\'t have any live tournaments\nright now. Check back soon!';
        break;
      case TournamentStatus.completed:
        emoji = '🏆';
        title = 'No Match History Yet';
        subtitle =
            'Completed tournaments will appear here\nafter your first match.';
        break;
      case TournamentStatus.cancelled:
        emoji = '❌';
        title = 'No Cancelled Events';
        subtitle = 'You have no cancelled tournaments.';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _C.purpleGlowFaint,
                shape: BoxShape.circle,
                border: Border.all(color: _C.border),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: _C.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _C.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
