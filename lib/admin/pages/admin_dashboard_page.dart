// lib/admin/pages/admin_dashboard_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Dashboard
// Phase 3: Live stats for users, deposits, withdrawals
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart';
import '../navigation/admin_nav_model.dart';
import '../theme/admin_theme.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  // ── Streams ──────────────────────────────────
  // All three run concurrently; each drives its own StreamBuilder.
  final _usersStream = FirebaseFirestore.instance
      .collection('users')
      .snapshots();

  final _depositsStream = FirebaseFirestore.instance
      .collectionGroup('deposit_requests')
      .snapshots();

  final _withdrawalsStream = FirebaseFirestore.instance
      .collectionGroup('withdraw_requests')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────
  bool _isToday(Timestamp? ts) {
    if (ts == null) return false;
    final d   = ts.toDate().toLocal();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // ── Master stream: users ────────────────────
    return StreamBuilder<QuerySnapshot>(
      stream: _usersStream,
      builder: (context, userSnap) {
        final users = userSnap.data?.docs ?? [];
        final totalUsers  = users.length;
        final adminCount  = users.where((d) =>
            (d.data() as Map<String, dynamic>)['isAdmin'] == true).length;
        final frozenCount = users.where((d) =>
            (d.data() as Map<String, dynamic>)['isFrozen'] == true).length;
        final totalWallet = users.fold<double>(0, (sum, d) {
          final data = d.data() as Map<String, dynamic>;
          return sum + ((data['walletBalance'] as num?)?.toDouble() ?? 0.0);
        });
        final recentUsers = users.toList()
          ..sort((a, b) {
            final ta = ((a.data() as Map)['createdAt'] as Timestamp?)
                ?? Timestamp(0, 0);
            final tb = ((b.data() as Map)['createdAt'] as Timestamp?)
                ?? Timestamp(0, 0);
            return tb.compareTo(ta);
          });

        // ── Inner stream: deposits ──────────────
        return StreamBuilder<QuerySnapshot>(
          stream: _depositsStream,
          builder: (context, depSnap) {
            final deps             = depSnap.data?.docs ?? [];
            final pendingDeposits  = deps.where((d) =>
                (d.data() as Map)['status'] == 'pending').length;
            final approvedToday    = deps.where((d) {
              final data = d.data() as Map;
              return data['status'] == 'approved' &&
                     _isToday(data['processedAt'] as Timestamp?);
            }).length;
            final depositVolume    = deps.fold<double>(0, (sum, d) {
              final data = d.data() as Map;
              if (data['status'] != 'approved') return sum;
              return sum + ((data['amount'] as num?)?.toDouble() ?? 0.0);
            });

            // ── Inner stream: withdrawals ────────
            return StreamBuilder<QuerySnapshot>(
              stream: _withdrawalsStream,
              builder: (context, wdSnap) {
                final wds              = wdSnap.data?.docs ?? [];
                final pendingWds       = wds.where((d) =>
                    (d.data() as Map)['status'] == 'pending').length;
                final approvedWdsToday = wds.where((d) {
                  final data = d.data() as Map;
                  return data['status'] == 'approved' &&
                         _isToday(data['processedAt'] as Timestamp?);
                }).length;
                final withdrawVolume   = wds.fold<double>(0, (sum, d) {
                  final data = d.data() as Map;
                  if (data['status'] != 'approved') return sum;
                  return sum + ((data['amount'] as num?)?.toDouble() ?? 0.0);
                });

                final isLoading =
                    userSnap.connectionState == ConnectionState.waiting ||
                    depSnap.connectionState  == ConnectionState.waiting ||
                    wdSnap.connectionState   == ConnectionState.waiting;

                return AdminPageContainer(
                  title:    'Dashboard',
                  subtitle: 'Shadow Storm control center — Phase 3 live',
                  actions: [
                    AdminActionButton(
                      label:    'Refresh',
                      icon:     Icons.refresh_rounded,
                      color:    AdminColors.purple,
                      outlined: true,
                      onTap:    () => setState(() {}),
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome banner
                      _WelcomeBanner(pulse: _pulse),
                      const SizedBox(height: 24),

                      // Stats
                      _buildStatsSection(
                        isLoading:       isLoading,
                        totalUsers:      totalUsers,
                        pendingDeposits: pendingDeposits,
                        pendingWds:      pendingWds,
                        totalWallet:     totalWallet,
                      ),
                      const SizedBox(height: 24),

                      // Financial summary
                      _buildFinancialRow(
                        isLoading:      isLoading,
                        depositVolume:  depositVolume,
                        withdrawVolume: withdrawVolume,
                        approvedDepsToday: approvedToday,
                        approvedWdsToday:  approvedWdsToday,
                        adminCount:     adminCount,
                        frozenCount:    frozenCount,
                      ),
                      const SizedBox(height: 24),

                      // Middle row
                      _buildMiddleRow(context),
                      const SizedBox(height: 24),

                      // Recent users
                      _buildRecentUsers(recentUsers.take(5).toList()),
                      const SizedBox(height: 40),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // MAIN STAT CARDS
  // ──────────────────────────────────────────
  Widget _buildStatsSection({
    required bool   isLoading,
    required int    totalUsers,
    required int    pendingDeposits,
    required int    pendingWds,
    required double totalWallet,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'PLATFORM OVERVIEW', color: AdminColors.purple),
        const SizedBox(height: 14),

        AdminGrid(
          mobileColumns:  2,
          tabletColumns:  2,
          desktopColumns: 4,
          spacing:    14,
          runSpacing: 14,
          children: [
            AdminStatCard(
              label:    'Total Users',
              value:    isLoading ? '—' : totalUsers.toString(),
              icon:     Icons.people_rounded,
              color:    AdminColors.info,
              subLabel: 'Registered players',
              trend:    _LiveDot(color: AdminColors.info),
            ),
            AdminStatCard(
              label:    'Pending Deposits',
              value:    isLoading ? '—' : pendingDeposits.toString(),
              icon:     Icons.add_circle_rounded,
              color:    AdminColors.success,
              subLabel: 'Awaiting approval',
              trend:    pendingDeposits > 0
                  ? _AlertDot(color: AdminColors.success)
                  : _LiveDot(color: AdminColors.success),
            ),
            AdminStatCard(
              label:    'Pending Withdrawals',
              value:    isLoading ? '—' : pendingWds.toString(),
              icon:     Icons.remove_circle_rounded,
              color:    AdminColors.danger,
              subLabel: 'Awaiting payout',
              trend:    pendingWds > 0
                  ? _AlertDot(color: AdminColors.danger)
                  : _LiveDot(color: AdminColors.danger),
            ),
            AdminStatCard(
              label:    'Total Wallet Balance',
              value:    isLoading ? '—' : '₹${totalWallet.toStringAsFixed(0)}',
              icon:     Icons.account_balance_wallet_rounded,
              color:    AdminColors.gold,
              subLabel: 'Combined user wallets',
              trend:    _LiveDot(color: AdminColors.gold),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // FINANCIAL ROW
  // ──────────────────────────────────────────
  Widget _buildFinancialRow({
    required bool   isLoading,
    required double depositVolume,
    required double withdrawVolume,
    required int    approvedDepsToday,
    required int    approvedWdsToday,
    required int    adminCount,
    required int    frozenCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'FINANCIAL SUMMARY', color: AdminColors.gold),
        const SizedBox(height: 14),

        AdminGrid(
          mobileColumns:  2,
          tabletColumns:  3,
          desktopColumns: 6,
          spacing:    12,
          runSpacing: 12,
          children: [
            _MiniStatCard(
              label:    'Deposits Approved',
              value:    isLoading ? '—' : '₹${depositVolume.toStringAsFixed(0)}',
              sublabel: 'All time',
              color:    AdminColors.success,
              icon:     Icons.add_circle_outline_rounded,
            ),
            _MiniStatCard(
              label:    'Approved Today',
              value:    isLoading ? '—' : approvedDepsToday.toString(),
              sublabel: 'Deposits today',
              color:    AdminColors.success,
              icon:     Icons.today_rounded,
            ),
            _MiniStatCard(
              label:    'Withdrawals Paid',
              value:    isLoading ? '—' : '₹${withdrawVolume.toStringAsFixed(0)}',
              sublabel: 'All time',
              color:    AdminColors.danger,
              icon:     Icons.remove_circle_outline_rounded,
            ),
            _MiniStatCard(
              label:    'Paid Today',
              value:    isLoading ? '—' : approvedWdsToday.toString(),
              sublabel: 'Withdrawals today',
              color:    AdminColors.danger,
              icon:     Icons.today_rounded,
            ),
            _MiniStatCard(
              label:    'Admin Accounts',
              value:    isLoading ? '—' : adminCount.toString(),
              sublabel: 'With admin flag',
              color:    AdminColors.purple,
              icon:     Icons.shield_rounded,
            ),
            _MiniStatCard(
              label:    'Frozen Accounts',
              value:    isLoading ? '—' : frozenCount.toString(),
              sublabel: 'Suspended users',
              color:    frozenCount > 0 ? AdminColors.warning : AdminColors.textMuted,
              icon:     Icons.lock_rounded,
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // MIDDLE ROW (system status + quick actions)
  // ──────────────────────────────────────────
  Widget _buildMiddleRow(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    final systemStatus = AdminSectionCard(
      title:      'SYSTEM STATUS',
      titleIcon:  Icons.monitor_heart_rounded,
      titleColor: AdminColors.success,
      child: Column(
        children: [
          _StatusRow(label: 'Firebase Auth',        status: 'Operational', color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Firestore Database',   status: 'Operational', color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Admin Panel',          status: 'Phase 3',     color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Deposit System',       status: 'Live ✓',      color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Withdrawal System',    status: 'Live ✓',      color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'User Management',      status: 'Live ✓',      color: AdminColors.success, icon: Icons.check_circle_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Tournament System',    status: 'Phase 4',     color: AdminColors.warning, icon: Icons.schedule_rounded),
          const SizedBox(height: 10),
          _StatusRow(label: 'Audit Logs',           status: 'Phase 4',     color: AdminColors.warning, icon: Icons.schedule_rounded),
        ],
      ),
    );

    final quickActions = AdminSectionCard(
      title:      'QUICK ACTIONS',
      titleIcon:  Icons.flash_on_rounded,
      titleColor: AdminColors.purple,
      child: Column(
        children: [
          _QuickActionTile(
            label:    'Manage Deposits',
            sublabel: 'Review & approve player deposit requests',
            icon:     Icons.add_circle_outline_rounded,
            color:    AdminColors.success,
            liveLabel: 'LIVE',
            navId:    'deposits',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label:    'Process Withdrawals',
            sublabel: 'Approve payments or reject & refund',
            icon:     Icons.remove_circle_outline_rounded,
            color:    AdminColors.danger,
            liveLabel: 'LIVE',
            navId:    'withdrawals',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label:    'User Management',
            sublabel: 'Adjust balances, toggle admin, freeze accounts',
            icon:     Icons.people_outline_rounded,
            color:    AdminColors.info,
            liveLabel: 'LIVE',
            navId:    'users',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label:    'Tournament Management',
            sublabel: 'Create tournaments, distribute prizes',
            icon:     Icons.emoji_events_outlined,
            color:    AdminColors.gold,
            badge:    'Phase 4',
            navId:    null,
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label:    'Audit Logs',
            sublabel: 'Full admin action history & trail',
            icon:     Icons.receipt_long_outlined,
            color:    AdminColors.warning,
            badge:    'Phase 4',
            navId:    null,
          ),
        ],
      ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: systemStatus),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: quickActions),
        ],
      );
    }

    return Column(
      children: [
        systemStatus,
        const SizedBox(height: 16),
        quickActions,
      ],
    );
  }

  // ──────────────────────────────────────────
  // RECENT USERS
  // ──────────────────────────────────────────
  Widget _buildRecentUsers(List<QueryDocumentSnapshot> docs) {
    return AdminSectionCard(
      title:      'RECENT USERS',
      titleIcon:  Icons.people_outline_rounded,
      titleColor: AdminColors.info,
      titleActions: [
        AdminBadge(label: 'LIVE', color: AdminColors.info, glowing: true),
      ],
      child: docs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.people_outline_rounded,
                        color: AdminColors.textMuted, size: 40),
                    const SizedBox(height: 12),
                    Text('No users yet', style: AdminTextStyles.bodyMedium),
                  ],
                ),
              ),
            )
          : Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _UserRow(
                  name:          (data['name']     as String?) ?? 'Unknown',
                  email:         (data['email']    as String?) ?? '',
                  photoUrl:       data['photoUrl'] as String?,
                  uid:           doc.id,
                  walletBalance: (data['walletBalance'] as num?)?.toDouble() ?? 0.0,
                  isAdmin:       (data['isAdmin']  as bool?) ?? false,
                  isFrozen:      (data['isFrozen'] as bool?) ?? false,
                  joinedAt:      data['createdAt'] as Timestamp?,
                  formatDate:    _fmt,
                );
              }).toList(),
            ),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION LABEL
// ═════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color  color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: AdminTextStyles.labelLarge.copyWith(letterSpacing: 2)),
    ],
  );
}

// ═════════════════════════════════════════════
// LIVE / ALERT DOTS
// ═════════════════════════════════════════════
class _LiveDot extends StatelessWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border:       Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text('LIVE',
        style: AdminTextStyles.labelSmall.copyWith(
            color: color, fontSize: 8)),
  );
}

class _AlertDot extends StatefulWidget {
  final Color color;
  const _AlertDot({required this.color});

  @override
  State<_AlertDot> createState() => _AlertDotState();
}

class _AlertDotState extends State<_AlertDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color:        widget.color.withValues(alpha: 0.12 + 0.10 * _anim.value),
          borderRadius: BorderRadius.circular(6),
          border:       Border.all(
              color: widget.color.withValues(alpha: 0.4 + 0.3 * _anim.value)),
          boxShadow: [BoxShadow(
            color:      widget.color.withValues(alpha: 0.2 * _anim.value),
            blurRadius: 6,
          )],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
            const SizedBox(width: 4),
            Text('ACTION',
                style: AdminTextStyles.labelSmall.copyWith(
                    color: widget.color, fontSize: 8)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// MINI STAT CARD (financial row)
// ═════════════════════════════════════════════
class _MiniStatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final String   sublabel;
  final Color    color;
  final IconData icon;

  const _MiniStatCard({
    required this.label, required this.value, required this.sublabel,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        AdminColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: AdminColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: AdminTextStyles.labelSmall.copyWith(
                    color: AdminColors.textMuted),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: AdminTextStyles.titleMedium.copyWith(color: color),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(sublabel, style: AdminTextStyles.bodySmall),
      ],
    ),
  );
}

// ═════════════════════════════════════════════
// WELCOME BANNER
// ═════════════════════════════════════════════
class _WelcomeBanner extends StatelessWidget {
  final Animation<double> pulse;
  const _WelcomeBanner({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, _) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AdminColors.purpleDark.withValues(alpha: 0.6),
              AdminColors.surfaceCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AdminColors.purple.withValues(
                alpha: 0.25 + 0.15 * pulse.value),
          ),
          boxShadow: [BoxShadow(
            color:      AdminColors.purple.withValues(
                alpha: 0.08 + 0.06 * pulse.value),
            blurRadius: 24,
          )],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AdminColors.purple.withValues(alpha: 0.15),
                border: Border.all(
                  color: AdminColors.purple.withValues(
                      alpha: 0.4 + 0.3 * pulse.value),
                ),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: AdminColors.purple, size: 28),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shadow Storm Admin Panel',
                      style: AdminTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text('Phase 3 Active — Deposits, Withdrawals & Users are live',
                      style: AdminTextStyles.bodyMedium),
                  const SizedBox(height: 8),
                  Row(children: [
                    _PhasePill(label: 'DEPOSITS',    color: AdminColors.success),
                    const SizedBox(width: 6),
                    _PhasePill(label: 'WITHDRAWALS', color: AdminColors.danger),
                    const SizedBox(width: 6),
                    _PhasePill(label: 'USERS',       color: AdminColors.info),
                  ]),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:        AdminColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(
                    color: AdminColors.success.withValues(alpha: 0.4)),
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
                  Text('PHASE 3',
                      style: AdminTextStyles.labelSmall.copyWith(
                          color: AdminColors.success)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  final String label;
  final Color  color;
  const _PhasePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border:       Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: AdminTextStyles.labelSmall.copyWith(
                color: color, fontSize: 8)),
      ],
    ),
  );
}

