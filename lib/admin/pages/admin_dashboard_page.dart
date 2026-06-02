// lib/admin/pages/admin_dashboard_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Dashboard
// F2: Full platform metrics, revenue analytics, tournament health, user growth
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/admin_page_container.dart';
import '../layout/admin_responsive.dart' hide AdminGrid;
import '../navigation/admin_nav_model.dart';
import '../theme/admin_theme.dart';
import '../services/admin_logs_service.dart';
import '../services/admin_settings_service.dart';
import '../services/admin_analytics_service.dart';
import '../services/admin_tournament_service.dart';
import '../widgets/admin_components.dart';

class AdminDashboardPage extends StatefulWidget {
  final AdminNavState navState;
  const AdminDashboardPage({super.key, required this.navState});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  PlatformMetrics  _metrics       = PlatformMetrics.empty();
  RevenueSnapshot? _revenue;
  UserGrowthData?  _growth;
  List<TournamentHealthItem> _healthItems = [];

  RevenuePeriod _selectedPeriod = RevenuePeriod.today;
  bool _loadingMetrics  = true;
  bool _loadingRevenue  = true;
  bool _loadingGrowth   = true;
  String? _metricsError;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _loadAll();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() { _loadingMetrics = true; _metricsError = null; });
    try {
      final results = await Future.wait([
        AdminAnalyticsService.instance.getPlatformMetrics(),
        AdminAnalyticsService.instance.getRevenueSnapshot(_selectedPeriod),
        AdminAnalyticsService.instance.getUserGrowth(),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics        = results[0] as PlatformMetrics;
        _revenue        = results[1] as RevenueSnapshot;
        _growth         = results[2] as UserGrowthData;
        _loadingMetrics = false;
        _loadingRevenue = false;
        _loadingGrowth  = false;
      });
      // Update sidebar badges
      widget.navState.badges.update(
        pendingDeposits:    _metrics.pendingDeposits,
        pendingWithdrawals: _metrics.pendingWithdrawals,
        tournamentAlerts:   _metrics.totalTournamentAlerts,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _metricsError = e.toString(); _loadingMetrics = false; });
    }

    // Load tournament health separately (streaming)
    AdminAnalyticsService.instance.tournamentHealthStream().listen((items) {
      if (!mounted) return;
      setState(() => _healthItems = items);
    });
  }

  Future<void> _loadRevenuePeriod(RevenuePeriod p) async {
    setState(() { _selectedPeriod = p; _loadingRevenue = true; });
    try {
      final rev = await AdminAnalyticsService.instance.getRevenueSnapshot(p);
      if (!mounted) return;
      setState(() { _revenue = rev; _loadingRevenue = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRevenue = false);
    }
  }

  // Fix status helper
  Future<void> _fixTournamentStatus(String id, String newStatus) async {
    try {
      await AdminTournamentService.instance.updateStatus(id, newStatus);
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AdminColors.danger,
      ));
    }
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2,'0');
    final m = d.minute.toString().padLeft(2,'0');
    return '${d.day} ${months[d.month - 1]}, $h:$m';
  }

  String _relative(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate().toLocal());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _logActionColor(String action) {
    if (action.contains('approved'))     return AdminColors.success;
    if (action.contains('rejected'))     return AdminColors.danger;
    if (action.contains('frozen'))       return AdminColors.warning;
    if (action.contains('tournament'))   return AdminColors.gold;
    if (action.contains('prize'))        return AdminColors.success;
    if (action.contains('admin_'))       return AdminColors.purple;
    if (action.contains('maintenance'))  return AdminColors.danger;
    if (action.contains('suspicious'))   return AdminColors.danger;
    return AdminColors.info;
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return AdminPageContainer(
      title:    'Dashboard',
      subtitle: 'Shadow Storm Platform — Real-time Monitoring',
      actions: [
        AdminActionButton(
          label:    'Refresh',
          icon:     Icons.refresh_rounded,
          color:    AdminColors.purple,
          outlined: true,
          onTap:    _loadAll,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(pulse: _pulse),
          const SizedBox(height: 16),

          // Settings-based alerts
          StreamBuilder<AdminSettings>(
            stream: AdminSettingsService.instance.settingsStream(),
            builder: (context, snap) {
              final s = snap.data;
              if (s == null) return const SizedBox.shrink();
              return Column(children: [
                if (s.maintenanceMode) ...[
                  AdminAlertBanner(
                    message:  '🔴 MAINTENANCE MODE ACTIVE — All player actions are blocked.',
                    color:    AdminColors.danger,
                    icon:     Icons.construction_rounded,
                  ),
                  const SizedBox(height: 8),
                ],
                if (s.walletFrozen) ...[
                  AdminAlertBanner(
                    message:  '❄️ WALLETS FROZEN — All deposit/withdrawal processing is paused.',
                    color:    AdminColors.warning,
                    icon:     Icons.ac_unit_rounded,
                  ),
                  const SizedBox(height: 8),
                ],
              ]);
            },
          ),

          if (_metricsError != null) ...[
            AdminAlertBanner(
              message: 'Failed to load metrics: $_metricsError',
              color:   AdminColors.danger,
              icon:    Icons.error_outline_rounded,
            ),
            const SizedBox(height: 12),
          ],

          // ── PLATFORM OVERVIEW GRID ─────────────────────
          _SectionLabel(label: 'PLATFORM OVERVIEW', color: AdminColors.purple),
          const SizedBox(height: 14),
          AdminGrid(
            mobileColumns: 2, tabletColumns: 2, desktopColumns: 4,
            spacing: 14, runSpacing: 14,
            children: [
              AdminStatCard(
                label:    'Total Users',
                value:    _loadingMetrics ? '—' : '${_metrics.totalUsers}',
                icon:     Icons.people_rounded,
                color:    AdminColors.info,
                subLabel: '+${_metrics.newUsersToday} today',
                trend:    _LiveDot(color: AdminColors.info),
              ),
              AdminStatCard(
                label:    'Total Tournaments',
                value:    _loadingMetrics ? '—' : '${_metrics.totalTournaments}',
                icon:     Icons.emoji_events_rounded,
                color:    AdminColors.gold,
                subLabel: '${_metrics.liveTournaments} live now',
                trend:    _metrics.liveTournaments > 0
                    ? _AlertDot(color: AdminColors.gold)
                    : _LiveDot(color: AdminColors.gold),
              ),
              AdminStatCard(
                label:    'Pending Transactions',
                value:    _loadingMetrics ? '—'
                    : '${_metrics.pendingDeposits + _metrics.pendingWithdrawals}',
                icon:     Icons.pending_rounded,
                color:    (_metrics.pendingDeposits + _metrics.pendingWithdrawals) > 0
                    ? AdminColors.warning : AdminColors.textMuted,
                subLabel: '${_metrics.pendingDeposits} deps · ${_metrics.pendingWithdrawals} wds',
                trend:    (_metrics.pendingDeposits + _metrics.pendingWithdrawals) > 0
                    ? _AlertDot(color: AdminColors.warning)
                    : _LiveDot(color: AdminColors.textMuted),
              ),
              AdminStatCard(
                label:    'Platform Profit',
                value:    _loadingMetrics ? '—'
                    : '₹${_metrics.platformProfit.toStringAsFixed(0)}',
                icon:     Icons.trending_up_rounded,
                color:    _metrics.platformProfit >= 0
                    ? AdminColors.success : AdminColors.danger,
                subLabel: 'Entry fees – prizes',
                trend:    _LiveDot(color: AdminColors.success),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── TOURNAMENT STATUS GRID ─────────────────────
          _SectionLabel(label: 'TOURNAMENT STATUS', color: AdminColors.gold),
          const SizedBox(height: 14),
          AdminGrid(
            mobileColumns: 2, tabletColumns: 3, desktopColumns: 5,
            spacing: 12, runSpacing: 12,
            children: [
              _MiniStatCard(label: 'Upcoming',  value: '${_metrics.upcomingTournaments}',   sublabel: 'scheduled',   color: AdminColors.info,    icon: Icons.schedule_rounded),
              _MiniStatCard(label: 'Live',       value: '${_metrics.liveTournaments}',       sublabel: 'in-progress', color: AdminColors.success,  icon: Icons.play_circle_rounded),
              _MiniStatCard(label: 'Completed',  value: '${_metrics.completedTournaments}',  sublabel: 'finished',    color: AdminColors.textMuted,icon: Icons.check_circle_outline_rounded),
              _MiniStatCard(label: 'Cancelled',  value: '${_metrics.cancelledTournaments}',  sublabel: 'cancelled',   color: AdminColors.danger,   icon: Icons.cancel_outlined),
              _MiniStatCard(label: 'Full',       value: '${_metrics.fullTournaments}',        sublabel: 'sold out',    color: AdminColors.gold,     icon: Icons.groups_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // ── ALERTS ─────────────────────────────────────
          _buildPlatformAlerts(),
          const SizedBox(height: 20),

          // ── USER STATS ─────────────────────────────────
          _SectionLabel(label: 'USER ANALYTICS', color: AdminColors.info),
          const SizedBox(height: 14),
          AdminGrid(
            mobileColumns: 2, tabletColumns: 4, desktopColumns: 4,
            spacing: 12, runSpacing: 12,
            children: [
              _MiniStatCard(label: 'New Today',   value: '${_metrics.newUsersToday}',   sublabel: 'registered today', color: AdminColors.success, icon: Icons.person_add_rounded),
              _MiniStatCard(label: 'New This Week',value: '${_metrics.newUsersThisWeek}', sublabel: 'past 7 days',  color: AdminColors.info,    icon: Icons.people_alt_rounded),
              _MiniStatCard(label: 'This Month',  value: '${_metrics.newUsersThisMonth}', sublabel: 'past 30 days', color: AdminColors.purple,  icon: Icons.calendar_month_rounded),
              _MiniStatCard(label: 'Frozen',      value: '${_metrics.frozenAccounts}',  sublabel: 'suspended',    color: _metrics.frozenAccounts > 0 ? AdminColors.danger : AdminColors.textMuted, icon: Icons.lock_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // ── REVENUE ANALYTICS ──────────────────────────
          _buildRevenueSection(),
          const SizedBox(height: 20),

          // ── FINANCIAL DETAILS ──────────────────────────
          _SectionLabel(label: 'FINANCIAL OVERVIEW', color: AdminColors.gold),
          const SizedBox(height: 14),
          AdminGrid(
            mobileColumns: 2, tabletColumns: 2, desktopColumns: 4,
            spacing: 12, runSpacing: 12,
            children: [
              _MiniStatCard(label: 'Deposit Volume',    value: '₹${_metrics.totalDepositVolume.toStringAsFixed(0)}',    sublabel: 'total approved', color: AdminColors.success, icon: Icons.add_circle_outline_rounded),
              _MiniStatCard(label: 'Withdrawal Volume', value: '₹${_metrics.totalWithdrawalVolume.toStringAsFixed(0)}', sublabel: 'total paid out', color: AdminColors.danger,  icon: Icons.remove_circle_outline_rounded),
              _MiniStatCard(label: 'Prize Payouts',     value: '₹${_metrics.totalPrizeDistributed.toStringAsFixed(0)}', sublabel: 'distributed',    color: AdminColors.gold,    icon: Icons.emoji_events_rounded),
              _MiniStatCard(label: 'Wallet Balance',    value: '₹${_metrics.totalWalletBalance.toStringAsFixed(0)}',    sublabel: 'combined users', color: AdminColors.purple,  icon: Icons.account_balance_wallet_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // ── TOURNAMENT OPERATIONS ──────────────────────
          _buildTournamentOperations(),
          const SizedBox(height: 20),

          // ── PENDING TRANSACTIONS ───────────────────────
          _buildPendingTransactions(),
          const SizedBox(height: 20),

          // ── MONITORING ROW ─────────────────────────────
          _buildMonitoringRow(context),
          const SizedBox(height: 20),

          // ── PLATFORM HEALTH ────────────────────────────
          _buildPlatformHealth(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────
  // PLATFORM ALERTS
  // ──────────────────────────────────────────────────────
  Widget _buildPlatformAlerts() {
    final alerts = <Widget>[];

    if (_metrics.pendingDeposits > 10) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.pendingDeposits} pending deposit requests awaiting approval.',
        color: AdminColors.success, icon: Icons.add_circle_outline_rounded,
        actionLabel: 'Review', onAction: () => widget.navState.setActive('deposits'),
      ));
    }
    if (_metrics.pendingWithdrawals > 5) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.pendingWithdrawals} pending withdrawal requests awaiting payout.',
        color: AdminColors.danger, icon: Icons.remove_circle_outline_rounded,
        actionLabel: 'Review', onAction: () => widget.navState.setActive('withdrawals'),
      ));
    }
    if (_metrics.missingCredentials > 0) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.missingCredentials} tournament(s) missing room credentials.',
        color: AdminColors.warning, icon: Icons.key_rounded,
        actionLabel: 'Fix', onAction: () => widget.navState.setActive('tournaments'),
      ));
    }
    if (_metrics.shouldBeLive > 0) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.shouldBeLive} tournament(s) should already be LIVE. Start time has passed.',
        color: AdminColors.danger, icon: Icons.alarm_rounded,
        actionLabel: 'Fix', onAction: () => widget.navState.setActive('tournaments'),
      ));
    }
    if (_metrics.shouldBeCompleted > 0) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.shouldBeCompleted} live tournament(s) appear to have ended. Mark as completed.',
        color: AdminColors.warning, icon: Icons.flag_rounded,
        actionLabel: 'Fix', onAction: () => widget.navState.setActive('tournaments'),
      ));
    }
    if (_metrics.awaitingPrizes > 0) {
      alerts.add(AdminAlertBanner(
        message: '${_metrics.awaitingPrizes} live tournament(s) need prize distribution.',
        color: AdminColors.gold, icon: Icons.emoji_events_rounded,
        actionLabel: 'Distribute', onAction: () => widget.navState.setActive('tournaments'),
      ));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'CRITICAL ALERTS', color: AdminColors.danger),
        const SizedBox(height: 12),
        ...alerts.map((a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: a)),
      ],
    );
  }

  // ──────────────────────────────────────────────────────
  // REVENUE ANALYTICS SECTION
  // ──────────────────────────────────────────────────────
  Widget _buildRevenueSection() {
    return AdminSectionCard(
      title:      'REVENUE ANALYTICS',
      titleIcon:  Icons.analytics_rounded,
      titleColor: AdminColors.gold,
      titleActions: [
        // Period selector
        ...RevenuePeriod.values.map((p) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GestureDetector(
            onTap: () => _loadRevenuePeriod(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedPeriod == p
                    ? AdminColors.gold.withValues(alpha: 0.15)
                    : AdminColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _selectedPeriod == p
                      ? AdminColors.gold.withValues(alpha: 0.5)
                      : AdminColors.border,
                ),
              ),
              child: Text(p.label,
                style: AdminTextStyles.labelSmall.copyWith(
                  color: _selectedPeriod == p ? AdminColors.gold : AdminColors.textMuted,
                  fontSize: 8,
                )),
            ),
          ),
        )),
      ],
      child: _loadingRevenue || _revenue == null
          ? const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AdminColors.gold, strokeWidth: 2)))
          : Column(
              children: [
                AdminGrid(
                  mobileColumns: 2, tabletColumns: 2, desktopColumns: 4,
                  spacing: 12, runSpacing: 12,
                  children: [
                    _RevStat(label: 'Deposits',    value: '₹${_revenue!.depositVolume.toStringAsFixed(0)}',     count: '${_revenue!.approvedDeposits} txns',   color: AdminColors.success),
                    _RevStat(label: 'Withdrawals', value: '₹${_revenue!.withdrawalVolume.toStringAsFixed(0)}',  count: '${_revenue!.approvedWithdrawals} txns', color: AdminColors.danger),
                    _RevStat(label: 'Entry Fees',  value: '₹${_revenue!.entryFeeCollected.toStringAsFixed(0)}', count: 'collected',                             color: AdminColors.gold),
                    _RevStat(label: 'Prize Paid',  value: '₹${_revenue!.prizeDistributed.toStringAsFixed(0)}',  count: 'distributed',                           color: AdminColors.purple),
                  ],
                ),
                const SizedBox(height: 16),
                // Net balance
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color:        _revenue!.platformProfit >= 0
                        ? AdminColors.success.withValues(alpha: 0.06)
                        : AdminColors.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _revenue!.platformProfit >= 0
                          ? AdminColors.success.withValues(alpha: 0.3)
                          : AdminColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      _revenue!.platformProfit >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      color: _revenue!.platformProfit >= 0
                          ? AdminColors.success : AdminColors.danger,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Platform Profit/Loss (${_selectedPeriod.label})',
                            style: AdminTextStyles.labelMedium.copyWith(letterSpacing: 1)),
                        Text(
                          '₹${_revenue!.platformProfit.toStringAsFixed(2)}',
                          style: AdminTextStyles.titleLarge.copyWith(
                            color: _revenue!.platformProfit >= 0
                                ? AdminColors.success : AdminColors.danger,
                          ),
                        ),
                      ],
                    )),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Net Balance', style: AdminTextStyles.labelSmall),
                        Text('₹${_revenue!.netBalance.toStringAsFixed(0)}',
                            style: AdminTextStyles.titleSmall.copyWith(
                                color: AdminColors.textSecondary)),
                      ],
                    ),
                  ]),
                ),
              ],
            ),
    );
  }

  // ──────────────────────────────────────────────────────
  // TOURNAMENT OPERATIONS PANEL
  // ──────────────────────────────────────────────────────
  Widget _buildTournamentOperations() {
    final items = _healthItems;
    final needsAttention = items.where((i) =>
        i.needsCredentials || i.shouldBeLive || i.shouldBeCompleted || i.awaitsPrizes
    ).toList();

    return AdminSectionCard(
      title:      'TOURNAMENT OPERATIONS',
      titleIcon:  Icons.sports_esports_rounded,
      titleColor: AdminColors.warning,
      titleActions: [
        AdminBadge(
          label: needsAttention.isNotEmpty ? '${needsAttention.length} ALERTS' : 'OK',
          color: needsAttention.isNotEmpty ? AdminColors.warning : AdminColors.success,
          glowing: needsAttention.isNotEmpty,
        ),
      ],
      child: needsAttention.isEmpty
          ? const AdminEmptyState(
              icon:     Icons.check_circle_outline_rounded,
              title:    'All tournaments healthy',
              subtitle: 'No operations require attention right now.',
              color:    AdminColors.success,
            )
          : Column(
              children: needsAttention.map((item) => _TournamentOpRow(
                item:    item,
                onFix:   (newStatus) => _fixTournamentStatus(item.id, newStatus),
                navToTournaments: () => widget.navState.setActive('tournaments'),
              )).toList(),
            ),
    );
  }

  // ──────────────────────────────────────────────────────
  // PENDING TRANSACTIONS WIDGET
  // ──────────────────────────────────────────────────────
  Widget _buildPendingTransactions() {
    final isDesktop = AdminResponsive.isDesktop(context);

    final depositsCard = AdminSectionCard(
      title:      'PENDING DEPOSITS',
      titleIcon:  Icons.add_circle_rounded,
      titleColor: AdminColors.success,
      titleActions: [
        if (_metrics.pendingDeposits > 0)
          AdminBadge(label: '${_metrics.pendingDeposits}', color: AdminColors.success, glowing: true),
      ],
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color:        AdminColors.success.withValues(alpha: 0.10),
                shape:        BoxShape.circle,
                border:       Border.all(color: AdminColors.success.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  '${_metrics.pendingDeposits}',
                  style: AdminTextStyles.titleLarge.copyWith(color: AdminColors.success),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Awaiting Approval', style: AdminTextStyles.titleSmall),
                Text('Deposit requests pending review', style: AdminTextStyles.bodySmall),
              ],
            )),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AdminActionButton(
              label: 'View Pending Deposits',
              icon:  Icons.arrow_forward_rounded,
              color: AdminColors.success,
              onTap: () => widget.navState.setActive('deposits'),
            ),
          ),
        ],
      ),
    );

    final withdrawalsCard = AdminSectionCard(
      title:      'PENDING WITHDRAWALS',
      titleIcon:  Icons.remove_circle_rounded,
      titleColor: AdminColors.danger,
      titleActions: [
        if (_metrics.pendingWithdrawals > 0)
          AdminBadge(label: '${_metrics.pendingWithdrawals}', color: AdminColors.danger, glowing: true),
      ],
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color:        AdminColors.danger.withValues(alpha: 0.10),
                shape:        BoxShape.circle,
                border:       Border.all(color: AdminColors.danger.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  '${_metrics.pendingWithdrawals}',
                  style: AdminTextStyles.titleLarge.copyWith(color: AdminColors.danger),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Awaiting Payout', style: AdminTextStyles.titleSmall),
                Text('Withdrawal requests pending processing', style: AdminTextStyles.bodySmall),
              ],
            )),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AdminActionButton(
              label: 'View Pending Withdrawals',
              icon:  Icons.arrow_forward_rounded,
              color: AdminColors.danger,
              onTap: () => widget.navState.setActive('withdrawals'),
            ),
          ),
        ],
      ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: depositsCard),
          const SizedBox(width: 16),
          Expanded(child: withdrawalsCard),
        ],
      );
    }
    return Column(children: [
      depositsCard,
      const SizedBox(height: 16),
      withdrawalsCard,
    ]);
  }

  // ──────────────────────────────────────────────────────
  // MONITORING ROW
  // ──────────────────────────────────────────────────────
  Widget _buildMonitoringRow(BuildContext context) {
    final isDesktop = AdminResponsive.isDesktop(context);

    final recentActivity = AdminSectionCard(
      title:      'RECENT ADMIN ACTIVITY',
      titleIcon:  Icons.history_rounded,
      titleColor: AdminColors.warning,
      titleActions: [AdminBadge(label: 'LIVE', color: AdminColors.warning, glowing: true)],
      contentPadding: EdgeInsets.zero,
      child: StreamBuilder<List<AdminLogEntry>>(
        stream: AdminLogsService.instance.logsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: List.generate(4, (_) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdminShimmerTile(height: 52),
              ))),
            );
          }
          final logs = snap.data ?? [];
          if (logs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No admin activity yet.',
                  style: TextStyle(color: AdminColors.textMuted, fontSize: 13))),
            );
          }
          return Column(
            children: logs.take(10).map((log) {
              final label = LogActions.labels[log.action] ?? log.action;
              final color = _logActionColor(log.action);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AdminColors.border, width: 0.5)),
                ),
                child: Row(children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color:        color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(4),
                      border:       Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(label,
                        style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    log.adminEmail.split('@').first,
                    style: AdminTextStyles.bodySmall.copyWith(color: AdminColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  )),
                  Text(_relative(log.createdAt),
                      style: AdminTextStyles.labelSmall.copyWith(
                          color: AdminColors.textMuted, fontSize: 9)),
                ]),
              );
            }).toList(),
          );
        },
      ),
    );

    final quickActions = AdminSectionCard(
      title:      'QUICK ACTIONS',
      titleIcon:  Icons.flash_on_rounded,
      titleColor: AdminColors.purple,
      child: Column(children: [
        _QuickActionTile(label: 'Create Tournament',       sublabel: 'Set up a new esports tournament',          icon: Icons.add_circle_outline_rounded,      color: AdminColors.gold,    navId: 'tournaments', navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'Process Withdrawals',     sublabel: 'Approve pending payout requests',          icon: Icons.remove_circle_outline_rounded,    color: AdminColors.danger,  navId: 'withdrawals',  navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'Review Deposits',         sublabel: 'Verify and approve deposit requests',      icon: Icons.add_circle_rounded,              color: AdminColors.success, navId: 'deposits',     navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'User Management',         sublabel: 'Manage players, freeze, balance adjust',   icon: Icons.people_rounded,                  color: AdminColors.info,    navId: 'users',        navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'Platform Settings',       sublabel: 'Configure UPI, maintenance, security',     icon: Icons.settings_rounded,                color: AdminColors.purple,  navId: 'settings',     navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'Admin Logs',              sublabel: 'View full audit trail',                    icon: Icons.receipt_long_rounded,            color: AdminColors.warning, navId: 'logs',         navState: widget.navState),
        const SizedBox(height: 8),
        _QuickActionTile(label: 'System Tools',            sublabel: 'Wallet recalc, CSV exports, diagnostics', icon: Icons.build_rounded,                   color: AdminColors.info,    navId: 'tools',        navState: widget.navState),
      ]),
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
    return Column(children: [
      recentActivity,
      const SizedBox(height: 16),
      quickActions,
    ]);
  }

  // ──────────────────────────────────────────────────────
  // PLATFORM HEALTH CARD
  // ──────────────────────────────────────────────────────
  Widget _buildPlatformHealth() {
    final items = [
      _HealthItem(label: 'Firestore',           status: 'Online',              ok: true,                                      icon: Icons.cloud_done_rounded),
      _HealthItem(label: 'Pending Deposits',     status: '${_metrics.pendingDeposits}',   ok: _metrics.pendingDeposits < 20,   icon: Icons.add_circle_outline_rounded),
      _HealthItem(label: 'Pending Withdrawals',  status: '${_metrics.pendingWithdrawals}',ok: _metrics.pendingWithdrawals < 10, icon: Icons.remove_circle_outline_rounded),
      _HealthItem(label: 'Live Tournaments',     status: '${_metrics.liveTournaments}',  ok: true,                             icon: Icons.sports_esports_rounded),
      _HealthItem(label: 'Missing Credentials', status: '${_metrics.missingCredentials}', ok: _metrics.missingCredentials == 0, icon: Icons.key_off_rounded),
      _HealthItem(label: 'Status Alerts',       status: '${_metrics.shouldBeLive + _metrics.shouldBeCompleted}', ok: _metrics.shouldBeLive + _metrics.shouldBeCompleted == 0, icon: Icons.warning_rounded),
      _HealthItem(label: 'Prize Pending',       status: '${_metrics.awaitingPrizes}',   ok: _metrics.awaitingPrizes == 0,      icon: Icons.emoji_events_outlined),
      _HealthItem(label: 'Frozen Accounts',     status: '${_metrics.frozenAccounts}',   ok: _metrics.frozenAccounts < 5,       icon: Icons.lock_rounded),
    ];

    return AdminSectionCard(
      title:      'PLATFORM HEALTH',
      titleIcon:  Icons.monitor_heart_rounded,
      titleColor: AdminColors.purple,
      child: AdminGrid(
        mobileColumns: 2, tabletColumns: 4, desktopColumns: 4,
        spacing: 10, runSpacing: 10,
        children: items.map((item) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        item.ok
                ? AdminColors.success.withValues(alpha: 0.05)
                : AdminColors.danger.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(
              color: item.ok
                  ? AdminColors.success.withValues(alpha: 0.2)
                  : AdminColors.danger.withValues(alpha: 0.3),
            ),
          ),
          child: Row(children: [
            Icon(item.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: item.ok ? AdminColors.success : AdminColors.danger,
                size: 14),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: AdminTextStyles.labelSmall.copyWith(
                        color: AdminColors.textMuted, fontSize: 8)),
                Text(item.status,
                    style: AdminTextStyles.bodySmall.copyWith(
                        color: item.ok ? AdminColors.success : AdminColors.danger)),
              ],
            )),
          ]),
        )).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HEALTH ITEM MODEL
