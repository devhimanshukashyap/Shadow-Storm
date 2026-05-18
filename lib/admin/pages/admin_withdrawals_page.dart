// lib/admin/pages/admin_withdrawals_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Withdrawal Management
// Phase 3: Realtime withdrawal processing panel
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart';
import '../theme/admin_theme.dart';
import '../services/admin_withdrawal_service.dart';

// ─────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────
class _WithdrawItem {
  final String requestId;
  final String uid;
  final double amount;
  final String method;       // 'upi' | 'bank'
  final String upiId;
  final String accountHolder;
  final String bankName;
  final String accountNumber;
  final String ifscCode;
  final String status;
  final Timestamp createdAt;
  final String? adminNote;
  final String? payoutReference;

  // Joined from users/{uid}
  String? playerName;
  String? playerEmail;
  String? playerPhoto;
  String? playerIgn;
  double? walletBalance;

  _WithdrawItem({
    required this.requestId,
    required this.uid,
    required this.amount,
    required this.method,
    required this.upiId,
    required this.accountHolder,
    required this.bankName,
    required this.accountNumber,
    required this.ifscCode,
    required this.status,
    required this.createdAt,
    this.adminNote,
    this.payoutReference,
  });

  factory _WithdrawItem.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _WithdrawItem(
      requestId:     doc.id,
      uid:           doc.reference.parent.parent!.id,
      amount:        (d['amount'] as num?)?.toDouble() ?? 0.0,
      method:        (d['method'] as String?) ?? 'upi',
      upiId:         (d['upiId'] as String?) ?? '',
      accountHolder: (d['accountHolder'] as String?) ?? '',
      bankName:      (d['bankName'] as String?) ?? '',
      accountNumber: (d['accountNumber'] as String?) ?? '',
      ifscCode:      (d['ifscCode'] as String?) ?? '',
      status:        (d['status'] as String?) ?? 'pending',
      createdAt:     (d['createdAt'] as Timestamp?) ?? Timestamp.now(),
      adminNote:     d['adminNote'] as String?,
      payoutReference: d['payoutReference'] as String?,
    );
  }

  Map<String, dynamic> toPaymentMap() => {
    'method':        method,
    'upiId':         upiId,
    'accountHolder': accountHolder,
    'bankName':      bankName,
    'accountNumber': accountNumber,
    'ifscCode':      ifscCode,
  };
}

// ─────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────
class AdminWithdrawalsPage extends StatefulWidget {
  const AdminWithdrawalsPage({super.key});

  @override
  State<AdminWithdrawalsPage> createState() => _AdminWithdrawalsPageState();
}

