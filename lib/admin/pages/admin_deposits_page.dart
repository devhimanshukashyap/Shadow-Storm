// lib/admin/pages/admin_deposits_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Deposit Management
// Phase 2: Production-grade moderation panel
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart';
import '../theme/admin_theme.dart';
import '../services/admin_wallet_service.dart';

// ─────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────
class _DepositItem {
  final String requestId;
  final String uid;
  final double amount;
  final String utr;
  final String status;
  final Timestamp createdAt;
  final String?   adminNote;

  // Joined from users/{uid}
  String? playerName;
  String? playerEmail;
  String? playerPhoto;
  String? playerIgn;

  _DepositItem({
    required this.requestId,
    required this.uid,
    required this.amount,
    required this.utr,
    required this.status,
    required this.createdAt,
    this.adminNote,
  });

  factory _DepositItem.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _DepositItem(
      requestId: doc.id,
      uid:       doc.reference.parent.parent!.id,
      amount:    (d['amount'] as num?)?.toDouble() ?? 0.0,
      utr:       (d['utr'] as String?) ?? '—',
      status:    (d['status'] as String?) ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?) ?? Timestamp.now(),
      adminNote: d['adminNote'] as String?,
    );
  }
}

// ─────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────
class AdminDepositsPage extends StatefulWidget {
  const AdminDepositsPage({super.key});

  @override
  State<AdminDepositsPage> createState() => _AdminDepositsPageState();
}

