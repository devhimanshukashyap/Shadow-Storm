// lib/screens/tournament_details_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Details Screen (Phase F1)
//
// Changes from v3:
//   PRIORITY 2: Room reveal uses TournamentService.instance.isRoomRevealed(t)
//     exclusively — no local reveal logic. Both _buildRoomSection and
//     _RoomNotYetRevealed display the admin-set roomRevealTime if present.
//
//   PRIORITY 3: Scaffold wrapped with MaintenanceGuard.
//
//   PRIORITY 4: walletFrozen check added before join.
//     If walletFrozen=true, tournament join is blocked with freeze message.
//     TournamentService.joinWithTeam() also enforces this server-side via
//     wallet balance deduction — but we block early for UX.
//
//   All original v3 widgets (TeamSlotSection, MyTeamSection, BannerHeader,
//   RoomWidgets, PrizeSections, JoinBar, etc.) kept 100% intact.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';
import '../models/team_slot_model.dart';
import '../services/tournament_service.dart';
import '../services/app_settings_service.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────
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
  static const live            = Color(0xFFFF4466);
  static const success         = Color(0xFF44FF99);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
}

// ─────────────────────────────────────────────
// PARTICIPANT RESULT MODEL
// ─────────────────────────────────────────────
class _ParticipantResult {
  final int placement, kills;
  final double winnings;
  final String status;

  const _ParticipantResult({required this.placement, required this.kills, required this.winnings, required this.status});

  factory _ParticipantResult.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return _ParticipantResult(
      placement: (d['placement'] as num?)?.toInt()    ?? 0,
      kills:     (d['kills']     as num?)?.toInt()    ?? 0,
      winnings:  (d['winnings']  as num?)?.toDouble() ?? 0.0,
      status:    d['status']    as String?             ?? 'registered',
    );
  }
}

// ─────────────────────────────────────────────
// TOURNAMENT DETAILS SCREEN
// ─────────────────────────────────────────────
class TournamentDetailsScreen extends StatefulWidget {
  final TournamentModel tournament;
  const TournamentDetailsScreen({super.key, required this.tournament});

  @override
  State<TournamentDetailsScreen> createState() => _TournamentDetailsScreenState();
}

