// lib/admin/pages/admin_tournaments_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Tournaments Page
// Phase 4: Full tournament lifecycle management UI
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart';
import '../theme/admin_theme.dart';
import '../services/admin_tournament_service.dart';

enum _RevealPreset {
  immediately,
  oneHourBefore,
  thirtyMinsBefore,
  fifteenMinsBefore,
  custom,
}

// ─────────────────────────────────────────────
// PRESET DATA
// ─────────────────────────────────────────────
class _Presets {
  static const battleRoyaleMaps = [
    'Bermuda', 'Bermuda Remastered', 'Purgatory',
    'Alpine', 'Kalahari', 'Nexterra', 'Random Map',
  ];
  static const clashSquadMaps = [
    'Bermuda CS', 'Kalahari CS', 'Alpine CS', 'Random CS',
  ];
  static List<String> mapsForType(String type) {
    if (type == 'clash_squad') return clashSquadMaps;
    return battleRoyaleMaps;
  }

  static const tournamentTypes = [
    ('battle_royale', 'Battle Royale', Icons.public_rounded),
    ('clash_squad',   'Clash Squad',   Icons.shield_rounded),
    ('lone_wolf',     'Lone Wolf',     Icons.person_rounded),
    ('lose_to_win',   'Lose To Win',   Icons.emoji_events_rounded),
    ('custom_league', 'Custom League', Icons.leaderboard_rounded),
    ('1v1_arena',     '1v1 Arena',     Icons.sports_kabaddi_rounded),
    ('2v2_arena',     '2v2 Arena',     Icons.group_rounded),
    ('sniper',        'Sniper Challenge', Icons.gps_fixed_rounded),
  ];

  static const modes = ['Solo', 'Duo', 'Squad', '2v2', '3v3', '4v4'];

  static const rewardTypes = [
    ('position', 'Placement Only'),
    ('kill',     'Kill Reward'),
    ('survival', 'Survival Reward'),
    ('mixed',    'Mixed Rewards'),
    ('winner',   'Winner Takes All'),
  ];

  static const List<int> maxPlayerOptions = [2, 4, 6, 8, 10, 12, 16, 20, 24, 30, 48, 60, 100];
  static const List<int> minimumLevels    = [0, 1, 5, 10, 15, 20, 25, 30, 40, 50];
}

// ─────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────
class AdminTournamentsPage extends StatefulWidget {
  const AdminTournamentsPage({super.key});

  @override
  State<AdminTournamentsPage> createState() => _AdminTournamentsPageState();
}

class _AdminTournamentsPageState extends State<AdminTournamentsPage>
    with SingleTickerProviderStateMixin {
  final _service = AdminTournamentService.instance;

  // ── Filters ──────────────────────────────────
  String _statusFilter = 'all';
  String _searchQuery  = '';
  final _searchCtrl = TextEditingController();

  // ── Analytics ────────────────────────────────
  TournamentAnalytics? _analytics;

  // ── Tab controller for status filters ────────
  late TabController _tabCtrl;
  final _statusTabs = ['all', 'upcoming', 'live', 'completed', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _statusTabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) return;
      setState(() => _statusFilter = _statusTabs[_tabCtrl.index]);
    });
    _loadAnalytics();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnalytics() async {
    try {
      final a = await _service.getAnalytics();
      if (mounted) setState(() => _analytics = a);
    } catch (_) {}
  }

  // ── Snackbar ──────────────────────────────────
  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          isError ? Icons.error_rounded : Icons.check_circle_rounded,
          color: isError ? AdminColors.danger : AdminColors.success,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(color: AdminColors.textPrimary))),
      ]),
      backgroundColor: AdminColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: (isError ? AdminColors.danger : AdminColors.success).withValues(alpha: 0.4),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    return AdminPageContainer(
      title:    'Tournament Management',
      subtitle: 'Create, manage and distribute prizes for esports tournaments',
      actions: [
        AdminActionButton(
          label:   'New Tournament',
          icon:    Icons.add_rounded,
          color:   AdminColors.gold,
          onTap:   () => _showCreateDialog(context),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Analytics cards ────────────────────
          _buildAnalyticsCards(isDesktop),
          const SizedBox(height: 24),

          // ── Filters + search ───────────────────
          _buildFiltersBar(),
          const SizedBox(height: 16),

          // ── Tournament stream ──────────────────
          StreamBuilder<List<AdminTournament>>(
            stream: _service.tournamentsStream(
              statusFilter: _statusFilter == 'all' ? null : _statusFilter,
            ),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _buildShimmer(isDesktop);
              }
              if (snap.hasError) {
                return _buildError(snap.error.toString());
              }
              final all = snap.data ?? [];
              final filtered = _searchQuery.isEmpty
                  ? all
                  : all.where((t) =>
                      t.title.toLowerCase().contains(_searchQuery) ||
                      t.tournamentType.toLowerCase().contains(_searchQuery) ||
                      t.mode.toLowerCase().contains(_searchQuery) ||
                      t.map.toLowerCase().contains(_searchQuery)).toList();

              if (filtered.isEmpty) return _buildEmpty();

              if (isDesktop) {
                return _TournamentTable(
                  tournaments: filtered,
                  onView:      (t) => _showParticipantsDialog(context, t),
                  onEdit:      (t) => _showEditDialog(context, t),
                  onStatus:    (t) => _showStatusDialog(context, t),
                  onFeature:   (t) => _toggleFeatured(t),
                  onDuplicate: (t) => _duplicateTournament(t),
                  onRoom:      (t) => _showRoomDialog(context, t),
                  onPrize:     (t) => _showPrizeDialog(context, t),
                  onCancel:    (t) => _showCancelDialog(context, t),
                  onDelete:    (t) => _showDeleteDialog(context, t),
                );
              }

              return _TournamentCardList(
                tournaments: filtered,
                onView:      (t) => _showParticipantsDialog(context, t),
                onEdit:      (t) => _showEditDialog(context, t),
                onStatus:    (t) => _showStatusDialog(context, t),
                onFeature:   (t) => _toggleFeatured(t),
                onDuplicate: (t) => _duplicateTournament(t),
                onRoom:      (t) => _showRoomDialog(context, t),
                onPrize:     (t) => _showPrizeDialog(context, t),
                onCancel:    (t) => _showCancelDialog(context, t),
                onDelete:    (t) => _showDeleteDialog(context, t),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ANALYTICS CARDS
  // ──────────────────────────────────────────────
  Widget _buildAnalyticsCards(bool isDesktop) {
    final a = _analytics;
    return AdminSectionCard(
      title:      'TOURNAMENT ANALYTICS',
      titleIcon:  Icons.analytics_rounded,
      titleColor: AdminColors.gold,
      titleActions: [
        GestureDetector(
          onTap: _loadAnalytics,
          child: const Icon(Icons.refresh_rounded, color: AdminColors.textMuted, size: 16),
        ),
      ],
      child: AdminGrid(
        mobileColumns:  2,
        tabletColumns:  4,
        desktopColumns: 8,
        spacing:    10,
        runSpacing: 10,
        children: [
          _MiniStat('Total',     a?.total.toString()     ?? '—', AdminColors.purple,    Icons.emoji_events_rounded),
          _MiniStat('Upcoming',  a?.upcoming.toString()  ?? '—', AdminColors.info,       Icons.schedule_rounded),
          _MiniStat('Live',      a?.live.toString()      ?? '—', AdminColors.danger,     Icons.circle_rounded),
          _MiniStat('Completed', a?.completed.toString() ?? '—', AdminColors.success,    Icons.check_circle_rounded),
          _MiniStat('Cancelled', a?.cancelled.toString() ?? '—', AdminColors.textMuted,  Icons.cancel_rounded),
          _MiniStat('Prize Pools',
              a != null ? '₹${_fmt(a.totalPrizePools)}' : '—', AdminColors.gold, Icons.workspace_premium_rounded),
          _MiniStat('Entry Collected',
              a != null ? '₹${_fmt(a.totalEntryCollected)}' : '—', AdminColors.success, Icons.add_circle_rounded),
          _MiniStat('Distributed',
              a != null ? '₹${_fmt(a.totalDistributed)}' : '—', AdminColors.purple, Icons.card_giftcard_rounded),
        ],
      ),
    );
  }

  Widget _MiniStat(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Expanded(child: Text(label,
                style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: AdminTextStyles.titleSmall.copyWith(color: color, fontSize: 16),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // FILTERS BAR
  // ──────────────────────────────────────────────
  Widget _buildFiltersBar() {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 2,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color:        AdminColors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AdminColors.border),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: AdminTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText:   'Search tournaments…',
                hintStyle:  AdminTextStyles.bodySmall,
                prefixIcon: Icon(Icons.search_rounded, color: AdminColors.textMuted, size: 18),
                border:     InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase().trim()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Status tabs
        Expanded(
          flex: 3,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color:        AdminColors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AdminColors.border),
            ),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor:   AdminColors.gold,
              indicatorWeight:  2,
              labelColor:       AdminColors.gold,
              unselectedLabelColor: AdminColors.textMuted,
              labelStyle:       AdminTextStyles.labelSmall.copyWith(fontSize: 10),
              unselectedLabelStyle: AdminTextStyles.labelSmall.copyWith(fontSize: 10),
              dividerColor:     Colors.transparent,
              tabs: const [
                Tab(text: 'ALL'),
                Tab(text: 'UPCOMING'),
                Tab(text: 'LIVE'),
                Tab(text: 'COMPLETED'),
                Tab(text: 'CANCELLED'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // EMPTY / ERROR / SHIMMER STATES
  // ──────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  AdminColors.gold.withValues(alpha: 0.08),
                border: Border.all(color: AdminColors.gold.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: AdminColors.gold, size: 32),
            ),
            const SizedBox(height: 16),
            Text('No tournaments found', style: AdminTextStyles.titleMedium),
            const SizedBox(height: 6),
            Text('Try adjusting filters or create a new tournament',
                style: AdminTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 40),
        const SizedBox(height: 12),
        Text('Failed to load tournaments', style: AdminTextStyles.titleSmall),
        Text(err, style: AdminTextStyles.bodySmall, textAlign: TextAlign.center),
      ]),
    ));
  }

  Widget _buildShimmer(bool isDesktop) {
    return Column(
      children: List.generate(4, (i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 72,
        decoration: BoxDecoration(
          color:        AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: AdminColors.border),
        ),
      )),
    );
  }

  // ──────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────
  Future<void> _toggleFeatured(AdminTournament t) async {
    try {
      await _service.setFeatured(t.id, t.title, !t.featured);
      _snack(t.featured ? 'Tournament unfeatured' : 'Tournament featured!');
      _loadAnalytics();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  Future<void> _duplicateTournament(AdminTournament t) async {
    try {
      await _service.duplicateTournament(t);
      _snack('Tournament duplicated!');
      _loadAnalytics();
    } catch (e) {
      _snack('Error: $e', isError: true);
    }
  }

  // ──────────────────────────────────────────────
  // DIALOGS
  // ──────────────────────────────────────────────
  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _TournamentFormDialog(
        title:    'Create Tournament',
        onSubmit: (data) async {
          await _service.createTournament(data);
          _snack('Tournament created!');
          _loadAnalytics();
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _TournamentFormDialog(
        title:      'Edit Tournament',
        tournament: t,
        onSubmit:   (data) async {
          await _service.updateTournament(t.id, data);
          _snack('Tournament updated!');
        },
      ),
    );
  }

  void _showStatusDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      builder: (_) => _StatusDialog(
        tournament: t,
        onUpdate: (newStatus) async {
          await _service.updateStatus(t.id, newStatus);
          _snack('Status updated to $newStatus');
          _loadAnalytics();
        },
      ),
    );
  }

  void _showParticipantsDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _ParticipantsDialog(tournament: t, service: _service),
    );
  }

  void _showRoomDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      builder: (_) => _RoomCredentialsDialog(
        tournament: t,
        onSave: (roomId, roomPw, revealTime) async {
          await _service.updateRoomCredentials(
            id:             t.id,
            title:          t.title,
            roomId:         roomId,
            roomPassword:   roomPw,
            roomRevealTime: revealTime != null ? Timestamp.fromDate(revealTime) : null,
          );
          _snack('Room credentials updated!');
        },
      ),
    );
  }

  void _showPrizeDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => _PrizeDistributionDialog(
        tournament: t,
        service:    _service,
        onSuccess:  () {
          _snack('Prizes distributed!');
          _loadAnalytics();
        },
      ),
    );
  }

  void _showCancelDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:   'Cancel Tournament',
        icon:    Icons.cancel_rounded,
        color:   AdminColors.danger,
        message: 'This will cancel "${t.title}" and refund ₹${t.entryFee.toStringAsFixed(0)} to all ${t.joinedPlayers} registered players.\n\nThis action cannot be undone.',
        confirmLabel: 'Cancel & Refund',
        onConfirm: () async {
          await _service.cancelWithRefund(
            tournamentId:    t.id,
            tournamentTitle: t.title,
            entryFee:        t.entryFee,
          );
          _snack('Tournament cancelled. Refunds issued.');
          _loadAnalytics();
        },
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, AdminTournament t) {
    showDialog(
      context: context,
      builder: (_) => _ConfirmDialog(
        title:   'Delete Tournament',
        icon:    Icons.delete_rounded,
        color:   AdminColors.danger,
        message: 'Permanently delete "${t.title}"?\n\nOnly upcoming tournaments with 0 participants can be deleted.',
        confirmLabel: 'Delete',
        onConfirm: () async {
          await _service.deleteTournament(t.id, t.title);
          _snack('Tournament deleted.');
          _loadAnalytics();
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────
  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────
// DESKTOP TABLE
// ─────────────────────────────────────────────
class _TournamentTable extends StatelessWidget {
  final List<AdminTournament> tournaments;
  final void Function(AdminTournament) onView;
  final void Function(AdminTournament) onEdit;
  final void Function(AdminTournament) onStatus;
  final void Function(AdminTournament) onFeature;
  final void Function(AdminTournament) onDuplicate;
  final void Function(AdminTournament) onRoom;
  final void Function(AdminTournament) onPrize;
  final void Function(AdminTournament) onCancel;
  final void Function(AdminTournament) onDelete;

  const _TournamentTable({
    required this.tournaments,
    required this.onView,
    required this.onEdit,
    required this.onStatus,
    required this.onFeature,
    required this.onDuplicate,
    required this.onRoom,
    required this.onPrize,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      title:     'TOURNAMENTS',
      titleIcon: Icons.emoji_events_rounded,
      titleColor: AdminColors.gold,
      titleActions: [
        AdminBadge(
          label:   '${tournaments.length} total',
          color:   AdminColors.textMuted,
        ),
      ],
      contentPadding: EdgeInsets.zero,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AdminColors.border)),
              color:  AdminColors.surfaceElevated,
            ),
            child: Row(children: [
              Expanded(flex: 3, child: Text('TOURNAMENT', style: _hStyle)),
              Expanded(flex: 2, child: Text('TYPE / MODE', style: _hStyle)),
              Expanded(flex: 1, child: Text('SLOTS',  style: _hStyle)),
              Expanded(flex: 1, child: Text('ENTRY',  style: _hStyle)),
              Expanded(flex: 1, child: Text('PRIZE',  style: _hStyle)),
              Expanded(flex: 1, child: Text('STATUS', style: _hStyle)),
              SizedBox(width: 220, child: Text('ACTIONS', style: _hStyle)),
            ]),
          ),
          ...tournaments.map((t) => _TournamentRow(
            tournament: t,
            onView:      () => onView(t),
            onEdit:      () => onEdit(t),
            onStatus:    () => onStatus(t),
            onFeature:   () => onFeature(t),
            onDuplicate: () => onDuplicate(t),
            onRoom:      () => onRoom(t),
            onPrize:     () => onPrize(t),
            onCancel:    () => onCancel(t),
            onDelete:    () => onDelete(t),
          )),
        ],
      ),
    );
  }

  static final _hStyle = AdminTextStyles.labelSmall.copyWith(
      color: AdminColors.textMuted, letterSpacing: 1.2, fontSize: 9);
}

