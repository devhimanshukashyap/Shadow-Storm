// lib/screens/tournament_details_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Tournament Details Screen (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1:
//   PRIORITY 0 — Team tournament registration completely overhauled:
//     • Slot 0 is always auto-filled from the player's own profile (leader).
//     • Slots 1-N allow manual teammate entry (IGN + Game UID per slot).
//     • Slot count is driven by tournament.requiredSlots and tournament.maxSlots.
//     • Players can add extra optional slots up to maxSlots.
//     • All slots are saved in the participant document as teamSlots array.
//     • Duplicate UID check enforced client-side before join.
//
//   PRIORITY 0.1 — Local teammate suggestions:
//     • After a successful join, all teammate slots are saved to
//       TeammateSuggestionsService (SharedPreferences, never Firebase).
//     • While entering a teammate UID/IGN, matching suggestions appear
//       as a dropdown below the field.
//
//   PRIORITY 0.2 — MY TEAM section shows full slot list including
//     all teammates' IGN and gameUid, sourced from participant.teamSlots.
//
//   PRIORITY 2 (F1 unchanged): Room reveal uses TournamentService.isRoomRevealed().
//   PRIORITY 3 (F1 unchanged): MaintenanceGuard wraps Scaffold.
//   PRIORITY 4 (F1 unchanged): walletFrozen blocks join.
//
//   All original widgets kept intact. Only TeamSlotSection is rebuilt.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tournament_model.dart';
import '../models/team_slot_model.dart';
import '../services/tournament_service.dart';
import '../services/app_settings_service.dart';
import '../services/teammate_suggestions_service.dart';

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
  bool _isJoined     = false;
  bool _isJoining    = false;
  bool _checkingJoin = true;

  _ParticipantResult? _myResult;
  List<TeamSlot>      _myTeamSlots  = [];

  // Pending slots for the registration form (one entry per team slot).
  // Index 0 = leader (auto-filled, never null after profile load).
  // Index 1+ = teammates (null until filled by player).
  List<TeamSlot?> _pendingSlots = [];

  String _userGameUid    = '';
  String _userIgn        = '';
  String _userReadableId = '';
  bool   _profileLoaded  = false;

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

  // ─── Slot initialisation ──────────────────────────────────────────────────

  void _initPendingSlots() {
    // Build required + optional initial slots.
    // required = tournament.requiredSlots (minimum team size)
    // Start with exactly requiredSlots slots (leader + required teammates).
    final count = widget.tournament.requiredSlots.clamp(1, widget.tournament.maxSlots);
    _pendingSlots = List.generate(count, (_) => null);
  }

  // ─── Profile load ────────────────────────────────────────────────────────

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
          // Auto-fill slot 0 (leader).
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

  // ─── Join check ──────────────────────────────────────────────────────────

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
          _myTeamSlots   = rawSlots.asMap().entries
              .map((e) => TeamSlot.fromMap(e.value as Map<String, dynamic>, e.key))
              .toList();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _checkingJoin = false);
    }
  }

  // ─── JOIN ─────────────────────────────────────────────────────────────────
  //
  // PRIORITY 0: collects all pending slots, validates, passes to service.
  // PRIORITY 0.1: saves teammates to local suggestions after success.
  // PRIORITY 4: blocks if walletFrozen.

  Future<void> _joinWithTeamSlots(TournamentModel t) async {
    if (_userId == null) { _showSnack('Please log in to join tournaments.'); return; }

    final settings = await AppSettingsService.instance.getSettings();

    if (settings.maintenanceMode) {
      _showSnack('Platform is under maintenance. Please try again later.');
      return;
    }
    if (settings.walletFrozen) {
      _showSnack(settings.walletFreezeReason.isNotEmpty
          ? 'Wallet frozen: ${settings.walletFreezeReason}'
          : 'Tournament entry is disabled while wallet is frozen.');
      return;
    }
    if (t.slotsLeft <= 0) { _showSnack('Tournament is full!'); return; }

    // Collect filled slots (non-null, with non-empty gameUid for non-leader).
    final filled = _pendingSlots.whereType<TeamSlot>().toList();

    // Validate minimum required slots.
    if (filled.length < t.requiredSlots) {
      _showSnack('Please fill all ${t.requiredSlots} required player slot(s).');
      return;
    }

    // Validate all non-leader slots have gameUid.
    for (final slot in filled) {
      if (slot.slotIndex > 0 && slot.gameUid.trim().isEmpty) {
        _showSnack('Please enter a Game UID for player slot ${slot.slotIndex + 1}.');
        return;
      }
    }

    // Duplicate gameUid check.
    final uids = filled
        .where((s) => s.gameUid.trim().isNotEmpty)
        .map((s) => s.gameUid.trim())
        .toList();
    if (uids.toSet().length != uids.length) {
      _showSnack('Duplicate Game UIDs found in your team. Each player must have a unique UID.');
      return;
    }

    setState(() => _isJoining = true);

    Map<String, dynamic> profile = {};
    try {
      final doc = await _db.collection('users').doc(_userId).get();
      profile   = doc.data() ?? {};
    } catch (_) {}

    final result = await _service.joinWithTeam(
      tournamentId: _tournamentId,
      slots:        filled,
      profile:      profile,
    );

    if (!mounted) return;

    if (result.success) {
      // PRIORITY 0.1: Save teammates locally (non-blocking).
      TeammateSuggestionsService.instance.saveFromSlots(filled).catchError((_) {});

      setState(() {
        _isJoined    = true;
        _isJoining   = false;
        _myTeamSlots = filled;
      });
      _showSuccessSnack('You\'re in! Good luck, ${_user?.displayName?.split(' ').first ?? 'Striker'}!');
    } else {
      setState(() => _isJoining = false);
      _showSnack(result.error ?? 'Failed to join. Please try again.');
    }
  }

  // ─── Snacks ──────────────────────────────────────────────────────────────

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

  // ─── BUILD ────────────────────────────────────────────────────────────────

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

  // ─── BODY ─────────────────────────────────────────────────────────────────

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
        // PRIORITY 0: Show team slot section for ALL team-mode tournaments,
        // not just _isTeamTournament — solo tournaments get a single-slot
        // confirmation view, team tournaments get the full slot editor.
        if (!_isJoined && !_checkingJoin) ...[
          const SizedBox(height: 16),
          _TeamSlotSection(
            tournament:    t,
            slots:         _pendingSlots,
            profileLoaded: _profileLoaded,
            service:       _service,
            onSlotsChanged: (updated) => setState(() => _pendingSlots = updated),
          ),
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

  // ─── SLIVER APP BAR ───────────────────────────────────────────────────────

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

  // ─── INFO ROW ─────────────────────────────────────────────────────────────

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

  // ─── ROOM SECTION ─────────────────────────────────────────────────────────

  Widget _buildRoomSection(TournamentModel t) {
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

  Widget _buildMyResultSection(_ParticipantResult result) {
    Color placementColor;
    if (result.placement == 1) {
      placementColor = _C.gold;
    } else if (result.placement <= 3) {
      placementColor = const Color(0xFFC0C0C0);
    } else if (result.placement <= 10) {
      placementColor = _C.success;
    } else {
      placementColor = _C.textSecondary;
    }

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
            if (t.killReward > 0) ...[const SizedBox(height: 10), _RewardBubble(icon: Icons.sports_kabaddi_rounded, color: _C.live, title: 'Kill Reward — ₹${t.killReward.toInt()} per kill', desc: 'Earn ₹${t.killReward.toInt()} for every elimination.')],
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

  // ─── JOIN BAR ─────────────────────────────────────────────────────────────

  Widget _buildJoinBar(TournamentModel t) {
    final isCompleted = t.status == TournamentStatus.completed;
    final isCancelled = t.status == TournamentStatus.cancelled;
    final isLive      = t.status == TournamentStatus.live;

    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.instance.settingsStream,
      builder: (context, settingsSnap) {
        final settings    = settingsSnap.data ?? const AppSettings();
        final frozen      = settings.walletFrozen;
        final maintenance = settings.maintenanceMode;

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

// ═════════════════════════════════════════════════════════════════════════════
// TEAM SLOT SECTION — PRIORITY 0 REWRITE
//
// Handles all team modes: Solo (1 slot), Duo (2), 3v3 (3), Squad (4), etc.
// Slot 0 = auto-filled leader (current user, read-only).
// Slots 1+ = teammate entry with IGN + Game UID fields + suggestions dropdown.
//
// Dynamic slot management:
//   • Starts with tournament.requiredSlots slots.
//   • Player can add up to tournament.maxSlots total.
//   • Player can remove down to tournament.requiredSlots minimum.
// ═════════════════════════════════════════════════════════════════════════════

class _TeamSlotSection extends StatefulWidget {
  final TournamentModel                  tournament;
  final List<TeamSlot?>                  slots;
  final bool                             profileLoaded;
  final TournamentService                service;
  final void Function(List<TeamSlot?>)   onSlotsChanged;

  const _TeamSlotSection({
    required this.tournament,
    required this.slots,
    required this.profileLoaded,
    required this.service,
    required this.onSlotsChanged,
  });

  @override
  State<_TeamSlotSection> createState() => _TeamSlotSectionState();
}

class _TeamSlotSectionState extends State<_TeamSlotSection> {
  // Controllers keyed by slot index (1+).
  final Map<int, TextEditingController> _uidCtrl = {};
  final Map<int, TextEditingController> _ignCtrl = {};

  // Lookup/suggestion state.
  final Map<int, bool>             _lookingUp   = {};
  final Map<int, String?>          _uidWarning  = {};
  final Map<int, bool>             _showSuggest = {};
  final Map<int, List<TeammateEntry>> _suggestions = {};

  @override
  void initState() {
    super.initState();
    _buildControllers();
  }

  void _buildControllers() {
    for (var i = 1; i < widget.slots.length; i++) {
      _uidCtrl[i] ??= TextEditingController(text: widget.slots[i]?.gameUid ?? '');
      _ignCtrl[i] ??= TextEditingController(text: widget.slots[i]?.ign     ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _uidCtrl.values) {
      c.dispose();
    }
    for (final c in _ignCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Slot add / remove ────────────────────────────────────────────────────

  void _addSlot() {
    final t = widget.tournament;
    if (widget.slots.length >= t.maxSlots) return;
    final i = widget.slots.length;
    _uidCtrl[i] = TextEditingController();
    _ignCtrl[i] = TextEditingController();
    widget.onSlotsChanged([...widget.slots, null]);
  }

  void _removeSlot(int index) {
    final t = widget.tournament;
    if (index == 0) return; // never remove leader
    if (widget.slots.length <= t.requiredSlots) return;

    // Dispose controllers for the removed index.
    _uidCtrl[index]?.dispose(); _uidCtrl.remove(index);
    _ignCtrl[index]?.dispose(); _ignCtrl.remove(index);
    _uidWarning.remove(index);
    _lookingUp.remove(index);
    _showSuggest.remove(index);
    _suggestions.remove(index);

    final updated = List<TeamSlot?>.from(widget.slots)..removeAt(index);

    // Re-key controllers for indices above the removed one.
    // Build fresh maps with corrected indices.
    final newUid = <int, TextEditingController>{};
    final newIgn = <int, TextEditingController>{};
    for (var j = 1; j < updated.length; j++) {
      final origIdx = j < index ? j : j + 1;
      newUid[j] = _uidCtrl[origIdx] ?? TextEditingController();
      newIgn[j] = _ignCtrl[origIdx] ?? TextEditingController();
    }
    _uidCtrl
      ..clear()
      ..addAll(newUid);
    _ignCtrl
      ..clear()
      ..addAll(newIgn);

    widget.onSlotsChanged(updated);
  }

  // ── Slot update ──────────────────────────────────────────────────────────

  void _updateSlot(int index) {
    final uid = _uidCtrl[index]?.text.trim() ?? '';
    final ign = _ignCtrl[index]?.text.trim() ?? '';
    final updated = List<TeamSlot?>.from(widget.slots);
    updated[index] = uid.isEmpty && ign.isEmpty
        ? null
        : TeamSlot(slotIndex: index, gameUid: uid, ign: ign);
    widget.onSlotsChanged(updated);
  }

  // ── Suggestion search ────────────────────────────────────────────────────

  void _onUidChanged(int index, String value) {
    _updateSlot(index);

    // Show suggestions when the player starts typing.
    final results = TeammateSuggestionsService.instance.search(value);
    setState(() {
      _suggestions[index]  = results;
      _showSuggest[index]  = results.isNotEmpty;
    });

    // Trigger UID lookup when long enough.
    if (value.trim().length >= 6) {
      _lookupGameUid(index, value.trim());
    } else {
      setState(() => _uidWarning[index] = null);
    }
  }

  void _onIgnChanged(int index, String value) {
    _updateSlot(index);
    // Also search suggestions by IGN.
    if (value.trim().length >= 2) {
      final results = TeammateSuggestionsService.instance.search(value);
      setState(() {
        _suggestions[index] = results;
        _showSuggest[index] = results.isNotEmpty;
      });
    }
  }

  Future<void> _lookupGameUid(int index, String gameUid) async {
    if (_lookingUp[index] == true) return;
    setState(() => _lookingUp[index] = true);

    final player = await widget.service.lookupPlayerByGameUid(gameUid);
    if (!mounted) return;

    setState(() {
      _lookingUp[index] = false;
      if (player == null) {
        _uidWarning[index] = null;
      } else {
        final level    = (player['gameLevel'] as num?)?.toInt() ?? 0;
        final minLevel = widget.tournament.minimumLevel;
        _uidWarning[index] = level > 0 && level < minLevel
            ? 'Level $level is below the minimum ($minLevel).'
            : null;
        // Auto-fill IGN if field is empty.
        final regIgn = player['ign'] as String? ?? '';
        if (regIgn.isNotEmpty && (_ignCtrl[index]?.text.isEmpty == true)) {
          _ignCtrl[index]?.text = regIgn;
          _updateSlot(index);
        }
      }
    });
  }

  void _applySuggestion(int index, TeammateEntry suggestion) {
    _uidCtrl[index]?.text = suggestion.gameUid;
    _ignCtrl[index]?.text = suggestion.ign;
    setState(() {
      _showSuggest[index]  = false;
      _suggestions[index]  = [];
    });
    _updateSlot(index);
    if (suggestion.gameUid.trim().length >= 6) {
      _lookupGameUid(index, suggestion.gameUid.trim());
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t          = widget.tournament;
    final isSolo     = t.requiredSlots <= 1 && t.maxSlots <= 1;
    final canAddMore = widget.slots.length < t.maxSlots;
    final canRemove  = widget.slots.length > t.requiredSlots;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.surfaceCard, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _C.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Section header.
          Row(children: [
            const Icon(Icons.group_rounded, color: _C.purple, size: 16),
            const SizedBox(width: 8),
            Text(
              isSolo ? 'REGISTRATION' : 'YOUR TEAM',
              style: const TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            const Spacer(),
            Text(
              isSolo ? '1 PLAYER' : '${widget.slots.length}/${t.maxSlots} SLOTS',
              style: const TextStyle(color: _C.textMuted, fontSize: 11),
            ),
          ]),
          const SizedBox(height: 14),

          // Slot 0 — Leader (always auto-filled, read-only).
          _buildLeaderSlot(),
          const SizedBox(height: 8),

          // Slots 1+ — Teammates.
          if (!isSolo)
            ...List.generate(widget.slots.length - 1, (i) {
              final slotIdx = i + 1;
              return _buildTeammateSlot(slotIdx);
            }),

          // Add/remove slot controls.
          if (!isSolo && (canAddMore || canRemove)) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (canRemove)
                _SlotControlBtn(
                  label: '− Remove slot',
                  color: _C.live,
                  onTap: () => _removeSlot(widget.slots.length - 1),
                ),
              if (canRemove && canAddMore) const SizedBox(width: 8),
              if (canAddMore)
                _SlotControlBtn(
                  label: '+ Add teammate',
                  color: _C.success,
                  onTap: _addSlot,
                ),
            ]),
          ],

          const SizedBox(height: 12),

          // Info banner.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: _C.purple, size: 13),
              const SizedBox(width: 8),
              Expanded(child: Text(
                isSolo
                    ? 'Your profile details will be used for this registration.'
                    : 'Enter each teammate\'s in-game UID and name. '
                      'Minimum level ${t.minimumLevel} required.',
                style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4),
              )),
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
      decoration: BoxDecoration(
        color: _C.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.purple.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _C.purple.withValues(alpha: 0.2), shape: BoxShape.circle,
            border: Border.all(color: _C.purple.withValues(alpha: 0.5)),
          ),
          child: const Center(child: Text('1', style: TextStyle(color: _C.purple, fontSize: 12, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: widget.profileLoaded
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    slot?.ign.isNotEmpty == true ? slot!.ign : 'Your IGN',
                    style: const TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  if (slot?.gameUid.isNotEmpty == true)
                    Text('UID: ${slot!.gameUid}',
                        style: const TextStyle(color: _C.textSecondary, fontSize: 11)),
                  if (slot?.readableId != null)
                    Text(slot!.readableId!,
                        style: const TextStyle(color: _C.textMuted, fontSize: 10)),
                ])
              : const Text('Loading your profile…',
                  style: TextStyle(color: _C.textMuted, fontSize: 12)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _C.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_rounded, color: _C.purple, size: 10),
            SizedBox(width: 4),
            Text('YOU', style: TextStyle(color: _C.purple, fontSize: 9, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildTeammateSlot(int index) {
    final warning     = _uidWarning[index];
    final looking     = _lookingUp[index] ?? false;
    final showSuggest = _showSuggest[index] ?? false;
    final suggestions = _suggestions[index] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.surfaceElevated, borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: warning != null ? _C.gold.withValues(alpha: 0.4) : _C.border,
            ),
          ),
          child: Column(children: [
            // Slot number + fields row.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _C.surfaceCard, shape: BoxShape.circle,
                    border: Border.all(color: _C.border),
                  ),
                  child: Center(child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: _C.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                  )),
                ),
              ),
              const SizedBox(width: 10),
              // UID field.
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('GAME UID', style: TextStyle(color: _C.textMuted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 3),
                TextFormField(
                  controller: _uidCtrl[index],
                  style: const TextStyle(color: _C.textPrimary, fontSize: 13),
                  keyboardType: TextInputType.number,
                  decoration: _fieldDeco(
                    'Enter game UID',
                    suffix: looking
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.purple)),
                          )
                        : null,
                  ),
                  onChanged: (v) => _onUidChanged(index, v),
                ),
              ])),
              const SizedBox(width: 8),
              // IGN field.
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('IN-GAME NAME', style: TextStyle(color: _C.textMuted, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 3),
                TextFormField(
                  controller: _ignCtrl[index],
                  style: const TextStyle(color: _C.textPrimary, fontSize: 13),
                  decoration: _fieldDeco('Enter IGN'),
                  onChanged: (v) => _onIgnChanged(index, v),
                ),
              ])),
            ]),

            // Warning row.
            if (warning != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 38),
                const Icon(Icons.warning_amber_rounded, color: _C.gold, size: 13),
                const SizedBox(width: 6),
                Expanded(child: Text(warning, style: const TextStyle(color: _C.gold, fontSize: 11))),
              ]),
            ],
          ]),
        ),

        // Suggestion dropdown.
        if (showSuggest && suggestions.isNotEmpty)
          _SuggestionDropdown(
            suggestions: suggestions,
            onSelect:    (s) => _applySuggestion(index, s),
            onDismiss:   () => setState(() => _showSuggest[index] = false),
          ),
      ],
    );
  }

  InputDecoration _fieldDeco(String label, {Widget? suffix}) => InputDecoration(
    labelText:       label,
    suffixIcon:      suffix,
    labelStyle:      const TextStyle(color: _C.textMuted, fontSize: 11),
    filled:          true,
    fillColor:       _C.surfaceCard,
    isDense:         true,
    contentPadding:  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.border)),
    enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.border)),
    focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.purple, width: 1.5)),
  );
}