class _TournamentDetailsScreenState extends State<TournamentDetailsScreen>
    with TickerProviderStateMixin {
  bool _isJoined   = false;
  bool _isJoining  = false;
  bool _checkingJoin = true;

  _ParticipantResult? _myResult;

  List<TeamSlot>  _myTeamSlots  = [];
  List<TeamSlot?> _pendingSlots = [];
  String _userGameUid   = '';
  String _userIgn       = '';
  String _userReadableId = '';
  bool   _profileLoaded = false;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  final TournamentService _service = TournamentService.instance;
  final FirebaseFirestore _db      = FirebaseFirestore.instance;
  final FirebaseAuth      _auth    = FirebaseAuth.instance;

  User?   get _user         => _auth.currentUser;
  String? get _userId       => _user?.uid;
  String  get _tournamentId => widget.tournament.id;
  bool    get _isTeamTournament => widget.tournament.requiredSlots > 1;

  @override
  void initState() {
    super.initState();
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _fadeIn    = CurvedAnimation(parent: _fadeCtrl,  curve: Curves.easeOutCubic);
    _pulse     = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _initPendingSlots();
    _checkIfJoined();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _initPendingSlots() {
    final count = widget.tournament.requiredSlots.clamp(1, widget.tournament.maxSlots);
    _pendingSlots = List.generate(count, (_) => null);
  }

  Future<void> _loadUserProfile() async {
    if (_userId == null) { setState(() => _profileLoaded = true); return; }
    try {
      final doc  = await _db.collection('users').doc(_userId).get();
      final d    = doc.data() ?? {};
      if (mounted) {
        setState(() {
          _userGameUid    = (d['gameUid']    as String?) ?? '';
          _userIgn        = (d['ign']        as String?) ?? _user?.displayName ?? '';
          _userReadableId = (d['readableId'] as String?) ?? '';
          _profileLoaded  = true;
          if (_pendingSlots.isNotEmpty) {
            _pendingSlots[0] = TeamSlot(
              slotIndex:  0,
              gameUid:    _userGameUid,
              ign:        _userIgn,
              userId:     _userId,
              readableId: _userReadableId.isNotEmpty ? _userReadableId : null,
            );
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _profileLoaded = true);
    }
  }

  Future<void> _checkIfJoined() async {
    if (_userId == null) { setState(() => _checkingJoin = false); return; }
    try {
      final doc = await _db
          .collection('tournaments').doc(_tournamentId)
          .collection('participants').doc(_userId).get();
      if (mounted) {
        setState(() { _isJoined = doc.exists; _checkingJoin = false; });
        if (doc.exists) {
          _myResult = _ParticipantResult.fromDoc(doc);
          final d        = doc.data() as Map<String, dynamic>? ?? {};
          final rawSlots = d['teamSlots'] as List<dynamic>? ?? [];
          _myTeamSlots   = rawSlots.asMap().entries.map((e) => TeamSlot.fromMap(e.value as Map<String, dynamic>, e.key)).toList();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _checkingJoin = false);
    }
  }

  // ─────────────────────────────────────────────
  // JOIN WITH TEAM
  // PRIORITY 4: Check walletFrozen BEFORE attempting join.
  // ─────────────────────────────────────────────
  Future<void> _joinWithTeamSlots(TournamentModel t) async {
    if (_userId == null) { _showSnack('Please log in to join tournaments.'); return; }

    final settings = await AppSettingsService.instance.getSettings();

    if (settings.maintenanceMode) {
      _showSnack('Platform is under maintenance. Please try again later.');
      return;
    }

    // PRIORITY 4: Block join when wallet is frozen.
    if (settings.walletFrozen) {
      _showSnack(settings.walletFreezeReason.isNotEmpty
          ? 'Wallet frozen: ${settings.walletFreezeReason}'
          : 'Tournament entry is disabled while wallet is frozen.');
      return;
    }

    if (t.slotsLeft <= 0) { _showSnack('Tournament is full!'); return; }

    final filled = _pendingSlots.whereType<TeamSlot>().toList();
    if (filled.length < t.requiredSlots) {
      _showSnack('Please fill all ${t.requiredSlots} player slot(s) before joining.');
      return;
    }
    if (filled.any((s) => s.gameUid.trim().isEmpty)) {
      _showSnack('Please enter a valid Game UID for each team member.');
      return;
    }
    final uids = filled.map((s) => s.gameUid.trim()).toList();
    if (uids.toSet().length != uids.length) {
      _showSnack('Duplicate Game UIDs found in your team.');
      return;
    }

    setState(() => _isJoining = true);

    Map<String, dynamic> profile = {};
    try {
      final doc = await _db.collection('users').doc(_userId).get();
      profile   = doc.data() ?? {};
    } catch (_) {}

    final result = await _service.joinWithTeam(
      tournamentId: _tournamentId, slots: filled, profile: profile,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() { _isJoined = true; _isJoining = false; _myTeamSlots = filled; });
      _showSuccessSnack('You\'re in! Good luck, ${_user?.displayName?.split(' ').first ?? 'Striker'}!');
    } else {
      setState(() => _isJoining = false);
      _showSnack(result.error ?? 'Failed to join. Please try again.');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _C.textPrimary)),
      backgroundColor: _C.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: _C.border)),
    ));
  }

  void _showSuccessSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: _C.success, size: 18), const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: _C.textPrimary))),
      ]),
      backgroundColor: _C.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _C.success.withValues(alpha: 0.4))),
    ));
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccessSnack('$label copied!');
  }

  // ─────────────────────────────────────────────
  // BUILD
  // PRIORITY 3: MaintenanceGuard wraps Scaffold.
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: _C.background,
        body: StreamBuilder<TournamentModel?>(
          stream: _service.tournamentByIdStream(_tournamentId),
          builder: (context, snap) {
            final t = snap.data ?? widget.tournament;
            return FadeTransition(
              opacity: _fadeIn,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(t),
                  SliverToBoxAdapter(child: _buildBody(t)),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: StreamBuilder<TournamentModel?>(
          stream: _service.tournamentByIdStream(_tournamentId),
          builder: (_, snap) => _buildJoinBar(snap.data ?? widget.tournament),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────
  Widget _buildBody(TournamentModel t) {
    final isCompleted = t.status == TournamentStatus.completed;
    final isCancelled = t.status == TournamentStatus.cancelled;

    List<Widget> statusContent;

    if (isCancelled) {
      statusContent = [_buildCancelledNotice(), const SizedBox(height: 100)];
    } else if (isCompleted) {
      statusContent = [
        if (_isJoined && _myResult != null) _buildMyResultSection(_myResult!),
        if (_isJoined && _myTeamSlots.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MyTeamSection(slots: _myTeamSlots, onCopy: _copyToClipboard),
        ],
        _buildCompletedPrizeSummary(t),
        if (t.rules != null && t.rules!.isNotEmpty) _buildRulesSection(t),
        const SizedBox(height: 100),
      ];
    } else {
      statusContent = [
        if (!_isJoined && _isTeamTournament && !_checkingJoin) ...[
          const SizedBox(height: 16),
          _TeamSlotSection(tournament: t, slots: _pendingSlots, profileLoaded: _profileLoaded, service: _service, onSlotsChanged: (updated) => setState(() => _pendingSlots = updated)),
        ],
        if (_isJoined && _myTeamSlots.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MyTeamSection(slots: _myTeamSlots, onCopy: _copyToClipboard),
        ],
        _buildRoomSection(t),
        const SizedBox(height: 16),
        _buildPrizeSection(t),
        const SizedBox(height: 16),
        _buildRewardExplanationSection(t),
        _buildMatchInfo(t),
        const SizedBox(height: 16),
        _buildSlotProgress(t),
        const SizedBox(height: 16),
        if (t.rules != null && t.rules!.isNotEmpty) _buildRulesSection(t),
        const SizedBox(height: 100),
      ];
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      _buildInfoRow(t),
      const SizedBox(height: 16),
      ...statusContent,
    ]);
  }

  // ─────────────────────────────────────────────
  // SLIVER APP BAR
  // ─────────────────────────────────────────────
  Widget _buildSliverAppBar(TournamentModel t) {
    return SliverAppBar(
      expandedHeight: 260, pinned: true, backgroundColor: _C.background,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: _C.surfaceCard.withValues(alpha: 0.9), shape: BoxShape.circle, border: Border.all(color: _C.border)), child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.textPrimary, size: 16)),
      ),
      flexibleSpace: FlexibleSpaceBar(background: _BannerHeader(tournament: t, pulse: _pulse), collapseMode: CollapseMode.parallax),
    );
  }

  // ─────────────────────────────────────────────
  // INFO ROW
  // ─────────────────────────────────────────────
  Widget _buildInfoRow(TournamentModel t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _QuickStat(icon: Icons.map_rounded,         label: 'MAP',    value: t.map,             color: _C.purpleLight),
        const SizedBox(width: 10),
        _QuickStat(icon: Icons.people_rounded,      label: 'MODE',   value: t.mode,            color: _C.purple),
        const SizedBox(width: 10),
        _QuickStat(icon: Icons.access_time_rounded, label: 'STARTS', value: t.startTimeDisplay, color: _C.gold, flex: 2),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // ROOM SECTION
  // PRIORITY 2: isRoomRevealed() is called here — single source of truth.
  // ─────────────────────────────────────────────
  Widget _buildRoomSection(TournamentModel t) {
    // PRIORITY 2: Delegate entirely to TournamentService.isRoomRevealed().
    final revealed = _service.isRoomRevealed(t);

    return _SectionCard(
      title: 'ROOM ACCESS', icon: Icons.meeting_room_rounded, iconColor: _C.purple,
      child: _checkingJoin
          ? const _RoomLoading()
          : !_isJoined
              ? const _RoomLocked()
              : revealed
                  ? _RoomRevealed(tournament: t, onCopy: _copyToClipboard)
                  : _RoomNotYetRevealed(tournament: t),
    );
  }

  // ─────────────────────────────────────────────
  // CANCELLED NOTICE
  // ─────────────────────────────────────────────
  Widget _buildCancelledNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.live.withValues(alpha: 0.4))),
        child: const Column(children: [
          Icon(Icons.cancel_outlined, color: _C.live, size: 36),
          SizedBox(height: 12),
          Text('Tournament Cancelled', style: TextStyle(color: _C.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text('This tournament has been cancelled by the organiser.\nIf you had registered, your entry fee has been refunded to your wallet.', style: TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.6), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // MY RESULT
  // ─────────────────────────────────────────────
  Widget _buildMyResultSection(_ParticipantResult result) {
    Color placementColor;
    if (result.placement == 1)       placementColor = _C.gold;
    else if (result.placement <= 3)  placementColor = const Color(0xFFC0C0C0);
    else if (result.placement <= 10) placementColor = _C.success;
    else                             placementColor = _C.textSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [placementColor.withValues(alpha: 0.10), _C.surfaceCard], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20), border: Border.all(color: placementColor.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded, color: _C.gold, size: 18), const SizedBox(width: 8),
            const Text('MY RESULT', style: TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _ResultStat(icon: Icons.leaderboard_rounded,             label: 'PLACEMENT', value: result.placement > 0 ? '#${result.placement}' : '—', color: placementColor)),
            Container(width: 1, height: 44, color: _C.border),
            Expanded(child: _ResultStat(icon: Icons.sports_kabaddi_rounded,          label: 'KILLS',     value: result.kills.toString(), color: _C.live)),
            Container(width: 1, height: 44, color: _C.border),
            Expanded(child: _ResultStat(icon: Icons.account_balance_wallet_rounded,  label: 'WINNINGS',  value: result.winnings > 0 ? '₹${result.winnings.toInt()}' : '—', color: result.winnings > 0 ? _C.success : _C.textMuted)),
          ]),
          if (result.winnings > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [_C.success.withValues(alpha: 0.12), _C.success.withValues(alpha: 0.04)]), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.success.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.workspace_premium_rounded, color: _C.success, size: 18), const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('WINNINGS CREDITED', style: TextStyle(color: _C.success, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  Text('₹${result.winnings.toInt()}', style: const TextStyle(color: _C.success, fontSize: 20, fontWeight: FontWeight.w900)),
                ]),
                const Spacer(),
                const Icon(Icons.check_circle_rounded, color: _C.success, size: 22),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // COMPLETED PRIZE SUMMARY
  // ─────────────────────────────────────────────
  Widget _buildCompletedPrizeSummary(TournamentModel t) {
    return _SectionCard(
      title: 'MATCH SUMMARY', icon: Icons.check_circle_outline_rounded, iconColor: _C.textMuted,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InfoTile(label: 'Tournament', value: t.title),
        _InfoTile(label: 'Mode', value: t.modeDisplay),
        _InfoTile(label: 'Map', value: t.map),
        _InfoTile(label: 'Prize Pool', value: t.prizePoolDisplay, valueColor: _C.gold),
        _InfoTile(label: 'Participants', value: '${t.joinedPlayers}/${t.maxPlayers}'),
        _InfoTile(label: 'Status', value: 'COMPLETED', valueColor: _C.textMuted),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // PRIZE SECTION
  // ─────────────────────────────────────────────
  Widget _buildPrizeSection(TournamentModel t) {
    return _SectionCard(
      title: 'PRIZE BREAKDOWN', icon: Icons.emoji_events_rounded, iconColor: _C.gold,
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [_C.gold.withValues(alpha: 0.12), _C.gold.withValues(alpha: 0.04)]), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.gold.withValues(alpha: 0.25))),
          child: Row(children: [
            const Icon(Icons.workspace_premium_rounded, color: _C.gold, size: 20), const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TOTAL PRIZE POOL', style: TextStyle(color: _C.gold.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text(t.prizePoolDisplay, style: const TextStyle(color: _C.gold, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        if (t.positions.isNotEmpty) ...[...t.positions.map((p) => _PositionRewardRow(reward: p)), const SizedBox(height: 10)],
        if (t.killReward > 0 || t.survivalReward > 0) _RewardTypeRow(tournament: t),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  // REWARD EXPLANATION
  // ─────────────────────────────────────────────
  Widget _buildRewardExplanationSection(TournamentModel t) {
    final hasDesc = t.rewardDescription?.trim().isNotEmpty == true;
    final hasAuto = t.killReward > 0 || t.survivalReward > 0 || t.positions.isNotEmpty;
    if (!hasDesc && !hasAuto) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _SectionCard(
        title: 'HOW REWARDS WORK', icon: Icons.info_rounded, iconColor: _C.purpleLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasAuto) ...[
            if (t.positions.isNotEmpty) _RewardBubble(icon: Icons.emoji_events_rounded, color: _C.gold, title: 'Placement Rewards', desc: 'Top ${t.positions.length} players earn prizes based on final placement.'),
            if (t.killReward > 0) ...[const SizedBox(height: 10), _RewardBubble(icon: Icons.sports_kabaddi_rounded, color: _C.live, title: 'Kill Reward — ₹${t.killReward.toInt()} per kill', desc: 'Earn ₹${t.killReward.toInt()} for every elimination. Paid out after match.')],
            if (t.survivalReward > 0) ...[const SizedBox(height: 10), _RewardBubble(icon: Icons.shield_rounded, color: _C.purpleLight, title: 'Survival Bonus — ₹${t.survivalReward.toInt()}', desc: 'Flat ₹${t.survivalReward.toInt()} for surviving to the final circle.')],
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)), child: Row(children: [const Icon(Icons.lightbulb_rounded, color: _C.gold, size: 14), const SizedBox(width: 8), Expanded(child: Text(_rewardTypeNote(t.rewardType), style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.5)))])),
          ],
          if (hasDesc) ...[
            if (hasAuto) ...[const SizedBox(height: 14), Container(height: 1, color: _C.border), const SizedBox(height: 12), const Row(children: [Icon(Icons.campaign_rounded, color: _C.purple, size: 13), SizedBox(width: 6), Text('FROM THE ORGANISER', style: TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1))]), const SizedBox(height: 10)],
            Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)), child: Text(t.rewardDescription!, style: const TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.65))),
          ],
        ]),
      ),
    );
  }

  String _rewardTypeNote(String type) {
    switch (type) {
      case 'kill':     return 'Kill-Based: Total reward depends on your kill count.';
      case 'survival': return 'Survival-Based: Stay alive as long as possible to earn bonuses.';
      case 'position': return 'Placement-Based: Only your final position determines your prize.';
      case 'mixed':    return 'Mixed: Total = Placement Prize + (Kills × Kill Reward).';
      default:         return 'Rewards are distributed based on match performance.';
    }
  }

  // ─────────────────────────────────────────────
  // MATCH INFO
  // ─────────────────────────────────────────────
  Widget _buildMatchInfo(TournamentModel t) {
    return _SectionCard(
      title: 'MATCH INFO', icon: Icons.sports_esports_rounded, iconColor: _C.purple,
      child: Column(children: [
        _InfoTile(label: 'Type', value: t.typeLabelDisplay),
        _InfoTile(label: 'Mode', value: t.mode),
        _InfoTile(label: 'Map', value: t.map),
        _InfoTile(label: 'Entry Fee', value: t.entryFeeDisplay, valueColor: t.entryFee > 0 ? _C.textPrimary : _C.success),
        _InfoTile(label: 'Reward', value: _rewardLabel(t.rewardType)),
        if (t.isTeamTournament) _InfoTile(label: 'Team Size', value: t.teamSizeDisplay),
      ]),
    );
  }

  String _rewardLabel(String type) {
    switch (type) {
      case 'kill':     return 'Kill Based';
      case 'survival': return 'Survival Based';
      case 'position': return 'Position Based';
      case 'mixed':    return 'Mixed';
      default:         return type;
    }
  }

  // ─────────────────────────────────────────────
  // SLOT PROGRESS
  // ─────────────────────────────────────────────
  Widget _buildSlotProgress(TournamentModel t) {
    return _SectionCard(
      title: 'SLOTS', icon: Icons.grid_view_rounded, iconColor: _C.purpleLight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RichText(text: TextSpan(children: [
            TextSpan(text: '${t.joinedPlayers}', style: const TextStyle(color: _C.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
            TextSpan(text: ' / ${t.maxPlayers}', style: const TextStyle(color: _C.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: t.isAlmostFull ? _C.live.withValues(alpha: 0.15) : _C.purpleGlowFaint, borderRadius: BorderRadius.circular(20), border: Border.all(color: t.isAlmostFull ? _C.live.withValues(alpha: 0.4) : _C.border)),
            child: Text(t.isAlmostFull ? '🔥 Almost Full' : '${t.slotsLeft} left', style: TextStyle(color: t.isAlmostFull ? _C.live : _C.purpleLight, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: t.fillPercent, minHeight: 6, backgroundColor: _C.surfaceElevated, valueColor: AlwaysStoppedAnimation(t.isAlmostFull ? _C.live : _C.purple))),
      ]),
    );
  }

  Widget _buildRulesSection(TournamentModel t) {
    return _SectionCard(
      title: 'RULES', icon: Icons.gavel_rounded, iconColor: _C.purpleLight,
      child: Text(t.rules ?? '', style: const TextStyle(color: _C.textSecondary, fontSize: 13, height: 1.6)),
    );
  }

  // ─────────────────────────────────────────────
  // JOIN BAR
  // PRIORITY 4: Shows frozen state in join bar.
  // ─────────────────────────────────────────────
  Widget _buildJoinBar(TournamentModel t) {
    final isCompleted = t.status == TournamentStatus.completed;
    final isCancelled = t.status == TournamentStatus.cancelled;
    final isLive      = t.status == TournamentStatus.live;

    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.instance.settingsStream,
      builder: (context, settingsSnap) {
        final settings     = settingsSnap.data ?? const AppSettings();
        final frozen       = settings.walletFrozen;
        final maintenance  = settings.maintenanceMode;

        return Container(
          decoration: const BoxDecoration(color: _C.surface, border: Border(top: BorderSide(color: _C.border))),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(children: [
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ENTRY FEE', style: TextStyle(color: _C.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  Text(t.entryFeeDisplay, style: const TextStyle(color: _C.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(width: 16),
                Expanded(
                  child: _isJoined
                      ? _JoinedBadge()
                      : isCompleted
                          ? const _DisabledButton(label: 'TOURNAMENT ENDED')
                          : isCancelled
                              ? const _DisabledButton(label: 'CANCELLED')
                              : t.isFull
                                  ? const _DisabledButton(label: 'TOURNAMENT FULL')
                                  : isLive
                                      ? const _DisabledButton(label: 'MATCH IN PROGRESS')
                                      : maintenance
                                          ? const _DisabledButton(label: 'MAINTENANCE MODE')
                                          : frozen
                                              ? const _DisabledButton(label: 'WALLET FROZEN')
                                              : _JoinButton(isLoading: _isJoining, onTap: () => _joinWithTeamSlots(t)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// TEAM SLOT SECTION (unchanged from v3)
// ─────────────────────────────────────────────
class _TeamSlotSection extends StatefulWidget {
  final TournamentModel tournament;
  final List<TeamSlot?> slots;
  final bool profileLoaded;
  final TournamentService service;
  final void Function(List<TeamSlot?>) onSlotsChanged;
  const _TeamSlotSection({required this.tournament, required this.slots, required this.profileLoaded, required this.service, required this.onSlotsChanged});
  @override State<_TeamSlotSection> createState() => _TeamSlotSectionState();
}

class _TeamSlotSectionState extends State<_TeamSlotSection> {
  final Map<int, TextEditingController> _gameUidCtrl = {};
  final Map<int, TextEditingController> _ignCtrl     = {};
  final Map<int, String?> _levelWarning = {};
  final Map<int, bool>    _lookingUp    = {};

  @override void initState() { super.initState(); _buildControllers(); }

  void _buildControllers() {
    for (var i = 1; i < widget.slots.length; i++) {
      _gameUidCtrl[i] ??= TextEditingController(text: widget.slots[i]?.gameUid ?? '');
      _ignCtrl[i]     ??= TextEditingController(text: widget.slots[i]?.ign     ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _gameUidCtrl.values) c.dispose();
    for (final c in _ignCtrl.values)     c.dispose();
    super.dispose();
  }

  void _addSlot() {
    if (widget.slots.length >= widget.tournament.maxSlots) return;
    final newIndex = widget.slots.length;
    _gameUidCtrl[newIndex] = TextEditingController();
    _ignCtrl[newIndex]     = TextEditingController();
    widget.onSlotsChanged([...widget.slots, null]);
  }

  void _removeLastSlot() {
    if (widget.slots.length <= widget.tournament.requiredSlots) return;
    final i = widget.slots.length - 1;
    _gameUidCtrl[i]?.dispose(); _gameUidCtrl.remove(i);
    _ignCtrl[i]?.dispose();     _ignCtrl.remove(i);
    _levelWarning.remove(i); _lookingUp.remove(i);
    widget.onSlotsChanged(widget.slots.sublist(0, i));
  }

  void _updateSlot(int index) {
    final gameUid = _gameUidCtrl[index]?.text.trim() ?? '';
    final ign     = _ignCtrl[index]?.text.trim() ?? '';
    final updated = List<TeamSlot?>.from(widget.slots);
    updated[index] = TeamSlot(slotIndex: index, gameUid: gameUid, ign: ign);
    widget.onSlotsChanged(updated);
  }

  Future<void> _lookupGameUid(int index, String gameUid) async {
    if (gameUid.length < 6) return;
    setState(() => _lookingUp[index] = true);
    final player = await widget.service.lookupPlayerByGameUid(gameUid);
    if (!mounted) return;
    setState(() {
      _lookingUp[index] = false;
      if (player == null) {
        _levelWarning[index] = null;
      } else {
        final level    = (player['gameLevel'] as num?)?.toInt() ?? 0;
        final minLevel = widget.tournament.minimumLevel;
        _levelWarning[index] = level < minLevel ? 'This player\'s level ($level) is below the minimum ($minLevel).' : null;
        final regIgn = player['ign'] as String? ?? '';
        if (regIgn.isNotEmpty && (_ignCtrl[index]?.text.isEmpty == true)) {
          _ignCtrl[index]?.text = regIgn;
          _updateSlot(index);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t          = widget.tournament;
    final canAddMore = widget.slots.length < t.maxSlots;
    final canRemove  = widget.slots.length > t.requiredSlots;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.group_rounded, color: _C.purple, size: 16), const SizedBox(width: 8),
            const Text('YOUR TEAM', style: TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            Text('${widget.slots.length}/${t.maxSlots} slots', style: const TextStyle(color: _C.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 14),
          _buildLeaderSlot(),
          const SizedBox(height: 6),
          ...List.generate(widget.slots.length - 1, (i) => _buildManualSlot(i + 1)),
          const SizedBox(height: 10),
          Row(children: [
            if (canRemove) _SlotControlBtn(label: '− Remove slot', color: _C.live, onTap: _removeLastSlot),
            if (canRemove && canAddMore) const SizedBox(width: 8),
            if (canAddMore) _SlotControlBtn(label: '+ Add player', color: _C.success, onTap: _addSlot),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.border)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: _C.purple, size: 13), const SizedBox(width: 8),
              Expanded(child: Text('Enter your teammates\' in-game UID and name. Only players with level ${t.minimumLevel}+ can participate.', style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildLeaderSlot() {
    final slot = widget.slots.isNotEmpty ? widget.slots[0] : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.purple.withValues(alpha: 0.35))),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: _C.purple.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: _C.purple.withValues(alpha: 0.5))), child: const Center(child: Text('1', style: TextStyle(color: _C.purple, fontSize: 12, fontWeight: FontWeight.w800)))),
        const SizedBox(width: 10),
        Expanded(child: widget.profileLoaded
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slot?.ign.isNotEmpty == true ? slot!.ign : 'Your IGN', style: const TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                if (slot?.gameUid.isNotEmpty == true) Text('UID: ${slot!.gameUid}', style: const TextStyle(color: _C.textSecondary, fontSize: 11)),
                if (slot?.readableId != null) Text(slot!.readableId!, style: const TextStyle(color: _C.textMuted, fontSize: 10)),
              ])
            : const Text('Loading your profile…', style: TextStyle(color: _C.textMuted, fontSize: 12))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _C.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_rounded, color: _C.purple, size: 10), SizedBox(width: 4), Text('YOU', style: TextStyle(color: _C.purple, fontSize: 9, fontWeight: FontWeight.w800))])),
      ]),
    );
  }

  Widget _buildManualSlot(int index) {
    final warning = _levelWarning[index];
    final looking = _lookingUp[index] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: warning != null ? _C.gold.withValues(alpha: 0.4) : _C.border)),
      child: Column(children: [
        Row(children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: _C.surfaceCard, shape: BoxShape.circle, border: Border.all(color: _C.border)), child: Center(child: Text('${index + 1}', style: const TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(
            controller: _gameUidCtrl[index], style: const TextStyle(color: _C.textPrimary, fontSize: 13),
            keyboardType: TextInputType.number,
            decoration: _slotInputDeco('Game UID', suffix: looking ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.purple))) : null),
            onChanged: (v) { _updateSlot(index); if (v.trim().length >= 6) _lookupGameUid(index, v.trim()); },
          )),
          const SizedBox(width: 8),
          Expanded(child: TextFormField(controller: _ignCtrl[index], style: const TextStyle(color: _C.textPrimary, fontSize: 13), decoration: _slotInputDeco('In-Game Name'), onChanged: (_) => _updateSlot(index))),
        ]),
        if (warning != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 38),
            const Icon(Icons.warning_amber_rounded, color: _C.gold, size: 13), const SizedBox(width: 6),
            Expanded(child: Text(warning, style: const TextStyle(color: _C.gold, fontSize: 11))),
          ]),
        ],
      ]),
    );
  }

  InputDecoration _slotInputDeco(String label, {Widget? suffix}) => InputDecoration(
    labelText: label, suffixIcon: suffix,
    labelStyle: const TextStyle(color: _C.textMuted, fontSize: 12),
    filled: true, fillColor: _C.surfaceCard, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.purple, width: 1.5)),
  );
}