class _TournamentRow extends StatefulWidget {
  final AdminTournament tournament;
  final VoidCallback onView, onEdit, onStatus, onFeature,
                     onDuplicate, onRoom, onPrize, onCancel, onDelete;

  const _TournamentRow({
    required this.tournament,
    required this.onView, required this.onEdit, required this.onStatus,
    required this.onFeature, required this.onDuplicate, required this.onRoom,
    required this.onPrize, required this.onCancel, required this.onDelete,
  });

  @override
  State<_TournamentRow> createState() => _TournamentRowState();
}

class _TournamentRowState extends State<_TournamentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered
              ? AdminColors.surfaceElevated.withValues(alpha: 0.5)
              : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AdminColors.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Title col
          Expanded(flex: 3, child: Row(children: [
            if (t.featured)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.star_rounded, color: AdminColors.gold, size: 13),
              ),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: AdminTextStyles.titleSmall, overflow: TextOverflow.ellipsis),
                Text(t.map,   style: AdminTextStyles.bodySmall,  overflow: TextOverflow.ellipsis),
              ],
            )),
          ])),

          // Type / mode
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_typeLabel(t.tournamentType), style: AdminTextStyles.bodyMedium),
              Text(t.mode,                       style: AdminTextStyles.bodySmall),
            ],
          )),

          // Slots
          Expanded(flex: 1, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.joinedPlayers}/${t.maxPlayers}',
                  style: AdminTextStyles.titleSmall.copyWith(
                      color: t.joinedPlayers >= t.maxPlayers
                          ? AdminColors.danger : AdminColors.textPrimary)),
              LinearProgressIndicator(
                value: t.maxPlayers > 0 ? t.joinedPlayers / t.maxPlayers : 0,
                backgroundColor: AdminColors.border,
                color: t.joinedPlayers >= t.maxPlayers
                    ? AdminColors.danger : AdminColors.purple,
                minHeight: 3,
              ),
            ],
          )),

          // Entry
          Expanded(flex: 1, child: Text(
            t.entryFee > 0 ? '₹${t.entryFee.toStringAsFixed(0)}' : 'FREE',
            style: AdminTextStyles.bodyMedium.copyWith(
                color: t.entryFee > 0 ? AdminColors.textPrimary : AdminColors.success),
          )),

          // Prize
          Expanded(flex: 1, child: Text(
            '₹${t.prizePool.toStringAsFixed(0)}',
            style: AdminTextStyles.titleSmall.copyWith(color: AdminColors.gold),
          )),

          // Status
          Expanded(flex: 1, child: _StatusBadge(status: t.status)),

          // Actions
          SizedBox(
            width: 220,
            child: _ActionMenu(
              tournament: t,
              onView:      widget.onView,
              onEdit:      widget.onEdit,
              onStatus:    widget.onStatus,
              onFeature:   widget.onFeature,
              onDuplicate: widget.onDuplicate,
              onRoom:      widget.onRoom,
              onPrize:     widget.onPrize,
              onCancel:    widget.onCancel,
              onDelete:    widget.onDelete,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MOBILE CARD LIST
// ─────────────────────────────────────────────
class _TournamentCardList extends StatelessWidget {
  final List<AdminTournament> tournaments;
  final void Function(AdminTournament) onView;
  final void Function(AdminTournament) onEdit;
  final void Function(AdminTournament) onStatus;
  final void Function(AdminTournament) onFeature;
  final void Function(AdminTournament) onDuplicate;
  final void Function(AdminTournament) onRoom;
  final void Function(AdminTournament) onPrize;
  final void Function(AdminTournament) onCancel;
  final void Function(AdminTournament) onDelete;

  const _TournamentCardList({
    required this.tournaments,
    required this.onView, required this.onEdit, required this.onStatus,
    required this.onFeature, required this.onDuplicate, required this.onRoom,
    required this.onPrize, required this.onCancel, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: tournaments.map((t) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: AdminColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(children: [
                if (t.featured)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.star_rounded, color: AdminColors.gold, size: 14),
                  ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: AdminTextStyles.titleSmall),
                    Text('${_typeLabel(t.tournamentType)} • ${t.mode} • ${t.map}',
                        style: AdminTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
                  ],
                )),
                _StatusBadge(status: t.status),
              ]),
            ),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                _CardStat('Entry', t.entryFee > 0 ? '₹${t.entryFee.toStringAsFixed(0)}' : 'FREE',
                    t.entryFee > 0 ? AdminColors.textPrimary : AdminColors.success),
                const SizedBox(width: 16),
                _CardStat('Prize', '₹${t.prizePool.toStringAsFixed(0)}', AdminColors.gold),
                const SizedBox(width: 16),
                _CardStat('Slots', '${t.joinedPlayers}/${t.maxPlayers}', AdminColors.info),
              ]),
            ),

            // Actions
            const Divider(color: AdminColors.border, height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  _SmallBtn('Participants', Icons.people_rounded, AdminColors.info,   () => onView(t)),
                  _SmallBtn('Edit',         Icons.edit_rounded,   AdminColors.purple, () => onEdit(t)),
                  _SmallBtn('Room',         Icons.meeting_room_rounded, AdminColors.warning, () => onRoom(t)),
                  if (t.status == 'completed' && !t.prizesDistributed)
                    _SmallBtn('Prizes', Icons.card_giftcard_rounded, AdminColors.gold, () => onPrize(t)),
                  _SmallBtn(
                    t.featured ? 'Unfeature' : 'Feature',
                    t.featured ? Icons.star_rounded : Icons.star_border_rounded,
                    AdminColors.gold,
                    () => onFeature(t),
                  ),
                  _SmallBtn('Duplicate', Icons.copy_rounded, AdminColors.textMuted, () => onDuplicate(t)),
                  if (t.status != 'completed' && t.status != 'cancelled')
                    _SmallBtn('Status', Icons.swap_horiz_rounded, AdminColors.info, () => onStatus(t)),
                  if (t.status != 'completed' && t.status != 'cancelled')
                    _SmallBtn('Cancel', Icons.cancel_rounded, AdminColors.danger, () => onCancel(t)),
                  if (t.status == 'upcoming' && t.joinedPlayers == 0)
                    _SmallBtn('Delete', Icons.delete_rounded, AdminColors.danger, () => onDelete(t)),
                ],
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _CardStat(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AdminTextStyles.labelSmall.copyWith(
          color: AdminColors.textMuted, fontSize: 9)),
      Text(value,  style: AdminTextStyles.titleSmall.copyWith(color: color)),
    ],
  );

  Widget _SmallBtn(String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(label, style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 10)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────
// ACTION MENU (desktop row)
// ─────────────────────────────────────────────
class _ActionMenu extends StatelessWidget {
  final AdminTournament tournament;
  final VoidCallback onView, onEdit, onStatus, onFeature,
                     onDuplicate, onRoom, onPrize, onCancel, onDelete;

  const _ActionMenu({
    required this.tournament,
    required this.onView, required this.onEdit, required this.onStatus,
    required this.onFeature, required this.onDuplicate, required this.onRoom,
    required this.onPrize, required this.onCancel, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(Icons.people_rounded,       AdminColors.info,      'Participants',  onView),
        _IconBtn(Icons.edit_rounded,         AdminColors.purple,    'Edit',          onEdit),
        _IconBtn(Icons.meeting_room_rounded, AdminColors.warning,   'Room',          onRoom),
        if (t.status == 'completed' && !t.prizesDistributed)
          _IconBtn(Icons.card_giftcard_rounded, AdminColors.gold, 'Distribute Prizes', onPrize),
        _IconBtn(
          t.featured ? Icons.star_rounded : Icons.star_border_rounded,
          AdminColors.gold,
          t.featured ? 'Unfeature' : 'Feature',
          onFeature,
        ),
        _IconBtn(Icons.copy_rounded, AdminColors.textMuted, 'Duplicate', onDuplicate),
        PopupMenuButton<String>(
          icon:  const Icon(Icons.more_vert_rounded, color: AdminColors.textMuted, size: 16),
          color: AdminColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AdminColors.border),
          ),
          itemBuilder: (_) => [
            if (t.status != 'completed' && t.status != 'cancelled')
              _menuItem('status',  Icons.swap_horiz_rounded,  'Change Status', AdminColors.info),
            if (t.status != 'completed' && t.status != 'cancelled')
              _menuItem('cancel',  Icons.cancel_rounded,       'Cancel & Refund', AdminColors.danger),
            if (t.status == 'upcoming' && t.joinedPlayers == 0)
              _menuItem('delete',  Icons.delete_rounded,       'Delete Tournament', AdminColors.danger),
          ],
          onSelected: (v) {
            switch (v) {
              case 'status': onStatus();    break;
              case 'cancel': onCancel();    break;
              case 'delete': onDelete();    break;
            }
          },
        ),
      ],
    );
  }

  Widget _IconBtn(IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
            border:       Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Text(label, style: AdminTextStyles.bodyMedium.copyWith(color: color)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// STATUS BADGE
// ─────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'live'      => (AdminColors.danger,  Icons.circle_rounded),
      'upcoming'  => (AdminColors.info,    Icons.schedule_rounded),
      'completed' => (AdminColors.success, Icons.check_circle_rounded),
      'cancelled' => (AdminColors.textMuted, Icons.cancel_rounded),
      _           => (AdminColors.textMuted, Icons.help_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 9),
        const SizedBox(width: 4),
        Text(status.toUpperCase(),
            style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 9)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// TOURNAMENT FORM DIALOG (Create / Edit)
// ─────────────────────────────────────────────
class _TournamentFormDialog extends StatefulWidget {
  final String             title;
  final AdminTournament?   tournament;
  final Future<void> Function(Map<String, dynamic>) onSubmit;

  const _TournamentFormDialog({
    required this.title,
    this.tournament,
    required this.onSubmit,
  });

  @override
  State<_TournamentFormDialog> createState() => _TournamentFormDialogState();
}

class _TournamentFormDialogState extends State<_TournamentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  // Controllers
  late TextEditingController _titleCtrl;
  late TextEditingController _subtitleCtrl;
  late TextEditingController _bannerCtrl;
  late TextEditingController _rulesCtrl;
  late TextEditingController _rewardDescCtrl;
  late TextEditingController _prizePoolCtrl;
  late TextEditingController _entryFeeCtrl;

  // Selectors
  late String _type;
  late String _mode;
  late String _map;
  late String _rewardType;
  late int    _maxPlayers;
  late int    _minimumLevel;
  late bool   _featured;
  late double _killReward;
  late double _survivalReward;
  late Map<String, double> _positions; // rank string → amount
  DateTime? _startTime;

  // Positions controllers
  final Map<String, TextEditingController> _posCtrl = {};

  @override
  void initState() {
    super.initState();
    final t = widget.tournament;
    _titleCtrl      = TextEditingController(text: t?.title       ?? '');
    _subtitleCtrl   = TextEditingController(text: t?.subtitle    ?? '');
    _bannerCtrl     = TextEditingController(text: t?.bannerUrl   ?? '');
    _rulesCtrl      = TextEditingController(text: t?.rules       ?? '');
    _rewardDescCtrl = TextEditingController(text: t?.rewardDescription ?? '');
    _prizePoolCtrl  = TextEditingController(text: t != null ? t.prizePool.toStringAsFixed(0) : '');
    _entryFeeCtrl   = TextEditingController(text: t != null ? t.entryFee.toStringAsFixed(0)  : '');

    _type         = t?.tournamentType ?? 'battle_royale';
    _mode         = t?.mode           ?? 'Squad';
    _map          = t?.map            ?? 'Bermuda';
    _rewardType   = t?.rewardType     ?? 'position';
    _maxPlayers   = t?.maxPlayers     ?? 48;
    _minimumLevel = t?.minimumLevel   ?? 0;
    _featured     = t?.featured       ?? false;
    _killReward   = t?.killReward     ?? 0.0;
    _survivalReward = t?.survivalReward ?? 0.0;
    _startTime    = t?.startTime?.toDate();

    // Build positions map
    _positions = {};
    if (t != null) {
      t.positions.forEach((k, v) {
        _positions[k] = (v as num).toDouble();
      });
    }
    _rebuildPosControllers();
  }

  void _rebuildPosControllers() {
    for (final c in _posCtrl.values) c.dispose();
    _posCtrl.clear();
    for (final entry in _positions.entries) {
      _posCtrl[entry.key] = TextEditingController(
          text: entry.value > 0 ? entry.value.toStringAsFixed(0) : '');
    }
  }

  @override
  void dispose() {
    for (final c in [_titleCtrl, _subtitleCtrl, _bannerCtrl,
                     _rulesCtrl, _rewardDescCtrl, _prizePoolCtrl, _entryFeeCtrl]) {
      c.dispose();
    }
    for (final c in _posCtrl.values) c.dispose();
    super.dispose();
  }

  void _addPosition() {
    final nextRank = (_positions.isEmpty
        ? 1
        : _positions.keys.map(int.parse).reduce(math.max) + 1).toString();
    setState(() {
      _positions[nextRank] = 0;
      _posCtrl[nextRank] = TextEditingController();
    });
  }

  void _removePosition(String rank) {
    setState(() {
      _positions.remove(rank);
      _posCtrl[rank]?.dispose();
      _posCtrl.remove(rank);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    // Build positions from controllers
    final posMap = <String, dynamic>{};
    for (final entry in _posCtrl.entries) {
      final val = double.tryParse(entry.value.text) ?? 0.0;
      if (val > 0) posMap[entry.key] = val;
    }

    final data = <String, dynamic>{
      'title':             _titleCtrl.text.trim(),
      'subtitle':          _subtitleCtrl.text.trim(),
      'bannerUrl':         _bannerCtrl.text.trim().isEmpty ? null : _bannerCtrl.text.trim(),
      'prizePool':         double.tryParse(_prizePoolCtrl.text) ?? 0.0,
      'entryFee':          double.tryParse(_entryFeeCtrl.text)  ?? 0.0,
      'maxPlayers':        _maxPlayers,
      'tournamentType':    _type,
      'mode':              _mode,
      'map':               _map,
      'featured':          _featured,
      'rewardType':        _rewardType,
      'killReward':        _killReward,
      'survivalReward':    _survivalReward,
      'positions':         posMap,
      'rules':             _rulesCtrl.text.trim().isEmpty ? null : _rulesCtrl.text.trim(),
      'rewardDescription': _rewardDescCtrl.text.trim().isEmpty ? null : _rewardDescCtrl.text.trim(),
      'minimumLevel':      _minimumLevel,
      if (_startTime != null) 'startTime': Timestamp.fromDate(_startTime!),
    };

    try {
      await widget.onSubmit(data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AdminColors.danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maps = _Presets.mapsForType(_type);
    if (!maps.contains(_map)) _map = maps.first;

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          children: [
            // Header
            _DialogHeader(title: widget.title, icon: Icons.emoji_events_rounded, color: AdminColors.gold),

            // Body
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel('BASIC INFO'),
                      const SizedBox(height: 10),

                      // Title + Subtitle
                      _FormRow(children: [
                        _FormField(ctrl: _titleCtrl,    label: 'Title*',    validator: _required),
                        _FormField(ctrl: _subtitleCtrl, label: 'Subtitle',  required: false),
                      ]),
                      const SizedBox(height: 10),
                      _FormField(ctrl: _bannerCtrl, label: 'Banner URL (optional)', required: false,
                          hint: 'https://…'),
                      const SizedBox(height: 20),

                      _sectionLabel('TOURNAMENT TYPE & MODE'),
                      const SizedBox(height: 10),

                      // Type chips
                      Wrap(spacing: 8, runSpacing: 8,
                        children: _Presets.tournamentTypes.map((rec) {
                          final (val, label, icon) = rec;
                          final sel = _type == val;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _type = val;
                              final maps = _Presets.mapsForType(val);
                              if (!maps.contains(_map)) _map = maps.first;
                            }),
                            child: _Chip(label: label, icon: icon, selected: sel,
                                color: AdminColors.purple),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Mode chips
                      _FormRow(children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mode', style: AdminTextStyles.labelSmall.copyWith(
                                color: AdminColors.textMuted)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6,
                              children: _Presets.modes.map((m) => GestureDetector(
                                onTap: () => setState(() => _mode = m),
                                child: _Chip(label: m, selected: _mode == m,
                                    color: AdminColors.info),
                              )).toList(),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Map', style: AdminTextStyles.labelSmall.copyWith(
                                color: AdminColors.textMuted)),
                            const SizedBox(height: 6),
                            _DropField(
                              value:   maps.contains(_map) ? _map : maps.first,
                              items:   maps,
                              onChanged: (v) => setState(() => _map = v!),
                            ),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 20),

                      _sectionLabel('PRIZE & ENTRY'),
                      const SizedBox(height: 10),
                      _FormRow(children: [
                        _FormField(ctrl: _prizePoolCtrl, label: 'Prize Pool (₹)*',
                            keyboard: TextInputType.number, validator: _required),
                        _FormField(ctrl: _entryFeeCtrl,  label: 'Entry Fee (₹, 0=FREE)',
                            keyboard: TextInputType.number, required: false),
                      ]),
                      const SizedBox(height: 10),

                      // Max players + min level
                      _FormRow(children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Max Players', style: AdminTextStyles.labelSmall.copyWith(
                                color: AdminColors.textMuted)),
                            const SizedBox(height: 6),
                            _DropField(
                              value:   _maxPlayers,
                              items:   _Presets.maxPlayerOptions,
                              onChanged: (v) => setState(() => _maxPlayers = v!),
                              itemLabel: (v) => v.toString(),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Minimum Level', style: AdminTextStyles.labelSmall.copyWith(
                                color: AdminColors.textMuted)),
                            const SizedBox(height: 6),
                            _DropField(
                              value:   _minimumLevel,
                              items:   _Presets.minimumLevels,
                              onChanged: (v) => setState(() => _minimumLevel = v!),
                              itemLabel: (v) => v == 0 ? 'No minimum' : 'Level $v',
                            ),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 20),

                      _sectionLabel('REWARD STRUCTURE'),
                      const SizedBox(height: 10),

                      Wrap(spacing: 8, runSpacing: 8,
                        children: _Presets.rewardTypes.map((rec) {
                          final (val, label) = rec;
                          return GestureDetector(
                            onTap: () => setState(() => _rewardType = val),
                            child: _Chip(label: label, selected: _rewardType == val,
                                color: AdminColors.gold),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Kill / survival rewards
                      if (_rewardType == 'kill' || _rewardType == 'mixed') ...[
                        _SliderField(
                          label: 'Kill Reward (₹ per kill)',
                          value: _killReward,
                          min: 0, max: 500, divisions: 100,
                          onChanged: (v) => setState(() => _killReward = v),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_rewardType == 'survival' || _rewardType == 'mixed') ...[
                        _SliderField(
                          label: 'Survival Reward (₹ flat)',
                          value: _survivalReward,
                          min: 0, max: 1000, divisions: 100,
                          onChanged: (v) => setState(() => _survivalReward = v),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Placement positions
                      if (_rewardType != 'kill' && _rewardType != 'survival') ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Position Prizes', style: AdminTextStyles.labelSmall.copyWith(
                                color: AdminColors.textMuted)),
                            GestureDetector(
                              onTap: _addPosition,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:        AdminColors.gold.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border:       Border.all(color: AdminColors.gold.withValues(alpha: 0.3)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.add_rounded, color: AdminColors.gold, size: 12),
                                  const SizedBox(width: 4),
                                  Text('Add Position', style: AdminTextStyles.labelSmall.copyWith(
                                      color: AdminColors.gold, fontSize: 10)),
                                ]),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...(_positions.entries.toList()
                          ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key))))
                          .map((entry) {
                          final rank = entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color:        AdminColors.gold.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border:       Border.all(color: AdminColors.gold.withValues(alpha: 0.3)),
                                ),
                                child: Center(child: Text(
                                  int.parse(rank) <= 3
                                      ? ['🥇','🥈','🥉'][int.parse(rank)-1]
                                      : '#$rank',
                                  style: const TextStyle(fontSize: 13),
                                )),
                              ),
                              const SizedBox(width: 8),
                              Text('Rank $rank', style: AdminTextStyles.bodyMedium,),
                              const SizedBox(width: 8),
                              Expanded(child: TextFormField(
                                controller: _posCtrl[rank],
                                style: AdminTextStyles.bodyMedium,
                                keyboardType: TextInputType.number,
                                decoration: _inputDeco('₹ Amount'),
                              )),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _removePosition(rank),
                                child: Icon(Icons.remove_circle_rounded,
                                    color: AdminColors.danger, size: 16),
                              ),
                            ]),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],

                      _FormField(ctrl: _rewardDescCtrl, label: 'Reward Description (shown to players)',
                          required: false, maxLines: 3),
                      const SizedBox(height: 20),

                      _sectionLabel('SCHEDULE & SETTINGS'),
                      const SizedBox(height: 10),

                      // Start time
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startTime ?? DateTime.now().add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            builder: (ctx, child) => Theme(
                              data: ThemeData.dark(),
                              child: child!,
                            ),
                          );
                          if (date == null || !mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(_startTime ?? DateTime.now()),
                            builder: (ctx, child) => Theme(
                              data: ThemeData.dark(),
                              child: child!,
                            ),
                          );
                          if (time == null) return;
                          setState(() => _startTime = DateTime(
                              date.year, date.month, date.day, time.hour, time.minute));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:        AdminColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border:       Border.all(color: AdminColors.border),
                          ),
                          child: Row(children: [
                            const Icon(Icons.schedule_rounded, color: AdminColors.info, size: 16),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              _startTime != null
                                  ? '${_startTime!.day}/${_startTime!.month}/${_startTime!.year} at '
                                    '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}'
                                  : 'Set start date & time',
                              style: _startTime != null
                                  ? AdminTextStyles.bodyMedium
                                  : AdminTextStyles.bodySmall,
                            )),
                            Icon(Icons.edit_calendar_rounded, color: AdminColors.textMuted, size: 14),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Featured toggle
                      GestureDetector(
                        onTap: () => setState(() => _featured = !_featured),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:        AdminColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border:       Border.all(
                              color: _featured
                                  ? AdminColors.gold.withValues(alpha: 0.4)
                                  : AdminColors.border,
                            ),
                          ),
                          child: Row(children: [
                            Icon(Icons.star_rounded,
                                color: _featured ? AdminColors.gold : AdminColors.textMuted, size: 16),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Featured Tournament', style: AdminTextStyles.titleSmall),
                                Text('Shown prominently on the player home screen',
                                    style: AdminTextStyles.bodySmall),
                              ],
                            )),
                            Switch(
                              value:           _featured,
                              onChanged:       (v) => setState(() => _featured = v),
                              activeColor:     AdminColors.gold,
                              inactiveThumbColor: AdminColors.textMuted,
                              trackColor:      WidgetStatePropertyAll(
                                  _featured ? AdminColors.gold.withValues(alpha: 0.3) : AdminColors.border),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 20),

                      _sectionLabel('RULES (OPTIONAL)'),
                      const SizedBox(height: 8),
                      _FormField(ctrl: _rulesCtrl, label: 'Match rules & regulations',
                          required: false, maxLines: 5),
                    ],
                  ),
                ),
              ),
            ),

            // Footer
            _DialogFooter(
              loading:      _loading,
              confirmLabel: widget.tournament == null ? 'Create Tournament' : 'Save Changes',
              confirmColor: AdminColors.gold,
              onCancel:     () => Navigator.pop(context),
              onConfirm:    _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Row(children: [
    Container(width: 3, height: 14,
        decoration: BoxDecoration(color: AdminColors.gold, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: AdminTextStyles.labelSmall.copyWith(
        color: AdminColors.textMuted, letterSpacing: 1.5)),
  ]);

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;
}

// ─────────────────────────────────────────────
// STATUS CHANGE DIALOG
// ─────────────────────────────────────────────
class _StatusDialog extends StatefulWidget {
  final AdminTournament tournament;
  final Future<void> Function(String) onUpdate;
  const _StatusDialog({required this.tournament, required this.onUpdate});

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  bool _loading = false;

  static const _transitions = {
    'upcoming': ['live', 'cancelled'],
    'live':     ['completed'],
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final allowed = _transitions[t.status] ?? [];

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(title: 'Change Status', icon: Icons.swap_horiz_rounded, color: AdminColors.info),
              const SizedBox(height: 16),
              Text('Current: ', style: AdminTextStyles.bodyMedium),
              const SizedBox(height: 4),
              _StatusBadge(status: t.status),
              const SizedBox(height: 20),
              if (allowed.isEmpty)
                Text('No further status transitions available.',
                    style: AdminTextStyles.bodyMedium, textAlign: TextAlign.center)
              else
                ...allowed.map((s) {
                  final (color, label) = switch (s) {
                    'live'      => (AdminColors.danger,  '🔴 Go Live'),
                    'completed' => (AdminColors.success, '✅ Mark Completed'),
                    'cancelled' => (AdminColors.textMuted, '❌ Cancel'),
                    _           => (AdminColors.purple,  s),
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _loading = true);
                          try {
                            await widget.onUpdate(s);
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            setState(() => _loading = false);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:        color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border:       Border.all(color: color.withValues(alpha: 0.35)),
                          ),
                          child: Center(child: _loading
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(label, style: AdminTextStyles.titleSmall.copyWith(color: color))),
                        ),
                      ),
                    ),
                  );
                }),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: AdminTextStyles.bodyMedium.copyWith(
                    color: AdminColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PARTICIPANTS DIALOG
// ─────────────────────────────────────────────
class _ParticipantsDialog extends StatefulWidget {
  final AdminTournament        tournament;
  final AdminTournamentService service;
 
  const _ParticipantsDialog({required this.tournament, required this.service});
 
  @override
  State<_ParticipantsDialog> createState() => _ParticipantsDialogState();
}
 
class _ParticipantsDialogState extends State<_ParticipantsDialog> {
  String _search = '';
  String _sort   = 'joinedAt';
  final _searchCtrl = TextEditingController();
 
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
 
  // ── Filter + sort helper ────────────────────────────────────────────────
  List<AdminParticipant> _applyFilters(List<AdminParticipant> all) {
    final List<AdminParticipant> list = _search.isEmpty
        ? List.from(all)
        : all.where((p) =>
            p.name.toLowerCase().contains(_search)  ||
            p.email.toLowerCase().contains(_search) ||
            p.ign.toLowerCase().contains(_search)   ||
            p.uid.toLowerCase().contains(_search)).toList();
 
    list.sort((a, b) {
      switch (_sort) {
        case 'name':
          return a.name.compareTo(b.name);
        case 'kills':
          return b.kills.compareTo(a.kills);
        case 'placement':
          final aP = a.placement == 0 ? 9999 : a.placement;
          final bP = b.placement == 0 ? 9999 : b.placement;
          return aP.compareTo(bP);
        default: // 'joinedAt'
          if (a.joinedAt == null && b.joinedAt == null) return 0;
          if (a.joinedAt == null) return 1;
          if (b.joinedAt == null) return -1;
          return a.joinedAt!.compareTo(b.joinedAt!);
      }
    });
    return list;
  }
 
  // ── Tiny stat chip ──────────────────────────────────────────────────────
  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AdminTextStyles.labelSmall.copyWith(
                    color: AdminColors.textMuted, fontSize: 8)),
            const SizedBox(height: 2),
            Text(value,
                style: AdminTextStyles.titleSmall.copyWith(
                    color: color, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
 
  // ── List body: loading / error / empty / data ───────────────────────────
  Widget _buildBody(
    AsyncSnapshot<List<AdminParticipant>> snap,
    List<AdminParticipant> filtered,
  ) {
    // Loading (no data yet)
    if (snap.connectionState == ConnectionState.waiting && filtered.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.info),
      );
    }
 
    // Error
    if (snap.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: AdminColors.danger, size: 36),
            const SizedBox(height: 8),
            Text('Error loading participants',
                style: AdminTextStyles.titleSmall),
            const SizedBox(height: 4),
            Text(snap.error.toString(),
                style: AdminTextStyles.bodySmall,
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }
 
    // Empty
    if (filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.people_outline_rounded,
              color: AdminColors.textMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            _search.isNotEmpty
                ? 'No participants match your search'
                : 'No participants yet',
            style: AdminTextStyles.bodyMedium,
          ),
          if (_search.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Players who register will appear here in real time',
                style: AdminTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
        ]),
      );
    }
 
    // Data
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: filtered.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AdminColors.border, height: 1),
      itemBuilder: (ctx, i) => _ParticipantRow(
        participant:  filtered[i],
        tournamentId: widget.tournament.id,
        entryFee:     widget.tournament.entryFee,
        service:      widget.service,
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            _DialogHeader(
              title: 'Participants — ${widget.tournament.title}',
              icon:  Icons.people_rounded,
              color: AdminColors.info,
            ),
 
            // ── Stream drives everything below the header ────────────────
            Expanded(
              child: StreamBuilder<List<AdminParticipant>>(
                stream: widget.service.participantsStream(widget.tournament.id),
                builder: (ctx, snap) {
                  final all      = snap.data ?? [];
                  final filtered = _applyFilters(all);
 
                  // Stats (computed from all, not filtered)
                  final total        = all.length;
                  final active       = all.where((p) => p.status == 'registered').length;
                  final disqualified = all.where((p) => p.status == 'disqualified').length;
                  final winners      = all.where((p) => p.status == 'winner').length;
                  final distributed  = all.fold<double>(
                      0.0, (s, p) => s + p.winnings);
 
                  return Column(
                    children: [
                      // ── Summary strip ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Row(children: [
                          _statTile('Total',        total.toString(),        AdminColors.info),
                          const SizedBox(width: 6),
                          _statTile('Active',       active.toString(),       AdminColors.success),
                          const SizedBox(width: 6),
                          _statTile('DQ\'d',        disqualified.toString(), AdminColors.danger),
                          const SizedBox(width: 6),
                          _statTile('Winners',      winners.toString(),      AdminColors.gold),
                          const SizedBox(width: 6),
                          _statTile(
                            'Distributed',
                            distributed > 0
                                ? '₹${distributed.toStringAsFixed(0)}'
                                : '₹0',
                            AdminColors.purple,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 10),
 
                      // ── Search + sort bar ──────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(children: [
                          Expanded(child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color:        AdminColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border:       Border.all(color: AdminColors.border),
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              style:      AdminTextStyles.bodySmall,
                              decoration: InputDecoration(
                                hintText: 'Search name, IGN, email, UID…',
                                hintStyle: AdminTextStyles.bodySmall.copyWith(
                                    color: AdminColors.textMuted),
                                prefixIcon: const Icon(Icons.search_rounded,
                                    color: AdminColors.textMuted, size: 15),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onChanged: (v) => setState(
                                  () => _search = v.toLowerCase().trim()),
                            ),
                          )),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 130,
                            child: _DropField<String>(
                            value: _sort,
                            items: ['joinedAt', 'name', 'kills', 'placement'],
                            onChanged: (v) =>
                                setState(() => _sort = v ?? 'joinedAt'),
                            itemLabel: (v) => switch (v) {
                              'placement' => 'Placement',
                              'kills'     => 'Kills',
                              'name'      => 'Name',
                              _           => 'Join Time',
                            },
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
 
                      // ── List body ──────────────────────────────────────
                      Expanded(child: _buildBody(snap, filtered)),
                    ],
                  );
                },
              ),
            ),
 
            // ── Footer ──────────────────────────────────────────────────
            const Divider(color: AdminColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(
                    '${widget.tournament.joinedPlayers}'
                    '/${widget.tournament.maxPlayers} slots filled',
                    style: AdminTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  )),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close',
                        style: AdminTextStyles.bodyMedium.copyWith(
                            color: AdminColors.textMuted)),
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