// ─────────────────────────────────────────────
class _HealthItem {
  final String   label;
  final String   status;
  final bool     ok;
  final IconData icon;
  const _HealthItem({required this.label, required this.status, required this.ok, required this.icon});
}

// ─────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color  color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 8),
    Text(label, style: AdminTextStyles.labelLarge.copyWith(letterSpacing: 2)),
  ]);
}

// ─────────────────────────────────────────────
// MINI STAT CARD
// ─────────────────────────────────────────────
class _MiniStatCard extends StatelessWidget {
  final String label, value, sublabel;
  final Color  color;
  final IconData icon;
  const _MiniStatCard({required this.label, required this.value, required this.sublabel, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        AdminColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      border:       Border.all(color: AdminColors.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text(label,
            style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted),
            overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 8),
      Text(value, style: AdminTextStyles.titleMedium.copyWith(color: color), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(sublabel, style: AdminTextStyles.bodySmall),
    ]),
  );
}

// ─────────────────────────────────────────────
// REVENUE STAT
// ─────────────────────────────────────────────
class _RevStat extends StatelessWidget {
  final String label, value, count;
  final Color  color;
  const _RevStat({required this.label, required this.value, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border:       Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.textMuted, fontSize: 9)),
      const SizedBox(height: 6),
      Text(value, style: AdminTextStyles.titleSmall.copyWith(color: color), overflow: TextOverflow.ellipsis),
      Text(count, style: AdminTextStyles.bodySmall),
    ]),
  );
}