// ─────────────────────────────────────────────
// MY TEAM SECTION (unchanged from v3)
// ─────────────────────────────────────────────
class _MyTeamSection extends StatelessWidget {
  final List<TeamSlot> slots;
  final void Function(String, String) onCopy;
  const _MyTeamSection({required this.slots, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.purple.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.group_rounded, color: _C.purple, size: 16), const SizedBox(width: 8),
            const Text('MY TEAM', style: TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            Text('${slots.length} player${slots.length == 1 ? '' : 's'}', style: const TextStyle(color: _C.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          ...slots.asMap().entries.map((e) => _buildSlotRow(e.key, e.value)),
        ]),
      ),
    );
  }

  Widget _buildSlotRow(int index, TeamSlot slot) {
    final maskedUid = slot.gameUid.length > 8 ? '${slot.gameUid.substring(0, 8)}…' : slot.gameUid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: slot.isLeader ? _C.purple.withValues(alpha: 0.15) : _C.surfaceElevated, shape: BoxShape.circle, border: Border.all(color: slot.isLeader ? _C.purple.withValues(alpha: 0.4) : _C.border)), child: Center(child: Text('${index + 1}', style: TextStyle(color: slot.isLeader ? _C.purple : _C.textMuted, fontSize: 11, fontWeight: FontWeight.w700)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(slot.ign.isNotEmpty ? slot.ign : 'Unknown', style: const TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            if (slot.isLeader) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _C.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: const Text('YOU', style: TextStyle(color: _C.purple, fontSize: 8, fontWeight: FontWeight.w800)))],
          ]),
          Row(children: [
            Text(maskedUid, style: const TextStyle(color: _C.textSecondary, fontSize: 11)),
            if (slot.readableId != null) ...[const Text(' · ', style: TextStyle(color: _C.textMuted)), Text(slot.readableId!, style: const TextStyle(color: _C.textMuted, fontSize: 11))],
          ]),
        ])),
        GestureDetector(onTap: () => onCopy(slot.gameUid, 'Game UID'), child: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.border)), child: const Icon(Icons.copy_rounded, color: _C.purple, size: 13))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SLOT CONTROL BUTTON