class _ParticipantRow extends StatefulWidget {
  final AdminParticipant       participant;
  final String                 tournamentId;
  final double                 entryFee;
  final AdminTournamentService service;
 
  const _ParticipantRow({
    required this.participant,
    required this.tournamentId,
    required this.entryFee,
    required this.service,
  });
 
  @override
  State<_ParticipantRow> createState() => _ParticipantRowState();
}
 
class _ParticipantRowState extends State<_ParticipantRow> {
  bool _expanded = false;
  bool _saving   = false;
 
  final _placementCtrl = TextEditingController();
  final _killsCtrl     = TextEditingController();
  final _winningsCtrl  = TextEditingController();
 
  @override
  void initState() {
    super.initState();
    final p = widget.participant;
    _placementCtrl.text = p.placement > 0 ? p.placement.toString() : '';
    _killsCtrl.text     = p.kills.toString();
    _winningsCtrl.text  = p.winnings > 0 ? p.winnings.toStringAsFixed(0) : '';
  }
 
  @override
  void dispose() {
    _placementCtrl.dispose();
    _killsCtrl.dispose();
    _winningsCtrl.dispose();
    super.dispose();
  }
 
  void _copyUid(BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: widget.participant.uid));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded,
            color: AdminColors.success, size: 14),
        const SizedBox(width: 8),
        Flexible(child: Text(
          'UID copied: ${widget.participant.uid}',
          style: const TextStyle(
              color: AdminColors.textPrimary, fontSize: 12),
          overflow: TextOverflow.ellipsis,
        )),
      ]),
      backgroundColor: AdminColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AdminColors.success.withOpacity(0.4)),
      ),
    ));
  }
 
  Future<void> _saveResult() async {
    setState(() => _saving = true);
    try {
      await widget.service.updateParticipantResult(
        tournamentId: widget.tournamentId,
        uid:          widget.participant.uid,
        placement:    int.tryParse(_placementCtrl.text)   ?? 0,
        kills:        int.tryParse(_killsCtrl.text)       ?? 0,
        winnings:     double.tryParse(_winningsCtrl.text) ?? 0,
      );
    } finally {
      if (mounted) setState(() { _saving = false; _expanded = false; });
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final p   = widget.participant;
    final isDQ = p.status == 'disqualified';
 
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          // ── Avatar ───────────────────────────────────────────────────
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape:  BoxShape.circle,
              color:  AdminColors.surfaceElevated,
              border: Border.all(
                  color: isDQ ? AdminColors.danger : AdminColors.border),
            ),
            child: Center(child: Text(
              p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
              style: AdminTextStyles.titleSmall.copyWith(
                  color: AdminColors.purple),
            )),
          ),
          const SizedBox(width: 10),
 
          // ── Player info ───────────────────────────────────────────────
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(p.name,
                    style: AdminTextStyles.titleSmall,
                    overflow: TextOverflow.ellipsis)),
                if (isDQ) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AdminColors.danger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('DQ',
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: AdminColors.danger, fontSize: 8)),
                  ),
                ],
                if (p.status == 'winner') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: AdminColors.gold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('WINNER',
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: AdminColors.gold, fontSize: 8)),
                  ),
                ],
              ]),
              // IGN + email
              Text(
                [
                  if (p.ign.isNotEmpty) p.ign,
                  if (p.email.isNotEmpty) p.email,
                ].join('  ·  '),
                style: AdminTextStyles.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )),
 
          // ── Stats badges ──────────────────────────────────────────────
          if (p.placement > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('#${p.placement}',
                  style: AdminTextStyles.titleSmall.copyWith(
                      color: AdminColors.gold)),
            ),
          if (p.kills > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${p.kills}K',
                  style: AdminTextStyles.bodyMedium.copyWith(
                      color: AdminColors.danger)),
            ),
          if (p.winnings > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('₹${p.winnings.toStringAsFixed(0)}',
                  style: AdminTextStyles.bodyMedium.copyWith(
                      color: AdminColors.success)),
            ),
 
          // ── Actions menu ──────────────────────────────────────────────
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AdminColors.textMuted, size: 16),
            color: AdminColors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AdminColors.border),
            ),
            itemBuilder: (_) => [
              _pmi('copyUid',       Icons.fingerprint_rounded,
                  'Copy UID',              AdminColors.info),
              _pmi('edit',          Icons.edit_rounded,
                  'Edit Result',           AdminColors.purple),
              _pmi('disqualify',    Icons.block_rounded,
                  'Disqualify',            AdminColors.warning),
              _pmi('remove',        Icons.person_remove_rounded,
                  'Remove + Refund',       AdminColors.danger),
              _pmi('removeNoRefund',Icons.delete_rounded,
                  'Remove (no refund)',    AdminColors.danger),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'copyUid':
                  _copyUid(context);
                case 'edit':
                  setState(() => _expanded = !_expanded);
                case 'disqualify':
                  await widget.service.disqualifyParticipant(
                    tournamentId: widget.tournamentId,
                    uid:          p.uid,
                    playerName:   p.name,
                  );
                case 'remove':
                  await widget.service.removeParticipant(
                    tournamentId: widget.tournamentId,
                    uid:          p.uid,
                    playerName:   p.name,
                    entryFee:     widget.entryFee,
                    refund:       true,
                  );
                case 'removeNoRefund':
                  await widget.service.removeParticipant(
                    tournamentId: widget.tournamentId,
                    uid:          p.uid,
                    playerName:   p.name,
                    entryFee:     widget.entryFee,
                    refund:       false,
                  );
              }
            },
          ),
        ]),
      ),
 
      // ── Inline edit panel ─────────────────────────────────────────────
      if (_expanded)
        Container(
          margin: const EdgeInsets.only(left: 46, bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        AdminColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: AdminColors.border),
          ),
          child: Row(children: [
            Expanded(child: _TinyField(ctrl: _placementCtrl, label: 'Placement')),
            const SizedBox(width: 8),
            Expanded(child: _TinyField(ctrl: _killsCtrl,     label: 'Kills')),
            const SizedBox(width: 8),
            Expanded(child: _TinyField(ctrl: _winningsCtrl,  label: '₹ Winnings')),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _saving ? null : _saveResult,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        AdminColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminColors.success.withOpacity(0.4)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AdminColors.success))
                    : Text('Save',
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: AdminColors.success)),
              ),
            ),
          ]),
        ),
    ]);
  }
 
  PopupMenuItem<String> _pmi(
          String v, IconData icon, String label, Color color) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(label, style: AdminTextStyles.bodyMedium.copyWith(color: color)),
        ]),
      );
}

