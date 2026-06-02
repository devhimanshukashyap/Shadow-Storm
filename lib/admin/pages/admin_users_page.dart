// lib/admin/pages/admin_users_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin User Management
// F2: Readable ID display, search by readableId/UID/name/IGN/email, createdAt column
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart' hide AdminGrid;
import '../theme/admin_theme.dart';
import '../services/admin_user_service.dart';
import '../widgets/admin_components.dart';

// ─────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery  = '';
  String _adminFilter  = 'all'; // all | admin | user | frozen
  String _sortOrder    = 'newest';

  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _searchCtrl.addListener(() =>
        setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  List<AdminUserData> _applyFilters(List<AdminUserData> all) {
    var list = all;

    switch (_adminFilter) {
      case 'admin':  list = list.where((u) =>  u.isAdmin).toList();  break;
      case 'user':   list = list.where((u) => !u.isAdmin).toList();  break;
      case 'frozen': list = list.where((u) =>  u.isFrozen).toList(); break;
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((u) {
        // Search by: name, email, UID, readableId, IGN, gameUid
        return u.uid.toLowerCase().contains(_searchQuery)
            || u.name.toLowerCase().contains(_searchQuery)
            || u.email.toLowerCase().contains(_searchQuery)
            || (u.ign    ?? '').toLowerCase().contains(_searchQuery)
            || (u.gameUid ?? '').toLowerCase().contains(_searchQuery)
            || (u.readableId ?? '').toLowerCase().contains(_searchQuery);
      }).toList();
    }

    list.sort((a, b) {
      switch (_sortOrder) {
        case 'balance_high': return b.walletBalance.compareTo(a.walletBalance);
        case 'balance_low':  return a.walletBalance.compareTo(b.walletBalance);
        case 'earnings_high': return b.totalEarnings.compareTo(a.totalEarnings);
        case 'newest': {
          final ta = a.createdAt ?? Timestamp(0, 0);
          final tb = b.createdAt ?? Timestamp(0, 0);
          return tb.compareTo(ta);
        }
        default: {
          final ta = a.createdAt ?? Timestamp(0, 0);
          final tb = b.createdAt ?? Timestamp(0, 0);
          return ta.compareTo(tb);
        }
      }
    });

    return list;
  }

  void _showUserDetail(AdminUserData user) {
    showDialog(
      context: context,
      builder: (_) => _UserDetailDialog(
        user:          user,
        onAdjust:      (delta, reason) => _executeAdjust(user, delta, reason),
        onToggleAdmin: (val) => _executeToggleAdmin(user, val),
        onFreeze:      (val) => _executeFreeze(user, val),
        onAddNote:     (note) => _executeAddNote(user, note),
      ),
    );
  }

  Future<void> _executeAdjust(AdminUserData user, double delta, String reason) async {
    setState(() => _actionLoading[user.uid] = true);
    try {
      await AdminUserService.instance.adjustBalance(
        uid: user.uid, playerName: user.name, delta: delta, reason: reason,
      );
      if (mounted) {
        _showSnack(
        '${delta >= 0 ? '✅' : '⚠️'}  Balance adjusted — ₹${delta.abs().toStringAsFixed(2)} ${delta >= 0 ? 'credited to' : 'debited from'} ${user.name}',
        delta >= 0 ? AdminColors.success : AdminColors.warning,
      );
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(user.uid));
    }
  }

  Future<void> _executeToggleAdmin(AdminUserData user, bool val) async {
    setState(() => _actionLoading[user.uid] = true);
    try {
      await AdminUserService.instance.setAdminFlag(
          uid: user.uid, playerName: user.name, isAdmin: val);
      if (mounted) {
        _showSnack(
        '${val ? '🛡️' : '👤'}  ${user.name} ${val ? 'promoted to admin' : 'removed from admin'}',
        AdminColors.purple,
      );
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(user.uid));
    }
  }

  Future<void> _executeFreeze(AdminUserData user, bool val) async {
    setState(() => _actionLoading[user.uid] = true);
    try {
      await AdminUserService.instance.setFrozen(
          uid: user.uid, playerName: user.name, frozen: val);
      if (mounted) {
        _showSnack(
        '${val ? '🔒' : '🔓'}  ${user.name}\'s account ${val ? 'frozen' : 'unfrozen'}',
        val ? AdminColors.danger : AdminColors.success,
      );
      }
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(user.uid));
    }
  }

  Future<void> _executeAddNote(AdminUserData user, String note) async {
    try {
      await AdminUserService.instance.addAdminNote(uid: user.uid, note: note);
      if (mounted) _showSnack('📝  Note saved for ${user.name}', AdminColors.info);
    } catch (e) {
      if (mounted) _showSnack('❌  Error: $e', AdminColors.danger);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary)),
      backgroundColor: AdminColors.surfaceElevated,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final hasError  = snap.hasError;
        var   allUsers  = <AdminUserData>[];

        if (snap.hasData) {
          allUsers = snap.data!.docs.map((d) => AdminUserData.fromDoc(d)).toList();
        }

        final totalUsers   = allUsers.length;
        final adminCount   = allUsers.where((u) => u.isAdmin).length;
        final frozenCount  = allUsers.where((u) => u.isFrozen).length;
        final totalBalance = allUsers.fold<double>(0, (s, u) => s + u.walletBalance);
        final filtered     = _applyFilters(allUsers);

        return AdminPageContainer(
          title:    'User Management',
          subtitle: 'View, manage, and moderate all registered players',
          actions: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        AdminColors.info.withValues(alpha: 0.10 + 0.06 * _pulse.value),
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(color: AdminColors.info.withValues(alpha: 0.4 + 0.2 * _pulse.value)),
                  boxShadow:    [BoxShadow(color: AdminColors.info.withValues(alpha: 0.12 * _pulse.value), blurRadius: 10)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: AdminColors.info)),
                  const SizedBox(width: 6),
                  Text('LIVE', style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.info)),
                ]),
              ),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Stats
            AdminGrid(
              mobileColumns: 2, tabletColumns: 2, desktopColumns: 4,
              spacing: 14, runSpacing: 14,
              children: [
                AdminStatCard(label: 'Total Users',  value: isLoading ? '—' : '$totalUsers', icon: Icons.people_rounded,                    color: AdminColors.info,    subLabel: 'Registered players'),
                AdminStatCard(label: 'Admins',       value: isLoading ? '—' : '$adminCount',  icon: Icons.shield_rounded,                    color: AdminColors.purple,  subLabel: 'Admin accounts'),
                AdminStatCard(label: 'Frozen',       value: isLoading ? '—' : '$frozenCount', icon: Icons.lock_rounded,                      color: AdminColors.danger,  subLabel: 'Suspended accounts'),
                AdminStatCard(label: 'Total Wallet', value: isLoading ? '—' : '₹${totalBalance.toStringAsFixed(0)}', icon: Icons.account_balance_wallet_rounded, color: AdminColors.gold, subLabel: 'Combined balance'),
              ],
            ),
            const SizedBox(height: 20),
            _buildFilters(),
            const SizedBox(height: 16),
            AdminSectionCard(
              title:      'ALL PLAYERS',
              titleIcon:  Icons.people_rounded,
              titleColor: AdminColors.info,
              titleActions: [
                AdminBadge(label: '${filtered.length} USERS', color: AdminColors.textMuted),
                const SizedBox(width: 8),
                AdminBadge(label: 'LIVE', color: AdminColors.info, glowing: true),
              ],
              child: _buildBody(
                isLoading: isLoading, hasError: hasError,
                users: filtered, error: snap.error?.toString(),
                formatDate: _formatDate,
              ),
            ),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }

  Widget _buildFilters() {
    final isDesktop = AdminResponsive.isDesktop(context);

    final searchField = Container(
      height: 40,
      decoration: BoxDecoration(
        color: AdminColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary),
        decoration: InputDecoration(
          hintText:  'Search name, SSP-ID, UID, email, IGN…',
          hintStyle: AdminTextStyles.bodySmall,
          prefixIcon: const Icon(Icons.search_rounded, color: AdminColors.textMuted, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                  child: const Icon(Icons.close_rounded, color: AdminColors.textMuted, size: 16),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );

    final filterChips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterChip(label: 'ALL',    value: 'all',    group: _adminFilter, color: AdminColors.purple,  onTap: (v) => setState(() => _adminFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'ADMINS', value: 'admin',  group: _adminFilter, color: AdminColors.info,    onTap: (v) => setState(() => _adminFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'USERS',  value: 'user',   group: _adminFilter, color: AdminColors.success, onTap: (v) => setState(() => _adminFilter = v)),
        const SizedBox(width: 6),
        _FilterChip(label: 'FROZEN', value: 'frozen', group: _adminFilter, color: AdminColors.danger,  onTap: (v) => setState(() => _adminFilter = v)),
      ],
    );

    final sortMenu = _SortDropdown(value: _sortOrder, onChanged: (v) => setState(() => _sortOrder = v));

    if (isDesktop) {
      return Row(children: [
        Expanded(flex: 3, child: searchField),
        const SizedBox(width: 12),
        filterChips,
        const SizedBox(width: 12),
        sortMenu,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      searchField,
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [filterChips, const SizedBox(width: 12), sortMenu]),
      ),
    ]);
  }

  Widget _buildBody({
    required bool isLoading, required bool hasError,
    required List<AdminUserData> users,
    required String Function(Timestamp?) formatDate, String? error,
  }) {
    if (isLoading) return const _ShimmerTable();
    if (hasError)  return _ErrorState(message: error ?? 'Unknown error');
    if (users.isEmpty) {
      return _EmptyState(
        hasFilter: _searchQuery.isNotEmpty || _adminFilter != 'all',
        onClear: () {
          _searchCtrl.clear();
          setState(() { _searchQuery = ''; _adminFilter = 'all'; });
        },
      );
    }
    final isDesktop = AdminResponsive.isDesktop(context);
    final isTablet  = AdminResponsive.isTablet(context);

    if (isDesktop || isTablet) {
      return _UsersTable(
        users: users, isTablet: isTablet,
        actionLoading: _actionLoading,
        formatDate: formatDate, onView: _showUserDetail,
      );
    }
    return _UsersCards(
      users: users, actionLoading: _actionLoading,
      formatDate: formatDate, onView: _showUserDetail,
    );
  }
}

