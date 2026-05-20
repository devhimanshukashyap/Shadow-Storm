// lib/admin/pages/admin_dashboard_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Dashboard
// Phase 5: Platform monitoring center, alerts, recent activity feed
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart' hide AdminGrid;
import '../navigation/admin_nav_model.dart';
import '../theme/admin_theme.dart';
import '../services/admin_logs_service.dart';
import '../services/admin_settings_service.dart';
import '../widgets/admin_components.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // ── Streams ──────────────────────────────────
  final _usersStream = FirebaseFirestore.instance
      .collection('users')
      .snapshots();

  final _depositsStream = FirebaseFirestore.instance
      .collectionGroup('deposit_requests')
      .snapshots();

  final _withdrawalsStream = FirebaseFirestore.instance
      .collectionGroup('withdraw_requests')
      .snapshots();

  final _tournamentsStream = FirebaseFirestore.instance
      .collection('tournaments')
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

  bool _isToday(Timestamp? ts) {
    if (ts == null) return false;
    final d = ts.toDate().toLocal();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $h:$m';
  }

  String _relative(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate().toLocal());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _logActionColor(String action) {
    if (action.contains('approved')) return AdminColors.success;
    if (action.contains('rejected')) return AdminColors.danger;
    if (action.contains('frozen')) return AdminColors.warning;
    if (action.contains('tournament')) return AdminColors.gold;
    if (action.contains('prize')) return AdminColors.success;
    if (action.contains('admin_')) return AdminColors.purple;
    if (action.contains('maintenance')) return AdminColors.danger;
    if (action.contains('suspicious')) return AdminColors.danger;
    return AdminColors.info;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _usersStream,
      builder: (context, userSnap) {
        final users = userSnap.data?.docs ?? [];
        final totalUsers = users.length;
        final adminCount = users
            .where((d) => (d.data() as Map)['isAdmin'] == true)
            .length;
        final frozenCount = users
            .where((d) => (d.data() as Map)['isFrozen'] == true)
            .length;
        final totalWallet = users.fold<double>(
          0,
          (s, d) =>
              s +
              (((d.data() as Map)['walletBalance'] as num?)?.toDouble() ?? 0.0),
        );
        final recentUsers = users.toList()
          ..sort((a, b) {
            final ta =
                ((a.data() as Map)['createdAt'] as Timestamp?) ??
                Timestamp(0, 0);
            final tb =
                ((b.data() as Map)['createdAt'] as Timestamp?) ??
                Timestamp(0, 0);
            return tb.compareTo(ta);
          });

        return StreamBuilder<QuerySnapshot>(
          stream: _depositsStream,
          builder: (context, depSnap) {
            final deps = depSnap.data?.docs ?? [];
            final pendingDeposits = deps
                .where((d) => (d.data() as Map)['status'] == 'pending')
                .length;
            final depositVolume = deps.fold<double>(0, (s, d) {
              final data = d.data() as Map;
              if (data['status'] != 'approved') return s;
              return s + ((data['amount'] as num?)?.toDouble() ?? 0.0);
            });
            final approvedToday = deps.where((d) {
              final data = d.data() as Map;
              return data['status'] == 'approved' &&
                  _isToday(data['processedAt'] as Timestamp?);
            }).length;

            return StreamBuilder<QuerySnapshot>(
              stream: _withdrawalsStream,
              builder: (context, wdSnap) {
                final wds = wdSnap.data?.docs ?? [];
                final pendingWds = wds
                    .where((d) => (d.data() as Map)['status'] == 'pending')
                    .length;
                final withdrawVolume = wds.fold<double>(0, (s, d) {
                  final data = d.data() as Map;
                  if (data['status'] != 'approved') return s;
                  return s + ((data['amount'] as num?)?.toDouble() ?? 0.0);
                });
                final approvedWdsToday = wds.where((d) {
                  final data = d.data() as Map;
                  return data['status'] == 'approved' &&
                      _isToday(data['processedAt'] as Timestamp?);
                }).length;

                return StreamBuilder<QuerySnapshot>(
                  stream: _tournamentsStream,
                  builder: (context, tSnap) {
                    final tournaments = tSnap.data?.docs ?? [];
                    final liveTournaments = tournaments
                        .where((d) => (d.data() as Map)['status'] == 'live')
                        .length;
                    final pendingCredentials = tournaments.where((d) {
                      final data = d.data() as Map;
                      return data['status'] == 'live' &&
                          (data['roomId'] == null ||
                              (data['roomId'] as String).isEmpty);
                    }).length;
                    final noResults = tournaments.where((d) {
                      final data = d.data() as Map;
                      return data['status'] == 'live' &&
                          (data['prizesDistributed'] as bool?) != true;
                    }).length;
                    final totalDistributed = tournaments.fold<double>(0, (
                      s,
                      d,
                    ) {
                      final data = d.data() as Map;
                      if ((data['prizesDistributed'] as bool?) != true)
                        return s;
                      return s +
                          ((data['prizePool'] as num?)?.toDouble() ?? 0.0);
                    });

                    final isLoading =
                        userSnap.connectionState == ConnectionState.waiting ||
                        depSnap.connectionState == ConnectionState.waiting ||
                        wdSnap.connectionState == ConnectionState.waiting;

                    return AdminPageContainer(
                      title: 'Dashboard',
                      subtitle: 'Shadow Storm — Phase 5 Platform Monitoring',
                      actions: [
                        AdminActionButton(
                          label: 'Refresh',
                          icon: Icons.refresh_rounded,
                          color: AdminColors.purple,
                          outlined: true,
                          onTap: () => setState(() {}),
                        ),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Welcome banner
                          _WelcomeBanner(pulse: _pulse),
                          const SizedBox(height: 16),

                          // Settings-based alerts
                          StreamBuilder<AdminSettings>(
                            stream: AdminSettingsService.instance
                                .settingsStream(),
                            builder: (context, settingsSnap) {
                              final s = settingsSnap.data;
                              if (s == null) return const SizedBox.shrink();
                              return Column(
                                children: [
                                  if (s.maintenanceMode) ...[
                                    AdminAlertBanner(
                                      message:
                                          '🔴 MAINTENANCE MODE ACTIVE — All player actions are blocked.',
                                      color: AdminColors.danger,
                                      icon: Icons.construction_rounded,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (s.walletFrozen) ...[
                                    AdminAlertBanner(
                                      message:
                                          '❄️ WALLETS FROZEN — All deposit/withdrawal processing is paused.',
                                      color: AdminColors.warning,
                                      icon: Icons.ac_unit_rounded,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              );
                            },
                          ),

                          // Platform alerts
                          _buildPlatformAlerts(
                            pendingDeposits: pendingDeposits,
                            pendingWds: pendingWds,
                            pendingCredentials: pendingCredentials,
                            liveNoResults: noResults,
                          ),
                          const SizedBox(height: 16),

                          // Platform health grid
                          _buildHealthGrid(
                            isLoading: isLoading,
                            totalUsers: totalUsers,
                            liveTournaments: liveTournaments,
                            pendingDeposits: pendingDeposits,
                            pendingWds: pendingWds,
                            totalDistributed: totalDistributed,
                            frozenCount: frozenCount,
                            adminCount: adminCount,
                            totalWallet: totalWallet,
                          ),
                          const SizedBox(height: 20),

                          // Financial summary
                          _buildFinancialRow(
                            isLoading: isLoading,
                            depositVolume: depositVolume,
                            withdrawVolume: withdrawVolume,
                            approvedDepsToday: approvedToday,
                            approvedWdsToday: approvedWdsToday,
                          ),
                          const SizedBox(height: 20),

                          // Monitoring row: recent admin activity + quick actions
                          _buildMonitoringRow(context),
                          const SizedBox(height: 20),

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
      },
    );
  }

  // ──────────────────────────────────────────
  // PLATFORM ALERTS
  // ──────────────────────────────────────────
  Widget _buildPlatformAlerts({
    required int pendingDeposits,
    required int pendingWds,
    required int pendingCredentials,
    required int liveNoResults,
  }) {
    final alerts = <Widget>[];

    if (pendingDeposits > 10) {
      alerts.add(
        AdminAlertBanner(
          message:
              '$pendingDeposits pending deposit requests awaiting approval.',
          color: AdminColors.success,
          icon: Icons.add_circle_outline_rounded,
          actionLabel: 'Review',
          onAction: () => _navigate(context, 'deposits'),
        ),
      );
    }
    if (pendingWds > 5) {
      alerts.add(
        AdminAlertBanner(
          message: '$pendingWds pending withdrawal requests awaiting payout.',
          color: AdminColors.danger,
          icon: Icons.remove_circle_outline_rounded,
          actionLabel: 'Review',
          onAction: () => _navigate(context, 'withdrawals'),
        ),
      );
    }
    if (pendingCredentials > 0) {
      alerts.add(
        AdminAlertBanner(
          message:
              '$pendingCredentials live tournament(s) missing room credentials.',
          color: AdminColors.warning,
          icon: Icons.key_rounded,
          actionLabel: 'Fix',
          onAction: () => _navigate(context, 'tournaments'),
        ),
      );
    }
    if (liveNoResults > 0) {
      alerts.add(
        AdminAlertBanner(
          message:
              '$liveNoResults live tournament(s) have not distributed prizes yet.',
          color: AdminColors.gold,
          icon: Icons.emoji_events_rounded,
          actionLabel: 'Distribute',
          onAction: () => _navigate(context, 'tournaments'),
        ),
      );
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      children: alerts
          .map(
            (a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: a),
          )
          .toList(),
    );
  }

  // ──────────────────────────────────────────
  // PLATFORM HEALTH GRID
  // ──────────────────────────────────────────
  Widget _buildHealthGrid({
    required bool isLoading,
    required int totalUsers,
    required int liveTournaments,
    required int pendingDeposits,
    required int pendingWds,
    required double totalDistributed,
    required int frozenCount,
    required int adminCount,
    required double totalWallet,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'PLATFORM HEALTH', color: AdminColors.purple),
        const SizedBox(height: 14),
        AdminGrid(
          //'AdminGrid' isn't a function. Try correcting the name to match an existing function, or define a method or function named 'AdminGrid'.
          mobileColumns: 2,
          tabletColumns: 4,
          desktopColumns: 4,
          spacing: 14,
          runSpacing: 14,
          children: [
            AdminStatCard(
              label: 'Total Users',
              value: isLoading ? '—' : totalUsers.toString(),
              icon: Icons.people_rounded,
              color: AdminColors.info,
              subLabel: 'Registered players',
              trend: _LiveDot(color: AdminColors.info),
            ),
            AdminStatCard(
              label: 'Live Tournaments',
              value: isLoading ? '—' : liveTournaments.toString(),
              icon: Icons.sports_esports_rounded,
              color: AdminColors.success,
              subLabel: 'Active right now',
              trend: liveTournaments > 0
                  ? _AlertDot(color: AdminColors.success)
                  : _LiveDot(color: AdminColors.success),
            ),
            AdminStatCard(
              label: 'Pending Txns',
              value: isLoading
                  ? '—'
                  : (pendingDeposits + pendingWds).toString(),
              icon: Icons.pending_rounded,
              color: (pendingDeposits + pendingWds) > 0
                  ? AdminColors.warning
                  : AdminColors.textMuted,
              subLabel: '$pendingDeposits deps · $pendingWds wds',
              trend: (pendingDeposits + pendingWds) > 0
                  ? _AlertDot(color: AdminColors.warning)
                  : _LiveDot(color: AdminColors.textMuted),
            ),
            AdminStatCard(
              label: 'Prizes Paid Out',
              value: isLoading
                  ? '—'
                  : '₹${totalDistributed.toStringAsFixed(0)}',
              icon: Icons.emoji_events_rounded,
              color: AdminColors.gold,
              subLabel: 'Total distributed',
              trend: _LiveDot(color: AdminColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AdminGrid(
          //'AdminGrid' isn't a function. Try correcting the name to match an existing function, or define a method or function named 'AdminGrid'.
          mobileColumns: 3,
          tabletColumns: 3,
          desktopColumns: 3,
          spacing: 12,
          runSpacing: 12,
          children: [
            _MiniStatCard(
              label: 'Frozen Accounts',
              value: isLoading ? '—' : frozenCount.toString(),
              sublabel: 'Suspended users',
              color: frozenCount > 0
                  ? AdminColors.danger
                  : AdminColors.textMuted,
              icon: Icons.lock_rounded,
            ),
            _MiniStatCard(
              label: 'Admin Accounts',
              value: isLoading ? '—' : adminCount.toString(),
              sublabel: 'With admin flag',
              color: AdminColors.purple,
              icon: Icons.shield_rounded,
            ),
            _MiniStatCard(
              label: 'Total Wallet',
              value: isLoading ? '—' : '₹${totalWallet.toStringAsFixed(0)}',
              sublabel: 'Combined balances',
              color: AdminColors.gold,
              icon: Icons.account_balance_wallet_rounded,
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
    required bool isLoading,
    required double depositVolume,
    required double withdrawVolume,
    required int approvedDepsToday,
    required int approvedWdsToday,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'FINANCIAL SUMMARY', color: AdminColors.gold),
        const SizedBox(height: 14),
        AdminGrid(
          //'AdminGrid' isn't a function. Try correcting the name to match an existing function, or define a method or function named 'AdminGrid'.
          mobileColumns: 2,
          tabletColumns: 2,
          desktopColumns: 4,
          spacing: 12,
          runSpacing: 12,
          children: [
            _MiniStatCard(
              label: 'Total Deposited',
              value: isLoading ? '—' : '₹${depositVolume.toStringAsFixed(0)}',
              sublabel: 'All-time approved',
              color: AdminColors.success,
              icon: Icons.add_circle_outline_rounded,
            ),
            _MiniStatCard(
              label: 'Deposits Today',
              value: isLoading ? '—' : approvedDepsToday.toString(),
              sublabel: 'Approved today',
              color: AdminColors.success,
              icon: Icons.today_rounded,
            ),
            _MiniStatCard(
              label: 'Total Withdrawn',
              value: isLoading ? '—' : '₹${withdrawVolume.toStringAsFixed(0)}',
              sublabel: 'All-time paid out',
              color: AdminColors.danger,
              icon: Icons.remove_circle_outline_rounded,
            ),
            _MiniStatCard(
              label: 'Withdrawals Today',
              value: isLoading ? '—' : approvedWdsToday.toString(),
              sublabel: 'Paid today',
              color: AdminColors.danger,
              icon: Icons.today_rounded,
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // MONITORING ROW
  // ──────────────────────────────────────────
  Widget _buildMonitoringRow(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    final recentActivity = AdminSectionCard(
      title: 'RECENT ADMIN ACTIVITY',
      titleIcon: Icons.history_rounded,
      titleColor: AdminColors.warning,
      titleActions: [
        AdminBadge(label: 'LIVE', color: AdminColors.warning, glowing: true),
      ],
      contentPadding: EdgeInsets.zero,
      child: StreamBuilder<List<AdminLogEntry>>(
        stream: AdminLogsService.instance.logsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AdminShimmerTile(height: 52),
                  ),
                ),
              ),
            );
          }
          final logs = snap.data ?? [];
          if (logs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No admin activity yet.',
                  style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
                ),
              ),
            );
          }
          return Column(
            children: logs.take(10).map((log) {
              final label = LogActions.labels[log.action] ?? log.action;
              final color = _logActionColor(log.action);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AdminColors.border, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        label,
                        style: AdminTextStyles.labelSmall.copyWith(
                          color: color,
                          fontSize: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.adminEmail.split('@').first,
                        style: AdminTextStyles.bodySmall.copyWith(
                          color: AdminColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _relative(log.createdAt),
                      style: AdminTextStyles.labelSmall.copyWith(
                        color: AdminColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );

    final quickActions = AdminSectionCard(
      title: 'QUICK ACTIONS',
      titleIcon: Icons.flash_on_rounded,
      titleColor: AdminColors.purple,
      child: Column(
        children: [
          _QuickActionTile(
            label: 'Create Tournament',
            sublabel: 'Set up a new esports tournament',
            icon: Icons.add_circle_outline_rounded,
            color: AdminColors.gold,
            liveLabel: 'LIVE',
            navId: 'tournaments',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label: 'Process Withdrawals',
            sublabel: 'Approve pending payout requests',
            icon: Icons.remove_circle_outline_rounded,
            color: AdminColors.danger,
            liveLabel: 'LIVE',
            navId: 'withdrawals',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label: 'Review Deposits',
            sublabel: 'Verify and approve deposit requests',
            icon: Icons.add_circle_rounded,
            color: AdminColors.success,
            liveLabel: 'LIVE',
            navId: 'deposits',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label: 'Open Logs',
            sublabel: 'View full admin audit trail',
            icon: Icons.receipt_long_rounded,
            color: AdminColors.warning,
            liveLabel: 'LIVE',
            navId: 'logs',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label: 'Platform Settings',
            sublabel: 'Configure UPI, maintenance, security',
            icon: Icons.settings_rounded,
            color: AdminColors.purple,
            liveLabel: 'LIVE',
            navId: 'settings',
          ),
          const SizedBox(height: 8),
          _QuickActionTile(
            label: 'System Tools',
            sublabel: 'Wallet recalc, CSV exports, suspicious activity',
            icon: Icons.build_rounded,
            color: AdminColors.info,
            liveLabel: 'LIVE',
            navId: 'tools',
          ),
        ],
      ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: recentActivity),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: quickActions),
        ],
      );
    }

    return Column(
      children: [recentActivity, const SizedBox(height: 16), quickActions],
    );
  }

  // ──────────────────────────────────────────
  // RECENT USERS
  // ──────────────────────────────────────────
  Widget _buildRecentUsers(List<QueryDocumentSnapshot> docs) {
    return AdminSectionCard(
      title: 'RECENT USERS',
      titleIcon: Icons.people_outline_rounded,
      titleColor: AdminColors.info,
      titleActions: [
        AdminBadge(label: 'LIVE', color: AdminColors.info, glowing: true),
      ],
      child: docs.isEmpty
          ? const AdminEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No users yet',
              subtitle: 'New registrations will appear here.',
              color: AdminColors.info,
            )
          : Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _UserRow(
                  name: (data['name'] as String?) ?? 'Unknown',
                  email: (data['email'] as String?) ?? '',
                  photoUrl: data['photoUrl'] as String?,
                  uid: doc.id,
                  walletBalance:
                      (data['walletBalance'] as num?)?.toDouble() ?? 0.0,
                  isAdmin: (data['isAdmin'] as bool?) ?? false,
                  isFrozen: (data['isFrozen'] as bool?) ?? false,
                  joinedAt: data['createdAt'] as Timestamp?,
                  formatDate: _fmt,
                );
              }).toList(),
            ),
    );
  }

  void _navigate(BuildContext context, String navId) {
    BuildContext? ctx = context;
    while (ctx != null) {
      final element = ctx as Element;
      if (element is StatefulElement) {
        final state = element.state;
        if (state.runtimeType.toString().contains('AdminShell')) {
          try {
            final navState = (state as dynamic)._navState as AdminNavState;
            navState.setActive(navId);
          } catch (_) {}
          return;
        }
      }
      // ERROR HERE: ctx = element.parent as BuildContext?;

      // FIX: Use a framework-compatible ancestor element traversal step
      Element? parentElement;
      element.visitAncestorElements((ancestor) {
        parentElement = ancestor;
        return false; // Return false to stop immediate deep traversal looping
      });
      ctx = parentElement;
    }
  }
}

// ═════════════════════════════════════════════
// SECTION LABEL
// ═════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: AdminTextStyles.labelLarge.copyWith(letterSpacing: 2)),
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
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      'LIVE',
      style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8),
    ),
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
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.12 + 0.10 * _anim.value),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.color.withValues(alpha: 0.4 + 0.3 * _anim.value),
        ),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.2 * _anim.value),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'ALERT',
            style: AdminTextStyles.labelSmall.copyWith(
              color: widget.color,
              fontSize: 8,
            ),
          ),
        ],
      ),
    ),
  );
}

// ═════════════════════════════════════════════
// MINI STAT CARD
// ═════════════════════════════════════════════
class _MiniStatCard extends StatelessWidget {
  final String label, value, sublabel;
  final Color color;
  final IconData icon;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AdminColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AdminColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: AdminTextStyles.labelSmall.copyWith(
                  color: AdminColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AdminTextStyles.titleMedium.copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
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
  Widget build(BuildContext context) => AnimatedBuilder(
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
            alpha: 0.25 + 0.15 * pulse.value,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AdminColors.purple.withValues(
              alpha: 0.08 + 0.06 * pulse.value,
            ),
            blurRadius: 24,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AdminColors.purple.withValues(alpha: 0.15),
              border: Border.all(
                color: AdminColors.purple.withValues(
                  alpha: 0.4 + 0.3 * pulse.value,
                ),
              ),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: AdminColors.purple,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shadow Storm Admin Panel',
                  style: AdminTextStyles.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Phase 5 Complete — All systems operational.',
                  style: AdminTextStyles.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _PhasePill(label: 'DEPOSITS', color: AdminColors.success),
                    _PhasePill(label: 'WITHDRAWALS', color: AdminColors.danger),
                    _PhasePill(label: 'USERS', color: AdminColors.info),
                    _PhasePill(label: 'TOURNAMENTS', color: AdminColors.gold),
                    _PhasePill(label: 'LOGS', color: AdminColors.warning),
                    _PhasePill(label: 'SETTINGS', color: AdminColors.purple),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AdminColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AdminColors.success.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.success,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'PHASE 5',
                  style: AdminTextStyles.labelSmall.copyWith(
                    color: AdminColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PhasePill extends StatelessWidget {
  final String label;
  final Color color;
  const _PhasePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8),
        ),
      ],
    ),
  );
}

// ═════════════════════════════════════════════
// QUICK ACTION TILE
// ═════════════════════════════════════════════
class _QuickActionTile extends StatefulWidget {
  final String label, sublabel;
  final IconData icon;
  final Color color;
  final String? liveLabel;
  final String? navId;

  const _QuickActionTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    this.liveLabel,
    this.navId,
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
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: isActive ? () => _navigateTo(context, widget.navId!) : null,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.25),
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    widget.liveLabel!,
                    style: AdminTextStyles.labelSmall.copyWith(
                      color: widget.color,
                      fontSize: 8,
                    ),
                  ),
                ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: widget.color.withValues(alpha: 0.5),
                  size: 12,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String navId) {
    BuildContext? ctx = context;
    while (ctx != null) {
      final element = ctx as Element;
      if (element is StatefulElement) {
        final state = element.state;
        if (state.runtimeType.toString().contains('AdminShell')) {
          try {
            final navState = (state as dynamic)._navState as AdminNavState;
            navState.setActive(navId);
          } catch (_) {}
          return;
        }
      }

      // FIX: Use visitAncestorElements to move up the tree safely
      Element? parentElement;
      element.visitAncestorElements((ancestor) {
        parentElement = ancestor;
        return false; // Stops traversal immediately after finding the direct parent
      });
      ctx = parentElement;
    }
  }
}