// ─────────────────────────────────────────────
// ROOM CREDENTIALS DIALOG
// ─────────────────────────────────────────────
class _RoomCredentialsDialog extends StatefulWidget {
  final AdminTournament tournament;
  final Future<void> Function(String?, String?, DateTime?) onSave;
 
  const _RoomCredentialsDialog({
    required this.tournament,
    required this.onSave,
  });
 
  @override
  State<_RoomCredentialsDialog> createState() => _RoomCredentialsDialogState();
}
 
class _RoomCredentialsDialogState extends State<_RoomCredentialsDialog> {
  late TextEditingController _roomIdCtrl;
  late TextEditingController _roomPwCtrl;
  bool _showPassword = false;
  bool _loading      = false;
 
  _RevealPreset _preset     = _RevealPreset.immediately;
  TimeOfDay?    _customTime;
 
  // ── Labels ──────────────────────────────────────────────────────────────
  static String _presetLabel(_RevealPreset p) => switch (p) {
    _RevealPreset.immediately       => 'Immediately (reveal now)',
    _RevealPreset.oneHourBefore     => '1 hour before tournament start',
    _RevealPreset.thirtyMinsBefore  => '30 minutes before start',
    _RevealPreset.fifteenMinsBefore => '15 minutes before start',
    _RevealPreset.custom            => 'Custom time',
  };
 
