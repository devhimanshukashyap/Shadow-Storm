// lib/admin/pages/admin_logs_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Logs Page
// Phase 5: Realtime log stream, filters, pagination, CSV export, shimmer
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../widgets/admin_page_container.dart';
import '../widgets/admin_components.dart';
import '../layout/admin_responsive.dart' hide AdminGrid;
import '../theme/admin_theme.dart';
import '../services/admin_logs_service.dart';

class AdminLogsPage extends StatefulWidget {
  const AdminLogsPage({super.key});

  @override
  State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<AdminLogsPage> {
  final AdminLogsService _service = AdminLogsService.instance;

  // Filter state
  AdminLogsFilter _filter = const AdminLogsFilter();

  // Pagination state
  final List<AdminLogEntry> _allEntries  = [];
  DocumentSnapshot?         _lastDoc;
  bool                      _loadingMore = false;
  bool                      _hasMore     = true;

  // Admins for dropdown
  List<({String uid, String email})> _admins = [];

  // UI state
  bool _showFilters   = false;
  bool _exporting     = false;
  final _searchCtrl   = TextEditingController();
  final _scrollCtrl   = ScrollController();

  // Expanded log IDs
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadAdmins();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    final admins = await _service.getDistinctAdmins();
    if (mounted) setState(() => _admins = admins);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _service.loadMoreLogs(
          filter: _filter, lastDoc: _lastDoc!);
      if (mounted) {
        setState(() {
          _allEntries.addAll(result.entries);
          _lastDoc   = result.lastDoc;
          _hasMore   = result.entries.length >= 25;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await _service.exportCsv(filter: _filter);
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/admin_logs_export.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Shadow Storm Admin Logs',
      );
    } catch (e) {
      _snack('Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _applySearch(String v) {
    setState(() {
      _filter = _filter.copyWith(keyword: v);
    });
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final color = isError ? AdminColors.danger : AdminColors.success;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminTextStyles.bodyMedium.copyWith(color: color)),
      backgroundColor: AdminColors.surfaceCard,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
    ));
  }

  // ─── Badge color per action ──────────────────
  Color _actionColor(String action) {
    if (action.startsWith('deposit') && action.endsWith('approved')) return AdminColors.success;
    if (action.startsWith('deposit') && action.endsWith('rejected')) return AdminColors.danger;
    if (action.startsWith('withdrawal') && action.endsWith('approved')) return AdminColors.success;
    if (action.startsWith('withdrawal') && action.endsWith('rejected')) return AdminColors.danger;
    if (action == 'prize_distributed') return AdminColors.success;
    if (action.startsWith('tournament')) return AdminColors.gold;
    if (action.startsWith('admin_')) return AdminColors.purple;
    if (action == 'account_frozen' || action == 'wallets_frozen') return AdminColors.danger;
    if (action == 'account_unfrozen' || action == 'wallets_unfrozen') return AdminColors.success;
    if (action == 'balance_adjusted') return AdminColors.info;
    if (action == 'settings_updated') return AdminColors.info;
    if (action == 'maintenance_enabled') return AdminColors.danger;
    if (action == 'maintenance_disabled') return AdminColors.success;
    if (action == 'suspicious_activity_detected') return AdminColors.warning;
    return AdminColors.textMuted;
  }

