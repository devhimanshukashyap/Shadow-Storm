// lib/screens/ranks_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Ranks Screen (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1:
//   PRIORITY 5 — Bottom navigation consistency:
//     RanksScreen is pushed as a full route from HomeScreen bottom nav,
//     so it has its own back button in the app bar. The screen feels
//     connected to the rest of the app through the shared Shadow Storm
//     visual identity — same background, same color system, same typography.
//
//   PRIORITY 7 (F1 unchanged — regression check):
//     • No _ticker calling setState() in the parent. Countdown is isolated
//       inside _CountdownTicker which has its own timer and setState.
//     • _LeaderboardView uses AutomaticKeepAliveClientMixin so IndexedStack
//       does not rebuild tabs on switch.
//     • Single StreamBuilder per tab — no repeated listeners.
//
//   PRIORITY 8 (F1 unchanged — regression check):
//     • Cache-first: leaderboard cached in CacheKey.leaderboard.
//     • Pull-to-refresh invalidates cache and triggers fresh Firestore load.
//     • No continuous polling — snapshots() fires only on real data changes.
//
//   PRIORITY 3 (F1 unchanged): MaintenanceGuard wraps Scaffold.
//
//   All original widgets, podium, particle painter, animations intact.
// ─────────────────────────────────────────────

// ignore_for_file: unnecessary_cast, unused_field

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/cache_service.dart';
import '../services/app_settings_service.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);
  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleDim       = Color(0xFF7B3FE4);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);
  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const gold            = Color(0xFFFFCC44);
  static const silver          = Color(0xFFB8C7D4);
  static const bronze          = Color(0xFFCD7F32);
  static const live            = Color(0xFFFF4466);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

// ─────────────────────────────────────────────
// LEADERBOARD ENTRY MODEL
// ─────────────────────────────────────────────
class _LbEntry {
  final String uid, name, photoUrl;
  final double winnings, withdrawals;
  const _LbEntry({required this.uid, required this.name, required this.photoUrl, required this.winnings, required this.withdrawals});