  static IconData _presetIcon(_RevealPreset p) => switch (p) {
    _RevealPreset.immediately       => Icons.bolt_rounded,
    _RevealPreset.oneHourBefore     => Icons.alarm_rounded,
    _RevealPreset.thirtyMinsBefore  => Icons.alarm_rounded,
    _RevealPreset.fifteenMinsBefore => Icons.alarm_rounded,
    _RevealPreset.custom            => Icons.tune_rounded,
  };
 
  // ── Whether this preset needs a known startTime ──────────────────────────
  static bool _needsStart(_RevealPreset p) =>
      p != _RevealPreset.immediately && p != _RevealPreset.custom;
 
  bool get _startAvailable => widget.tournament.startTime != null;
 
  @override
  void initState() {
    super.initState();
    final t = widget.tournament;
    _roomIdCtrl = TextEditingController(text: t.roomId       ?? '');
    _roomPwCtrl = TextEditingController(text: t.roomPassword ?? '');
 
    // Try to re-derive the preset from a previously saved roomRevealTime
    if (t.roomRevealTime != null && t.startTime != null) {
      final reveal = t.roomRevealTime!.toDate();
      final start  = t.startTime!.toDate();
      final diffMins = start.difference(reveal).inMinutes;
 
      _preset = switch (diffMins) {
        60  => _RevealPreset.oneHourBefore,
        30  => _RevealPreset.thirtyMinsBefore,
        15  => _RevealPreset.fifteenMinsBefore,
        _   => _RevealPreset.custom,
      };
      if (_preset == _RevealPreset.custom) {
        _customTime = TimeOfDay.fromDateTime(reveal);
      }
    }
  }
 