// ═════════════════════════════════════════════
// TABLE (Desktop / Tablet)
// ═════════════════════════════════════════════
class _UsersTable extends StatelessWidget {
  final List<AdminUserData>          users;
  final bool                         isTablet;
  final Map<String, bool>            actionLoading;
  final String Function(Timestamp?)  formatDate;
  final void Function(AdminUserData) onView;

  const _UsersTable({
    required this.users, required this.isTablet,
    required this.actionLoading, required this.formatDate, required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: AdminDecorations.tableHeader,
        child: Row(children: [
          Expanded(flex: 3, child: _hdr('PLAYER')),
          if (!isTablet) Expanded(flex: 2, child: _hdr('READABLE ID')),
          if (!isTablet) Expanded(flex: 2, child: _hdr('WALLET')),
          if (!isTablet) Expanded(flex: 2, child: _hdr('STATS')),
          Expanded(flex: 2, child: _hdr('ROLE')),
          if (!isTablet) Expanded(flex: 2, child: _hdr('JOINED')),
          Expanded(flex: 2, child: _hdr('ACTIONS')),
        ]),
      ),
      ...users.asMap().entries.map((e) => _UserTableRow(
        user: e.value, isEven: e.key.isEven, isTablet: isTablet,
        isLoading: actionLoading[e.value.uid] ?? false,
        formatDate: formatDate, onView: () => onView(e.value),
      )),
    ]);
  }

  Widget _hdr(String label) => Text(label,
      style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted, letterSpacing: 1.2));
}

