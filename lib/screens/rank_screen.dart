// lib/screens/ranks_screen.dart
// ─────────────────────────────────────────────
// RANKS SCREEN  (v1)
// Weekly leaderboard based on:
//   • Highest earnings
//   • Highest tournament wins
//   • Highest withdrawals
// Features:
//   • Top-3 animated podium
//   • Tab-based leaderboard filter (Earnings / Wins / Withdrawals)
//   • Animated entry cards
//   • Realtime Firestore integration
//   • Weekly reset label
// ─────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS  (same as HomeScreen)
// ─────────────────────────────────────────────
class _C {
  // static const background      = Color(0xFF06040E);
  // static const surface         = Color(0xFF0E0A1A);
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
  // static const goldGlow        = Color(0x55FFCC44);
  static const silver          = Color(0xFFB8C7D4);
  static const bronze          = Color(0xFFCD7F32);
  // static const live            = Color(0xFFFF4466);
  // static const success         = Color(0xFF44FF99);

  static const border          = Color(0x337B3FE4);
  // static const borderBright    = Color(0x667B3FE4);
}

// ─────────────────────────────────────────────
// LEADERBOARD ENTRY MODEL
// ─────────────────────────────────────────────
class LeaderboardEntry {
  final String uid;
  final String name;
  final String ign;          // In-Game Name
  final String photoUrl;
  final double totalEarnings;
  final int    totalWins;
  final double totalWithdrawals;
  final int    rank;

  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.ign,
    required this.photoUrl,
    required this.totalEarnings,
    required this.totalWins,
    required this.totalWithdrawals,
    required this.rank,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> data, int rank) {
    return LeaderboardEntry(
      uid:               data['uid']               as String? ?? '',
      name:              data['name']              as String? ?? 'Unknown',
      ign:               data['ign']               as String? ?? 'Player',
      photoUrl:          data['photoUrl']          as String? ?? '',
      totalEarnings:     (data['totalEarnings']    as num?)?.toDouble() ?? 0.0,
      totalWins:         (data['totalWins']        as num?)?.toInt()    ?? 0,
      totalWithdrawals:  (data['totalWithdrawals'] as num?)?.toDouble() ?? 0.0,
      rank:              rank,
    );
  }
}

// ─────────────────────────────────────────────
// LEADERBOARD SERVICE
// Reads from Firestore: weekly_leaderboard/{weekId}/entries/
// ─────────────────────────────────────────────
class LeaderboardService {
  static final LeaderboardService instance = LeaderboardService._();
  LeaderboardService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns the current ISO week id like "2025-W23"
  String get _currentWeekId {
    final now  = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    final week = ((now.difference(jan1).inDays + jan1.weekday) / 7).ceil();
    return '${now.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Stream of leaderboard entries sorted by [sortField] descending.
  /// Firestore collection: weekly_leaderboard/{weekId}/entries
  Stream<List<LeaderboardEntry>> leaderboardStream(String sortField) {
    return _db
        .collection('weekly_leaderboard')
        .doc(_currentWeekId)
        .collection('entries')
        .orderBy(sortField, descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      return snap.docs.asMap().entries.map((e) {
        return LeaderboardEntry.fromMap(
          e.value.data(),
          e.key + 1, // 1-based rank
        );
      }).toList();
    });
  }

  /// Week label e.g. "Week 23 · 2025"
  String get weekLabel {
    final now  = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    final week = ((now.difference(jan1).inDays + jan1.weekday) / 7).ceil();
    return 'Week $week · ${now.year}';
  }

  /// Next Monday midnight (week reset)
  DateTime get nextReset {
    final now  = DateTime.now();
    final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
    final reset = daysUntilMonday == 0
        ? now.add(const Duration(days: 7))
        : now.add(Duration(days: daysUntilMonday));
    return DateTime(reset.year, reset.month, reset.day);
  }
}

// ─────────────────────────────────────────────
// RANKS SCREEN
// ─────────────────────────────────────────────
class RanksScreen extends StatefulWidget {
  const RanksScreen({super.key});

  @override
  State<RanksScreen> createState() => _RanksScreenState();
}