// ─────────────────────────────────────────────
class _SlotControlBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _SlotControlBtn({required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.35))), child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
  );
}

// ─────────────────────────────────────────────
// BANNER HEADER (unchanged from v3)
// ─────────────────────────────────────────────
class _BannerHeader extends StatelessWidget {
  final TournamentModel tournament; final Animation<double> pulse;
  const _BannerHeader({required this.tournament, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final t        = tournament;
    final hasBanner = t.bannerUrl != null && t.bannerUrl!.isNotEmpty;
    return Stack(fit: StackFit.expand, children: [
      if (hasBanner) Image.network(t.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _FallbackBanner(type: t.tournamentType))
      else _FallbackBanner(type: t.tournamentType),
      DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.15), _C.background.withValues(alpha: 0.97)], stops: const [0.0, 1.0]))),
      Positioned(bottom: 20, left: 20, right: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _StatusBadge(status: t.status, pulse: pulse),
        const SizedBox(height: 10),
        Text(t.title, style: const TextStyle(color: _C.textPrimary, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, shadows: [Shadow(color: _C.purpleGlow, blurRadius: 16)])),
        const SizedBox(height: 4),
        Text(t.subtitle, style: const TextStyle(color: _C.textSecondary, fontSize: 13)),
      ])),
    ]);
  }
}