class _UserTableRow extends StatefulWidget {
  final AdminUserData           user;
  final bool                    isEven, isTablet, isLoading;
  final String Function(Timestamp?) formatDate;
  final VoidCallback            onView;

  const _UserTableRow({
    required this.user, required this.isEven, required this.isTablet,
    required this.isLoading, required this.formatDate, required this.onView,
  });

  @override
  State<_UserTableRow> createState() => _UserTableRowState();
}

class _UserTableRowState extends State<_UserTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered
              ? AdminColors.surfaceElevated.withValues(alpha: 0.8)
              : (widget.isEven ? AdminColors.surfaceCard : AdminColors.background),
          border: const Border(bottom: BorderSide(color: AdminColors.border, width: 0.5)),
        ),
        child: Row(children: [
          // Player
          Expanded(flex: 3, child: Row(children: [
            _UserAvatar(photoUrl: user.photoUrl, size: 32, isFrozen: user.isFrozen),
            const SizedBox(width: 8),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.name, style: AdminTextStyles.titleSmall, overflow: TextOverflow.ellipsis),
              Text(user.email, style: AdminTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
              if (user.ign != null && user.ign!.isNotEmpty)
                Text('IGN: ${user.ign}',
                    style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.purple),
                    overflow: TextOverflow.ellipsis),
            ])),
          ])),

          // Readable ID
          if (!widget.isTablet)
            Expanded(flex: 2, child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: user.readableId ?? user.uid));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color:        AdminColors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(5),
                  border:       Border.all(color: AdminColors.purple.withValues(alpha: 0.25)),
                ),
                child: Text(
                  user.readableId ?? '—',
                  style: AdminTextStyles.labelSmall.copyWith(
                      color: AdminColors.purple, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )),

          // Wallet
          if (!widget.isTablet)
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('₹${user.walletBalance.toStringAsFixed(2)}',
                  style: AdminTextStyles.titleSmall.copyWith(color: AdminColors.gold)),
              Text('+₹${user.totalDeposits.toStringAsFixed(0)} dep', style: AdminTextStyles.bodySmall),
            ])),

          // Stats
          if (!widget.isTablet)
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${user.tournamentsPlayed} tournaments', style: AdminTextStyles.bodySmall),
              Text('${user.wins} wins',
                  style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.gold)),
            ])),

          // Role
          Expanded(flex: 2, child: Row(children: [
            if (user.isAdmin)
              _RoleBadge(label: 'ADMIN', color: AdminColors.purple)
            else
              _RoleBadge(label: 'PLAYER', color: AdminColors.textMuted),
            if (user.isFrozen) ...[
              const SizedBox(width: 4),
              _RoleBadge(label: 'FROZEN', color: AdminColors.danger),
            ],
          ])),

          // Joined
          if (!widget.isTablet)
            Expanded(flex: 2, child: Text(widget.formatDate(user.createdAt),
                style: AdminTextStyles.bodySmall)),

          // Actions
          Expanded(flex: 2, child: widget.isLoading
              ? const Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.purple)))
              : _TinyButton(label: 'View', icon: Icons.manage_accounts_rounded,
                  color: AdminColors.info, onTap: widget.onView)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// MOBILE CARDS