// ─────────────────────────────────────────────
// SUGGESTION DROPDOWN — PRIORITY 0.1
// ─────────────────────────────────────────────

class _SuggestionDropdown extends StatelessWidget {
  final List<TeammateEntry>          suggestions;
  final void Function(TeammateEntry) onSelect;
  final VoidCallback                  onDismiss;

  const _SuggestionDropdown({
    required this.suggestions,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 38, bottom: 6),
      decoration: BoxDecoration(
        color: _C.surfaceElevated, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.purple.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: _C.purpleGlow.withValues(alpha: 0.3), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              const Icon(Icons.history_rounded, color: _C.textMuted, size: 11),
              const SizedBox(width: 6),
              const Text('RECENT TEAMMATES', style: TextStyle(color: _C.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const Spacer(),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(Icons.close_rounded, color: _C.textMuted, size: 14),
              ),
            ]),
          ),
          Container(height: 1, color: _C.border),
          // Suggestion list.
          ...suggestions.take(5).map((s) => GestureDetector(
            onTap: () => onSelect(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _C.border.withValues(alpha: 0.5))),
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _C.purple.withValues(alpha: 0.1), shape: BoxShape.circle,
                    border: Border.all(color: _C.purple.withValues(alpha: 0.3)),
                  ),
                  child: Center(child: Text(
                    s.ign.isNotEmpty ? s.ign[0].toUpperCase() : '?',
                    style: const TextStyle(color: _C.purple, fontSize: 11, fontWeight: FontWeight.w800),
                  )),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.ign.isNotEmpty ? s.ign : 'Unknown', style: const TextStyle(color: _C.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(s.gameUid, style: const TextStyle(color: _C.textSecondary, fontSize: 10)),
                ])),
                const Icon(Icons.north_west_rounded, color: _C.textMuted, size: 12),
              ]),
            ),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MY TEAM SECTION — PRIORITY 0.2