  @override
  void dispose() {
    _roomIdCtrl.dispose();
    _roomPwCtrl.dispose();
    super.dispose();
  }
 
  // ── Compute the absolute reveal DateTime from preset ────────────────────
  DateTime? _computeRevealTime() {
    final startTime = widget.tournament.startTime?.toDate();
    switch (_preset) {
      case _RevealPreset.immediately:
        return DateTime.now();
      case _RevealPreset.oneHourBefore:
        return startTime?.subtract(const Duration(hours: 1));
      case _RevealPreset.thirtyMinsBefore:
        return startTime?.subtract(const Duration(minutes: 30));
      case _RevealPreset.fifteenMinsBefore:
        return startTime?.subtract(const Duration(minutes: 15));
      case _RevealPreset.custom:
        if (_customTime == null) return null;
        final now = DateTime.now();
        return DateTime(
            now.year, now.month, now.day,
            _customTime!.hour, _customTime!.minute);
    }
  }
 
  // ── Open time picker for custom preset ──────────────────────────────────
  Future<void> _pickCustomTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _customTime ?? TimeOfDay.now(),
      builder: (ctx, child) =>
          Theme(data: ThemeData.dark(), child: child!),
    );
    if (t != null && mounted) setState(() => _customTime = t);
  }
 
  // ── Format TimeOfDay nicely ──────────────────────────────────────────────
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
 
  // ── Format DateTime nicely ───────────────────────────────────────────────
  String _fmtDt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
 
  @override
  Widget build(BuildContext context) {
    final computedTime = _computeRevealTime();
    final showInfo     = computedTime != null &&
                         _preset != _RevealPreset.immediately;
 
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────────
            _DialogHeader(
              title: 'Room Credentials',
              icon:  Icons.meeting_room_rounded,
              color: AdminColors.warning,
            ),
 
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
 
                  // ── Room ID ────────────────────────────────────────────
                  _LabeledField(
                    label: 'Room ID',
                    ctrl:  _roomIdCtrl,
                    hint:  'e.g. 2847291',
                    suffix: GestureDetector(
                      onTap: () => Clipboard.setData(
                          ClipboardData(text: _roomIdCtrl.text)),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.copy_rounded,
                            color: AdminColors.textMuted, size: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
 
                  // ── Room Password ──────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Room Password',
                          style: AdminTextStyles.labelSmall.copyWith(
                              color: AdminColors.textMuted, fontSize: 10)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller:  _roomPwCtrl,
                        style:       AdminTextStyles.bodyMedium,
                        obscureText: !_showPassword,
                        decoration:  _inputDeco('e.g. 1234').copyWith(
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => setState(
                                    () => _showPassword = !_showPassword),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: AdminColors.textMuted, size: 14,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Clipboard.setData(
                                    ClipboardData(text: _roomPwCtrl.text)),
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.copy_rounded,
                                      color: AdminColors.textMuted, size: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
 
                  // ── Reveal section label ───────────────────────────────
                  Row(children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(
                        color: AdminColors.warning,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('REVEAL CREDENTIALS TO PLAYERS',
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: AdminColors.textMuted, letterSpacing: 1.2)),
                  ]),
                  const SizedBox(height: 10),
 
                  // ── Preset radio options ───────────────────────────────
                  ..._RevealPreset.values.map((p) {
                    final selected    = _preset == p;
                    final unavailable = _needsStart(p) && !_startAvailable;
 
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: unavailable ? null : () async {
                          setState(() => _preset = p);
                          if (p == _RevealPreset.custom) _pickCustomTime();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: unavailable
                                ? AdminColors.surfaceElevated.withValues(alpha: 0.5)
                                : selected
                                    ? AdminColors.warning.withValues(alpha: 0.1)
                                    : AdminColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? AdminColors.warning.withValues(alpha: 0.55)
                                  : AdminColors.border,
                            ),
                          ),
                          child: Row(children: [
                            // Radio circle
                            Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? AdminColors.warning
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selected
                                      ? AdminColors.warning
                                      : AdminColors.textMuted,
                                  width: 1.5,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 10, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              _presetIcon(p),
                              size: 14,
                              color: unavailable
                                  ? AdminColors.textMuted.withValues(alpha: 0.4)
                                  : selected
                                      ? AdminColors.warning
                                      : AdminColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _presetLabel(p),
                                  style: AdminTextStyles.bodyMedium.copyWith(
                                    color: unavailable
                                        ? AdminColors.textMuted.withValues(alpha: 0.45)
                                        : selected
                                            ? AdminColors.warning
                                            : AdminColors.textPrimary,
                                  ),
                                ),
                                if (unavailable)
                                  Text('Set tournament start time first',
                                      style: AdminTextStyles.bodySmall.copyWith(
                                          color: AdminColors.danger,
                                          fontSize: 10)),
                                if (p == _RevealPreset.custom &&
                                    selected &&
                                    _customTime != null)
                                  Text(
                                    'Today at ${_fmtTime(_customTime!)}',
                                    style: AdminTextStyles.bodySmall.copyWith(
                                        color: AdminColors.warning),
                                  ),
                              ],
                            )),
                            // Edit button for custom preset
                            if (p == _RevealPreset.custom && selected)
                              GestureDetector(
                                onTap: _pickCustomTime,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AdminColors.warning.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AdminColors.warning.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.edit_rounded,
                                      color: AdminColors.warning, size: 12),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    );
                  }),
 
                  // ── Computed reveal time banner ────────────────────────
                  if (showInfo) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AdminColors.info.withValues(alpha: 0.25)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AdminColors.info, size: 14),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'Credentials become visible at  ${_fmtDt(computedTime)}',
                          style: AdminTextStyles.bodySmall.copyWith(
                              color: AdminColors.info),
                        )),
                      ]),
                    ),
                  ],
 
                  const SizedBox(height: 10),
                  Text(
                    'Room credentials are only visible to registered '
                    'participants after the reveal time.',
                    style: AdminTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
 
            // ── Footer ───────────────────────────────────────────────────
            _DialogFooter(
              loading:      _loading,
              confirmLabel: 'Save Credentials',
              confirmColor: AdminColors.warning,
              onCancel:     () => Navigator.pop(context),
              onConfirm: () async {
                // Guard: custom preset requires a time
                if (_preset == _RevealPreset.custom && _customTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Please pick a custom reveal time.'),
                    backgroundColor: AdminColors.danger,
                  ));
                  return;
                }
                setState(() => _loading = true);
                try {
                  await widget.onSave(
                    _roomIdCtrl.text.trim().isEmpty
                        ? null : _roomIdCtrl.text.trim(),
                    _roomPwCtrl.text.trim().isEmpty
                        ? null : _roomPwCtrl.text.trim(),
                    _computeRevealTime(),
                  );
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => _loading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PRIZE DISTRIBUTION DIALOG
// ─────────────────────────────────────────────
class _PrizeDistributionDialog extends StatefulWidget {
  final AdminTournament        tournament;
  final AdminTournamentService service;
  final VoidCallback           onSuccess;
  const _PrizeDistributionDialog({
    required this.tournament, required this.service, required this.onSuccess,
  });

  @override
  State<_PrizeDistributionDialog> createState() => _PrizeDistributionDialogState();
}

class _PrizeDistributionDialogState extends State<_PrizeDistributionDialog> {
  // uid → {name, placement, amount}
  final Map<String, Map<String, dynamic>> _entries = {};
  bool _loading = false;
  bool _distributing = false;
  List<AdminParticipant> _participants = [];

  @override
  void initState() {
    super.initState();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournament.id)
          .collection('participants')
          .get();
      final list = snap.docs.map((d) => AdminParticipant.fromDoc(d)).toList()
        ..sort((a, b) => a.placement.compareTo(b.placement));
      setState(() {
        _participants = list;
        _loading = false;
      });

      // Pre-populate from positions map
      final posMap = widget.tournament.positions;
      for (final p in list) {
        final key = p.placement.toString();
        final amount = (posMap[key] as num?)?.toDouble() ?? 0.0;
        if (amount > 0) {
          _entries[p.uid] = {
            'name':      p.name,
            'placement': p.placement,
            'amount':    amount,
            'ctrl':      TextEditingController(text: amount.toStringAsFixed(0)),
          };
        }
      }
      setState(() {});
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  double get _totalEntering => _entries.values.fold(0.0, (s, e) {
    final v = double.tryParse((e['ctrl'] as TextEditingController).text) ?? 0.0;
    return s + v;
  });

  Future<void> _distribute() async {
    final entries = <PrizeEntry>[];
    for (final entry in _entries.entries) {
      final amount = double.tryParse(
          (entry.value['ctrl'] as TextEditingController).text) ?? 0.0;
      if (amount <= 0) continue;
      entries.add(PrizeEntry(
        uid:         entry.key,
        playerName:  entry.value['name'] as String,
        amount:      amount,
        placement:   entry.value['placement'] as int,
      ));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No prize amounts entered')));
      return;
    }

    setState(() => _distributing = true);
    try {
      await widget.service.distributePrizes(
        tournamentId:   widget.tournament.id,
        tournamentTitle: widget.tournament.title,
        entries:        entries,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _distributing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AdminColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total    = widget.tournament.prizePool;
    final entering = _totalEntering;
    final over     = entering > total + 0.01;

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820),
        child: Column(
          children: [
            _DialogHeader(title: 'Distribute Prizes', icon: Icons.card_giftcard_rounded,
                color: AdminColors.gold),

            // Prize summary
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(child: _PrizeStat('Prize Pool', '₹${total.toStringAsFixed(0)}', AdminColors.gold)),
                const SizedBox(width: 8),
                Expanded(child: _PrizeStat('Distributing', '₹${entering.toStringAsFixed(0)}',
                    over ? AdminColors.danger : AdminColors.success)),
                const SizedBox(width: 8),
                Expanded(child: _PrizeStat('Remaining', '₹${(total - entering).toStringAsFixed(0)}',
                    over ? AdminColors.danger : AdminColors.textMuted)),
              ]),
            ),

            if (over) Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        AdminColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: AdminColors.danger.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_rounded, color: AdminColors.danger, size: 14),
                  const SizedBox(width: 6),
                  Text('Over-distribution! Reduce prize amounts.',
                      style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.danger)),
                ]),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AdminColors.gold))
                  : _participants.isEmpty
                      ? Center(child: Text('No participants', style: AdminTextStyles.bodyMedium))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _participants.length,
                          itemBuilder: (ctx, i) {
                            final p = _participants[i];
                            final hasEntry = _entries.containsKey(p.uid);
                            final ctrl = hasEntry
                                ? (_entries[p.uid]!['ctrl'] as TextEditingController)
                                : null;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:        hasEntry
                                    ? AdminColors.gold.withValues(alpha: 0.06)
                                    : AdminColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                                border:       Border.all(
                                  color: hasEntry
                                      ? AdminColors.gold.withValues(alpha: 0.3)
                                      : AdminColors.border,
                                ),
                              ),
                              child: Row(children: [
                                // Rank
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color:        AdminColors.gold.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border:       Border.all(color: AdminColors.gold.withValues(alpha: 0.25)),
                                  ),
                                  child: Center(child: Text(
                                    p.placement > 0 ? '#${p.placement}' : '?',
                                    style: AdminTextStyles.labelSmall.copyWith(
                                        color: AdminColors.gold, fontSize: 10),
                                  )),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: AdminTextStyles.titleSmall),
                                    if (p.ign.isNotEmpty)
                                      Text(p.ign, style: AdminTextStyles.bodySmall),
                                  ],
                                )),

                                // Amount field
                                SizedBox(
                                  width: 110,
                                  child: Row(children: [
                                    Expanded(child: TextFormField(
                                      controller: ctrl,
                                      style: AdminTextStyles.bodyMedium.copyWith(
                                          color: AdminColors.gold),
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDeco('₹ 0').copyWith(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    )),
                                  ]),
                                ),
                                const SizedBox(width: 8),

                                // Toggle winner
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (hasEntry) {
                                        (_entries[p.uid]!['ctrl'] as TextEditingController).dispose();
                                        _entries.remove(p.uid);
                                      } else {
                                        _entries[p.uid] = {
                                          'name':      p.name,
                                          'placement': p.placement,
                                          'amount':    0.0,
                                          'ctrl':      TextEditingController(),
                                        };
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: hasEntry
                                          ? AdminColors.gold.withValues(alpha: 0.2)
                                          : AdminColors.surfaceCard,
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(
                                        color: hasEntry
                                            ? AdminColors.gold.withValues(alpha: 0.6)
                                            : AdminColors.border,
                                      ),
                                    ),
                                    child: Icon(
                                      hasEntry ? Icons.check_rounded : Icons.add_rounded,
                                      color: hasEntry ? AdminColors.gold : AdminColors.textMuted,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
            ),

            _DialogFooter(
              loading:      _distributing,
              confirmLabel: 'Distribute ₹${entering.toStringAsFixed(0)}',
              confirmColor: over ? AdminColors.textMuted : AdminColors.gold,
              onCancel:  () => Navigator.pop(context),
              onConfirm: over ? null : _distribute,
            ),
          ],
        ),
      ),
    );
  }

  Widget _PrizeStat(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border:       Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(children: [
      Text(label, style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted, fontSize: 9)),
      const SizedBox(height: 2),
      Text(value, style: AdminTextStyles.titleSmall.copyWith(color: color)),
    ]),
  );
}