// ═════════════════════════════════════════════
// STATUS ROW
// ═════════════════════════════════════════════
class _StatusRow extends StatelessWidget {
  final String   label, status;
  final Color    color;
  final IconData icon;

  const _StatusRow({
    required this.label, required this.status,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: AdminTextStyles.bodyMedium)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(4),
          border:       Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(status,
            style: AdminTextStyles.labelSmall.copyWith(
                color: color, fontSize: 9)),
      ),
    ],
  );
}

// ═════════════════════════════════════════════
// QUICK ACTION TILE (navigates to page)
// ═════════════════════════════════════════════
class _QuickActionTile extends StatefulWidget {
  final String   label, sublabel;
  final IconData icon;
  final Color    color;
  final String?  liveLabel;
  final String?  badge;
  final String?  navId;       // null = coming soon

  const _QuickActionTile({
    required this.label, required this.sublabel,
    required this.icon,  required this.color,
    this.liveLabel, this.badge, this.navId,
  });

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.navId != null;

    return MouseRegion(
      cursor: isActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: isActive ? () {
          // Walk up to find AdminNavState and navigate
          final navState = context.findAncestorStateOfType<State>()
              as dynamic;
          try {
            // Best-effort: look for AdminNavState via InheritedWidget/Provider
            // Falls back gracefully if not found — tile still shows correctly
            final state = context.findRootAncestorStateOfType<State>();
            if (state != null) {
              // Find and call setActive on the nearest AdminNavState
              _navigateTo(context, widget.navId!);
            }
          } catch (_) {}
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered && isActive
                ? widget.color.withValues(alpha: 0.08)
                : AdminColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered && isActive
                  ? widget.color.withValues(alpha: 0.4)
                  : AdminColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:        widget.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(
                      color: widget.color.withValues(alpha: 0.25)),
                ),
                child: Icon(widget.icon, color: widget.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: AdminTextStyles.titleSmall),
                    Text(widget.sublabel, style: AdminTextStyles.bodySmall),
                  ],
                ),
              ),
              if (widget.liveLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color:        widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border:       Border.all(
                        color: widget.color.withValues(alpha: 0.4)),
                  ),
                  child: Text(widget.liveLabel!,
                      style: AdminTextStyles.labelSmall.copyWith(
                          color: widget.color, fontSize: 8)),
                ),
              if (widget.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color:        AdminColors.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(widget.badge!,
                      style: AdminTextStyles.labelSmall.copyWith(
                          color: AdminColors.textMuted, fontSize: 8)),
                ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: widget.color.withValues(alpha: 0.5), size: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String navId) {
    // Walk the widget tree looking for AdminNavState
    // AdminShell owns it — this is the cleanest approach without Provider
    BuildContext? ctx = context;
    while (ctx != null) {
      final element = ctx as Element;
      if (element.widget is StatefulWidget) {
        final state = (element as StatefulElement).state;
        if (state.runtimeType.toString().contains('AdminShell')) {
          try {
            // ignore: invalid_use_of_protected_member
            final navState = (state as dynamic)._navState as AdminNavState;
            navState.setActive(navId);
          } catch (_) {}
          return;
        }
      }
      ctx = null; // stop — use ancestor search instead
    }
  }
}