// ═════════════════════════════════════════════
class _UsersCards extends StatelessWidget {
  final List<AdminUserData>          users;
  final Map<String, bool>            actionLoading;
  final String Function(Timestamp?)  formatDate;
  final void Function(AdminUserData) onView;

  const _UsersCards({
    required this.users, required this.actionLoading,
    required this.formatDate, required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: users.map((user) {
      final loading = actionLoading[user.uid] ?? false;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        AdminColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: user.isFrozen
                ? AdminColors.danger.withValues(alpha: 0.3)
                : user.isAdmin
                    ? AdminColors.purple.withValues(alpha: 0.3)
                    : AdminColors.border,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _UserAvatar(photoUrl: user.photoUrl, size: 40, isFrozen: user.isFrozen),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.name, style: AdminTextStyles.titleSmall),
              Text(user.email, style: AdminTextStyles.bodySmall, overflow: TextOverflow.ellipsis),
              if (user.readableId != null)
                Text(user.readableId!,
                    style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.purple)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (user.isAdmin)  _RoleBadge(label: 'ADMIN',  color: AdminColors.purple),
              if (user.isFrozen) _RoleBadge(label: 'FROZEN', color: AdminColors.danger),
            ]),
          ]),
          const SizedBox(height: 12),
          AdminGrid(
            mobileColumns: 3, tabletColumns: 3, desktopColumns: 3,
            spacing: 8, runSpacing: 8,
            children: [
              _StatMini(label: 'BALANCE',     value: '₹${user.walletBalance.toStringAsFixed(0)}', color: AdminColors.gold),
              _StatMini(label: 'TOURNAMENTS', value: '${user.tournamentsPlayed}',                  color: AdminColors.info),
              _StatMini(label: 'WINS',        value: '${user.wins}',                              color: AdminColors.success),
            ],
          ),
          const SizedBox(height: 12),
          loading
              ? const Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.purple)))
              : SizedBox(
                  width: double.infinity,
                  child: AdminActionButton(
                    label: 'View & Manage', icon: Icons.manage_accounts_rounded,
                    color: AdminColors.info, outlined: true, onTap: () => onView(user),
                  ),
                ),
        ]),
      );
    }).toList());
  }
}

// ═════════════════════════════════════════════
// USER DETAIL DIALOG
// ═════════════════════════════════════════════
class _UserDetailDialog extends StatefulWidget {
  final AdminUserData                         user;
  final Future<void> Function(double, String) onAdjust;
  final Future<void> Function(bool)           onToggleAdmin;
  final Future<void> Function(bool)           onFreeze;
  final Future<void> Function(String)         onAddNote;

  const _UserDetailDialog({
    required this.user, required this.onAdjust,
    required this.onToggleAdmin, required this.onFreeze, required this.onAddNote,
  });

  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  AdminUserWithHistory? _detail;
  bool _loadingDetail = false;
  String? _detailError;

  final _adjustCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool  _isCredit   = true;
  bool  _adjusting  = false;
  String? _adjustError;