class _FallbackBanner extends StatelessWidget {
  final String type;
  const _FallbackBanner({required this.type});
  static Color _accent(String t) {
    switch (t) {
      case 'clash_squad':   return const Color(0xFFFF6B35);
      case 'lone_wolf':     return const Color(0xFF00D4FF);
      case 'lose_to_win':   return const Color(0xFFFF4466);
      case '2v2':           return const Color(0xFF44FF99);
      case '1v1_arena':     return const Color(0xFFFFCC44);
      case 'sniper':        return const Color(0xFF00D4FF);
      case 'custom_league': return const Color(0xFFFFCC44);
      default:              return const Color(0xFF9D55FF);
    }
  }
  @override
  Widget build(BuildContext context) {
    final accent = _accent(type);
    return Container(color: _C.surfaceCard, child: CustomPaint(painter: _EsportsBannerPainter(accent: accent)));
  }
}

class _EsportsBannerPainter extends CustomPainter {
  final Color accent;
  const _EsportsBannerPainter({required this.accent});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..shader = const LinearGradient(colors: [Color(0xFF0D0820), Color(0xFF06040E), Color(0xFF110830)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    final dot = Paint()..color = accent.withValues(alpha: 0.07);
    for (var c = 0; c < 25; c++) { for (var r = 0; r < 12; r++) { canvas.drawCircle(Offset(c * 32.0, r * 28.0), 1.5, dot); } }
    final line = Paint()..color = accent.withValues(alpha: 0.2)..strokeWidth = 1.5;
    for (var i = 0; i < 4; i++) { canvas.drawLine(Offset(size.width * 0.6 + i * 16, 0), Offset(size.width, size.height * 0.6 + i * 16), line); }
  }
  @override bool shouldRepaint(covariant _EsportsBannerPainter old) => old.accent != accent;
}

// ─────────────────────────────────────────────
// ROOM WIDGETS (unchanged from v3)
// ─────────────────────────────────────────────
class _RoomLoading extends StatelessWidget {
  const _RoomLoading();
  @override Widget build(BuildContext context) => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2))));
}