//
// Displays full team roster after successful registration.
// Shows all slots from participant.teamSlots including teammates.
// ─────────────────────────────────────────────

class _MyTeamSection extends StatelessWidget {
  final List<TeamSlot>           slots;
  final void Function(String, String) onCopy;

  const _MyTeamSection({required this.slots, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.surfaceCard, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.purple.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.group_rounded, color: _C.purple, size: 16),
            const SizedBox(width: 8),
            const Text('MY TEAM', style: TextStyle(color: _C.textSecondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            Text('${slots.length} player${slots.length == 1 ? '' : 's'}',
                style: const TextStyle(color: _C.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          ...slots.asMap().entries.map((e) => _buildSlotRow(e.key, e.value)),
        ]),
      ),
    );
  }

  Widget _buildSlotRow(int index, TeamSlot slot) {
    final displayUid = slot.gameUid.length > 10
        ? '${slot.gameUid.substring(0, 10)}…'
        : slot.gameUid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: slot.isLeader ? _C.purple.withValues(alpha: 0.15) : _C.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: slot.isLeader ? _C.purple.withValues(alpha: 0.4) : _C.border),
          ),
          child: Center(child: Text(
            '${index + 1}',
            style: TextStyle(
              color: slot.isLeader ? _C.purple : _C.textMuted,
              fontSize: 11, fontWeight: FontWeight.w700,
            ),
          )),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(
              slot.ign.isNotEmpty ? slot.ign : 'Unknown',
              style: const TextStyle(color: _C.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            )),
            if (slot.isLeader) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _C.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('YOU', style: TextStyle(color: _C.purple, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
          if (slot.gameUid.isNotEmpty)
            Row(children: [
              Text(displayUid, style: const TextStyle(color: _C.textSecondary, fontSize: 11)),
              if (slot.readableId != null) ...[
                const Text(' · ', style: TextStyle(color: _C.textMuted)),
                Text(slot.readableId!, style: const TextStyle(color: _C.textMuted, fontSize: 11)),
              ],
            ]),
        ])),
        if (slot.gameUid.isNotEmpty)
          GestureDetector(
            onTap: () => onCopy(slot.gameUid, 'Game UID'),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.border),
              ),
              child: const Icon(Icons.copy_rounded, color: _C.purple, size: 13),
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// SLOT CONTROL BUTTON
// ─────────────────────────────────────────────