  final _noteCtrl  = TextEditingController();
  bool  _savingNote = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadDetail();
  }

  @override
  void dispose() {
    _tabs.dispose(); _adjustCtrl.dispose();
    _reasonCtrl.dispose(); _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() { _loadingDetail = true; _detailError = null; });
    try {
      final d = await AdminUserService.instance.getUserWithHistory(widget.user.uid);
      if (mounted) setState(() { _detail = d; _loadingDetail = false; });
    } catch (e) {
      if (mounted) setState(() { _detailError = e.toString(); _loadingDetail = false; });
    }
  }

  Future<void> _submitAdjust() async {
    final amt = double.tryParse(_adjustCtrl.text.trim());
    if (amt == null || amt <= 0) { setState(() => _adjustError = 'Enter a valid positive amount'); return; }
    if (_reasonCtrl.text.trim().isEmpty) { setState(() => _adjustError = 'Reason is required'); return; }
    setState(() { _adjusting = true; _adjustError = null; });
    try {
      await widget.onAdjust(_isCredit ? amt : -amt, _reasonCtrl.text.trim());
      if (mounted) { _adjustCtrl.clear(); _reasonCtrl.clear(); Navigator.pop(context); }
    } catch (e) {
      if (mounted) setState(() { _adjustError = e.toString(); _adjusting = false; });
    }
  }

  Future<void> _submitNote() async {
    if (_noteCtrl.text.trim().isEmpty) return;
    setState(() => _savingNote = true);
    try {
      await widget.onAddNote(_noteCtrl.text.trim());
      if (mounted) { _noteCtrl.clear(); Navigator.pop(context); }
    } catch (_) {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  String _fmtTs(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month-1]} ${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = _detail?.user ?? widget.user;
    return Dialog(
      backgroundColor: AdminColors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AdminColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
            child: Column(children: [
              Row(children: [
                _UserAvatar(photoUrl: user.photoUrl, size: 44, isFrozen: user.isFrozen),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(user.name, style: AdminTextStyles.titleLarge)),
                    if (user.isAdmin) ...[
                      _RoleBadge(label: 'ADMIN', color: AdminColors.purple),
                      const SizedBox(width: 6),
                    ],
                    if (user.isFrozen)
                      _RoleBadge(label: 'FROZEN', color: AdminColors.danger),
                  ]),
                  Text(user.email, style: AdminTextStyles.bodySmall),
                  // Readable ID row
                  if (user.readableId != null)
                    GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: user.readableId!)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:        AdminColors.purple.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border:       Border.all(color: AdminColors.purple.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(user.readableId!,
                                style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.purple)),
                            const SizedBox(width: 4),
                            const Icon(Icons.copy_rounded, size: 9, color: AdminColors.purple),
                          ]),
                        ),
                      ]),
                    ),
                  if (user.ign != null && user.ign!.isNotEmpty)
                    Text('IGN: ${user.ign} · Game UID: ${user.gameUid ?? '—'}',
                        style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.purple)),
                ])),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AdminColors.textMuted, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 16),
              // Wallet strip
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        AdminColors.gold.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: AdminColors.gold.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  Expanded(child: _WalletStat(label: 'WALLET',      value: '₹${user.walletBalance.toStringAsFixed(2)}',   color: AdminColors.gold)),
                  Expanded(child: _WalletStat(label: 'DEPOSITS',    value: '₹${user.totalDeposits.toStringAsFixed(0)}',    color: AdminColors.success)),
                  Expanded(child: _WalletStat(label: 'WITHDRAWALS', value: '₹${user.totalWithdrawals.toStringAsFixed(0)}', color: AdminColors.danger)),
                  Expanded(child: _WalletStat(label: 'WINNINGS',    value: '₹${user.totalEarnings.toStringAsFixed(0)}',    color: AdminColors.purple)),
                ]),
              ),
              const SizedBox(height: 14),
              TabBar(
                controller: _tabs,
                labelColor:            AdminColors.purple,
                unselectedLabelColor:  AdminColors.textMuted,
                indicatorColor:        AdminColors.purple,
                indicatorSize:         TabBarIndicatorSize.label,
                labelStyle:            AdminTextStyles.labelMedium.copyWith(color: AdminColors.purple),
                unselectedLabelStyle:  AdminTextStyles.labelMedium,
                tabs: const [Tab(text: 'OVERVIEW'), Tab(text: 'ADJUST BALANCE'), Tab(text: 'CONTROLS')],
              ),
            ]),
          ),
          Expanded(child: TabBarView(controller: _tabs, children: [
            _loadingDetail
                ? const Center(child: CircularProgressIndicator(color: AdminColors.purple, strokeWidth: 2))
                : _detailError != null
                    ? Center(child: Text(_detailError!, style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.danger)))
                    : _buildOverviewTab(user),
            _buildAdjustTab(),
            _buildControlsTab(user),
          ])),
        ]),
      ),
    );
  }

  Widget _buildOverviewTab(AdminUserData user) {
    final txns = _detail?.transactions ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminGrid(
          mobileColumns: 2, tabletColumns: 3, desktopColumns: 3,
          spacing: 10, runSpacing: 10,
          children: [
            _StatMini(label: 'TOURNAMENTS', value: '${user.tournamentsPlayed}', color: AdminColors.info),
            _StatMini(label: 'WINS',        value: '${user.wins}',              color: AdminColors.gold),
            _StatMini(label: 'JOINED',      value: _fmtTs(user.createdAt).split('  ').first, color: AdminColors.textMuted),
          ],
        ),
        const SizedBox(height: 20),
        Text('RECENT TRANSACTIONS', style: AdminTextStyles.labelMedium.copyWith(letterSpacing: 1.4)),
        const SizedBox(height: 10),
        if (txns.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:        AdminColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: AdminColors.border),
            ),
            child: Center(child: Text('No transactions yet', style: AdminTextStyles.bodySmall)),
          )
        else
          ...txns.map((txn) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:        AdminColors.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AdminColors.border),
            ),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _txnColor(txn.type).withValues(alpha: 0.12),
                ),
                child: Icon(_txnIcon(txn.type), color: _txnColor(txn.type), size: 14),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(txn.description,
                    style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
                Text(_fmtTs(txn.createdAt), style: AdminTextStyles.bodySmall),
              ])),
              Text('${_txnPrefix(txn.type)}₹${txn.amount.toStringAsFixed(2)}',
                  style: AdminTextStyles.titleSmall.copyWith(color: _txnColor(txn.type))),
            ]),
          )),
      ]),
    );
  }

  Widget _buildAdjustTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _isCredit = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:        _isCredit ? AdminColors.success.withValues(alpha: 0.12) : AdminColors.surfaceElevated,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                border:       Border.all(color: _isCredit ? AdminColors.success.withValues(alpha: 0.5) : AdminColors.border),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_rounded, color: _isCredit ? AdminColors.success : AdminColors.textMuted, size: 16),
                const SizedBox(width: 6),
                Text('CREDIT', style: AdminTextStyles.labelMedium.copyWith(
                    color: _isCredit ? AdminColors.success : AdminColors.textMuted)),
              ]),
            ),
          )),
          Expanded(child: GestureDetector(
            onTap: () => setState(() => _isCredit = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:        !_isCredit ? AdminColors.danger.withValues(alpha: 0.12) : AdminColors.surfaceElevated,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                border:       Border.all(color: !_isCredit ? AdminColors.danger.withValues(alpha: 0.5) : AdminColors.border),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.remove_rounded, color: !_isCredit ? AdminColors.danger : AdminColors.textMuted, size: 16),
                const SizedBox(width: 6),
                Text('DEBIT', style: AdminTextStyles.labelMedium.copyWith(
                    color: !_isCredit ? AdminColors.danger : AdminColors.textMuted)),
              ]),
            ),
          )),
        ]),
        const SizedBox(height: 16),
        Text('Amount (₹)', style: AdminTextStyles.labelMedium.copyWith(color: AdminColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.border),
          ),
          child: TextField(
            controller: _adjustCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary),
            decoration: InputDecoration(
              hintText: '0.00', hintStyle: AdminTextStyles.bodySmall,
              prefixText: '₹  ', prefixStyle: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.gold),
              border: InputBorder.none, contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Reason', style: AdminTextStyles.labelMedium.copyWith(color: AdminColors.textSecondary)),
          const SizedBox(width: 6),
          Text('*', style: AdminTextStyles.labelMedium.copyWith(color: AdminColors.danger)),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _adjustError != null ? AdminColors.danger.withValues(alpha: 0.6) : AdminColors.border),
          ),
          child: TextField(
            controller: _reasonCtrl, maxLines: 2,
            style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Reason for adjustment (visible in audit log)', hintStyle: AdminTextStyles.bodySmall,
              border: InputBorder.none, contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        if (_adjustError != null) ...[
          const SizedBox(height: 6),
          Text(_adjustError!, style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.danger)),
        ],
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: AdminActionButton(
          label: _adjusting ? 'Processing…' : '${_isCredit ? 'Credit' : 'Debit'} Wallet',
          icon:  _isCredit ? Icons.add_rounded : Icons.remove_rounded,
          color: _isCredit ? AdminColors.success : AdminColors.danger,
          onTap: _adjusting ? null : _submitAdjust,
        )),
      ]),
    );
  }

  Widget _buildControlsTab(AdminUserData user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ControlCard(
          title:    'Admin Privileges',
          subtitle: user.isAdmin ? '${user.name} has admin access' : '${user.name} is a regular player',
          icon: Icons.shield_rounded, color: AdminColors.purple,
          trailing: Switch(
            value: user.isAdmin, activeColor: AdminColors.purple,
            onChanged: (v) { Navigator.pop(context); widget.onToggleAdmin(v); },
          ),
        ),
        const SizedBox(height: 12),
        _ControlCard(
          title:    'Account Freeze',
          subtitle: user.isFrozen ? 'Account is frozen — user cannot log in' : 'Account is active',
          icon: Icons.lock_rounded, color: AdminColors.danger,
          trailing: Switch(
            value: user.isFrozen, activeColor: AdminColors.danger,
            onChanged: (v) { Navigator.pop(context); widget.onFreeze(v); },
          ),
        ),
        const SizedBox(height: 20),
        Text('ADMIN NOTE', style: AdminTextStyles.labelMedium.copyWith(letterSpacing: 1.4)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.border),
          ),
          child: TextField(
            controller: _noteCtrl, maxLines: 3,
            style: AdminTextStyles.bodyMedium.copyWith(color: AdminColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Internal note about this player…', hintStyle: AdminTextStyles.bodySmall,
              border: InputBorder.none, contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: AdminActionButton(
          label: _savingNote ? 'Saving…' : 'Save Note',
          icon: Icons.save_rounded, color: AdminColors.info, outlined: true,
          onTap: _savingNote ? null : _submitNote,
        )),
      ]),
    );
  }

  Color    _txnColor(String type) => switch (type) {
    'deposit'          => AdminColors.success,
    'withdrawal'       => AdminColors.danger,
    'refund'           => AdminColors.warning,
    'tournament_entry' => AdminColors.info,
    'winnings'         => AdminColors.gold,
    _                  => AdminColors.textMuted,
  };
  IconData _txnIcon(String type) => switch (type) {
    'deposit'          => Icons.add_circle_rounded,
    'withdrawal'       => Icons.remove_circle_rounded,
    'refund'           => Icons.replay_rounded,
    'tournament_entry' => Icons.emoji_events_rounded,
    'winnings'         => Icons.military_tech_rounded,
    _                  => Icons.swap_horiz_rounded,
  };
  String   _txnPrefix(String type) => switch (type) {
    'deposit' || 'winnings' || 'refund' => '+',
    'withdrawal' => '-',
    _ => '',
  };
}