class _RanksScreenState extends State<RanksScreen>
    with TickerProviderStateMixin {

  final LeaderboardService _svc = LeaderboardService.instance;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  late TabController _tabCtrl;

  // Tab config: label → Firestore field
  static const _tabs = [
    ('💰 Earnings',    'totalEarnings'),
    ('🏆 Wins',        'totalWins'),
    ('💸 Withdrawals', 'totalWithdrawals'),
  ];

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeIn;

  // Countdown timer
  late Timer _countdownTimer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();

    _tabCtrl  = TabController(length: _tabs.length, vsync: this);
    _fadeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);

    _computeTimeLeft();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_computeTimeLeft);
    });
  }

  void _computeTimeLeft() {
    _timeLeft = _svc.nextReset.difference(DateTime.now());
    if (_timeLeft.isNegative) _timeLeft = Duration.zero;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _fadeCtrl.dispose();
    _countdownTimer.cancel();
    super.dispose();
  }

  String _fmtCountdown(Duration d) {
    final h  = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m  = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s  = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inDays}d $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + 64 + 12;

    return FadeTransition(
      opacity: _fadeIn,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPad)),

          // ── Header ──────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Tab bar ─────────────────────────────
          SliverToBoxAdapter(child: _buildTabBar()),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // ── Tab content ─────────────────────────
          SliverToBoxAdapter(child: _buildTabContent()),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ── HEADER ──────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 18,
            decoration: BoxDecoration(
              color: _C.gold, borderRadius: BorderRadius.circular(2),
            )),
          const SizedBox(width: 8),
          Text('WEEKLY', style: const TextStyle(
            color: _C.textSecondary, fontSize: 12,
            fontWeight: FontWeight.w700, letterSpacing: 1.5,
          )),
          const SizedBox(width: 5),
          Text('LEADERBOARD', style: const TextStyle(
            color: _C.gold, fontSize: 12,
            fontWeight: FontWeight.w700, letterSpacing: 1.5,
          )),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _C.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.timer_outlined, color: _C.gold, size: 13),
              const SizedBox(width: 5),
              Text(_fmtCountdown(_timeLeft), style: const TextStyle(
                color: _C.gold, fontSize: 11, fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              )),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        Text(_svc.weekLabel, style: const TextStyle(
          color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500,
        )),
        const SizedBox(height: 4),
        const Text(
          'Resets every Monday at midnight',
          style: TextStyle(color: _C.textMuted, fontSize: 10),
        ),
      ]),
    );
  }

  // ── TAB BAR ─────────────────────────────────
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _C.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.border),
        ),
        child: TabBar(
          controller: _tabCtrl,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_C.purpleDim, _C.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: _C.purpleGlow, blurRadius: 8)],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: _C.textMuted,
          labelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500,
          ),
          tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
        ),
      ),
    );
  }

  // ── TAB CONTENT ─────────────────────────────
  Widget _buildTabContent() {
    return SizedBox(
      // Needs a fixed height inside a CustomScrollView
      height: MediaQuery.of(context).size.height * 0.85,
      child: TabBarView(
        controller: _tabCtrl,
        children: _tabs.map((t) {
          return _LeaderboardTabContent(
            sortField: t.$2,
            myUid:     _myUid,
            service:   _svc,
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LEADERBOARD TAB CONTENT
// Handles stream + podium + list
// ─────────────────────────────────────────────
class _LeaderboardTabContent extends StatelessWidget {
  final String             sortField;
  final String?            myUid;
  final LeaderboardService service;

  const _LeaderboardTabContent({
    required this.sortField,
    required this.myUid,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LeaderboardEntry>>(
      stream: service.leaderboardStream(sortField),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: _LoadingIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(message: 'Could not load leaderboard.');
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return const _EmptyState(message: 'No data yet for this week.\nBe the first to compete!');
        }

        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // Podium (top 3)
            if (entries.length >= 3) ...[
              const SizedBox(height: 8),
              _PodiumSection(
                entries:   entries.take(3).toList(),
                sortField: sortField,
              ),
              const SizedBox(height: 20),
            ],

            // Rest of list (4th onwards)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: entries.skip(entries.length >= 3 ? 3 : 0)
                    .toList()
                    .asMap()
                    .entries
                    .map((e) => _LeaderboardCard(
                          entry:     e.value,
                          sortField: sortField,
                          isMe:      e.value.uid == myUid,
                          delay:     e.key,
                        ))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// PODIUM SECTION  — top 3 trophy display
// ─────────────────────────────────────────────
class _PodiumSection extends StatefulWidget {
  final List<LeaderboardEntry> entries;   // exactly 3 entries
  final String                 sortField;
  const _PodiumSection({required this.entries, required this.sortField});

  @override
  State<_PodiumSection> createState() => _PodiumSectionState();
}

class _PodiumSectionState extends State<_PodiumSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Reorder for podium display: 2nd | 1st | 3rd
    final List<LeaderboardEntry?> podium = [
      widget.entries.length > 1 ? widget.entries[1] : null,
      widget.entries.isNotEmpty  ? widget.entries[0] : null,
      widget.entries.length > 2 ? widget.entries[2] : null,
    ];

    final heights = [100.0, 130.0, 80.0]; // 2nd, 1st, 3rd platform heights

    return ScaleTransition(
      scale: _anim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _C.border),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1535), _C.surfaceCard],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final entry = podium[i];
              final rankNum = i == 0 ? 2 : (i == 1 ? 1 : 3);
              return Expanded(child: _PodiumSlot(
                entry:    entry,
                rank:     rankNum,
                height:   heights[i],
                sortField: widget.sortField,
              ));
            }),
          ),
        ),
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final LeaderboardEntry? entry;
  final int               rank;
  final double            height;
  final String            sortField;

  const _PodiumSlot({
    required this.entry, required this.rank,
    required this.height, required this.sortField,
  });

  Color get _rankColor => switch (rank) {
    1 => _C.gold,
    2 => _C.silver,
    _ => _C.bronze,
  };

  String get _rankEmoji => switch (rank) {
    1 => '👑',
    2 => '🥈',
    _ => '🥉',
  };

  String _valueStr(LeaderboardEntry e) => switch (sortField) {
    'totalWins'        => '${e.totalWins} W',
    'totalWithdrawals' => '₹${e.totalWithdrawals.toStringAsFixed(0)}',
    _                  => '₹${e.totalEarnings.toStringAsFixed(0)}',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Crown / medal
        Text(_rankEmoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),

        // Avatar
        if (entry != null) ...[
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _rankColor, width: 2.5),
              boxShadow: [BoxShadow(
                color: _rankColor.withValues(alpha: 0.4), blurRadius: 10,
              )],
            ),
            child: ClipOval(
              child: entry!.photoUrl.isNotEmpty
                  ? Image.network(entry!.photoUrl, fit: BoxFit.cover)
                  : Container(
                      color: _C.surfaceElevated,
                      child: Center(child: Text(
                        (entry!.name.isNotEmpty ? entry!.name[0] : '?').toUpperCase(),
                        style: TextStyle(color: _rankColor, fontWeight: FontWeight.w900, fontSize: 20),
                      )),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(entry!.ign,
            style: const TextStyle(
              color: _C.textPrimary, fontSize: 11, fontWeight: FontWeight.w700,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(_valueStr(entry!),
            style: TextStyle(color: _rankColor, fontSize: 10, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: _C.surfaceElevated,
              border: Border.all(color: _C.border),
            ),
            child: const Center(child: Icon(Icons.person_outline, color: _C.textMuted, size: 24)),
          ),
          const SizedBox(height: 6),
          const Text('—', style: TextStyle(color: _C.textMuted, fontSize: 12)),
        ],
        const SizedBox(height: 6),

        // Platform
        Container(
          width: double.infinity, height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [
                _rankColor.withValues(alpha: 0.2),
                _rankColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border(
              top:   BorderSide(color: _rankColor.withValues(alpha: 0.5), width: 1),
              left:  BorderSide(color: _rankColor.withValues(alpha: 0.2), width: 1),
              right: BorderSide(color: _rankColor.withValues(alpha: 0.2), width: 1),
            ),
          ),
          child: Center(
            child: Text('#$rank', style: TextStyle(
              color: _rankColor, fontSize: 22, fontWeight: FontWeight.w900,
            )),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// LEADERBOARD CARD  (4th place onwards)
// ─────────────────────────────────────────────
class _LeaderboardCard extends StatefulWidget {
  final LeaderboardEntry entry;
  final String           sortField;
  final bool             isMe;
  final int              delay; // stagger index

  const _LeaderboardCard({
    required this.entry, required this.sortField,
    required this.isMe,  required this.delay,
  });

  @override
  State<_LeaderboardCard> createState() => _LeaderboardCardState();
}

class _LeaderboardCardState extends State<_LeaderboardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _slide;
  late Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400),
    );
    _slide   = Tween(begin: 30.0, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    Future.delayed(Duration(milliseconds: 50 + widget.delay * 60), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String _valueStr() => switch (widget.sortField) {
    'totalWins'        => '${widget.entry.totalWins} Wins',
    'totalWithdrawals' => '₹${widget.entry.totalWithdrawals.toStringAsFixed(0)}',
    _                  => '₹${widget.entry.totalEarnings.toStringAsFixed(0)}',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: Offset(0, _slide.value),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isMe
              ? _C.purple.withValues(alpha: 0.08)
              : _C.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isMe ? _C.purple.withValues(alpha: 0.4) : _C.border,
            width: widget.isMe ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // Rank number
          SizedBox(
            width: 32,
            child: Text('#${widget.entry.rank}',
              style: TextStyle(
                color: _C.textMuted, fontSize: 13, fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),

          // Avatar
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isMe ? _C.purple : _C.border, width: 1.5,
              ),
            ),
            child: ClipOval(
              child: widget.entry.photoUrl.isNotEmpty
                  ? Image.network(widget.entry.photoUrl, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _AvatarFallback(name: widget.entry.name))
                  : _AvatarFallback(name: widget.entry.name),
            ),
          ),
          const SizedBox(width: 12),

          // Name + IGN
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(widget.entry.name,
                style: const TextStyle(
                  color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              )),
              if (widget.isMe) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _C.purpleGlowFaint,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _C.purple.withValues(alpha: 0.4)),
                  ),
                  child: const Text('YOU', style: TextStyle(
                    color: _C.purpleLight, fontSize: 8, fontWeight: FontWeight.w800,
                  )),
                ),
              ],
            ]),
            Text(widget.entry.ign,
              style: const TextStyle(
                color: _C.textMuted, fontSize: 11, fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ])),

          // Value
          Text(_valueStr(),
            style: const TextStyle(
              color: _C.gold, fontSize: 13, fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// UTILITY WIDGETS
// ─────────────────────────────────────────────
class _AvatarFallback extends StatelessWidget {
  final String name;
  const _AvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.surfaceElevated,
      child: Center(child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: _C.purple, fontWeight: FontWeight.w900, fontSize: 16,
        ),
      )),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: const [
      SizedBox(
        width: 36, height: 36,
        child: CircularProgressIndicator(
          color: _C.purple, strokeWidth: 2,
        ),
      ),
      SizedBox(height: 12),
      Text('Loading leaderboard…',
        style: TextStyle(color: _C.textMuted, fontSize: 12)),
    ]);
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF4466), size: 40),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: _C.textSecondary, fontSize: 13),
          textAlign: TextAlign.center),
      ]),
    ));
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏆', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(message,
          style: const TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center),
      ]),
    ));
  }
}

// ════════════════════════════════════════════
// FIRESTORE COLLECTION STRUCTURE (docs only)
// ════════════════════════════════════════════
//
//  weekly_leaderboard/
//    {weekId}/               ← e.g. "2025-W23"
//      entries/
//        {uid}/
//          uid:              String
//          name:             String
//          ign:              String  ← In-Game Name
//          photoUrl:         String
//          totalEarnings:    Number  (updated by Cloud Function on winnings)
//          totalWins:        Number  (updated by Cloud Function on tournament end)
//          totalWithdrawals: Number  (updated by Cloud Function on approved withdrawal)
//
// Recommended: Cloud Function triggers on wallet_transactions writes
// to aggregate into weekly_leaderboard/{weekId}/entries/{uid}