class _AdminDepositsPageState extends State<AdminDepositsPage>
    with SingleTickerProviderStateMixin {

  // ── Animation ────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  // ── Filters ──────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery   = '';
  String _statusFilter  = 'all';   // all | pending | approved | rejected
  String _sortOrder     = 'newest'; // newest | oldest

  // ── User data cache ───────────────────────
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _fetchingUids = {};

  // ── Loading states ────────────────────────
  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────
  // USER CACHE
  // ──────────────────────────────────────────
  void _prefetchUser(String uid) {
    if (_userCache.containsKey(uid) || _fetchingUids.contains(uid)) return;
    _fetchingUids.add(uid);
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .then((doc) {
          if (!mounted) return;
          setState(() {
            _userCache[uid] = doc.data() ?? {};
            _fetchingUids.remove(uid);
          });
        })
        .catchError((_) { _fetchingUids.remove(uid); });
  }

  // ──────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────
  String _formatDate(Timestamp ts) {
    final d = ts.toDate().toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m';
  }

  bool _isToday(Timestamp ts) {
    final d   = ts.toDate().toLocal();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  List<_DepositItem> _applyFilters(List<_DepositItem> all) {
    var list = all;

    // Status filter
    if (_statusFilter != 'all') {
      list = list.where((d) => d.status == _statusFilter).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      list = list.where((d) {
        final user = _userCache[d.uid] ?? {};
        final name  = ((user['name'] as String?) ?? '').toLowerCase();
        final email = ((user['email'] as String?) ?? '').toLowerCase();
        final ign   = ((user['ign'] as String?) ?? '').toLowerCase();
        return d.uid.toLowerCase().contains(_searchQuery)
            || d.utr.toLowerCase().contains(_searchQuery)
            || name.contains(_searchQuery)
            || email.contains(_searchQuery)
            || ign.contains(_searchQuery);
      }).toList();
    }

    // Sort
    list.sort((a, b) => _sortOrder == 'newest'
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));

    return list;
  }

  // ──────────────────────────────────────────
  // APPROVE FLOW
  // ──────────────────────────────────────────
  void _showApproveDialog(_DepositItem item) {
    final user = _userCache[item.uid] ?? {};
    final name = (user['name'] as String?) ?? 'Unknown Player';
    showDialog(
      context: context,
      builder: (_) => _ApproveDialog(
        item:       item,
        playerName: name,
        onConfirm:  (note) => _executeApprove(item, name, note),
      ),
    );
  }

  Future<void> _executeApprove(
      _DepositItem item, String playerName, String? note) async {
    setState(() => _actionLoading[item.requestId] = true);
    try {
      await AdminWalletService.instance.approveDeposit(
        uid:        item.uid,
        requestId:  item.requestId,
        amount:     item.amount,
        utr:        item.utr,
        playerName: playerName,
        adminNote:  note,
      );
      if (mounted) {
        _showSnack('✅  Deposit approved — ₹${item.amount.toStringAsFixed(0)} credited to $playerName',
            AdminColors.success);
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(item.requestId));
    }
  }

  // ──────────────────────────────────────────
  // REJECT FLOW
  // ──────────────────────────────────────────
  void _showRejectDialog(_DepositItem item) {
    final user = _userCache[item.uid] ?? {};
    final name = (user['name'] as String?) ?? 'Unknown Player';
    showDialog(
      context: context,
      builder: (_) => _RejectDialog(
        item:       item,
        playerName: name,
        onConfirm:  (note) => _executeReject(item, name, note),
      ),
    );
  }

  Future<void> _executeReject(
      _DepositItem item, String playerName, String note) async {
    setState(() => _actionLoading[item.requestId] = true);
    try {
      await AdminWalletService.instance.rejectDeposit(
        uid:        item.uid,
        requestId:  item.requestId,
        amount:     item.amount,
        utr:        item.utr,
        playerName: playerName,
        adminNote:  note,
      );
      if (mounted) {
        _showSnack('⛔  Deposit rejected for $playerName', AdminColors.warning);
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(item.requestId));
    }
  }

  // ──────────────────────────────────────────
  // VIEW DETAIL
  // ──────────────────────────────────────────
  void _showDetail(_DepositItem item) {
    final user = _userCache[item.uid] ?? {};
    showDialog(
      context: context,
      builder: (_) => _DetailDialog(item: item, userData: user),
    );
  }

  // ──────────────────────────────────────────
  // SNACK
  // ──────────────────────────────────────────
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AdminTextStyles.bodyMedium.copyWith(
            color: AdminColors.textPrimary)),
        backgroundColor: AdminColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ──────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('deposit_requests')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final hasError  = snap.hasError;
        final allItems  = <_DepositItem>[];

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final item = _DepositItem.fromDoc(doc);
            allItems.add(item);
            _prefetchUser(item.uid);
          }
        }

        // Attach user data from cache
        for (final item in allItems) {
          final user = _userCache[item.uid] ?? {};
          item.playerName  = user['name']     as String?;
          item.playerEmail = user['email']    as String?;
          item.playerPhoto = user['photoUrl'] as String?;
          item.playerIgn   = user['ign']      as String?;
        }

        // Stats (from unfiltered list)
        final pending       = allItems.where((d) => d.status == 'pending').length;
        final approvedToday = allItems.where((d) =>
            d.status == 'approved' && _isToday(d.createdAt)).length;
        final rejectedToday = allItems.where((d) =>
            d.status == 'rejected' && _isToday(d.createdAt)).length;
        final totalVolume   = allItems
            .where((d) => d.status == 'approved')
            .fold<double>(0, (sum, d) => sum + d.amount);

        final filtered = _applyFilters(allItems);

        return AdminPageContainer(
          title:    'Deposit Management',
          subtitle: 'Review and process all player deposit requests',
          actions: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:  AdminColors.success.withValues(alpha: 0.10 + 0.06 * _pulse.value),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AdminColors.success.withValues(alpha: 0.4 + 0.2 * _pulse.value),
                  ),
                  boxShadow: [BoxShadow(
                    color: AdminColors.success.withValues(alpha: 0.12 * _pulse.value),
                    blurRadius: 10,
                  )],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AdminColors.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('LIVE', style: AdminTextStyles.labelSmall.copyWith(
                        color: AdminColors.success)),
                  ],
                ),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stats ─────────────────────────────
              _buildStats(
                pending:       pending,
                approvedToday: approvedToday,
                rejectedToday: rejectedToday,
                totalVolume:   totalVolume,
                isLoading:     isLoading,
              ),
              const SizedBox(height: 20),

              // ── Filters ────────────────────────────
              _buildFilters(),
              const SizedBox(height: 16),

              // ── Table / Cards ──────────────────────
              AdminSectionCard(
                title:      'DEPOSIT REQUESTS',
                titleIcon:  Icons.add_circle_rounded,
                titleColor: AdminColors.success,
                titleActions: [
                  AdminBadge(
                    label:   '${filtered.length} RECORDS',
                    color:   AdminColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  AdminBadge(
                    label:   'LIVE',
                    color:   AdminColors.success,
                    glowing: true,
                  ),
                ],
                child: _buildBody(
                  isLoading: isLoading,
                  hasError:  hasError,
                  items:     filtered,
                  error:     snap.error?.toString(),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // STATS
  // ──────────────────────────────────────────
  Widget _buildStats({
    required int    pending,
    required int    approvedToday,
    required int    rejectedToday,
    required double totalVolume,
    required bool   isLoading,
  }) {
    return AdminGrid(
      mobileColumns:  2,
      tabletColumns:  2,
      desktopColumns: 4,
      spacing:    14,
      runSpacing: 14,
      children: [
        AdminStatCard(
          label:    'Pending',
          value:    isLoading ? '—' : pending.toString(),
          icon:     Icons.pending_rounded,
          color:    AdminColors.warning,
          subLabel: 'Awaiting approval',
        ),
        AdminStatCard(
          label:    'Approved Today',
          value:    isLoading ? '—' : approvedToday.toString(),
          icon:     Icons.check_circle_rounded,
          color:    AdminColors.success,
          subLabel: 'Processed today',
        ),
        AdminStatCard(
          label:    'Rejected Today',
          value:    isLoading ? '—' : rejectedToday.toString(),
          icon:     Icons.cancel_rounded,
          color:    AdminColors.danger,
          subLabel: 'Rejected today',
        ),
        AdminStatCard(
          label:    'Total Volume',
          value:    isLoading ? '—' : '₹${totalVolume.toStringAsFixed(0)}',
          icon:     Icons.account_balance_wallet_rounded,
          color:    AdminColors.gold,
          subLabel: 'All approved deposits',
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // FILTERS BAR
  // ──────────────────────────────────────────
  Widget _buildFilters() {
    final isDesktop = AdminResponsive.isDesktop(context);

    final searchField = Container(
      height: 40,
      decoration: BoxDecoration(
        color:        AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: AdminColors.border),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary),
        decoration: InputDecoration(
          hintText:       'Search by name, UID, UTR…',
          hintStyle:      AdminTextStyles.bodySmall,
          prefixIcon:     Icon(Icons.search_rounded,
              color: AdminColors.textMuted, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close_rounded,
                      color: AdminColors.textMuted, size: 16),
                )
              : null,
          border:          InputBorder.none,
          contentPadding:  const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );

    final statusChips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(label: 'ALL',      value: 'all',      group: _statusFilter,
            color: AdminColors.purple,  onTap: (v) => setState(() => _statusFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'PENDING',  value: 'pending',  group: _statusFilter,
            color: AdminColors.warning, onTap: (v) => setState(() => _statusFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'APPROVED', value: 'approved', group: _statusFilter,
            color: AdminColors.success, onTap: (v) => setState(() => _statusFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'REJECTED', value: 'rejected', group: _statusFilter,
            color: AdminColors.danger,  onTap: (v) => setState(() => _statusFilter = v)),
      ],
    );

    final sortBtn = _SortButton(
      value:    _sortOrder,
      onChanged: (v) => setState(() => _sortOrder = v),
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(flex: 3, child: searchField),
          const SizedBox(width: 12),
          statusChips,
          const SizedBox(width: 12),
          sortBtn,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        searchField,
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [statusChips, const SizedBox(width: 12), sortBtn]),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // BODY
  // ──────────────────────────────────────────
  Widget _buildBody({
    required bool             isLoading,
    required bool             hasError,
    required List<_DepositItem> items,
    String?                   error,
  }) {
    if (isLoading) return const _ShimmerTable();
    if (hasError)  return _ErrorState(message: error ?? 'Unknown error');
    if (items.isEmpty) {
      return _EmptyState(
        hasFilter: _searchQuery.isNotEmpty || _statusFilter != 'all',
        onClear: () {
          _searchCtrl.clear();
          setState(() { _searchQuery = ''; _statusFilter = 'all'; });
        },
      );
    }

    final isDesktop = AdminResponsive.isDesktop(context);
    final isTablet  = AdminResponsive.isTablet(context);

    if (isDesktop || isTablet) {
      return _DepositTable(
        items:         items,
        isTablet:      isTablet,
        userCache:     _userCache,
        actionLoading: _actionLoading,
        formatDate:    _formatDate,
        onView:        _showDetail,
        onApprove:     _showApproveDialog,
        onReject:      _showRejectDialog,
      );
    }

    return _DepositCards(
      items:         items,
      userCache:     _userCache,
      actionLoading: _actionLoading,
      formatDate:    _formatDate,
      onView:        _showDetail,
      onApprove:     _showApproveDialog,
      onReject:      _showRejectDialog,
    );
  }
}

// ═════════════════════════════════════════════
// TABLE (Desktop / Tablet)
// ═════════════════════════════════════════════
class _DepositTable extends StatelessWidget {
  final List<_DepositItem>              items;
  final bool                            isTablet;
  final Map<String, Map<String, dynamic>> userCache;
  final Map<String, bool>               actionLoading;
  final String Function(Timestamp)      formatDate;
  final void Function(_DepositItem)     onView;
  final void Function(_DepositItem)     onApprove;
  final void Function(_DepositItem)     onReject;

  const _DepositTable({
    required this.items,
    required this.isTablet,
    required this.userCache,
    required this.actionLoading,
    required this.formatDate,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: AdminDecorations.tableHeader,
          child: Row(
            children: [
              Expanded(flex: 3, child: _headerCell('PLAYER')),
              Expanded(flex: 2, child: _headerCell('AMOUNT')),
              if (!isTablet) Expanded(flex: 2, child: _headerCell('UTR')),
              Expanded(flex: 2, child: _headerCell('STATUS')),
              if (!isTablet) Expanded(flex: 3, child: _headerCell('CREATED AT')),
              Expanded(flex: isTablet ? 3 : 4, child: _headerCell('ACTIONS')),
            ],
          ),
        ),

        // Rows
        ...items.asMap().entries.map((entry) {
          final i    = entry.key;
          final item = entry.value;
          final user = userCache[item.uid] ?? {};
          return _DepositTableRow(
            item:          item,
            userData:      user,
            isEven:        i.isEven,
            isTablet:      isTablet,
            isLoading:     actionLoading[item.requestId] ?? false,
            formatDate:    formatDate,
            onView:        () => onView(item),
            onApprove:     () => onApprove(item),
            onReject:      () => onReject(item),
          );
        }),
      ],
    );
  }

  Widget _headerCell(String label) => Text(
    label,
    style: AdminTextStyles.labelSmall.copyWith(
        color: AdminColors.textMuted, letterSpacing: 1.2),
  );
}

class _DepositTableRow extends StatefulWidget {
  final _DepositItem                item;
  final Map<String, dynamic>        userData;
  final bool                        isEven;
  final bool                        isTablet;
  final bool                        isLoading;
  final String Function(Timestamp)  formatDate;
  final VoidCallback                onView;
  final VoidCallback                onApprove;
  final VoidCallback                onReject;

  const _DepositTableRow({
    required this.item,
    required this.userData,
    required this.isEven,
    required this.isTablet,
    required this.isLoading,
    required this.formatDate,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_DepositTableRow> createState() => _DepositTableRowState();
}

class _DepositTableRowState extends State<_DepositTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final name  = (widget.userData['name']  as String?) ?? widget.item.uid.substring(0, 8);
    final photo = widget.userData['photoUrl'] as String?;
    final isPending = widget.item.status == 'pending';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered
              ? AdminColors.surfaceElevated.withValues(alpha: 0.8)
              : (widget.isEven
                  ? AdminColors.surfaceCard
                  : AdminColors.background),
          border: Border(
            bottom: BorderSide(color: AdminColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Player
            Expanded(flex: 3, child: _PlayerCell(
              name:     name,
              uid:      widget.item.uid,
              photoUrl: photo,
            )),

            // Amount
            Expanded(flex: 2, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${widget.item.amount.toStringAsFixed(2)}',
                  style: AdminTextStyles.titleSmall.copyWith(
                      color: AdminColors.gold),
                ),
              ],
            )),

            // UTR (desktop only)
            if (!widget.isTablet)
              Expanded(flex: 2, child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.item.utr));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('UTR copied'),
                        duration: Duration(seconds: 1)));
                },
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.item.utr,
                        style: AdminTextStyles.bodySmall.copyWith(
                          fontFamily: 'monospace',
                          color: AdminColors.info,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, size: 10,
                        color: AdminColors.textMuted),
                  ],
                ),
              )),

            // Status
            Expanded(flex: 2, child: _StatusBadge(status: widget.item.status)),

            // Created (desktop only)
            if (!widget.isTablet)
              Expanded(flex: 3, child: Text(
                widget.formatDate(widget.item.createdAt),
                style: AdminTextStyles.bodySmall,
              )),

            // Actions
            Expanded(flex: widget.isTablet ? 3 : 4, child: widget.isLoading
                ? const Center(
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AdminColors.purple)))
                : Row(
                    children: [
                      _TinyButton(
                        label: 'View',
                        icon:  Icons.visibility_rounded,
                        color: AdminColors.info,
                        onTap: widget.onView,
                      ),
                      const SizedBox(width: 4),
                      if (isPending) ...[
                        _TinyButton(
                          label: 'Approve',
                          icon:  Icons.check_rounded,
                          color: AdminColors.success,
                          onTap: widget.onApprove,
                        ),
                        const SizedBox(width: 4),
                        _TinyButton(
                          label:    'Reject',
                          icon:     Icons.close_rounded,
                          color:    AdminColors.danger,
                          outlined: true,
                          onTap:    widget.onReject,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// CARDS (Mobile)
// ═════════════════════════════════════════════
class _DepositCards extends StatelessWidget {
  final List<_DepositItem>              items;
  final Map<String, Map<String, dynamic>> userCache;
  final Map<String, bool>               actionLoading;
  final String Function(Timestamp)      formatDate;
  final void Function(_DepositItem)     onView;
  final void Function(_DepositItem)     onApprove;
  final void Function(_DepositItem)     onReject;

  const _DepositCards({
    required this.items,
    required this.userCache,
    required this.actionLoading,
    required this.formatDate,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) {
        final user     = userCache[item.uid] ?? {};
        final name     = (user['name'] as String?) ?? item.uid.substring(0, 8);
        final photo    = user['photoUrl'] as String?;
        final loading  = actionLoading[item.requestId] ?? false;
        final isPending = item.status == 'pending';

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:        AdminColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: _borderColor(item.status)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: player + status
              Row(
                children: [
                  _PlayerAvatar(photoUrl: photo, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AdminTextStyles.titleSmall),
                        Text(
                          '${item.uid.substring(0, 10)}…',
                          style: AdminTextStyles.bodySmall.copyWith(
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: item.status),
                ],
              ),

              const SizedBox(height: 12),

              // Info row
              Row(
                children: [
                  _InfoChip(label: 'AMOUNT',
                      value: '₹${item.amount.toStringAsFixed(2)}',
                      color: AdminColors.gold),
                  const SizedBox(width: 8),
                  Expanded(child: _InfoChip(label: 'UTR',
                      value: item.utr, color: AdminColors.info)),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                formatDate(item.createdAt),
                style: AdminTextStyles.bodySmall,
              ),

              if (item.adminNote != null && item.adminNote!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes_rounded,
                          size: 12, color: AdminColors.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.adminNote!,
                          style: AdminTextStyles.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Actions
              loading
                  ? const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: AdminColors.purple)))
                  : Row(
                      children: [
                        _TinyButton(
                          label: 'View',
                          icon:  Icons.visibility_rounded,
                          color: AdminColors.info,
                          onTap: () => onView(item),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: AdminActionButton(
                              label: 'Approve',
                              icon:  Icons.check_rounded,
                              color: AdminColors.success,
                              onTap: () => onApprove(item),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AdminActionButton(
                              label:    'Reject',
                              icon:     Icons.close_rounded,
                              color:    AdminColors.danger,
                              outlined: true,
                              onTap:    () => onReject(item),
                            ),
                          ),
                        ],
                      ],
                    ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _borderColor(String status) {
    return switch (status) {
      'approved' => AdminColors.success.withValues(alpha: 0.3),
      'rejected' => AdminColors.danger.withValues(alpha: 0.2),
      _          => AdminColors.warning.withValues(alpha: 0.25),
    };
  }
}

// ═════════════════════════════════════════════
// DIALOGS
// ═════════════════════════════════════════════

class _ApproveDialog extends StatefulWidget {
  final _DepositItem              item;
  final String                    playerName;
  final void Function(String?)    onConfirm;

  const _ApproveDialog({
    required this.item,
    required this.playerName,
    required this.onConfirm,
  });

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _noteCtrl = TextEditingController();
  bool  _loading  = false;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminColors.success.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.success.withValues(alpha: 0.12),
                    border: Border.all(color: AdminColors.success.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: AdminColors.success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Approve Deposit', style: AdminTextStyles.titleLarge),
                    Text('This will credit the player\'s wallet',
                        style: AdminTextStyles.bodySmall),
                  ],
                )),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AdminColors.textMuted, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 20),

              // Summary card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AdminColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(
                      color: AdminColors.success.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _DialogRow(label: 'Player', value: widget.playerName),
                    _DialogRow(label: 'Amount',
                        value: '₹${widget.item.amount.toStringAsFixed(2)}',
                        valueColor: AdminColors.gold),
                    _DialogRow(label: 'UTR', value: widget.item.utr,
                        mono: true),
                    _DialogRow(label: 'Request ID',
                        value: widget.item.requestId.length > 14
                            ? '${widget.item.requestId.substring(0, 14)}…'
                            : widget.item.requestId,
                        mono: true, isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text('Admin Note (optional)',
                  style: AdminTextStyles.labelMedium.copyWith(
                      color: AdminColors.textSecondary)),
              const SizedBox(height: 6),
              _NoteField(controller: _noteCtrl, hint: 'Payment verified, UTR matched…'),

              const SizedBox(height: 20),

              Row(children: [
                Expanded(child: AdminActionButton(
                  label:    'Cancel',
                  icon:     Icons.close_rounded,
                  color:    AdminColors.textMuted,
                  outlined: true,
                  onTap:    () => Navigator.pop(context),
                )),
                const SizedBox(width: 10),
                Expanded(child: AdminActionButton(
                  label: _loading ? 'Processing…' : 'Approve Deposit',
                  icon:  Icons.check_rounded,
                  color: AdminColors.success,
                  onTap: _loading ? () {} : () async {
                    setState(() => _loading = true);
                    Navigator.pop(context);
                    widget.onConfirm(_noteCtrl.text.trim().isEmpty
                        ? null : _noteCtrl.text.trim());
                  },
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  final _DepositItem              item;
  final String                    playerName;
  final void Function(String)     onConfirm;

  const _RejectDialog({
    required this.item,
    required this.playerName,
    required this.onConfirm,
  });

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _noteCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminColors.danger.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.danger.withValues(alpha: 0.12),
                    border: Border.all(color: AdminColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AdminColors.danger, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reject Deposit', style: AdminTextStyles.titleLarge),
                    Text('Wallet balance will NOT be affected',
                        style: AdminTextStyles.bodySmall),
                  ],
                )),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AdminColors.textMuted, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AdminColors.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(
                      color: AdminColors.danger.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _DialogRow(label: 'Player', value: widget.playerName),
                    _DialogRow(label: 'Amount',
                        value: '₹${widget.item.amount.toStringAsFixed(2)}',
                        valueColor: AdminColors.gold),
                    _DialogRow(label: 'UTR', value: widget.item.utr,
                        mono: true, isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Row(children: [
                Text('Rejection Reason',
                    style: AdminTextStyles.labelMedium.copyWith(
                        color: AdminColors.textSecondary)),
                const SizedBox(width: 6),
                Text('*', style: AdminTextStyles.labelMedium.copyWith(
                    color: AdminColors.danger)),
              ]),
              const SizedBox(height: 6),
              _NoteField(
                controller: _noteCtrl,
                hint: 'UTR not found, invalid amount, duplicate request…',
                errorText: _error,
              ),

              const SizedBox(height: 20),

              Row(children: [
                Expanded(child: AdminActionButton(
                  label:    'Cancel',
                  icon:     Icons.close_rounded,
                  color:    AdminColors.textMuted,
                  outlined: true,
                  onTap:    () => Navigator.pop(context),
                )),
                const SizedBox(width: 10),
                Expanded(child: AdminActionButton(
                  label: 'Reject Deposit',
                  icon:  Icons.block_rounded,
                  color: AdminColors.danger,
                  onTap: () {
                    final note = _noteCtrl.text.trim();
                    if (note.isEmpty) {
                      setState(() => _error = 'Rejection reason is required');
                      return;
                    }
                    Navigator.pop(context);
                    widget.onConfirm(note);
                  },
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailDialog extends StatelessWidget {
  final _DepositItem         item;
  final Map<String, dynamic> userData;

  const _DetailDialog({required this.item, required this.userData});

  String _fmt(Timestamp ts) {
    final d = ts.toDate().toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month-1]} ${d.year}  '
        '${d.hour.toString().padLeft(2,'0')}:'
        '${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final name  = (userData['name']         as String?) ?? 'Unknown';
    final email = (userData['email']        as String?) ?? '—';
    final ign   = (userData['ign']          as String?) ?? '—';
    final bal   = (userData['walletBalance'] as num?)?.toDouble() ?? 0.0;
    final photo = userData['photoUrl']      as String?;

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Expanded(child: Text('Deposit Detail',
                    style: AdminTextStyles.titleLarge)),
                _StatusBadge(status: item.status),
                const SizedBox(width: 10),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AdminColors.textMuted, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),

              const SizedBox(height: 20),

              // Player section
              Row(children: [
                _PlayerAvatar(photoUrl: photo, size: 48),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AdminTextStyles.titleMedium),
                    Text(email, style: AdminTextStyles.bodySmall),
                    Text('IGN: $ign', style: AdminTextStyles.bodySmall),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Wallet Balance', style: AdminTextStyles.bodySmall),
                    Text('₹${bal.toStringAsFixed(2)}',
                        style: AdminTextStyles.titleSmall.copyWith(
                            color: AdminColors.gold)),
                  ],
                ),
              ]),

              const SizedBox(height: 20),
              Divider(color: AdminColors.border, height: 1),
              const SizedBox(height: 20),

              // Deposit info
              AdminSectionCard(
                title:      'REQUEST DETAILS',
                titleIcon:  Icons.receipt_rounded,
                titleColor: AdminColors.info,
                child: Column(
                  children: [
                    _DialogRow(label: 'Request ID', value: item.requestId, mono: true),
                    _DialogRow(label: 'UID',        value: item.uid,       mono: true),
                    _DialogRow(label: 'Amount',
                        value: '₹${item.amount.toStringAsFixed(2)}',
                        valueColor: AdminColors.gold),
                    _DialogRow(label: 'UTR',  value: item.utr, mono: true),
                    _DialogRow(label: 'Date', value: _fmt(item.createdAt)),
                    if (item.adminNote != null && item.adminNote!.isNotEmpty)
                      _DialogRow(label: 'Admin Note', value: item.adminNote!,
                          isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: AdminActionButton(
                  label: 'Close',
                  icon:  Icons.close_rounded,
                  color: AdminColors.textMuted,
                  outlined: true,
                  onTap: () => Navigator.pop(context),
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
// SMALL REUSABLE WIDGETS
// ═════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'approved' => AdminBadge(label: 'APPROVED', color: AdminColors.success, glowing: true),
      'rejected' => AdminBadge(label: 'REJECTED', color: AdminColors.danger),
      _          => AdminBadge(label: 'PENDING',  color: AdminColors.warning),
    };
  }
}

class _PlayerCell extends StatelessWidget {
  final String  name;
  final String  uid;
  final String? photoUrl;
  const _PlayerCell({required this.name, required this.uid, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PlayerAvatar(photoUrl: photoUrl, size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AdminTextStyles.titleSmall,
                  overflow: TextOverflow.ellipsis),
              Text('${uid.substring(0, 8)}…',
                  style: AdminTextStyles.bodySmall.copyWith(
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  final String? photoUrl;
  final double  size;
  const _PlayerAvatar({this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AdminColors.surfaceElevated,
        border: Border.all(color: AdminColors.border),
      ),
      child: photoUrl != null
          ? ClipOval(child: Image.network(
              photoUrl!, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(Icons.person_rounded,
                  color: AdminColors.textMuted, size: size * 0.5)))
          : Icon(Icons.person_rounded,
              color: AdminColors.textMuted, size: size * 0.5),
    );
  }
}

class _TinyButton extends StatefulWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final bool     outlined;
  final VoidCallback onTap;

  const _TinyButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  State<_TinyButton> createState() => _TinyButtonState();
}

class _TinyButtonState extends State<_TinyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color:        widget.outlined
                ? Colors.transparent
                : widget.color.withValues(alpha: _hovered ? 0.22 : 0.14),
            borderRadius: BorderRadius.circular(6),
            border:       Border.all(
              color: widget.color.withValues(alpha: _hovered ? 0.7 : 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 11, color: widget.color),
              const SizedBox(width: 4),
              Text(widget.label,
                  style: AdminTextStyles.labelSmall.copyWith(
                      color: widget.color, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String   label;
  final String   value;
  final String   group;
  final Color    color;
  final void Function(String) onTap;

  const _FilterChip({
    required this.label, required this.value, required this.group,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = value == group;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        active
              ? color.withValues(alpha: 0.15)
              : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(
            color: active ? color.withValues(alpha: 0.5) : AdminColors.border,
          ),
        ),
        child: Text(label,
            style: AdminTextStyles.labelSmall.copyWith(
              color:        active ? color : AdminColors.textMuted,
              letterSpacing: 0.8,
            )),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _SortButton({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(value == 'newest' ? 'oldest' : 'newest'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: AdminColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == 'newest'
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: AdminColors.purple,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              value == 'newest' ? 'NEWEST' : 'OLDEST',
              style: AdminTextStyles.labelSmall.copyWith(
                  color: AdminColors.purple, letterSpacing: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _InfoChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AdminTextStyles.labelSmall.copyWith(
              color: AdminColors.textMuted, fontSize: 8)),
          Text(value, style: AdminTextStyles.titleSmall.copyWith(color: color),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _DialogRow extends StatelessWidget {
  final String  label;
  final String  value;
  final Color?  valueColor;
  final bool    mono;
  final bool    isLast;

  const _DialogRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono    = false,
    this.isLast  = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AdminTextStyles.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: (mono
                  ? AdminTextStyles.bodySmall.copyWith(fontFamily: 'monospace')
                  : AdminTextStyles.bodyMedium).copyWith(
                color: valueColor ?? AdminColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;
  final String?               errorText;

  const _NoteField({
    required this.controller,
    required this.hint,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(
          color: errorText != null
              ? AdminColors.danger.withValues(alpha: 0.6)
              : AdminColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller:    controller,
            maxLines:      3,
            style:         AdminTextStyles.bodyMedium.copyWith(
                color: AdminColors.textPrimary),
            decoration:    InputDecoration(
              hintText:       hint,
              hintStyle:      AdminTextStyles.bodySmall,
              border:         InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: Text(errorText!,
                  style: AdminTextStyles.bodySmall.copyWith(
                      color: AdminColors.danger)),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// LOADING / EMPTY / ERROR STATES
// ═════════════════════════════════════════════

class _ShimmerTable extends StatefulWidget {
  const _ShimmerTable();

  @override
  State<_ShimmerTable> createState() => _ShimmerTableState();
}

class _ShimmerTableState extends State<_ShimmerTable>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Column(
        children: List.generate(5, (i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AdminDecorations.tableRow(isEven: i.isEven).color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            // Avatar shimmer
            Container(width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AdminColors.surfaceElevated.withValues(
                      alpha: 0.4 + 0.4 * _anim.value),
                )),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 10, width: 100,
                    color: AdminColors.surfaceElevated.withValues(
                        alpha: 0.4 + 0.4 * _anim.value)),
                const SizedBox(height: 5),
                Container(height: 8, width: 140,
                    color: AdminColors.surfaceElevated.withValues(
                        alpha: 0.2 + 0.2 * _anim.value)),
              ],
            )),
            Container(height: 10, width: 60,
                color: AdminColors.surfaceElevated.withValues(
                    alpha: 0.3 + 0.3 * _anim.value)),
            const SizedBox(width: 16),
            Container(height: 22, width: 70,
                decoration: BoxDecoration(
                  color: AdminColors.surfaceElevated.withValues(
                      alpha: 0.3 + 0.3 * _anim.value),
                  borderRadius: BorderRadius.circular(6),
                )),
          ]),
        )),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool         hasFilter;
  final VoidCallback onClear;

  const _EmptyState({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AdminColors.surfaceElevated,
                border: Border.all(color: AdminColors.border),
              ),
              child: Icon(
                hasFilter
                    ? Icons.search_off_rounded
                    : Icons.inbox_rounded,
                color: AdminColors.textMuted,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No matching requests' : 'No deposit requests yet',
              style: AdminTextStyles.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'Try adjusting your search or filters'
                  : 'Deposit requests will appear here in real-time',
              style: AdminTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              AdminActionButton(
                label:    'Clear Filters',
                icon:     Icons.filter_alt_off_rounded,
                color:    AdminColors.purple,
                outlined: true,
                onTap:    onClear,
              ),
            ],
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AdminColors.danger.withValues(alpha: 0.08),
                border: Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: AdminColors.danger, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Failed to load deposits', style: AdminTextStyles.titleSmall),
            const SizedBox(height: 6),
            Text(
              message,
              style: AdminTextStyles.bodySmall.copyWith(
                  color: AdminColors.danger.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'Check your Firestore indexes (see setup instructions)',
              style: AdminTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}