// ─────────────────────────────────────────────
// CONFIRM DIALOG (cancel / delete)
// ─────────────────────────────────────────────
class _ConfirmDialog extends StatefulWidget {
  final String   title, message, confirmLabel;
  final IconData icon;
  final Color    color;
  final Future<void> Function() onConfirm;

  const _ConfirmDialog({
    required this.title, required this.message, required this.confirmLabel,
    required this.icon, required this.color, required this.onConfirm,
  });

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: widget.color.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  widget.color.withValues(alpha: 0.1),
                  border: Border.all(color: widget.color.withValues(alpha: 0.35)),
                ),
                child: Icon(widget.icon, color: widget.color, size: 26),
              ),
              const SizedBox(height: 16),
              Text(widget.title, style: AdminTextStyles.titleLarge),
              const SizedBox(height: 10),
              Text(widget.message,
                  style: AdminTextStyles.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),

              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color:        AdminColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(color: AdminColors.border),
                    ),
                    child: Center(child: Text('Cancel',
                        style: AdminTextStyles.bodyMedium)),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: _loading ? null : () async {
                    setState(() => _loading = true);
                    try {
                      await widget.onConfirm();
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() => _loading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: AdminColors.danger,
                        ));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color:        widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(color: widget.color.withValues(alpha: 0.4)),
                    ),
                    child: Center(child: _loading
                        ? SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: widget.color))
                        : Text(widget.confirmLabel,
                            style: AdminTextStyles.titleSmall.copyWith(color: widget.color))),
                  ),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// REUSABLE DIALOG COMPONENTS