class _RoomLocked extends StatelessWidget {
  const _RoomLocked();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: const Column(children: [
        Icon(Icons.lock_rounded, color: _C.purple, size: 24),
        SizedBox(height: 12),
        Text('Room Details Locked', style: TextStyle(color: _C.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('Join the tournament to unlock Room ID and Password.', textAlign: TextAlign.center, style: TextStyle(color: _C.textSecondary, fontSize: 12, height: 1.5)),
      ]),
    );
  }
}

// PRIORITY 2: Shows admin-set roomRevealTime if available.
class _RoomNotYetRevealed extends StatelessWidget {
  final TournamentModel tournament;
  const _RoomNotYetRevealed({required this.tournament});
  @override
  Widget build(BuildContext context) {
    // PRIORITY 2: Display admin roomRevealTime if explicitly set.
    final revealTime = tournament.roomRevealTime
        ?? (tournament.startTime?.subtract(const Duration(minutes: 30)));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.gold.withValues(alpha: 0.25))),
      child: Row(children: [
        const Icon(Icons.lock_clock_rounded, color: _C.gold, size: 20), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Room details not yet revealed', style: TextStyle(color: _C.gold, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            revealTime != null
                ? 'Credentials will be available 30 minutes before match start.'
                : 'Credentials will be revealed by the organiser before the match.',
            style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4),
          ),
        ])),
      ]),
    );
  }
}