// ─────────────────────────────────────────────
// SMALL WIDGETS
// ─────────────────────────────────────────────
class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double  size;
  final bool    isFrozen;
  const _UserAvatar({this.photoUrl, required this.size, this.isFrozen = false});

  @override
  Widget build(BuildContext context) => Stack(children: [
    Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle, color: AdminColors.surfaceElevated,
        border: Border.all(
          color: isFrozen ? AdminColors.danger.withValues(alpha: 0.6) : AdminColors.border,
          width: isFrozen ? 2 : 1,
        ),
      ),
      child: photoUrl != null
          ? ClipOval(child: Image.network(photoUrl!, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(Icons.person_rounded, color: AdminColors.textMuted, size: size * 0.5)))
          : Icon(Icons.person_rounded, color: AdminColors.textMuted, size: size * 0.5),
    ),
    if (isFrozen)
      Positioned(right: 0, bottom: 0, child: Container(
        width: size * 0.38, height: size * 0.38,
        decoration: BoxDecoration(
          color: AdminColors.danger, shape: BoxShape.circle,
          border: Border.all(color: AdminColors.surfaceCard, width: 1.5),
        ),
        child: Icon(Icons.lock_rounded, color: Colors.white, size: size * 0.22),
      )),
  ]);
}

class _RoleBadge extends StatelessWidget {
  final String label; final Color color;
  const _RoleBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8)),
  );
}