// ─────────────────────────────────────────────
class _DialogHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color    color;

  const _DialogHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color:        color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
            border:       Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: AdminTextStyles.titleMedium)),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color:        AdminColors.surfaceElevated,
              borderRadius: BorderRadius.circular(7),
              border:       Border.all(color: AdminColors.border),
            ),
            child: const Icon(Icons.close_rounded, color: AdminColors.textMuted, size: 14),
          ),
        ),
      ]),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  final bool     loading;
  final String   confirmLabel;
  final Color    confirmColor;
  final VoidCallback          onCancel;
  final VoidCallback? onConfirm;

  const _DialogFooter({
    required this.loading, required this.confirmLabel, required this.confirmColor,
    required this.onCancel, required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AdminColors.border)),
      ),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: onCancel,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color:        AdminColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AdminColors.border),
            ),
            child: Center(child: Text('Cancel', style: AdminTextStyles.bodyMedium)),
          ),
        )),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: GestureDetector(
          onTap: loading || onConfirm == null ? null : onConfirm,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: onConfirm != null
                  ? LinearGradient(colors: [confirmColor, confirmColor.withValues(alpha: 0.7)])
                  : null,
              color: onConfirm == null ? AdminColors.surfaceElevated : null,
              borderRadius: BorderRadius.circular(10),
              boxShadow: onConfirm != null ? [
                BoxShadow(color: confirmColor.withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4)),
              ] : null,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(confirmLabel,
                      style: AdminTextStyles.titleSmall.copyWith(
                          color: onConfirm != null ? Colors.white : AdminColors.textMuted)),
            ),
          ),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// FORM HELPER WIDGETS
// ─────────────────────────────────────────────
class _FormRow extends StatelessWidget {
  final List<Widget> children;
  const _FormRow({required this.children});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 480) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children.map((c) =>
            Padding(padding: const EdgeInsets.only(bottom: 10), child: c)).toList(),
      );
    }
    final rowChildren = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) rowChildren.add(const SizedBox(width: 10));
      rowChildren.add(Expanded(child: children[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren);
  }
}

extension _Indexed<E> on Iterable<E> {
  Iterable<T> mapIndexed<T>(T Function(int index, E element) f) sync* {
    var i = 0;
    for (final e in this) yield f(i++, e);
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController  ctrl;
  final String                 label;
  final String?                hint;
  final bool                   required;
  final TextInputType          keyboard;
  final String? Function(String?)? validator;
  final int                    maxLines;

  const _FormField({
    required this.ctrl,
    required this.label,
    this.hint,
    this.required = true,
    this.keyboard = TextInputType.text,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:   ctrl,
      style:        AdminTextStyles.bodyMedium,
      keyboardType: keyboard,
      maxLines:     maxLines,
      validator:    validator ?? (required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null),
      decoration: _inputDeco(label, hint: hint),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String                label;
  final TextEditingController ctrl;
  final String?               hint;
  final Widget?               suffix;

  const _LabeledField({required this.label, required this.ctrl, this.hint, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AdminTextStyles.labelSmall.copyWith(
            color: AdminColors.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          style:      AdminTextStyles.bodyMedium,
          decoration: _inputDeco(hint ?? label, suffix: suffix),
        ),
      ],
    );
  }
}

class _TinyField extends StatelessWidget {
  final TextEditingController ctrl;
  final String                label;
  const _TinyField({required this.ctrl, required this.label});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller:   ctrl,
    style:        AdminTextStyles.bodySmall,
    keyboardType: TextInputType.number,
    decoration:   _inputDeco(label).copyWith(isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
  );
}

class _DropField<T> extends StatelessWidget {
  final T                  value;
  final List<T>            items;
  final void Function(T?)  onChanged;
  final String Function(T)? itemLabel;

  const _DropField({
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
    final labelFn = itemLabel ?? (T v) => v.toString();
    return DropdownButtonFormField<T>(
      value:         items.contains(value) ? value : items.first,
      style:         AdminTextStyles.bodyMedium,
      dropdownColor: AdminColors.surfaceElevated,
      decoration:    _inputDeco('').copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: items.map((item) => DropdownMenuItem<T>(
        value: item,
        child: Text(labelFn(item), style: AdminTextStyles.bodyMedium),
      )).toList(),
      onChanged: onChanged,
    );
  }
}

class _Chip extends StatelessWidget {
  final String   label;
  final IconData? icon;
  final bool     selected;
  final Color    color;

  const _Chip({required this.label, this.icon, required this.selected, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color:        selected ? color.withValues(alpha: 0.18) : AdminColors.surfaceElevated,
      borderRadius: BorderRadius.circular(8),
      border:       Border.all(
        color: selected ? color.withValues(alpha: 0.6) : AdminColors.border,
      ),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[
        Icon(icon, color: selected ? color : AdminColors.textMuted, size: 12),
        const SizedBox(width: 5),
      ],
      Text(label, style: AdminTextStyles.labelSmall.copyWith(
          color: selected ? color : AdminColors.textMuted, fontSize: 11)),
    ]),
  );
}

class _SliderField extends StatelessWidget {
  final String   label;
  final double   value;
  final double   min, max;
  final int      divisions;
  final void Function(double) onChanged;

  const _SliderField({
    required this.label, required this.value,
    required this.min, required this.max,
    required this.divisions, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Expanded(child: Text(label, style: AdminTextStyles.labelSmall.copyWith(
            color: AdminColors.textMuted, fontSize: 10))),
        Text('₹${value.toStringAsFixed(0)}',
            style: AdminTextStyles.titleSmall.copyWith(color: AdminColors.gold)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor:   AdminColors.gold,
          inactiveTrackColor: AdminColors.border,
          thumbColor:         AdminColors.gold,
          overlayColor:       AdminColors.gold.withValues(alpha: 0.15),
          trackHeight:        3,
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// SHARED INPUT DECORATION
// ─────────────────────────────────────────────
InputDecoration _inputDeco(String label, {String? hint, Widget? suffix}) => InputDecoration(
  labelText:     label,
  hintText:      hint,
  suffixIcon:    suffix,
  labelStyle:    AdminTextStyles.bodySmall.copyWith(color: AdminColors.textMuted),
  hintStyle:     AdminTextStyles.bodySmall.copyWith(color: AdminColors.textMuted),
  filled:        true,
  fillColor:     AdminColors.surfaceElevated,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide:   const BorderSide(color: AdminColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide:   const BorderSide(color: AdminColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide:   const BorderSide(color: AdminColors.purple, width: 1.5),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide:   const BorderSide(color: AdminColors.danger),
  ),
);

// ─────────────────────────────────────────────
// HELPER
// ─────────────────────────────────────────────
String _typeLabel(String type) {
  return switch (type) {
    'battle_royale' => 'Battle Royale',
    'clash_squad'   => 'Clash Squad',
    'lone_wolf'     => 'Lone Wolf',
    'lose_to_win'   => 'Lose To Win',
    'custom_league' => 'Custom League',
    '1v1_arena'     => '1v1 Arena',
    '2v2_arena'     => '2v2 Arena',
    'sniper'        => 'Sniper Challenge',
    _               => type,
  };
}