class _RoomRevealed extends StatelessWidget {
  final TournamentModel tournament;
  final void Function(String, String) onCopy;
  const _RoomRevealed({required this.tournament, required this.onCopy});
  @override
  Widget build(BuildContext context) {
    final t       = tournament;
    final hasRoom = t.roomId?.isNotEmpty == true;
    final hasPw   = t.roomPassword?.isNotEmpty == true;

    if (!hasRoom && !hasPw) {
      return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.gold.withValues(alpha: 0.25))), child: const Row(children: [Icon(Icons.hourglass_top_rounded, color: _C.gold, size: 16), SizedBox(width: 8), Text('Room details loading soon…', style: TextStyle(color: _C.gold, fontSize: 12, fontWeight: FontWeight.w600))]));
    }

    return Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.success.withValues(alpha: 0.3))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_rounded, color: _C.success, size: 15), SizedBox(width: 6), Text("You're registered — room details unlocked", style: TextStyle(color: _C.success, fontSize: 12, fontWeight: FontWeight.w600))])),
      const SizedBox(height: 12),
      if (hasRoom) _RoomField(label: 'ROOM ID', value: t.roomId!, icon: Icons.meeting_room_rounded, onCopy: () => onCopy(t.roomId!, 'Room ID')),
      if (hasRoom && hasPw) const SizedBox(height: 10),
      if (hasPw)   _RoomField(label: 'PASSWORD', value: t.roomPassword!, icon: Icons.vpn_key_rounded, onCopy: () => onCopy(t.roomPassword!, 'Password')),
    ]);
  }
}