// ─────────────────────────────────────────────
// LIVE DOT
// ─────────────────────────────────────────────
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
        style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8)),
  );
}

// ─────────────────────────────────────────────
// ALERT DOT
// ─────────────────────────────────────────────
class _AlertDot extends StatefulWidget {
  final Color color;
  const _AlertDot({required this.color});
  @override State<_AlertDot> createState() => _AlertDotState();
}

class _AlertDotState extends State<_AlertDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:        widget.color.withValues(alpha: 0.12 + 0.10 * _anim.value),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: widget.color.withValues(alpha: 0.4 + 0.3 * _anim.value)),
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.2 * _anim.value), blurRadius: 6)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        const SizedBox(width: 4),
        Text('ALERT', style: AdminTextStyles.labelSmall.copyWith(color: widget.color, fontSize: 8)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────
// TOURNAMENT OPERATIONS ROW
// ─────────────────────────────────────────────
class _TournamentOpRow extends StatelessWidget {
  final TournamentHealthItem item;
  final void Function(String) onFix;
  final VoidCallback navToTournaments;

  const _TournamentOpRow({required this.item, required this.onFix, required this.navToTournaments});

  @override
  Widget build(BuildContext context) {
    String issue;
    Color  color;
    String fixLabel;
    String? fixStatus;

    if (item.shouldBeLive) {
      issue = 'Should be LIVE — start time has passed';
      color = AdminColors.danger;
      fixLabel = 'Mark LIVE';
      fixStatus = 'live';
    } else if (item.shouldBeCompleted) {
      issue = 'Possibly ended — consider marking completed';
      color = AdminColors.warning;
      fixLabel = 'Mark Completed';
      fixStatus = 'completed';
    } else if (item.awaitsPrizes) {
      issue = 'Prize distribution pending';
      color = AdminColors.gold;
      fixLabel = 'Go to Tournaments';
      fixStatus = null;
    } else if (item.needsCredentials) {
      issue = 'Missing room credentials (ID${item.hasRoomPassword ? '' : ' & password'})';
      color = AdminColors.warning;
      fixLabel = 'Go to Tournaments';
      fixStatus = null;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.title,
                style: AdminTextStyles.titleSmall.copyWith(color: AdminColors.textPrimary),
                overflow: TextOverflow.ellipsis),
            Text(issue, style: AdminTextStyles.bodySmall.copyWith(color: color)),
          ],
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: fixStatus != null ? () => onFix(fixStatus!) : navToTournaments,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(fixLabel,
                style: AdminTextStyles.labelSmall.copyWith(color: color)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// QUICK ACTION TILE
// ─────────────────────────────────────────────
class _QuickActionTile extends StatefulWidget {
  final String   label;
  final String   sublabel;
  final IconData icon;
  final Color    color;
  final String   navId;
  final AdminNavState navState;

  const _QuickActionTile({
    required this.label, required this.sublabel, required this.icon,
    required this.color, required this.navId, required this.navState,
  });

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: () => widget.navState.setActive(widget.navId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        _hovered ? widget.color.withValues(alpha: 0.08) : AdminColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
            color: _hovered ? widget.color.withValues(alpha: 0.4) : AdminColors.border,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        widget.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:       Border.all(color: widget.color.withValues(alpha: 0.25)),
            ),
            child: Icon(widget.icon, color: widget.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label, style: AdminTextStyles.titleSmall),
              Text(widget.sublabel, style: AdminTextStyles.bodySmall),
            ],
          )),
          Icon(Icons.arrow_forward_ios_rounded,
              color: widget.color.withValues(alpha: 0.5), size: 12),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────
// WELCOME BANNER
// ─────────────────────────────────────────────
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
          colors: [AdminColors.purpleDark.withValues(alpha: 0.6), AdminColors.surfaceCard],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AdminColors.purple.withValues(alpha: 0.25 + 0.15 * pulse.value),
        ),
        boxShadow: [BoxShadow(
          color: AdminColors.purple.withValues(alpha: 0.08 + 0.06 * pulse.value),
          blurRadius: 24,
        )],
      ),
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape:  BoxShape.circle,
            color:  AdminColors.purple.withValues(alpha: 0.15),
            border: Border.all(
              color: AdminColors.purple.withValues(alpha: 0.4 + 0.3 * pulse.value),
            ),
          ),
          child: const Icon(Icons.admin_panel_settings_rounded, color: AdminColors.purple, size: 28),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shadow Storm Admin Panel', style: AdminTextStyles.titleLarge),
            const SizedBox(height: 4),
            Text('Phase F2 — Full platform monitoring and control.', style: AdminTextStyles.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _PhasePill(label: 'METRICS',     color: AdminColors.info),
              _PhasePill(label: 'REVENUE',     color: AdminColors.gold),
              _PhasePill(label: 'TOURNAMENTS', color: AdminColors.success),
              _PhasePill(label: 'USERS',       color: AdminColors.purple),
              _PhasePill(label: 'HEALTH',      color: AdminColors.warning),
            ]),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:        AdminColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: AdminColors.success.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AdminColors.success)),
            const SizedBox(width: 6),
            Text('PHASE F2', style: AdminTextStyles.labelSmall.copyWith(color: AdminColors.success)),
          ]),
        ),
      ]),
    ),
  );
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
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 5),
      Text(label, style: AdminTextStyles.labelSmall.copyWith(color: color, fontSize: 8)),
    ]),
  );
}