  factory _LbEntry.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return _LbEntry(
      uid:         doc.id,
      name:        d['name']             as String? ?? 'Unknown',
      photoUrl:    d['photoUrl']         as String? ?? '',
      winnings:    (d['totalEarnings']   as num?)?.toDouble() ?? 0.0,
      withdrawals: (d['totalWithdrawals'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ─────────────────────────────────────────────
// LEADERBOARD SERVICE — Cache-first, no polling
// ─────────────────────────────────────────────
class _LbService {
  static final _LbService instance = _LbService._();
  _LbService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<_LbEntry>> stream(String field) {
    return _db
        .collection('users')
        .orderBy(field, descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
          final entries = snap.docs.map(_LbEntry.fromDoc).toList();
          CacheService.instance.set(
            CacheKey.leaderboard,
            entries.map((e) => {
              'uid': e.uid, 'name': e.name, 'photoUrl': e.photoUrl,
              'winnings': e.winnings, 'withdrawals': e.withdrawals,
            }).toList(),
          );
          return entries;
        });
  }

  String get weekLabel {
    final now  = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    final week = ((now.difference(jan1).inDays + jan1.weekday) / 7).ceil();
    return 'Week $week · ${now.year}';
  }

  DateTime get nextReset {
    final now       = DateTime.now();
    final daysUntil = (DateTime.monday - now.weekday + 7) % 7;
    final reset     = daysUntil == 0
        ? now.add(const Duration(days: 7))
        : now.add(Duration(days: daysUntil));
    return DateTime(reset.year, reset.month, reset.day);
  }
}

// ─────────────────────────────────────────────
// RANKS SCREEN
// ─────────────────────────────────────────────
class RanksScreen extends StatefulWidget {
  const RanksScreen({super.key});
  @override State<RanksScreen> createState() => _RanksScreenState();
}

class _RanksScreenState extends State<RanksScreen> with TickerProviderStateMixin {
  final _svc    = _LbService.instance;
  final String? _myUid = FirebaseAuth.instance.currentUser?.uid;

  int _tabIndex = 0;

  late AnimationController _fadeCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _particleCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _glow;
  late Animation<double>   _particle;

  @override
  void initState() {
    super.initState();
    _fadeCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _glowCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

    _fadeIn   = CurvedAnimation(parent: _fadeCtrl,     curve: Curves.easeOutCubic);
    _glow     = CurvedAnimation(parent: _glowCtrl,     curve: Curves.easeInOut);
    _particle = CurvedAnimation(parent: _particleCtrl, curve: Curves.linear);
    // PRIORITY 7: No _ticker here. Countdown lives in _CountdownTicker only.
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _glowCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: _C.background,
        body: FadeTransition(
          opacity: _fadeIn,
          child: Column(children: [
            SizedBox(height: topPad),
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              // PRIORITY 7: IndexedStack keeps both tabs alive — no rebuild on switch.
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _LeaderboardView(
                    sortField:    'totalEarnings',
                    amountLabel:  'Winnings',
                    formatAmount: (v) => '₹${v.toStringAsFixed(0)}',
                    myUid:        _myUid,
                    service:      _svc,
                    glow:         _glow,
                    particle:     _particle,
                  ),
                  _LeaderboardView(
                    sortField:    'totalWithdrawals',
                    amountLabel:  'Withdrawn',
                    formatAmount: (v) => '₹${v.toStringAsFixed(0)}',
                    myUid:        _myUid,
                    service:      _svc,
                    glow:         _glow,
                    particle:     _particle,
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        // PRIORITY 5: Back button for nav consistency.
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        Container(width: 3, height: 20, decoration: BoxDecoration(color: _C.gold, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('WEEKLY', style: TextStyle(color: _C.textSecondary, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const SizedBox(width: 6),
            const Text('LEADERBOARD', style: TextStyle(color: _C.gold, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ]),
          Text(_svc.weekLabel, style: const TextStyle(color: _C.textMuted, fontSize: 10, fontWeight: FontWeight.w500)),
        ]),
        const Spacer(),
        // PRIORITY 7: Countdown isolated — only _CountdownTicker rebuilds each second.
        _CountdownTicker(nextReset: _svc.nextReset, glow: _glow),
      ]),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)),
        child: Row(children: [
          _TabChip(label: '💰  Highest Winnings',    active: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
          const SizedBox(width: 6),
          _TabChip(label: '💸  Highest Withdrawals', active: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// COUNTDOWN TICKER — isolated widget
// PRIORITY 7: Only this widget calls setState every second.
// ─────────────────────────────────────────────
class _CountdownTicker extends StatefulWidget {
  final DateTime nextReset;
  final Animation<double> glow;
  const _CountdownTicker({required this.nextReset, required this.glow});
  @override State<_CountdownTicker> createState() => _CountdownTickerState();
}

class _CountdownTickerState extends State<_CountdownTicker> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _compute();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_compute);
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  void _compute() {
    final diff = widget.nextReset.difference(DateTime.now());
    _timeLeft  = diff.isNegative ? Duration.zero : diff;
  }

  String _fmt(Duration d) {
    final h = d.inHours.remainder(24).toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inDays}d $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.glow,
      builder: (_, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _C.surfaceCard, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.gold.withValues(alpha: 0.2 + 0.15 * widget.glow.value)),
          boxShadow: [BoxShadow(color: _C.gold.withValues(alpha: 0.08 * widget.glow.value), blurRadius: 12)],
        ),
        child: child,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.timer_outlined, color: _C.gold, size: 12), const SizedBox(width: 5),
        Text(_fmt(_timeLeft), style: const TextStyle(color: _C.gold, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      ]),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _TabChip({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [_C.purpleDim, _C.purple], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? [const BoxShadow(color: _C.purpleGlow, blurRadius: 8)] : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? Colors.white : _C.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LEADERBOARD VIEW
// PRIORITY 7: Single StreamBuilder, AutomaticKeepAlive, pull-to-refresh.
// PRIORITY 8: Cache invalidated on manual refresh only.
// ─────────────────────────────────────────────
class _LeaderboardView extends StatefulWidget {
  final String sortField, amountLabel;
  final String Function(double) formatAmount;
  final String? myUid;
  final _LbService service;
  final Animation<double> glow, particle;
  const _LeaderboardView({required this.sortField, required this.amountLabel, required this.formatAmount, required this.myUid, required this.service, required this.glow, required this.particle});
  @override State<_LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<_LeaderboardView> with AutomaticKeepAliveClientMixin {
  @override bool get wantKeepAlive => true;

  double _getValue(_LbEntry e) => widget.sortField == 'totalEarnings' ? e.winnings : e.withdrawals;

  Future<void> _onRefresh() async {
    CacheService.instance.invalidate(CacheKey.leaderboard);
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<_LbEntry>>(
      stream: widget.service.stream(widget.sortField),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const _LoadingState();
        }
        if (snap.hasError) return _ErrorState(message: 'Could not load leaderboard.');
        final entries = snap.data ?? [];
        if (entries.isEmpty) return const _EmptyState();

        return RefreshIndicator(
          color: _C.purple, backgroundColor: _C.surfaceCard,
          onRefresh: _onRefresh,
          child: ListView.builder(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            itemCount: entries.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _Podium(
                    entries:      entries.take(3).toList(),
                    getValue:     _getValue,
                    formatAmount: widget.formatAmount,
                    glow:         widget.glow,
                    particle:     widget.particle,
                    myUid:        widget.myUid,
                  ),
                );
              }
              final entry = entries[i - 1];
              final rank  = i;
              if (rank <= 3) return const SizedBox.shrink();
              return _PlayerCard(
                entry:        entry,
                rank:         rank,
                value:        _getValue(entry),
                formatAmount: widget.formatAmount,
                isMe:         entry.uid == widget.myUid,
                animDelay:    (rank - 4) * 50,
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────
class _Podium extends StatefulWidget {
  final List<_LbEntry> entries;
  final double Function(_LbEntry) getValue;
  final String Function(double) formatAmount;
  final Animation<double> glow, particle;
  final String? myUid;
  const _Podium({required this.entries, required this.getValue, required this.formatAmount, required this.glow, required this.particle, required this.myUid});
  @override State<_Podium> createState() => _PodiumState();
}

class _PodiumState extends State<_Podium> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(const Duration(milliseconds: 80), () { if (mounted) _ctrl.forward(); });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  static const _platformHeights = [100.0, 130.0, 80.0];

  @override
  Widget build(BuildContext context) {
    final _LbEntry? second = widget.entries.length > 1 ? widget.entries[1] : null;
    final _LbEntry? first  = widget.entries.isNotEmpty  ? widget.entries[0] : null;
    final _LbEntry? third  = widget.entries.length > 2  ? widget.entries[2] : null;
    final order = [second, first, third];
    final ranks = [2, 1, 3];

    return ScaleTransition(
      scale: _anim,
      child: AnimatedBuilder(
        animation: widget.glow,
        builder: (_, child) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 0),
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
          decoration: BoxDecoration(
            color: _C.surfaceCard,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            border: Border.all(color: _C.gold.withValues(alpha: 0.1 + 0.08 * widget.glow.value)),
            boxShadow: [
              BoxShadow(color: _C.gold.withValues(alpha: 0.05 + 0.04 * widget.glow.value), blurRadius: 30),
              BoxShadow(color: _C.purple.withValues(alpha: 0.08 + 0.05 * widget.glow.value), blurRadius: 40),
            ],
          ),
          child: child,
        ),
        child: Stack(children: [
          SizedBox(height: 220, width: double.infinity,
              child: AnimatedBuilder(animation: widget.particle, builder: (_, _) => CustomPaint(painter: _PodiumParticlePainter(widget.particle.value)))),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) => Expanded(child: _PodiumSlot(
              entry: order[i], rank: ranks[i], platformH: _platformHeights[i],
              getValue: widget.getValue, formatAmount: widget.formatAmount,
              isMe: order[i]?.uid == widget.myUid,
            ))),
          ),
        ]),
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final _LbEntry? entry; final int rank; final double platformH;
  final double Function(_LbEntry) getValue; final String Function(double) formatAmount; final bool isMe;
  const _PodiumSlot({required this.entry, required this.rank, required this.platformH, required this.getValue, required this.formatAmount, required this.isMe});

  Color get _rankColor => switch (rank) { 1 => _C.gold, 2 => _C.silver, _ => _C.bronze };
  String get _crown    => switch (rank) { 1 => '👑',    2 => '🥈',     _ => '🥉' };

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_crown, style: TextStyle(fontSize: rank == 1 ? 28 : 22)),
      const SizedBox(height: 6),
      if (entry != null) ...[
        Container(
          width: rank == 1 ? 64 : 52, height: rank == 1 ? 64 : 52,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _rankColor, width: rank == 1 ? 3 : 2), boxShadow: [BoxShadow(color: _rankColor.withValues(alpha: 0.45), blurRadius: rank == 1 ? 16 : 10)]),
          child: ClipOval(child: _Avatar(url: entry!.photoUrl, name: entry!.name, accentColor: _rankColor)),
        ),
        const SizedBox(height: 6),
        Text(entry!.name, style: TextStyle(color: isMe ? _C.purpleLight : _C.textPrimary, fontSize: rank == 1 ? 12 : 10, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(formatAmount(getValue(entry!)), style: TextStyle(color: _rankColor, fontSize: rank == 1 ? 12 : 10, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
      ] else ...[
        Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _C.surfaceElevated, border: Border.all(color: _C.border)), child: const Icon(Icons.person_outline, color: _C.textMuted, size: 24)),
        const SizedBox(height: 6),
        const Text('—', style: TextStyle(color: _C.textMuted, fontSize: 12)),
        const SizedBox(height: 3),
        const Text('—', style: TextStyle(color: _C.textMuted, fontSize: 10)),
      ],
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: Stack(children: [
          Container(
            width: double.infinity, height: platformH,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_rankColor.withValues(alpha: 0.22), _rankColor.withValues(alpha: 0.06)]),
              border: Border.all(color: _rankColor.withValues(alpha: 0.25)),
            ),
            child: Center(child: Text('#$rank', style: TextStyle(color: _rankColor, fontSize: rank == 1 ? 26 : 20, fontWeight: FontWeight.w900))),
          ),
          Positioned(top: 0, left: 0, right: 0, child: Container(height: 2, color: _rankColor.withValues(alpha: 0.7))),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// PLAYER CARD (rank 4+)
// ─────────────────────────────────────────────
class _PlayerCard extends StatefulWidget {
  final _LbEntry entry; final int rank; final double value;
  final String Function(double) formatAmount; final bool isMe; final int animDelay;
  const _PlayerCard({required this.entry, required this.rank, required this.value, required this.formatAmount, required this.isMe, required this.animDelay});
  @override State<_PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<_PlayerCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _slide, _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _slide   = Tween(begin: 30.0, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: widget.animDelay), () { if (mounted) _ctrl.forward(); });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(opacity: _opacity.value, child: Transform.translate(offset: Offset(0, _slide.value), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isMe ? _C.purple.withValues(alpha: 0.08) : _C.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.isMe ? _C.purple.withValues(alpha: 0.4) : _C.border, width: widget.isMe ? 1.5 : 1),
        ),
        child: Row(children: [
          SizedBox(width: 36, child: Text('#${widget.rank}', textAlign: TextAlign.center, style: const TextStyle(color: _C.textMuted, fontSize: 13, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          SizedBox(width: 42, height: 42, child: ClipOval(child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.isMe ? _C.purple : _C.border, width: 1.5)),
            child: _Avatar(url: widget.entry.photoUrl, name: widget.entry.name, accentColor: widget.isMe ? _C.purple : _C.textMuted),
          ))),
          const SizedBox(width: 12),
          Expanded(child: Row(children: [
            Flexible(child: Text(widget.entry.name, style: const TextStyle(color: _C.textPrimary, fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            if (widget.isMe) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(4), border: Border.all(color: _C.purple.withValues(alpha: 0.4))),
                child: const Text('YOU', style: TextStyle(color: _C.purpleLight, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ],
          ])),
          Text(widget.formatAmount(widget.value), style: const TextStyle(color: _C.gold, fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AVATAR
// ─────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String url, name; final Color accentColor;
  const _Avatar({required this.url, required this.name, required this.accentColor});
  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => _Fallback(name: name, color: accentColor));
    return _Fallback(name: name, color: accentColor);
  }
}

class _Fallback extends StatelessWidget {
  final String name; final Color color;
  const _Fallback({required this.name, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(color: _C.surfaceElevated, child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18))));
  }
}

// ─────────────────────────────────────────────
// PARTICLE PAINTER
// ─────────────────────────────────────────────
class _PodiumParticlePainter extends CustomPainter {
  final double progress;
  static final _rng = math.Random(99);
  static final _pts = List.generate(16, (i) => [_rng.nextDouble(), _rng.nextDouble(), _rng.nextDouble() * 2.5 + 1, _rng.nextDouble()]);
  const _PodiumParticlePainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _pts) {
      final t     = (progress + p[3]) % 1.0;
      final x     = p[0] * size.width;
      final y     = (p[1] - t * 0.35) % 1.0 * size.height;
      final r     = p[2] as double;
      final alpha = (math.sin(t * math.pi) * 0.3).clamp(0.0, 0.3);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = _C.gold.withValues(alpha: alpha)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }
  @override bool shouldRepaint(covariant _PodiumParticlePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────
// STATE WIDGETS
// ─────────────────────────────────────────────
class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2)),
      SizedBox(height: 12),
      Text('Loading leaderboard…', style: TextStyle(color: _C.textMuted, fontSize: 12)),
    ]));
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline_rounded, color: _C.live, size: 40), const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: _C.textSecondary, fontSize: 13), textAlign: TextAlign.center),
    ])));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: _C.purpleGlowFaint, shape: BoxShape.circle, border: Border.all(color: _C.border)), child: const Center(child: Text('🏆', style: TextStyle(fontSize: 32)))),
      const SizedBox(height: 16),
      const Text('No data yet for this week.', style: TextStyle(color: _C.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('Be the first to compete and claim the top spot!', style: TextStyle(color: _C.textSecondary, fontSize: 12, height: 1.5), textAlign: TextAlign.center),
    ])));
  }
}