// ═════════════════════════════════════════════
// USER ROW
// ═════════════════════════════════════════════
class _UserRow extends StatelessWidget {
  final String name, email, uid;
  final String? photoUrl;
  final double walletBalance;
  final bool isAdmin, isFrozen;
  final Timestamp? joinedAt;
  final String Function(Timestamp?) formatDate;

  const _UserRow({
    required this.name,
    required this.email,
    required this.uid,
    this.photoUrl,
    required this.walletBalance,
    required this.isAdmin,
    required this.isFrozen,
    this.joinedAt,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AdminColors.border, width: 0.5)),
    ),
    child: Row(
      children: [
        Stack(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AdminColors.surfaceElevated,
                border: Border.all(
                  color: isFrozen
                      ? AdminColors.danger.withValues(alpha: 0.5)
                      : AdminColors.border,
                ),
              ),
              child: photoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        photoUrl!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.person_rounded,
                          color: AdminColors.textMuted,
                          size: 18,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      color: AdminColors.textMuted,
                      size: 18,
                    ),
            ),
            if (isFrozen)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AdminColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AdminColors.surfaceCard,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 7,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: AdminTextStyles.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AdminColors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AdminColors.purple.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'ADMIN',
                        style: AdminTextStyles.labelSmall.copyWith(
                          color: AdminColors.purple,
                          fontSize: 7,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                email,
                style: AdminTextStyles.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${walletBalance.toStringAsFixed(2)}',
              style: AdminTextStyles.titleSmall.copyWith(
                color: AdminColors.gold,
              ),
            ),
            Text(formatDate(joinedAt), style: AdminTextStyles.bodySmall),
          ],
        ),
      ],
    ),
  );
}