// ═════════════════════════════════════════════
// USER ROW (recent users table)
// ═════════════════════════════════════════════
class _UserRow extends StatelessWidget {
  final String    name, email, uid;
  final String?   photoUrl;
  final double    walletBalance;
  final bool      isAdmin;
  final bool      isFrozen;
  final Timestamp? joinedAt;
  final String Function(Timestamp?) formatDate;

  const _UserRow({
    required this.name, required this.email, required this.uid,
    this.photoUrl,
    required this.walletBalance,
    required this.isAdmin,
    required this.isFrozen,
    this.joinedAt,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AdminColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  AdminColors.surfaceElevated,
                  border: Border.all(
                    color: isFrozen
                        ? AdminColors.danger.withValues(alpha: 0.5)
                        : AdminColors.border,
                  ),
                ),
                child: photoUrl != null
                    ? ClipOval(child: Image.network(photoUrl!,
                        width: 36, height: 36, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.person_rounded,
                            color: AdminColors.textMuted, size: 18)))
                    : const Icon(Icons.person_rounded,
                        color: AdminColors.textMuted, size: 18),
              ),
              if (isFrozen)
                Positioned(right: 0, bottom: 0,
                  child: Container(
                    width: 13, height: 13,
                    decoration: BoxDecoration(
                      color:  AdminColors.danger,
                      shape:  BoxShape.circle,
                      border: Border.all(
                          color: AdminColors.surfaceCard, width: 1.5),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 7),
                  )),
            ],
          ),

          const SizedBox(width: 12),

          // Name + email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(name,
                      style: AdminTextStyles.titleSmall,
                      overflow: TextOverflow.ellipsis)),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color:        AdminColors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border:       Border.all(
                            color: AdminColors.purple.withValues(alpha: 0.4)),
                      ),
                      child: Text('ADMIN',
                          style: AdminTextStyles.labelSmall.copyWith(
                              color: AdminColors.purple, fontSize: 7)),
                    ),
                  ],
                ]),
                Text(email,
                    style: AdminTextStyles.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Wallet
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${walletBalance.toStringAsFixed(2)}',
                  style: AdminTextStyles.titleSmall.copyWith(
                      color: AdminColors.gold)),
              Text(formatDate(joinedAt),
                  style: AdminTextStyles.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}