  // ─── Format timestamp ────────────────────────
  String _fmt(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'][d.month - 1];
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.day} $m ${d.year}, $h:$min';
  }

  // ─── Format relative time ────────────────────
  String _relative(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate().toLocal());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    return AdminPageContainer(
      title:    'System Logs',
      subtitle: 'Realtime audit trail — all admin actions',
      actions: [
        if (_exporting)
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AdminColors.gold),
          )
        else
          AdminActionButton(
            label:    'Export CSV',
            icon:     Icons.download_rounded,
            color:    AdminColors.gold,
            outlined: true,
            onTap:    _exportCsv,
          ),
        AdminActionButton(
          label:    _showFilters ? 'Hide Filters' : 'Filters',
          icon:     Icons.filter_list_rounded,
          color:    _filter.hasActiveFilters
              ? AdminColors.purple
              : AdminColors.textMuted,
          outlined: true,
          onTap:    () => setState(() => _showFilters = !_showFilters),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          StreamBuilder<AdminLogsStats>(
            stream: _service.statsStream(),
            builder: (context, snap) {
              final stats = snap.data;
              return _buildStatsRow(stats);
            },
          ),
          const SizedBox(height: 16),

          // Search bar
          _buildSearchBar(),
          const SizedBox(height: 12),

          // Filter panel
          if (_showFilters) ...[
            _buildFilterPanel(),
            const SizedBox(height: 12),
          ],

          // Active filter chips
          if (_filter.hasActiveFilters) ...[
            _buildActiveFilterChips(),
            const SizedBox(height: 12),
          ],

          // Log list (realtime stream for first page)
          StreamBuilder<List<AdminLogEntry>>(
            stream: _service.logsStream(filter: _filter),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _buildShimmer();
              }
              if (snap.hasError) {
                return AdminEmptyState(
                  icon:     Icons.error_outline_rounded,
                  title:    'Error loading logs',
                  subtitle: snap.error.toString(),
                  color:    AdminColors.danger,
                );
              }

              final entries = snap.data ?? [];

              // Update pagination state from stream's first page
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // We'll store the last doc from the raw query — here we just
                // display the stream results directly without merging allEntries
                // since this is the first page (realtime).
              });

              if (entries.isEmpty) {
                return AdminEmptyState(
                  icon:     Icons.receipt_long_rounded,
                  title:    'No logs found',
                  subtitle: _filter.hasActiveFilters
                      ? 'No logs match your current filters.'
                      : 'Admin actions will appear here.',
                  color:    AdminColors.warning,
                );
              }

              return _buildLogList(entries, isDesktop);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STATS ROW
  // ─────────────────────────────────────────────
  Widget _buildStatsRow(AdminLogsStats? stats) {
    return AdminGrid( //'AdminGrid' isn't a function. Try correcting the name to match an existing function, or define a method or function named 'AdminGrid'.
      mobileColumns:  2,
      tabletColumns:  4,
      desktopColumns: 4,
      spacing:    12,
      runSpacing: 12,
      children: [
        AdminStatChip(
          label: 'Today',
          value: stats != null ? stats.totalToday.toString() : '—',
          color: AdminColors.info,
          icon:  Icons.today_rounded,
        ),
        AdminStatChip(
          label: 'Tournaments',
          value: stats != null
              ? (stats.actionCounts.entries
                      .where((e) => e.key.startsWith('tournament'))
                      .fold(0, (s, e) => s + e.value))
                  .toString()
              : '—',
          color: AdminColors.gold,
          icon:  Icons.emoji_events_rounded,
        ),
        AdminStatChip(
          label: 'Wallet',
          value: stats != null
              ? ((stats.actionCounts['deposit_approved'] ?? 0) +
                      (stats.actionCounts['withdrawal_approved'] ?? 0))
                  .toString()
              : '—',
          color: AdminColors.success,
          icon:  Icons.account_balance_wallet_rounded,
        ),
        AdminStatChip(
          label: 'Danger',
          value: stats != null
              ? ((stats.actionCounts['account_frozen'] ?? 0) +
                      (stats.actionCounts['maintenance_enabled'] ?? 0) +
                      (stats.actionCounts['wallets_frozen'] ?? 0))
                  .toString()
              : '—',
          color: AdminColors.danger,
          icon:  Icons.warning_rounded,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // SEARCH BAR
  // ─────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color:        AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.search_rounded,
                color: AdminColors.textMuted, size: 18),
          ),
          Expanded(
            child: TextField(
              controller:  _searchCtrl,
              onChanged:   _applySearch,
              style: AdminTextStyles.bodyMedium
                  .copyWith(color: AdminColors.textPrimary),
              decoration: const InputDecoration(
                hintText:        'Search action, admin email, target UID…',
                hintStyle:       TextStyle(
                    color: AdminColors.textMuted, fontSize: 13),
                border:          InputBorder.none,
                contentPadding:  EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_filter.keyword.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                _applySearch('');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.close_rounded,
                    color: AdminColors.textMuted, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // FILTER PANEL
  // ─────────────────────────────────────────────
  Widget _buildFilterPanel() {
    return AdminSectionCard(
      title:     'FILTERS',
      titleIcon: Icons.filter_list_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action type chips
          Text('Action Type',
              style: AdminTextStyles.labelMedium
                  .copyWith(color: AdminColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _filterChip(
                label: 'All',
                selected: _filter.actionType == null,
                color: AdminColors.purple,
                onTap: () => setState(() =>
                    _filter = _filter.copyWith(clearAction: true)),
              ),
              ...LogActions.all.map((action) {
                final label = LogActions.labels[action] ?? action;
                final color = _actionColor(action);
                return _filterChip(
                  label:    label,
                  selected: _filter.actionType == action,
                  color:    color,
                  onTap:    () => setState(() =>
                      _filter = _filter.copyWith(actionType: action)),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // Admin filter
          if (_admins.isNotEmpty) ...[
            Text('Admin',
                style: AdminTextStyles.labelMedium
                    .copyWith(color: AdminColors.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                _filterChip(
                  label: 'All Admins',
                  selected: _filter.adminUid == null,
                  color: AdminColors.info,
                  onTap: () => setState(() =>
                      _filter = _filter.copyWith(clearAdmin: true)),
                ),
                ..._admins.map((a) => _filterChip(
                  label: a.email.split('@').first,
                  selected: _filter.adminUid == a.uid,
                  color: AdminColors.info,
                  onTap: () => setState(() =>
                      _filter = _filter.copyWith(adminUid: a.uid)),
                )),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Date range
          Row(children: [
            Expanded(child: _datePicker(
              label:   'From Date',
              value:   _filter.dateFrom,
              onPick:  (d) => setState(() =>
                  _filter = _filter.copyWith(dateFrom: d)),
              onClear: () => setState(() =>
                  _filter = _filter.copyWith(clearDateFrom: true)),
            )),
            const SizedBox(width: 12),
            Expanded(child: _datePicker(
              label:   'To Date',
              value:   _filter.dateTo,
              onPick:  (d) => setState(() =>
                  _filter = _filter.copyWith(dateTo: d)),
              onClear: () => setState(() =>
                  _filter = _filter.copyWith(clearDateTo: true)),
            )),
          ]),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        selected ? color.withValues(alpha: 0.15) : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : AdminColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: AdminTextStyles.labelMedium.copyWith(
                color: selected ? color : AdminColors.textMuted,
                fontSize: 10)),
      ),
    );
  }

  Widget _datePicker({
    required String   label,
    required DateTime? value,
    required void Function(DateTime) onPick,
    required VoidCallback onClear,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context:  context,
          initialDate: value ?? DateTime.now(),
          firstDate:   DateTime(2024),
          lastDate:    DateTime.now(),
          builder:     (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                  primary: AdminColors.purple),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: AdminColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: AdminColors.textMuted, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null
                    ? '${value.day}/${value.month}/${value.year}'
                    : label,
                style: AdminTextStyles.bodySmall.copyWith(
                    color: value != null
                        ? AdminColors.textPrimary
                        : AdminColors.textMuted),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    color: AdminColors.textMuted, size: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    if (_filter.actionType != null) {
      chips.add(_activeChip(
        label:   'Action: ${LogActions.labels[_filter.actionType!] ?? _filter.actionType!}',
        color:   _actionColor(_filter.actionType!),
        onRemove: () => setState(() => _filter = _filter.copyWith(clearAction: true)),
      ));
    }
    if (_filter.adminUid != null) {
      final email = _admins
          .firstWhere((a) => a.uid == _filter.adminUid,
              orElse: () => (uid: '', email: 'Unknown'))
          .email;
      chips.add(_activeChip(
        label:   'Admin: $email',
        color:   AdminColors.info,
        onRemove: () => setState(() => _filter = _filter.copyWith(clearAdmin: true)),
      ));
    }
    if (_filter.dateFrom != null) {
      chips.add(_activeChip(
        label:   'From: ${_filter.dateFrom!.day}/${_filter.dateFrom!.month}',
        color:   AdminColors.purple,
        onRemove: () => setState(() => _filter = _filter.copyWith(clearDateFrom: true)),
      ));
    }
    if (_filter.dateTo != null) {
      chips.add(_activeChip(
        label:   'To: ${_filter.dateTo!.day}/${_filter.dateTo!.month}',
        color:   AdminColors.purple,
        onRemove: () => setState(() => _filter = _filter.copyWith(clearDateTo: true)),
      ));
    }
    if (_filter.keyword.isNotEmpty) {
      chips.add(_activeChip(
        label:   '"${_filter.keyword}"',
        color:   AdminColors.warning,
        onRemove: () {
          _searchCtrl.clear();
          setState(() => _filter = _filter.copyWith(keyword: ''));
        },
      ));
    }

    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }

  Widget _activeChip({
    required String label,
    required Color  color,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AdminTextStyles.labelSmall.copyWith(color: color)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, color: color, size: 12),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LOG LIST
  // ─────────────────────────────────────────────
  Widget _buildLogList(List<AdminLogEntry> entries, bool isDesktop) {
    return AdminSectionCard(
      title:     'LOG ENTRIES',
      titleIcon: Icons.receipt_long_rounded,
      titleColor: AdminColors.warning,
      titleActions: [
        AdminBadge(
          label: '${entries.length}+ logs',
          color: AdminColors.warning,
          glowing: true,
        ),
      ],
      contentPadding: EdgeInsets.zero,
      child: Column(
        children: [
          ...entries.asMap().entries.map((entry) {
            final idx = entry.key;
            final log = entry.value;
            return _LogCard(
              log:          log,
              color:        _actionColor(log.action),
              expanded:     _expanded.contains(log.id),
              isEven:       idx.isEven,
              formatTs:     _fmt,
              relativeTs:   _relative,
              onToggle:     () => setState(() {
                if (_expanded.contains(log.id)) {
                  _expanded.remove(log.id);
                } else {
                  _expanded.add(log.id);
                }
              }),
            );
          }),
          // Load more indicator
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AdminColors.purple),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHIMMER
  // ─────────────────────────────────────────────
  Widget _buildShimmer() {
    return Column(
      children: List.generate(6, (i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AdminShimmerTile(height: 72),
      )),
    );
  }
}

// ═════════════════════════════════════════════
// LOG CARD
// ═════════════════════════════════════════════
class _LogCard extends StatelessWidget {
  final AdminLogEntry log;
  final Color         color;
  final bool          expanded;
  final bool          isEven;
  final String Function(Timestamp?) formatTs;
  final String Function(Timestamp?) relativeTs;
  final VoidCallback  onToggle;

  const _LogCard({
    required this.log,
    required this.color,
    required this.expanded,
    required this.isEven,
    required this.formatTs,
    required this.relativeTs,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final label = LogActions.labels[log.action] ?? log.action;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: expanded
            ? color.withValues(alpha: 0.05)
            : isEven
                ? AdminColors.surfaceCard
                : AdminColors.surface,
        border: Border(
          bottom: BorderSide(color: AdminColors.border, width: 0.5),
          left:   BorderSide(
            color: expanded ? color : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  // Action badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border:       Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Text(label,
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: color, fontSize: 9)),
                  ),
                  const SizedBox(width: 10),

                  // Admin email
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log.adminEmail,
                            style: AdminTextStyles.titleSmall,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          log.targetUid.isNotEmpty
                              ? 'Target: ${log.targetUid.length > 20 ? "${log.targetUid.substring(0, 20)}…" : log.targetUid}'
                              : '',
                          style: AdminTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Timestamp
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(relativeTs(log.createdAt),
                          style: AdminTextStyles.labelSmall.copyWith(
                              color: AdminColors.textMuted, fontSize: 9)),
                      Text(formatTs(log.createdAt),
                          style: AdminTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),

                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns:    expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AdminColors.textMuted, size: 18),
                  ),
                ],
              ),
            ),
          ),

          // Expanded details
          if (expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AdminColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.data_object_rounded,
                          color: color, size: 14),
                      const SizedBox(width: 6),
                      Text('DETAILS PAYLOAD',
                          style: AdminTextStyles.labelSmall
                              .copyWith(color: color, letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 10),
                    ...log.details.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text('${e.key}:',
                                style: AdminTextStyles.labelSmall.copyWith(
                                    color: AdminColors.textSecondary,
                                    fontSize: 10)),
                          ),
                          Expanded(
                            child: Text(
                              e.value.toString(),
                              style: AdminTextStyles.bodySmall.copyWith(
                                  color: AdminColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 6),
                    Text('Log ID: ${log.id}',
                        style: AdminTextStyles.labelSmall.copyWith(
                            color: AdminColors.textMuted, fontSize: 9)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}