class _RoomField extends StatelessWidget {
  final String label, value; final IconData icon; final VoidCallback onCopy;
  const _RoomField({required this.label, required this.value, required this.icon, required this.onCopy});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.borderBright)),
      child: Row(children: [
        Icon(icon, color: _C.purple, size: 16), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: _C.textPrimary, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ])),
        GestureDetector(onTap: onCopy, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.border)), child: const Icon(Icons.copy_rounded, color: _C.purple, size: 14))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SHARED SECTION WIDGETS (unchanged from v3)
// ─────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final TournamentStatus status; final Animation<double> pulse;
  const _StatusBadge({required this.status, required this.pulse});
  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (status) {
      case TournamentStatus.live:      color = _C.live;      label = 'LIVE NOW';   break;
      case TournamentStatus.completed: color = _C.textMuted; label = 'COMPLETED';  break;
      case TournamentStatus.cancelled: color = _C.live;      label = 'CANCELLED';  break;
      case TournamentStatus.upcoming:  color = _C.purple;    label = 'UPCOMING';   break;
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: status == TournamentStatus.live ? 0.5 + 0.3 * pulse.value : 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (status == TournamentStatus.live) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.5 + 0.5 * pulse.value), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)])),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ]),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title; final IconData icon; final Color iconColor; final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.iconColor, required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: iconColor, size: 16), const SizedBox(width: 7), Text(title, style: const TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2))]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label, value; final Color? valueColor;
  const _InfoTile({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
      Expanded(flex: 2, child: Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 12))),
      Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: valueColor ?? _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
    ]));
  }
}

class _QuickStat extends StatelessWidget {
  final IconData icon; final String label, value; final Color color; final int flex;
  const _QuickStat({required this.icon, required this.label, required this.value, required this.color, this.flex = 1});
  @override
  Widget build(BuildContext context) {
    return Expanded(flex: flex, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: Row(children: [
        Icon(icon, color: color, size: 14), const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        ])),
      ]),
    ));
  }
}

class _ResultStat extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _ResultStat({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: color, size: 18), const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    ]);
  }
}

class _RewardBubble extends StatelessWidget {
  final IconData icon; final Color color; final String title, desc;
  const _RewardBubble({required this.icon, required this.color, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 14)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(desc, style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.5)),
        ])),
      ]),
    );
  }
}

class _PositionRewardRow extends StatelessWidget {
  final PositionReward reward;
  const _PositionRewardRow({required this.reward});
  static const _medals = ['🥇', '🥈', '🥉'];
  static const _colors = [_C.gold, Color(0xFFC0C0C0), Color(0xFFCD7F32)];
  @override
  Widget build(BuildContext context) {
    final r     = reward.rank;
    final emoji = r <= 3 ? _medals[r - 1] : '#$r';
    final color = r <= 3 ? _colors[r - 1] : _C.textSecondary;
    final label = r <= 3 ? ['1st Place', '2nd Place', '3rd Place'][r - 1] : 'Rank $r';
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
      SizedBox(width: 36, child: Text(emoji, style: const TextStyle(fontSize: 18))),
      Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      const Spacer(),
      Text('₹${reward.amount.toInt()}', style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
    ]));
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
      decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
      child: Row(children: [
        if (t.killReward > 0) ...[const Icon(Icons.sports_kabaddi_rounded, color: _C.live, size: 16), const SizedBox(width: 6), Expanded(child: Text('₹${t.killReward.toInt()} per kill', style: const TextStyle(color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)))],
        if (t.killReward > 0 && t.survivalReward > 0) Container(width: 1, height: 20, color: _C.border, margin: const EdgeInsets.symmetric(horizontal: 12)),
        if (t.survivalReward > 0) ...[const Icon(Icons.shield_rounded, color: _C.purpleLight, size: 16), const SizedBox(width: 6), Expanded(child: Text('₹${t.survivalReward.toInt()} survival', style: const TextStyle(color: _C.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)))],
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// JOIN BAR WIDGETS (unchanged from v3)
// ─────────────────────────────────────────────
class _JoinButton extends StatefulWidget {
  final bool isLoading; final VoidCallback onTap;
  const _JoinButton({required this.isLoading, required this.onTap});
  @override State<_JoinButton> createState() => _JoinButtonState();
}
class _JoinButtonState extends State<_JoinButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp:   (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        height: 50,
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [_C.purple, _C.purpleDim], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))]),
        child: Center(child: widget.isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('JOIN TOURNAMENT', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5))),
      )),
    );
  }
}

class _JoinedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 50, decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.success.withValues(alpha: 0.4))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_rounded, color: _C.success, size: 18), SizedBox(width: 8), Text('REGISTERED', style: TextStyle(color: _C.success, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5))]));
  }
}

class _DisabledButton extends StatelessWidget {
  final String label;
  const _DisabledButton({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(height: 50, decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border)), child: Center(child: Text(label, style: const TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1))));
  }
}