class _AdminWithdrawalsPageState extends State<AdminWithdrawalsPage>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery  = '';
  String _statusFilter = 'all';
  String _sortOrder    = 'newest';

  final Map<String, Map<String, dynamic>> _userCache  = {};
  final Set<String>                       _fetchingUids = {};
  final Map<String, bool>                 _actionLoading = {};

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

  // ── User cache ──────────────────────────────
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

  // ── Helpers ─────────────────────────────────
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

  List<_WithdrawItem> _applyFilters(List<_WithdrawItem> all) {
    var list = all;

    if (_statusFilter != 'all') {
      list = list.where((w) => w.status == _statusFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((w) {
        final user  = _userCache[w.uid] ?? {};
        final name  = ((user['name']  as String?) ?? '').toLowerCase();
        final email = ((user['email'] as String?) ?? '').toLowerCase();
        final ign   = ((user['ign']   as String?) ?? '').toLowerCase();
        return w.uid.toLowerCase().contains(_searchQuery)
            || w.upiId.toLowerCase().contains(_searchQuery)
            || name.contains(_searchQuery)
            || email.contains(_searchQuery)
            || ign.contains(_searchQuery);
      }).toList();
    }

    list.sort((a, b) => _sortOrder == 'newest'
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));

    return list;
  }

  // ── Approve flow ────────────────────────────
  void _showApproveDialog(_WithdrawItem item) {
    final user = _userCache[item.uid] ?? {};
    final name = (user['name'] as String?) ?? 'Unknown Player';
    showDialog(
      context: context,
      builder: (_) => _ApproveDialog(
        item:       item,
        playerName: name,
        onConfirm:  (ref, note) => _executeApprove(item, name, ref, note),
      ),
    );
  }

  Future<void> _executeApprove(
      _WithdrawItem item, String playerName, String ref, String? note) async {
    setState(() => _actionLoading[item.requestId] = true);
    try {
      await AdminWithdrawalService.instance.approveWithdrawal(
        uid:             item.uid,
        requestId:       item.requestId,
        amount:          item.amount,
        playerName:      playerName,
        payoutReference: ref,
        adminNote:       note,
      );
      if (mounted) {
        _showSnack(
          '✅  Withdrawal approved — ₹${item.amount.toStringAsFixed(0)} for $playerName',
          AdminColors.success,
        );
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(item.requestId));
    }
  }

  // ── Reject flow ─────────────────────────────
  void _showRejectDialog(_WithdrawItem item) {
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
      _WithdrawItem item, String playerName, String note) async {
    setState(() => _actionLoading[item.requestId] = true);
    try {
      await AdminWithdrawalService.instance.rejectWithdrawal(
        uid:        item.uid,
        requestId:  item.requestId,
        amount:     item.amount,
        playerName: playerName,
        adminNote:  note,
      );
      if (mounted) {
        _showSnack(
          '⛔  Withdrawal rejected — ₹${item.amount.toStringAsFixed(0)} refunded to $playerName',
          AdminColors.warning,
        );
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(item.requestId));
    }
  }

  // ── Detail view ─────────────────────────────
  void _showDetail(_WithdrawItem item) {
    final user = _userCache[item.uid] ?? {};
    showDialog(
      context: context,
      builder: (_) => _DetailDialog(item: item, userData: user),
    );
  }

  // ── Snack ────────────────────────────────────
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: AdminTextStyles.bodyMedium.copyWith(
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

  // ── Build ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('withdraw_requests')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final hasError  = snap.hasError;
        final allItems  = <_WithdrawItem>[];

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final item = _WithdrawItem.fromDoc(doc);
            allItems.add(item);
            _prefetchUser(item.uid);
          }
        }

        // Attach cached user data
        for (final item in allItems) {
          final user = _userCache[item.uid] ?? {};
          item.playerName    = user['name']          as String?;
          item.playerEmail   = user['email']         as String?;
          item.playerPhoto   = user['photoUrl']      as String?;
          item.playerIgn     = user['ign']           as String?;
          item.walletBalance = (user['walletBalance'] as num?)?.toDouble();
        }

        // Stats
        final pending       = allItems.where((w) => w.status == 'pending').length;
        final approvedToday = allItems.where((w) =>
            w.status == 'approved' && _isToday(w.createdAt)).length;
        final rejectedToday = allItems.where((w) =>
            w.status == 'rejected' && _isToday(w.createdAt)).length;
        final totalVolume   = allItems
            .where((w) => w.status == 'approved')
            .fold<double>(0, (sum, w) => sum + w.amount);

        final filtered = _applyFilters(allItems);

        return AdminPageContainer(
          title:    'Withdrawal Management',
          subtitle: 'Review and process all player withdrawal requests',
          actions: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AdminColors.danger.withValues(
                      alpha: 0.10 + 0.06 * _pulse.value),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AdminColors.danger.withValues(
                        alpha: 0.4 + 0.2 * _pulse.value),
                  ),
                  boxShadow: [BoxShadow(
                    color: AdminColors.danger.withValues(
                        alpha: 0.12 * _pulse.value),
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
                        color: AdminColors.danger,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('LIVE', style: AdminTextStyles.labelSmall.copyWith(
                        color: AdminColors.danger)),
                  ],
                ),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStats(
                pending:       pending,
                approvedToday: approvedToday,
                rejectedToday: rejectedToday,
                totalVolume:   totalVolume,
                isLoading:     isLoading,
              ),
              const SizedBox(height: 20),
              _buildFilters(),
              const SizedBox(height: 16),
              AdminSectionCard(
                title:      'WITHDRAWAL REQUESTS',
                titleIcon:  Icons.remove_circle_rounded,
                titleColor: AdminColors.danger,
                titleActions: [
                  AdminBadge(
                    label: '${filtered.length} RECORDS',
                    color: AdminColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  AdminBadge(
                    label:   'LIVE',
                    color:   AdminColors.danger,
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
          subLabel: 'Awaiting payout',
        ),
        AdminStatCard(
          label:    'Paid Today',
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
          subLabel: 'Refunded today',
        ),
        AdminStatCard(
          label:    'Total Paid Out',
          value:    isLoading ? '—' : '₹${totalVolume.toStringAsFixed(0)}',
          icon:     Icons.payments_rounded,
          color:    AdminColors.gold,
          subLabel: 'All approved withdrawals',
        ),
      ],
    );
  }

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
        style: AdminTextStyles.bodyMedium.copyWith(
            color: AdminColors.textPrimary),
        decoration: InputDecoration(
          hintText:  'Search by name, UID, UPI ID, IGN…',
          hintStyle: AdminTextStyles.bodySmall,
          prefixIcon: Icon(Icons.search_rounded,
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
          border:         InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
      value:     _sortOrder,
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

  Widget _buildBody({
    required bool               isLoading,
    required bool               hasError,
    required List<_WithdrawItem> items,
    String?                     error,
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
      return _WithdrawTable(
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

    return _WithdrawCards(
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
class _WithdrawTable extends StatelessWidget {
  final List<_WithdrawItem>               items;
  final bool                              isTablet;
  final Map<String, Map<String, dynamic>> userCache;
  final Map<String, bool>                 actionLoading;
  final String Function(Timestamp)        formatDate;
  final void Function(_WithdrawItem)      onView;
  final void Function(_WithdrawItem)      onApprove;
  final void Function(_WithdrawItem)      onReject;

  const _WithdrawTable({
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: AdminDecorations.tableHeader,
          child: Row(
            children: [
              Expanded(flex: 3, child: _hdr('PLAYER')),
              Expanded(flex: 2, child: _hdr('AMOUNT')),
              Expanded(flex: 2, child: _hdr('METHOD')),
              if (!isTablet) Expanded(flex: 3, child: _hdr('PAYMENT DETAILS')),
              Expanded(flex: 2, child: _hdr('STATUS')),
              if (!isTablet) Expanded(flex: 3, child: _hdr('CREATED AT')),
              Expanded(flex: isTablet ? 3 : 4, child: _hdr('ACTIONS')),
            ],
          ),
        ),
        ...items.asMap().entries.map((entry) {
          final i    = entry.key;
          final item = entry.value;
          final user = userCache[item.uid] ?? {};
          return _WithdrawTableRow(
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

  Widget _hdr(String label) => Text(label,
      style: AdminTextStyles.labelSmall.copyWith(
          color: AdminColors.textMuted, letterSpacing: 1.2));
}

class _WithdrawTableRow extends StatefulWidget {
  final _WithdrawItem               item;
  final Map<String, dynamic>        userData;
  final bool                        isEven;
  final bool                        isTablet;
  final bool                        isLoading;
  final String Function(Timestamp)  formatDate;
  final VoidCallback                onView;
  final VoidCallback                onApprove;
  final VoidCallback                onReject;

  const _WithdrawTableRow({
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
  State<_WithdrawTableRow> createState() => _WithdrawTableRowState();
}

class _WithdrawTableRowState extends State<_WithdrawTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final name      = (widget.userData['name'] as String?) ??
        widget.item.uid.substring(0, 8);
    final photo     = widget.userData['photoUrl'] as String?;
    final isPending = widget.item.status == 'pending';
    final isUpi     = widget.item.method == 'upi';

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
          border: const Border(
            bottom: BorderSide(color: AdminColors.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: _PlayerCell(
              name:     name,
              uid:      widget.item.uid,
              photoUrl: photo,
            )),

            Expanded(flex: 2, child: Text(
              '₹${widget.item.amount.toStringAsFixed(2)}',
              style: AdminTextStyles.titleSmall.copyWith(
                  color: AdminColors.gold),
            )),

            // Method badge
            Expanded(flex: 2, child: _MethodBadge(isUpi: isUpi)),

            // Payment details (desktop only)
            if (!widget.isTablet)
              Expanded(flex: 3, child: GestureDetector(
                onTap: () {
                  final val = isUpi
                      ? widget.item.upiId
                      : widget.item.accountNumber;
                  Clipboard.setData(ClipboardData(text: val));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied'),
                        duration: Duration(seconds: 1)));
                },
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        isUpi
                            ? widget.item.upiId.isNotEmpty
                                ? widget.item.upiId
                                : '—'
                            : widget.item.accountNumber.isNotEmpty
                                ? '${widget.item.bankName} ···${widget.item.accountNumber.length > 4 ? widget.item.accountNumber.substring(widget.item.accountNumber.length - 4) : widget.item.accountNumber}'
                                : '—',
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

            Expanded(flex: 2, child: _StatusBadge(
                status: widget.item.status)),

            if (!widget.isTablet)
              Expanded(flex: 3, child: Text(
                widget.formatDate(widget.item.createdAt),
                style: AdminTextStyles.bodySmall,
              )),

            Expanded(flex: widget.isTablet ? 3 : 4,
              child: widget.isLoading
                  ? const Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: AdminColors.purple)))
                  : Row(
                      children: [
                        _TinyButton(
                          label: 'View',
                          icon:  Icons.visibility_rounded,
                          color: AdminColors.info,
                          onTap: widget.onView,
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 4),
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
// MOBILE CARDS
// ═════════════════════════════════════════════
class _WithdrawCards extends StatelessWidget {
  final List<_WithdrawItem>               items;
  final Map<String, Map<String, dynamic>> userCache;
  final Map<String, bool>                 actionLoading;
  final String Function(Timestamp)        formatDate;
  final void Function(_WithdrawItem)      onView;
  final void Function(_WithdrawItem)      onApprove;
  final void Function(_WithdrawItem)      onReject;

  const _WithdrawCards({
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
        final user      = userCache[item.uid] ?? {};
        final name      = (user['name'] as String?) ?? item.uid.substring(0, 8);
        final photo     = user['photoUrl'] as String?;
        final loading   = actionLoading[item.requestId] ?? false;
        final isPending = item.status == 'pending';
        final isUpi     = item.method == 'upi';

        return Container(
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

              Row(
                children: [
                  _InfoChip(label: 'AMOUNT',
                      value: '₹${item.amount.toStringAsFixed(2)}',
                      color: AdminColors.gold),
                  const SizedBox(width: 8),
                  _MethodBadge(isUpi: isUpi),
                ],
              ),

              const SizedBox(height: 8),

              if (isUpi && item.upiId.isNotEmpty)
                _InfoChip(
                  label: 'UPI ID',
                  value: item.upiId,
                  color: AdminColors.info,
                )
              else if (!isUpi && item.accountNumber.isNotEmpty)
                _InfoChip(
                  label: 'BANK',
                  value: '${item.bankName} · ···${item.accountNumber.length > 4 ? item.accountNumber.substring(item.accountNumber.length - 4) : item.accountNumber}',
                  color: AdminColors.info,
                ),

              const SizedBox(height: 8),

              Text(formatDate(item.createdAt),
                  style: AdminTextStyles.bodySmall),

              const SizedBox(height: 12),

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

  Color _borderColor(String status) => switch (status) {
    'approved' => AdminColors.success.withValues(alpha: 0.3),
    'rejected' => AdminColors.danger.withValues(alpha: 0.2),
    _          => AdminColors.warning.withValues(alpha: 0.25),
  };
}

// ═════════════════════════════════════════════
// APPROVE DIALOG
// ═════════════════════════════════════════════
class _ApproveDialog extends StatefulWidget {
  final _WithdrawItem                       item;
  final String                              playerName;
  final void Function(String ref, String? note) onConfirm;

  const _ApproveDialog({
    required this.item,
    required this.playerName,
    required this.onConfirm,
  });

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _refCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _refError;

  @override
  void dispose() {
    _refCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUpi = widget.item.method == 'upi';

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminColors.success.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
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
                    Text('Approve Withdrawal',
                        style: AdminTextStyles.titleLarge),
                    Text('Mark this payout as sent',
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

              // Summary
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AdminColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(
                      color: AdminColors.success.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  _DialogRow(label: 'Player',  value: widget.playerName),
                  _DialogRow(label: 'Amount',
                      value: '₹${widget.item.amount.toStringAsFixed(2)}',
                      valueColor: AdminColors.gold),
                  _DialogRow(label: 'Method',
                      value: isUpi ? '📱 UPI' : '🏦 Bank Transfer'),
                  if (isUpi && widget.item.upiId.isNotEmpty)
                    _DialogRow(label: 'UPI ID',
                        value: widget.item.upiId, mono: true),
                  if (!isUpi) ...[
                    if (widget.item.bankName.isNotEmpty)
                      _DialogRow(label: 'Bank',
                          value: widget.item.bankName),
                    if (widget.item.accountNumber.isNotEmpty)
                      _DialogRow(label: 'Account',
                          value: widget.item.accountNumber, mono: true),
                    if (widget.item.ifscCode.isNotEmpty)
                      _DialogRow(label: 'IFSC',
                          value: widget.item.ifscCode, mono: true),
                    if (widget.item.accountHolder.isNotEmpty)
                      _DialogRow(label: 'Holder',
                          value: widget.item.accountHolder),
                  ],
                  _DialogRow(label: 'Request ID',
                      value: widget.item.requestId.length > 14
                          ? '${widget.item.requestId.substring(0, 14)}…'
                          : widget.item.requestId,
                      mono: true, isLast: true),
                ]),
              ),

              const SizedBox(height: 16),

              // Payout reference (required)
              Row(children: [
                Text('Payout Reference',
                    style: AdminTextStyles.labelMedium.copyWith(
                        color: AdminColors.textSecondary)),
                const SizedBox(width: 6),
                Text('*', style: AdminTextStyles.labelMedium.copyWith(
                    color: AdminColors.danger)),
              ]),
              const SizedBox(height: 6),
              _NoteField(
                controller: _refCtrl,
                hint:       'UTR number, transaction ID, reference…',
                maxLines:   1,
                errorText:  _refError,
              ),

              const SizedBox(height: 12),

              Text('Admin Note (optional)',
                  style: AdminTextStyles.labelMedium.copyWith(
                      color: AdminColors.textSecondary)),
              const SizedBox(height: 6),
              _NoteField(
                controller: _noteCtrl,
                hint:       'Payment sent via IMPS…',
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
                  label: 'Approve & Mark Paid',
                  icon:  Icons.check_rounded,
                  color: AdminColors.success,
                  onTap: () {
                    final ref = _refCtrl.text.trim();
                    if (ref.isEmpty) {
                      setState(() => _refError = 'Payout reference is required');
                      return;
                    }
                    Navigator.pop(context);
                    widget.onConfirm(
                      ref,
                      _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
                    );
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

// ═════════════════════════════════════════════
// REJECT DIALOG
// ═════════════════════════════════════════════
class _RejectDialog extends StatefulWidget {
  final _WithdrawItem            item;
  final String                   playerName;
  final void Function(String)    onConfirm;

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
                    Text('Reject Withdrawal',
                        style: AdminTextStyles.titleLarge),
                    Text('Balance will be refunded to player',
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

              // Refund notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        AdminColors.warning.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                      color: AdminColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AdminColors.warning, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '₹${widget.item.amount.toStringAsFixed(2)} will be refunded to ${widget.playerName}\'s wallet',
                        style: AdminTextStyles.bodySmall.copyWith(
                            color: AdminColors.warning),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        AdminColors.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(
                      color: AdminColors.danger.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  _DialogRow(label: 'Player', value: widget.playerName),
                  _DialogRow(label: 'Amount',
                      value: '₹${widget.item.amount.toStringAsFixed(2)}',
                      valueColor: AdminColors.gold),
                  _DialogRow(label: 'Method',
                      value: widget.item.method == 'upi' ? 'UPI' : 'Bank Transfer',
                      isLast: true),
                ]),
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
                hint:       'Invalid UPI, account closed, failed payment…',
                errorText:  _error,
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
                  label: 'Reject & Refund',
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

// ═════════════════════════════════════════════
// DETAIL DIALOG
// ═════════════════════════════════════════════
class _DetailDialog extends StatelessWidget {
  final _WithdrawItem        item;
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
    final name    = (userData['name']          as String?) ?? 'Unknown';
    final email   = (userData['email']         as String?) ?? '—';
    final ign     = (userData['ign']           as String?) ?? '—';
    final bal     = (userData['walletBalance']  as num?)?.toDouble() ?? 0.0;
    final photo   = userData['photoUrl']       as String?;
    final isUpi   = item.method == 'upi';

    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('Withdrawal Detail',
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
                    Text('Current Balance', style: AdminTextStyles.bodySmall),
                    Text('₹${bal.toStringAsFixed(2)}',
                        style: AdminTextStyles.titleSmall.copyWith(
                            color: AdminColors.gold)),
                  ],
                ),
              ]),

              const SizedBox(height: 20),
              Divider(color: AdminColors.border, height: 1),
              const SizedBox(height: 20),

              AdminSectionCard(
                title:      'REQUEST DETAILS',
                titleIcon:  Icons.receipt_rounded,
                titleColor: AdminColors.danger,
                child: Column(children: [
                  _DialogRow(label: 'Request ID', value: item.requestId, mono: true),
                  _DialogRow(label: 'UID',        value: item.uid,       mono: true),
                  _DialogRow(label: 'Amount',
                      value: '₹${item.amount.toStringAsFixed(2)}',
                      valueColor: AdminColors.gold),
                  _DialogRow(label: 'Date',   value: _fmt(item.createdAt)),
                  if (item.payoutReference != null && item.payoutReference!.isNotEmpty)
                    _DialogRow(label: 'Payout Ref',
                        value: item.payoutReference!, mono: true),
                  if (item.adminNote != null && item.adminNote!.isNotEmpty)
                    _DialogRow(label: 'Admin Note', value: item.adminNote!),
                ]),
              ),

              const SizedBox(height: 12),

              AdminSectionCard(
                title:      'PAYMENT DETAILS',
                titleIcon:  isUpi
                    ? Icons.smartphone_rounded
                    : Icons.account_balance_rounded,
                titleColor: AdminColors.info,
                child: Column(children: isUpi ? [
                  _DialogRow(label: 'Method', value: '📱 UPI'),
                  _DialogRow(label: 'UPI ID', value: item.upiId.isNotEmpty ? item.upiId : '—',
                      mono: true, isLast: true),
                ] : [
                  _DialogRow(label: 'Method',  value: '🏦 Bank Transfer'),
                  _DialogRow(label: 'Bank',    value: item.bankName.isNotEmpty ? item.bankName : '—'),
                  _DialogRow(label: 'Holder',  value: item.accountHolder.isNotEmpty ? item.accountHolder : '—'),
                  _DialogRow(label: 'Account', value: item.accountNumber.isNotEmpty ? item.accountNumber : '—', mono: true),
                  _DialogRow(label: 'IFSC',    value: item.ifscCode.isNotEmpty ? item.ifscCode : '—',
                      mono: true, isLast: true),
                ]),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: AdminActionButton(
                  label:    'Close',
                  icon:     Icons.close_rounded,
                  color:    AdminColors.textMuted,
                  outlined: true,
                  onTap:    () => Navigator.pop(context),
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
// SMALL SHARED WIDGETS
// ═════════════════════════════════════════════

class _MethodBadge extends StatelessWidget {
  final bool isUpi;
  const _MethodBadge({required this.isUpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: (isUpi ? AdminColors.info : AdminColors.gold)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (isUpi ? AdminColors.info : AdminColors.gold)
              .withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUpi ? Icons.smartphone_rounded : Icons.account_balance_rounded,
            size: 10,
            color: isUpi ? AdminColors.info : AdminColors.gold,
          ),
          const SizedBox(width: 4),
          Text(
            isUpi ? 'UPI' : 'BANK',
            style: AdminTextStyles.labelSmall.copyWith(
              color: isUpi ? AdminColors.info : AdminColors.gold,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) => switch (status) {
    'approved' => AdminBadge(label: 'APPROVED', color: AdminColors.success, glowing: true),
    'rejected' => AdminBadge(label: 'REJECTED', color: AdminColors.danger),
    _          => AdminBadge(label: 'PENDING',  color: AdminColors.warning),
  };
}

class _PlayerCell extends StatelessWidget {
  final String  name;
  final String  uid;
  final String? photoUrl;
  const _PlayerCell({required this.name, required this.uid, this.photoUrl});

  @override
  Widget build(BuildContext context) => Row(
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

class _PlayerAvatar extends StatelessWidget {
  final String? photoUrl;
  final double  size;
  const _PlayerAvatar({this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AdminColors.surfaceElevated,
      border: Border.all(color: AdminColors.border),
    ),
    child: photoUrl != null
        ? ClipOval(child: Image.network(photoUrl!, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(Icons.person_rounded,
                color: AdminColors.textMuted, size: size * 0.5)))
        : Icon(Icons.person_rounded,
            color: AdminColors.textMuted, size: size * 0.5),
  );
}

class _TinyButton extends StatefulWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final bool     outlined;
  final VoidCallback onTap;

  const _TinyButton({
    required this.label, required this.icon, required this.color,
    required this.onTap, this.outlined = false,
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
            color: widget.outlined
                ? Colors.transparent
                : widget.color.withValues(alpha: _hovered ? 0.22 : 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: widget.color.withValues(alpha: _hovered ? 0.7 : 0.35)),
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
          color:        active ? color.withValues(alpha: 0.15) : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(
              color: active ? color.withValues(alpha: 0.5) : AdminColors.border),
        ),
        child: Text(label,
            style: AdminTextStyles.labelSmall.copyWith(
                color: active ? color : AdminColors.textMuted,
                letterSpacing: 0.8)),
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
              color: AdminColors.purple, size: 14,
            ),
            const SizedBox(width: 5),
            Text(value == 'newest' ? 'NEWEST' : 'OLDEST',
                style: AdminTextStyles.labelSmall.copyWith(
                    color: AdminColors.purple, letterSpacing: 0.8)),
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
  Widget build(BuildContext context) => Container(
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

class _DialogRow extends StatelessWidget {
  final String  label;
  final String  value;
  final Color?  valueColor;
  final bool    mono;
  final bool    isLast;

  const _DialogRow({
    required this.label, required this.value,
    this.valueColor, this.mono = false, this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label,
              style: AdminTextStyles.bodySmall)),
          Expanded(child: Text(value,
            style: (mono
                ? AdminTextStyles.bodySmall.copyWith(fontFamily: 'monospace')
                : AdminTextStyles.bodyMedium).copyWith(
              color: valueColor ?? AdminColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          )),
        ],
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  final TextEditingController controller;
  final String                hint;
  final String?               errorText;
  final int                   maxLines;

  const _NoteField({
    required this.controller,
    required this.hint,
    this.errorText,
    this.maxLines = 3,
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
            maxLines:      maxLines,
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

// ─ Loading / Empty / Error states ─────────────

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
  Widget build(BuildContext context) => Center(
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
              hasFilter ? Icons.search_off_rounded : Icons.inbox_rounded,
              color: AdminColors.textMuted, size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter ? 'No matching requests' : 'No withdrawal requests yet',
            style: AdminTextStyles.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try adjusting your search or filters'
                : 'Withdrawal requests will appear here in real-time',
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

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
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
          Text('Failed to load withdrawals',
              style: AdminTextStyles.titleSmall),
          const SizedBox(height: 6),
          Text(message,
              style: AdminTextStyles.bodySmall.copyWith(
                  color: AdminColors.danger.withValues(alpha: 0.7)),
              textAlign: TextAlign.center, maxLines: 3,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text('Check your Firestore indexes (see setup instructions)',
              style: AdminTextStyles.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}