class _SlotControlBtn extends StatelessWidget {
  final String   label;
  final Color    color;
  final VoidCallback onTap;

  const _SlotControlBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
// ALL REMAINING WIDGETS — UNCHANGED FROM F1
// (BannerHeader, RoomWidgets, PrizeSections, JoinBar atoms, etc.)
// ════════════════════════════════════════════════════════════════════

class _BannerHeader extends StatelessWidget {
  final TournamentModel tournament; final Animation<double> pulse;
  const _BannerHeader({required this.tournament, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final t         = tournament;
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

class _RoomNotYetRevealed extends StatelessWidget {
  final TournamentModel tournament;
  const _RoomNotYetRevealed({required this.tournament});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.gold.withValues(alpha: 0.25))),
      child: const Row(children: [
        Icon(Icons.lock_clock_rounded, color: _C.gold, size: 20), SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Room details not yet revealed', style: TextStyle(color: _C.gold, fontSize: 13, fontWeight: FontWeight.w700)),
          SizedBox(height: 2),
          Text('Credentials will be available 30 minutes before match start.', style: TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4)),
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
      if (hasRoom) _RoomField(label: 'ROOM ID',   value: t.roomId!,       icon: Icons.meeting_room_rounded, onCopy: () => onCopy(t.roomId!, 'Room ID')),
      if (hasRoom && hasPw) const SizedBox(height: 10),
      if (hasPw)   _RoomField(label: 'PASSWORD',  value: t.roomPassword!, icon: Icons.vpn_key_rounded,      onCopy: () => onCopy(t.roomPassword!, 'Password')),
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

class _StatusBadge extends StatelessWidget {
  final TournamentStatus status; final Animation<double> pulse;
  const _StatusBadge({required this.status, required this.pulse});
  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (status) {
      case TournamentStatus.live:      color = _C.live;      label = 'LIVE NOW';  break;
      case TournamentStatus.completed: color = _C.textMuted; label = 'COMPLETED'; break;
      case TournamentStatus.cancelled: color = _C.live;      label = 'CANCELLED'; break;
      case TournamentStatus.upcoming:  color = _C.purple;    label = 'UPCOMING';  break;
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