class _StatMini extends StatelessWidget {
  final String label, value; final Color color;
  const _StatMini({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted, fontSize: 8)),
      const SizedBox(height: 2),
      Text(value, style: AdminTextStyles.titleSmall.copyWith(color: color), overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _WalletStat extends StatelessWidget {
  final String label, value; final Color color;
  const _WalletStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: AdminTextStyles.titleSmall.copyWith(color: color)),
    Text(label, style: AdminTextStyles.labelSmall.copyWith(fontSize: 8)),
  ]);
}

class _ControlCard extends StatelessWidget {
  final String title, subtitle; final IconData icon; final Color color; final Widget trailing;
  const _ControlCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.trailing});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AdminColors.border),
    ),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AdminTextStyles.titleSmall),
        Text(subtitle, style: AdminTextStyles.bodySmall),
      ])),
      trailing,
    ]),
  );
}

class _TinyButton extends StatefulWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _TinyButton({required this.label, required this.icon, required this.color, required this.onTap});
  @override State<_TinyButton> createState() => _TinyButtonState();
}
class _TinyButtonState extends State<_TinyButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:        widget.color.withValues(alpha: _hovered ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: widget.color.withValues(alpha: _hovered ? 0.7 : 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, size: 12, color: widget.color),
          const SizedBox(width: 5),
          Text(widget.label, style: AdminTextStyles.labelSmall.copyWith(color: widget.color)),
        ]),
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label, value, group; final Color color; final void Function(String) onTap;
  const _FilterChip({required this.label, required this.value, required this.group, required this.color, required this.onTap});
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
          border:       Border.all(color: active ? color.withValues(alpha: 0.5) : AdminColors.border),
        ),
        child: Text(label, style: AdminTextStyles.labelSmall.copyWith(
            color: active ? color : AdminColors.textMuted, letterSpacing: 0.8)),
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final String value; final void Function(String) onChanged;
  const _SortDropdown({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: AdminColors.surfaceElevated, borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AdminColors.border),
    ),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, dropdownColor: AdminColors.surfaceElevated,
      style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.purple),
      icon:  const Icon(Icons.keyboard_arrow_down_rounded, color: AdminColors.purple, size: 16),
      items: const [
        DropdownMenuItem(value: 'newest',       child: Text('NEWEST')),
        DropdownMenuItem(value: 'oldest',        child: Text('OLDEST')),
        DropdownMenuItem(value: 'balance_high',  child: Text('BAL HIGH')),
        DropdownMenuItem(value: 'balance_low',   child: Text('BAL LOW')),
        DropdownMenuItem(value: 'earnings_high', child: Text('EARNINGS')),
      ],
      onChanged: (v) { if (v != null) onChanged(v); },
    )),
  );
}

class _ShimmerTable extends StatefulWidget {
  const _ShimmerTable();
  @override State<_ShimmerTable> createState() => _ShimmerTableState();
}
class _ShimmerTableState extends State<_ShimmerTable> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Column(children: List.generate(6, (i) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AdminDecorations.tableRow(isEven: i.isEven).color, borderRadius: BorderRadius.circular(4)),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AdminColors.surfaceElevated.withValues(alpha: 0.4 + 0.4 * _anim.value),
        )),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 10, width: 120, color: AdminColors.surfaceElevated.withValues(alpha: 0.4 + 0.4 * _anim.value)),
          const SizedBox(height: 5),
          Container(height: 8, width: 160, color: AdminColors.surfaceElevated.withValues(alpha: 0.2 + 0.2 * _anim.value)),
        ])),
        Container(height: 22, width: 60, decoration: BoxDecoration(
          color: AdminColors.surfaceElevated.withValues(alpha: 0.3 + 0.3 * _anim.value),
          borderRadius: BorderRadius.circular(6),
        )),
      ]),
    ))),
  );
}

class _EmptyState extends StatelessWidget {
  final bool hasFilter; final VoidCallback onClear;
  const _EmptyState({required this.hasFilter, required this.onClear});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: AdminColors.surfaceElevated,
          border: Border.all(color: AdminColors.border),
        ),
        child: Icon(hasFilter ? Icons.search_off_rounded : Icons.people_outline_rounded,
            color: AdminColors.textMuted, size: 28),
      ),
      const SizedBox(height: 16),
      Text(hasFilter ? 'No matching users' : 'No users yet', style: AdminTextStyles.titleSmall),
      const SizedBox(height: 6),
      Text(hasFilter ? 'Try adjusting search or filters' : 'Users will appear here as they register',
          style: AdminTextStyles.bodySmall, textAlign: TextAlign.center),
      if (hasFilter) ...[
        const SizedBox(height: 16),
        AdminActionButton(label: 'Clear Filters', icon: Icons.filter_alt_off_rounded,
            color: AdminColors.purple, outlined: true, onTap: onClear),
      ],
    ]),
  ));
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AdminColors.danger.withValues(alpha: 0.08),
          border: Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.error_outline_rounded, color: AdminColors.danger, size: 28),
      ),
      const SizedBox(height: 16),
      Text('Failed to load users', style: AdminTextStyles.titleSmall),
      const SizedBox(height: 6),
      Text(message, style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.danger.withValues(alpha: 0.7)),
          textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
    ]),
  ));
}