// lib/screens/wallet_screen.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Wallet Screen (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1:
//
//   PRIORITY 4 — TRANSACTION CENTER:
//     Replaced separate Deposits / Withdrawals / History tabs with a
//     single unified transaction list containing ALL wallet activity:
//       • Deposit Request (pending / approved / rejected)
//       • Withdrawal Request (pending / approved / rejected)
//       • Tournament Entry Fee
//       • Tournament Winnings
//       • Refund
//       • Manual Adjustment
//
//     Filter chips:
//       All | Deposits | Withdrawals | Winnings | Refunds
//
//     Each transaction shows:
//       type icon, amount (+/-), status pill, date, description
//
//     Status colors:
//       Pending  → gold
//       Approved → green
//       Rejected → red
//       Completed → green
//
//     The transaction list merges data from THREE Firestore subcollections:
//       users/{uid}/transactions        ← main tx log (entries, winnings, refunds)
//       users/{uid}/deposit_requests    ← deposit status tracking
//       users/{uid}/withdraw_requests   ← withdrawal status tracking
//
//     Deposit and Withdraw ACTION tabs remain:
//       Quick action buttons (Deposit / Withdraw) open bottom sheets
//       so the player can still submit new requests from this screen.
//       The bottom sheet UI is the same as the old section forms.
//
//   PRIORITY 3 (F1 unchanged): MaintenanceGuard wraps Scaffold.
//   PRIORITY 4 (F1 unchanged): walletFrozen enforced — deposit/withdraw
//     action buttons disabled with freeze notice.
//
//   All original design tokens, animations, UPI QR, form logic intact.
// ─────────────────────────────────────────────

// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/wallet_service.dart';
import '../services/app_settings_service.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
class _C {
  static const background      = Color(0xFF06040E);
  static const surface         = Color(0xFF0E0A1A);
  static const surfaceCard     = Color(0xFF130F22);
  static const surfaceElevated = Color(0xFF1A1430);
  static const purple          = Color(0xFF9D55FF);
  static const purpleLight     = Color(0xFFB07EF8);
  static const purpleGlow      = Color(0x559D55FF);
  static const purpleGlowFaint = Color(0x229D55FF);
  static const textPrimary     = Color(0xFFEDE0FF);
  static const textSecondary   = Color(0xFF9B8DC0);
  static const textMuted       = Color(0xFF5A4E80);
  static const gold            = Color(0xFFFFCC44);
  static const goldGlow        = Color(0x55FFCC44);
  static const live            = Color(0xFFFF4466);
  static const liveGlow        = Color(0x55FF4466);
  static const success         = Color(0xFF44FF99);
  static const discord         = Color(0xFF5865F2);
  static const telegram        = Color(0xFF229ED9);
  static const border          = Color(0x337B3FE4);
  static const borderBright    = Color(0x667B3FE4);
  static const pending         = Color(0xFFFFCC44);
  static const approved        = Color(0xFF44FF99);
  static const rejected        = Color(0xFFFF4466);
  static const frozen          = Color(0xFFFFAA22);
}

TextStyle _ts({double size = 14, FontWeight weight = FontWeight.w400, Color color = _C.textPrimary, double letterSpacing = 0, double height = 1.4}) =>
    TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: height, fontFamily: 'Roboto');

Color _statusColor(String s) {
  switch (s) {
    case 'approved':  return _C.approved;
    case 'completed': return _C.approved;
    case 'rejected':  return _C.rejected;
    default:          return _C.pending;
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours  < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays   < 1) return '${diff.inHours}h ago';
  if (diff.inDays   < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

// ─────────────────────────────────────────────
// UNIFIED TRANSACTION ITEM MODEL
//
// Merges data from three Firestore subcollections into one list.
// ─────────────────────────────────────────────

enum _TxCategory { deposit, withdrawal, winnings, refund, entry, adjustment }

class _UnifiedTx {
  final String      id;
  final _TxCategory category;
  final double      amount;
  final String      status;   // pending | approved | rejected | completed
  final String      description;
  final DateTime    createdAt;
  final bool        isCredit;

  const _UnifiedTx({
    required this.id,
    required this.category,
    required this.amount,
    required this.status,
    required this.description,
    required this.createdAt,
    required this.isCredit,
  });

  factory _UnifiedTx.fromDepositRequest(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    return _UnifiedTx(
      id:          doc.id,
      category:    _TxCategory.deposit,
      amount:      (d['amount'] as num?)?.toDouble() ?? 0.0,
      status:      status,
      description: 'UTR: ${d['utr'] as String? ?? '—'}',
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCredit:    true,
    );
  }

  factory _UnifiedTx.fromWithdrawRequest(DocumentSnapshot doc) {
    final d      = doc.data() as Map<String, dynamic>;
    final status = d['status'] as String? ?? 'pending';
    final method = d['method'] as String? ?? 'upi';
    final dest   = method == 'upi'
        ? (d['upiId'] as String? ?? '—')
        : (d['accountHolder'] as String? ?? '—');
    return _UnifiedTx(
      id:          doc.id,
      category:    _TxCategory.withdrawal,
      amount:      (d['amount'] as num?)?.toDouble() ?? 0.0,
      status:      status,
      description: '${ method == 'upi' ? 'UPI' : 'Bank'}: $dest',
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCredit:    false,
    );
  }

  factory _UnifiedTx.fromTransaction(DocumentSnapshot doc) {
    final d    = doc.data() as Map<String, dynamic>;
    final type = d['type'] as String? ?? '';
    final desc = d['description'] as String? ?? '';
    _TxCategory cat;
    bool credit;
    switch (type) {
      case 'deposit':
        cat    = _TxCategory.deposit;     credit = true;  break;
      case 'withdrawal':
        cat    = _TxCategory.withdrawal;  credit = false; break;
      case 'winnings':
        cat    = _TxCategory.winnings;    credit = true;  break;
      case 'refund':
        cat    = _TxCategory.refund;      credit = true;  break;
      case 'tournament_entry':
        cat    = _TxCategory.entry;       credit = false; break;
      case 'manual_adjustment':
        cat    = _TxCategory.adjustment;  credit = (d['amount'] as num? ?? 0) >= 0; break;
      default:
        cat    = _TxCategory.entry;       credit = false;
    }
    return _UnifiedTx(
      id:          doc.id,
      category:    cat,
      amount:      (d['amount'] as num?)?.toDouble() ?? 0.0,
      status:      d['status'] as String? ?? 'completed',
      description: desc,
      createdAt:   (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isCredit:    credit,
    );
  }

  String get typeLabel {
    switch (category) {
      case _TxCategory.deposit:    return 'Deposit';
      case _TxCategory.withdrawal: return 'Withdrawal';
      case _TxCategory.winnings:   return 'Winnings';
      case _TxCategory.refund:     return 'Refund';
      case _TxCategory.entry:      return 'Tournament Entry';
      case _TxCategory.adjustment: return 'Balance Adjustment';
    }
  }

  IconData get icon {
    switch (category) {
      case _TxCategory.deposit:    return Icons.add_circle_rounded;
      case _TxCategory.withdrawal: return Icons.remove_circle_rounded;
      case _TxCategory.winnings:   return Icons.emoji_events_rounded;
      case _TxCategory.refund:     return Icons.replay_rounded;
      case _TxCategory.entry:      return Icons.sports_esports_rounded;
      case _TxCategory.adjustment: return Icons.tune_rounded;
    }
  }

  Color get iconColor {
    switch (category) {
      case _TxCategory.deposit:    return _C.success;
      case _TxCategory.withdrawal: return _C.live;
      case _TxCategory.winnings:   return _C.gold;
      case _TxCategory.refund:     return _C.frozen;
      case _TxCategory.entry:      return _C.purple;
      case _TxCategory.adjustment: return _C.purpleLight;
    }
  }
}

// ─────────────────────────────────────────────
// FILTER OPTION
// ─────────────────────────────────────────────
enum _FilterTab { all, deposits, withdrawals, winnings, refunds }

extension _FilterTabExt on _FilterTab {
  String get label {
    switch (this) {
      case _FilterTab.all:         return 'All';
      case _FilterTab.deposits:    return 'Deposits';
      case _FilterTab.withdrawals: return 'Withdrawals';
      case _FilterTab.winnings:    return 'Winnings';
      case _FilterTab.refunds:     return 'Refunds';
    }
  }

  bool matches(_UnifiedTx tx) {
    switch (this) {
      case _FilterTab.all:         return true;
      case _FilterTab.deposits:    return tx.category == _TxCategory.deposit;
      case _FilterTab.withdrawals: return tx.category == _TxCategory.withdrawal;
      case _FilterTab.winnings:    return tx.category == _TxCategory.winnings;
      case _FilterTab.refunds:     return tx.category == _TxCategory.refund;
    }
  }
}

// ─────────────────────────────────────────────
// WALLET SCREEN
// ─────────────────────────────────────────────
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with TickerProviderStateMixin {
  final WalletService _svc = WalletService.instance;

  _FilterTab _activeFilter = _FilterTab.all;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double>   _fadeIn;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    _pulse  = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return MaintenanceGuard(
      child: Scaffold(
        backgroundColor: _C.background,
        body: FadeTransition(
          opacity: _fadeIn,
          child: StreamBuilder<AppSettings>(
            stream: AppSettingsService.instance.settingsStream,
            builder: (context, settingsSnap) {
              final settings = settingsSnap.data ?? const AppSettings();
              return Column(children: [
                SizedBox(height: topPad),
                _buildAppBar(),
                _buildBalanceHero(),
                _buildApprovalNotice(),
                if (settings.walletFrozen)
                  _buildWalletFrozenBanner(settings.walletFreezeReason),
                _buildActionButtons(settings),
                const SizedBox(height: 4),
                Expanded(
                  child: _TransactionCenter(
                    svc:          _svc,
                    activeFilter: _activeFilter,
                    onFilterChanged: (f) => setState(() => _activeFilter = f),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWalletFrozenBanner(String reason) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:  _C.frozen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.frozen.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.ac_unit_rounded, color: _C.frozen, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('WALLET FROZEN', style: TextStyle(color: _C.frozen, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          Text(
            reason.isNotEmpty ? reason : 'Deposits and withdrawals are temporarily disabled.',
            style: const TextStyle(color: _C.textSecondary, fontSize: 11, height: 1.4),
          ),
        ])),
      ]),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _C.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: _C.purpleGlowFaint, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
          child: const Icon(Icons.account_balance_wallet_rounded, color: _C.purple, size: 17),
        ),
        const SizedBox(width: 10),
        Text('WALLET', style: _ts(size: 17, weight: FontWeight.w900, letterSpacing: 2)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.success.withValues(alpha: 0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PulseDot(color: _C.success, pulse: _pulse), const SizedBox(width: 5),
            Text('LIVE', style: _ts(size: 9, weight: FontWeight.w800, color: _C.success, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildApprovalNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_C.gold.withValues(alpha: 0.10), _C.purple.withValues(alpha: 0.07)], begin: Alignment.centerLeft, end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _C.gold.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.schedule_rounded, color: _C.gold, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Text('Deposits & withdrawals are processed daily between 8 PM and 8 AM.', style: _ts(size: 11, color: _C.textSecondary, height: 1.4))),
        ]),
      ),
    );
  }

  Widget _buildBalanceHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: StreamBuilder<WalletData>(
        stream: _svc.walletDataStream(),
        builder: (ctx, snap) {
          final d       = snap.data ?? WalletData.empty;
          final loading = snap.connectionState == ConnectionState.waiting;
          return AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: _C.purple.withValues(alpha: 0.18 + 0.10 * _pulse.value), blurRadius: 28 + 8 * _pulse.value)],
              ),
              child: child,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(children: [
                Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1540), Color(0xFF0D0920), _C.surface], stops: [0.0, 0.55, 1.0]))),
                Positioned.fill(child: CustomPaint(painter: _HoloPainter())),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: _C.borderBright)))),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: _C.purple, size: 16), const SizedBox(width: 7),
                      Text('WALLET BALANCE', style: _ts(size: 10, weight: FontWeight.w700, color: _C.textSecondary, letterSpacing: 1.4)),
                    ]),
                    const SizedBox(height: 10),
                    loading
                        ? _ShimmerBox(width: 180, height: 44)
                        : Text('₹${d.balance.toStringAsFixed(2)}', style: _ts(size: 38, weight: FontWeight.w900, color: _C.gold, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text('Available Balance', style: _ts(size: 11, color: _C.textMuted)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _BalanceStat(label: 'WINNINGS',  value: loading ? null : d.totalEarnings,    color: _C.gold,    icon: Icons.emoji_events_rounded)),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(label: 'DEPOSITED', value: loading ? null : d.totalDeposits,    color: _C.success, icon: Icons.add_circle_outline_rounded)),
                      Container(width: 1, height: 32, color: _C.border),
                      Expanded(child: _BalanceStat(label: 'WITHDRAWN', value: loading ? null : d.totalWithdrawals, color: _C.live,    icon: Icons.remove_circle_outline_rounded)),
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  /// PRIORITY 4: Action buttons for Deposit and Withdraw.
  /// Open bottom sheets. Replaced the old indexed section switcher.
  Widget _buildActionButtons(AppSettings settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        Expanded(
          child: _ActionButton(
            icon:    Icons.add_rounded,
            label:   'DEPOSIT',
            color:   _C.success,
            frozen:  settings.walletFrozen,
            onTap:   settings.walletFrozen ? null : () => _showDepositSheet(settings),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon:    Icons.remove_rounded,
            label:   'WITHDRAW',
            color:   _C.live,
            frozen:  settings.walletFrozen,
            onTap:   settings.walletFrozen ? null : () => _showWithdrawSheet(settings),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon:    Icons.support_agent_rounded,
            label:   'SUPPORT',
            color:   _C.discord,
            frozen:  false,
            onTap:   () => _showSupportSheet(),
          ),
        ),
      ]),
    );
  }

  void _showDepositSheet(AppSettings settings) {
    showModalBottomSheet(
      context:       context,
      isScrollControlled: true,
      backgroundColor: _C.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DepositSheet(service: _svc),
    );
  }

  void _showWithdrawSheet(AppSettings settings) {
    showModalBottomSheet(
      context:       context,
      isScrollControlled: true,
      backgroundColor: _C.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _WithdrawSheet(service: _svc),
    );
  }

  void _showSupportSheet() {
    showModalBottomSheet(
      context:       context,
      isScrollControlled: true,
      backgroundColor: _C.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _SupportSheet(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRANSACTION CENTER — PRIORITY 4
//
// Merges deposit_requests + withdraw_requests + transactions into one list.
// Sorted newest-first. Filtered by _FilterTab.
// ═════════════════════════════════════════════════════════════════════════════

class _TransactionCenter extends StatelessWidget {
  final WalletService  svc;
  final _FilterTab     activeFilter;
  final void Function(_FilterTab) onFilterChanged;

  const _TransactionCenter({
    required this.svc,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final uid = svc.currentUid;
    if (uid == null) {
      return const Center(child: Text('Not logged in.', style: TextStyle(color: _C.textMuted)));
    }

    return StreamBuilder<List<_UnifiedTx>>(
      stream: _mergedStream(uid),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting && !snap.hasData;
        final all     = snap.data ?? [];

        // Apply filter.
        final filtered = all.where(activeFilter.matches).toList();

        return Column(children: [
          // Filter chips.
          _buildFilterRow(),
          const SizedBox(height: 4),

          // Transaction list.
          Expanded(
            child: loading
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: _C.purple, strokeWidth: 2)))
                : filtered.isEmpty
                    ? _EmptyTransactions(filter: activeFilter)
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _TxRow(tx: filtered[i]),
                      ),
          ),
        ]);
      },
    );
  }

  // Merge all three subcollections into one sorted stream.
  Stream<List<_UnifiedTx>> _mergedStream(String uid) {
    final db = svc.db;

    final depositStream = db
        .collection('users').doc(uid).collection('deposit_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_UnifiedTx.fromDepositRequest).toList());

    final withdrawStream = db
        .collection('users').doc(uid).collection('withdraw_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_UnifiedTx.fromWithdrawRequest).toList());

    final txStream = db
        .collection('users').doc(uid).collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_UnifiedTx.fromTransaction).toList());

    // Combine the three streams.
    return StreamZip([depositStream, withdrawStream, txStream]).map((lists) {
      final merged = <_UnifiedTx>[];

      // Add deposit requests.
      merged.addAll(lists[0]);

      // Add withdraw requests.
      merged.addAll(lists[1]);

      // Add transactions — but de-duplicate against deposit/withdrawal requests
      // that already appear above (to avoid showing a deposit twice: once as a
      // deposit_request and once as a completed transactions/{id} entry).
      // We keep transactions that are NOT of type deposit/withdrawal
      // (entries, winnings, refunds, adjustments always show from transactions).
      // Deposits and withdrawals show from their request docs (richer status).
      for (final tx in lists[2]) {
        if (tx.category != _TxCategory.deposit &&
            tx.category != _TxCategory.withdrawal) {
          merged.add(tx);
        }
      }

      // Sort newest-first.
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return merged;
    });
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: _FilterTab.values.map((tab) {
            final active = tab == activeFilter;
            return GestureDetector(
              onTap: () => onFilterChanged(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? _C.purpleGlowFaint : _C.surfaceCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? _C.purple.withValues(alpha: 0.65) : _C.border,
                    width: active ? 1.5 : 1,
                  ),
                  boxShadow: active ? [BoxShadow(color: _C.purpleGlow.withValues(alpha: 0.4), blurRadius: 8)] : null,
                ),
                child: Text(
                  tab.label,
                  style: TextStyle(
                    color: active ? _C.purpleLight : _C.textMuted,
                    fontSize: 12, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TRANSACTION ROW — PRIORITY 4
// ─────────────────────────────────────────────
class _TxRow extends StatelessWidget {
  final _UnifiedTx tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(tx.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Row(children: [
        // Icon badge.
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: tx.iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(tx.icon, color: tx.iconColor, size: 20),
        ),
        const SizedBox(width: 12),

        // Type + description + status.
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx.typeLabel, style: _ts(size: 13, weight: FontWeight.w700)),
          if (tx.description.isNotEmpty)
            Text(tx.description, style: _ts(size: 11, color: _C.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Row(children: [
            _StatusPill(status: tx.status, color: statusColor),
            const SizedBox(width: 8),
            Text(_timeAgo(tx.createdAt), style: _ts(size: 10, color: _C.textMuted)),
          ]),
        ])),
        const SizedBox(width: 8),

        // Amount.
        Text(
          '${tx.isCredit ? '+' : '-'}₹${tx.amount.toStringAsFixed(2)}',
          style: _ts(size: 14, weight: FontWeight.w900,
              color: tx.isCredit ? _C.success : _C.live),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────
class _EmptyTransactions extends StatelessWidget {
  final _FilterTab filter;
  const _EmptyTransactions({required this.filter});

  @override
  Widget build(BuildContext context) {
    final label = filter == _FilterTab.all
        ? 'No transactions yet.\nDeposit funds to get started!'
        : 'No ${filter.label.toLowerCase()} found.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _C.purpleGlowFaint, shape: BoxShape.circle,
              border: Border.all(color: _C.border),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: _C.purple, size: 28),
          ),
          const SizedBox(height: 16),
          Text(label,
              textAlign: TextAlign.center,
              style: _ts(size: 13, color: _C.textSecondary, height: 1.5)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ACTION BUTTON
// ─────────────────────────────────────────────
class _ActionButton extends StatefulWidget {
  final IconData icon; final String label; final Color color;
  final bool frozen; final VoidCallback? onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.frozen, this.onTap});
  @override State<_ActionButton> createState() => _ActionButtonState();
}
class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) { if (!disabled) _ctrl.forward(); },
      onTapUp:   (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: disabled ? _C.surfaceCard : widget.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled ? _C.border : widget.color.withValues(alpha: 0.55),
            width: disabled ? 1 : 1.5,
          ),
          boxShadow: disabled ? [] : [BoxShadow(color: widget.color.withValues(alpha: 0.25), blurRadius: 12)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, color: disabled ? _C.textMuted : widget.color, size: 20),
          const SizedBox(height: 5),
          Text(widget.label, style: _ts(size: 10, weight: FontWeight.w700, color: disabled ? _C.textMuted : widget.color, letterSpacing: 0.4)),
        ]),
      )),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DEPOSIT BOTTOM SHEET
// (Full form preserved from F1 DepositSection, adapted as modal sheet)
// ═════════════════════════════════════════════════════════════════════════════

class _DepositSheet extends StatefulWidget {
  final WalletService service;
  const _DepositSheet({required this.service});
  @override State<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<_DepositSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _utrCtrl    = TextEditingController();
  bool    _loading     = false;
  String? _error;
  bool    _success     = false;
  bool    _paymentDone = false;
  String  _upiLink     = '';

  final _quick = [100, 250, 500, 1000, 2500, 5000];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    setState(() { _upiLink = (amount != null && amount >= 50) ? buildUpiDeepLink(amount) : ''; });
  }

  @override
  void dispose() { _amountCtrl.dispose(); _utrCtrl.dispose(); super.dispose(); }

  Future<void> _launchUpi() async {
    if (_upiLink.isEmpty) return;
    final launched = await launchUrl(Uri.parse(_upiLink), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No UPI app found.'), backgroundColor: _C.live));
    } else {
      setState(() => _paymentDone = true);
    }
  }

  Future<void> _launch(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitDepositRequest(
        amount: double.parse(_amountCtrl.text.trim()),
        utr:    _utrCtrl.text.trim(),
      );
      setState(() { _success = true; _loading = false; _paymentDone = false; });
      _amountCtrl.clear(); _utrCtrl.clear();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount    = double.tryParse(_amountCtrl.text.trim());
    final hasAmount = amount != null && amount >= 50;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Column(children: [
        // Handle.
        Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4,
            decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),

        // Header.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.add_circle_rounded, color: _C.success, size: 20),
            const SizedBox(width: 10),
            Text('DEPOSIT FUNDS', style: _ts(size: 16, weight: FontWeight.w900, letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: _C.textMuted, size: 22)),
          ]),
        ),
        const SizedBox(height: 14),
        Divider(color: _C.border, height: 1),

        Expanded(child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            controller: scrollCtrl,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 40 + bottomPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StepBadge(number: '1', label: 'ENTER DEPOSIT AMOUNT'),
              const SizedBox(height: 10),
              _StyledField(
                controller: _amountCtrl, hint: 'Enter deposit amount',
                keyboardType: TextInputType.number, prefixText: '₹ ',
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  if (n < 50) return 'Minimum deposit is ₹50';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _quick.map((a) {
                final sel = _amountCtrl.text == a.toString();
                return GestureDetector(
                  onTap: () => setState(() => _amountCtrl.text = a.toString()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? _C.purpleGlowFaint : _C.surfaceCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? _C.purple : _C.border, width: sel ? 1.5 : 1),
                    ),
                    child: Text('₹$a', style: _ts(size: 12, weight: FontWeight.w700, color: sel ? _C.purpleLight : _C.textSecondary)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 22),
              _StepBadge(number: '2', label: 'SCAN QR OR PAY WITH UPI APP'),
              const SizedBox(height: 10),
              _UpiPayCard(upiLink: _upiLink, hasAmount: hasAmount, amount: amount, onPayTap: _launchUpi),
              const SizedBox(height: 22),
              AnimatedOpacity(
                opacity: _paymentDone ? 1.0 : 0.45,
                duration: const Duration(milliseconds: 300),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _StepBadge(number: '3', label: 'ENTER YOUR UTR NUMBER'),
                  const SizedBox(height: 10),
                  _paymentDone
                      ? _InfoBanner(icon: Icons.check_circle_outline_rounded, color: _C.success, text: 'Payment initiated. Enter your UTR to complete the request.')
                      : _InfoBanner(icon: Icons.info_outline_rounded, color: _C.purple, text: 'Complete UPI payment first, then enter your UTR to submit.'),
                  const SizedBox(height: 12),
                  _StyledField(
                    controller: _utrCtrl, hint: 'Paste your UTR / Transaction ID',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'UTR is required';
                      if (v.trim().length < 6) return 'Invalid UTR number';
                      return null;
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              _FieldLabel('SEND SCREENSHOT FOR FASTER APPROVAL'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _SupportButton(label: 'Discord', sublabel: '@mastersenpai1', color: _C.discord, icon: Icons.forum_rounded, onTap: () => _launch('https://discord.gg/2eUqD7wtBR'))),
                const SizedBox(width: 10),
                Expanded(child: _SupportButton(label: 'Telegram', sublabel: '@Anonymaster_a', color: _C.telegram, icon: Icons.send_rounded, onTap: () => _launch('https://t.me/Anonymaster_a'))),
              ]),
              const SizedBox(height: 18),
              if (_error   != null) _StatusBanner(text: _error!, isError: true),
              if (_success)         _StatusBanner(text: '✅ Deposit request submitted! Pending admin approval. Approvals: 8 PM – 8 AM.', isError: false),
              const SizedBox(height: 4),
              _GlowButton(label: _loading ? 'SUBMITTING…' : 'SUBMIT DEPOSIT REQUEST', icon: Icons.upload_rounded, onTap: _loading ? null : _submit),
            ]),
          ),
        )),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WITHDRAW BOTTOM SHEET
// (Full form preserved from F1 WithdrawSection, adapted as modal sheet)
// ═════════════════════════════════════════════════════════════════════════════

class _WithdrawSheet extends StatefulWidget {
  final WalletService service;
  const _WithdrawSheet({required this.service});
  @override State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _formKey     = GlobalKey<FormState>();
  final _amountCtrl  = TextEditingController();
  final _upiCtrl     = TextEditingController();
  final _holderCtrl  = TextEditingController();
  final _bankCtrl    = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl    = TextEditingController();
  String  _method    = 'upi';
  bool    _loading   = false;
  String? _error;
  bool    _success   = false;
  double  _liveBalance = 0.0;

  @override
  void initState() { super.initState(); _amountCtrl.addListener(() => setState(() {})); }
  @override
  void dispose() {
    for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _enteredAmount => double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
  bool get _exceedsBalance  => _enteredAmount > 0 && _enteredAmount > _liveBalance;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_exceedsBalance) return;
    setState(() { _loading = true; _error = null; _success = false; });
    try {
      await widget.service.submitWithdrawRequest(
        amount: _enteredAmount, method: _method,
        upiId: _upiCtrl.text.trim(), accountHolder: _holderCtrl.text.trim(),
        bankName: _bankCtrl.text.trim(), accountNumber: _accountCtrl.text.trim(),
        ifscCode: _ifscCtrl.text.trim(),
      );
      setState(() { _success = true; _loading = false; });
      for (final c in [_amountCtrl, _upiCtrl, _holderCtrl, _bankCtrl, _accountCtrl, _ifscCtrl]) {
        c.clear();
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => StreamBuilder<WalletData>(
        stream: widget.service.walletDataStream(),
        builder: (ctx, snap) {
          _liveBalance = snap.data?.balance ?? 0.0;
          return Column(children: [
            Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4,
                decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.remove_circle_rounded, color: _C.live, size: 20),
                const SizedBox(width: 10),
                Text('WITHDRAW FUNDS', style: _ts(size: 16, weight: FontWeight.w900, letterSpacing: 1.5)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: _C.textMuted, size: 22)),
              ]),
            ),
            const SizedBox(height: 14),
            Divider(color: _C.border, height: 1),
            Expanded(child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: scrollCtrl,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 16, 16, 40 + bottomPad),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _LiveBalanceChip(balance: _liveBalance),
                  const SizedBox(height: 16),
                  _InfoBanner(icon: Icons.schedule_rounded, color: _C.gold, text: 'Withdrawals processed within 24 hours after admin approval. Approvals: 8 PM – 8 AM.'),
                  const SizedBox(height: 18),
                  _FieldLabel('WITHDRAW AMOUNT  (₹)'),
                  _StyledField(
                    controller: _amountCtrl, hint: 'Enter amount',
                    keyboardType: TextInputType.number, prefixText: '₹ ',
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      if (n < 100) return 'Minimum withdrawal is ₹100';
                      if (n > _liveBalance) return 'Amount exceeds balance (₹${_liveBalance.toStringAsFixed(2)})';
                      return null;
                    },
                  ),
                  if (_exceedsBalance) ...[
                    const SizedBox(height: 10),
                    _InsufficientBanner(available: _liveBalance, requested: _enteredAmount),
                  ],
                  const SizedBox(height: 18),
                  _FieldLabel('WITHDRAWAL METHOD'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _MethodToggle(label: '📱  UPI',          active: _method == 'upi',  onTap: () => setState(() => _method = 'upi'))),
                    const SizedBox(width: 10),
                    Expanded(child: _MethodToggle(label: '🏦  Bank Transfer', active: _method == 'bank', onTap: () => setState(() => _method = 'bank'))),
                  ]),
                  const SizedBox(height: 18),
                  if (_method == 'upi') ...[
                    _FieldLabel('UPI ID'),
                    _StyledField(controller: _upiCtrl, hint: 'yourname@bank',
                        validator: (v) { if (v == null || v.trim().isEmpty) return 'UPI ID is required'; if (!v.contains('@')) return 'Invalid UPI ID format'; return null; }),
                    const SizedBox(height: 14),
                    _FieldLabel('ACCOUNT HOLDER NAME'),
                    _StyledField(controller: _holderCtrl, hint: 'Full name as registered',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
                  ],
                  if (_method == 'bank') ...[
                    _FieldLabel('ACCOUNT HOLDER NAME'),
                    _StyledField(controller: _holderCtrl, hint: 'Full name as on bank account',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
                    const SizedBox(height: 14),
                    _FieldLabel('BANK NAME'),
                    _StyledField(controller: _bankCtrl, hint: 'e.g. State Bank of India',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank name is required' : null),
                    const SizedBox(height: 14),
                    _FieldLabel('ACCOUNT NUMBER'),
                    _StyledField(controller: _accountCtrl, hint: 'Enter account number', keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) { if (v == null || v.trim().isEmpty) return 'Required'; if (v.trim().length < 8) return 'Invalid account number'; return null; }),
                    const SizedBox(height: 14),
                    _FieldLabel('IFSC CODE'),
                    _StyledField(controller: _ifscCtrl, hint: 'e.g. SBIN0001234',
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) { if (v == null || v.trim().isEmpty) return 'Required'; if (v.trim().length != 11) return 'IFSC must be 11 characters'; return null; }),
                  ],
                  const SizedBox(height: 18),
                  if (_error   != null) _StatusBanner(text: _error!, isError: true),
                  if (_success)         _StatusBanner(text: '✅ Withdrawal submitted! Processing within 24 hours after admin approval.', isError: false),
                  const SizedBox(height: 4),
                  _GlowButton(
                    label: _loading ? 'SUBMITTING…' : 'SUBMIT WITHDRAWAL',
                    icon:  Icons.arrow_upward_rounded,
                    color: _exceedsBalance ? _C.textMuted : _C.live,
                    onTap: (_loading || _exceedsBalance) ? null : _submit,
                  ),
                ]),
              ),
            )),
          ]);
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORT BOTTOM SHEET (unchanged from F1 SupportSection)
// ═════════════════════════════════════════════════════════════════════════════

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

  Future<void> _launch(BuildContext ctx, String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Could not open: $url'), backgroundColor: _C.live));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Column(children: [
        Container(margin: const EdgeInsets.only(top: 12, bottom: 8), width: 40, height: 4,
            decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Icon(Icons.support_agent_rounded, color: _C.discord, size: 20),
            const SizedBox(width: 10),
            Text('SUPPORT', style: _ts(size: 16, weight: FontWeight.w900, letterSpacing: 1.5)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close_rounded, color: _C.textMuted, size: 22)),
          ]),
        ),
        const SizedBox(height: 14),
        Divider(color: _C.border, height: 1),
        Expanded(child: SingleChildScrollView(
          controller: scrollCtrl,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _InfoBanner(icon: Icons.support_agent_rounded, color: _C.purple, text: 'Contact our support team on Discord or Telegram. We respond within 30 minutes.'),
            const SizedBox(height: 20),
            _PremiumSupportCard(platform: 'DISCORD', name: '! SHADOW', handle: '@mastersenpai1', serverLabel: 'Shadow Storm Community', color: _C.discord, icon: Icons.forum_rounded, badge: 'MAIN SUPPORT', onTap: () => _launch(context, 'https://discord.gg/2eUqD7wtBR')),
            const SizedBox(height: 12),
            _PremiumSupportCard(platform: 'TELEGRAM', name: 'Anonymaster', handle: '@Anonymaster_a', serverLabel: 'Direct message for fast support', color: _C.telegram, icon: Icons.send_rounded, badge: 'QUICK RESPONSE', onTap: () => _launch(context, 'https://t.me/Anonymaster_a')),
            const SizedBox(height: 24),
            Text('COMMON ISSUES', style: _ts(size: 10, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 1.4)),
            const SizedBox(height: 12),
            ...[
              ('My deposit is pending for too long?', 'Contact support with your UTR. Approvals happen daily 8 PM – 8 AM.'),
              ('Withdrawal not received?', 'Withdrawals take up to 24 hours. Contact support with your request ID.'),
              ('Wrong UTR submitted?', 'Message support immediately with the correct UTR.'),
              ('Balance not updated after winning?', 'Winnings are credited within 30 minutes of tournament end.'),
            ].map((pair) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _FaqCard(question: pair.$1, answer: pair.$2))),
          ]),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// ALL REUSABLE ATOMS (preserved from F1)
// ─────────────────────────────────────────────

class _StepBadge extends StatelessWidget {
  final String number, label;
  const _StepBadge({required this.number, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 24, height: 24, decoration: BoxDecoration(color: _C.purple, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _C.purpleGlow, blurRadius: 8)]), child: Center(child: Text(number, style: _ts(size: 11, weight: FontWeight.w900, color: Colors.white)))),
      const SizedBox(width: 8),
      Text(label, style: _ts(size: 10, weight: FontWeight.w800, color: _C.textSecondary, letterSpacing: 1.2)),
    ]);
  }
}

class _InsufficientBanner extends StatelessWidget {
  final double available, requested;
  const _InsufficientBanner({required this.available, required this.requested});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.live.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.live.withValues(alpha: 0.45))),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _C.live, size: 16), const SizedBox(width: 8),
        Expanded(child: Text('Trying to withdraw ₹${requested.toStringAsFixed(2)} but balance is ₹${available.toStringAsFixed(2)}.', style: _ts(size: 11, color: _C.textSecondary))),
      ]),
    );
  }
}

class _LiveBalanceChip extends StatelessWidget {
  final double balance;
  const _LiveBalanceChip({required this.balance});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: _C.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.success.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_rounded, color: _C.success, size: 16), const SizedBox(width: 10),
        Text('Available Balance:', style: _ts(size: 12, color: _C.textSecondary)), const Spacer(),
        Text('₹${balance.toStringAsFixed(2)}', style: _ts(size: 15, weight: FontWeight.w900, color: _C.success)),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status; final Color color;
  const _StatusPill({required this.status, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(status.toUpperCase(), style: _ts(size: 9, weight: FontWeight.w800, color: color, letterSpacing: 0.8)),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label; final double? value; final Color color; final IconData icon;
  const _BalanceStat({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13), const SizedBox(height: 4),
      value == null ? _ShimmerBox(width: 50, height: 14) : Text('₹${value!.toStringAsFixed(0)}', style: _ts(size: 12, weight: FontWeight.w800, color: color), overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(label, style: _ts(size: 8, weight: FontWeight.w700, color: _C.textMuted, letterSpacing: 0.8)),
    ]);
  }
}

class _UpiPayCard extends StatelessWidget {
  final String upiLink; final bool hasAmount; final double? amount; final VoidCallback onPayTap;
  const _UpiPayCard({required this.upiLink, required this.hasAmount, required this.amount, required this.onPayTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _C.surfaceCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.gold.withValues(alpha: 0.35)), boxShadow: [BoxShadow(color: _C.goldGlow.withValues(alpha: 0.15), blurRadius: 20)]),
      child: Column(children: [
        Text('PAY TO THIS UPI', style: _ts(size: 9, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 1.4)),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: hasAmount && upiLink.isNotEmpty
              ? Container(key: ValueKey(upiLink), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: _C.gold.withValues(alpha: 0.25), blurRadius: 16)]),
                  child: QrImageView(data: upiLink, version: QrVersions.auto, size: 150, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M))
              : Container(key: const ValueKey('ph'), width: 150, height: 150, decoration: BoxDecoration(color: _C.surfaceElevated, borderRadius: BorderRadius.circular(14), border: Border.all(color: _C.border.withValues(alpha: 0.5))),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.qr_code_2_rounded, color: _C.textMuted, size: 40), const SizedBox(height: 8), Text('Enter amount\nto generate QR', style: _ts(size: 11, color: _C.textMuted, height: 1.5), textAlign: TextAlign.center)])),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _C.gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.gold.withValues(alpha: 0.25))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.account_balance_rounded, color: _C.gold, size: 15), const SizedBox(width: 8), Text(upiId, style: _ts(size: 14, weight: FontWeight.w900, color: _C.gold))]),
        ),
        if (amount != null && amount! > 0) ...[const SizedBox(height: 6), Text('Amount: ₹${amount!.toStringAsFixed(2)}', style: _ts(size: 12, color: _C.textSecondary, weight: FontWeight.w600))],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: hasAmount ? onPayTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: hasAmount
                  ? const LinearGradient(colors: [Color(0xFF9D55FF), Color(0xFF5865F2)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : LinearGradient(colors: [_C.surfaceElevated, _C.surfaceElevated]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: hasAmount ? [BoxShadow(color: _C.purple.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))] : [],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.payment_rounded, color: hasAmount ? Colors.white : _C.textMuted, size: 18), const SizedBox(width: 8),
              Text('PAY WITH UPI', style: _ts(size: 13, weight: FontWeight.w900, letterSpacing: 1.2, color: hasAmount ? Colors.white : _C.textMuted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PremiumSupportCard extends StatefulWidget {
  final String platform, name, handle, serverLabel, badge; final Color color; final IconData icon; final VoidCallback onTap;
  const _PremiumSupportCard({required this.platform, required this.name, required this.handle, required this.serverLabel, required this.color, required this.icon, required this.badge, required this.onTap});
  @override State<_PremiumSupportCard> createState() => _PremiumSupportCardState();
}
class _PremiumSupportCardState extends State<_PremiumSupportCard> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: widget.color.withValues(alpha: 0.4)), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 4))]),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.color.withValues(alpha: 0.4))), child: Icon(widget.icon, color: widget.color, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(widget.platform, style: _ts(size: 13, weight: FontWeight.w900, color: widget.color, letterSpacing: 1)),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), child: Text(widget.badge, style: _ts(size: 8, weight: FontWeight.w800, color: widget.color, letterSpacing: 0.8))),
            ]),
            const SizedBox(height: 3),
            Text(widget.name, style: _ts(size: 14, weight: FontWeight.w800)),
            Text(widget.handle, style: _ts(size: 11, color: _C.textMuted)),
            const SizedBox(height: 2),
            Text(widget.serverLabel, style: _ts(size: 10, color: _C.textSecondary)),
          ])),
          Icon(Icons.open_in_new_rounded, color: widget.color.withValues(alpha: 0.7), size: 18),
        ]),
      )),
    );
  }
}

class _FaqCard extends StatefulWidget {
  final String question, answer;
  const _FaqCard({required this.question, required this.answer});
  @override State<_FaqCard> createState() => _FaqCardState();
}
class _FaqCardState extends State<_FaqCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _open ? _C.purpleGlowFaint : _C.surfaceCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: _open ? _C.purple.withValues(alpha: 0.4) : _C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.question, style: _ts(size: 12, weight: FontWeight.w700))),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _C.textMuted, size: 18),
          ]),
          if (_open) ...[const SizedBox(height: 8), Text(widget.answer, style: _ts(size: 11, color: _C.textSecondary, height: 1.5))],
        ]),
      ),
    );
  }
}

class _GlowButton extends StatefulWidget {
  final String label; final IconData icon; final Color color; final VoidCallback? onTap;
  const _GlowButton({required this.label, required this.icon, this.color = _C.purple, this.onTap});
  @override State<_GlowButton> createState() => _GlowButtonState();
}
class _GlowButtonState extends State<_GlowButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.97).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      onTapDown: (_) { if (!disabled) _ctrl.forward(); },
      onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: disabled ? [_C.surfaceElevated, _C.surfaceElevated] : [widget.color, widget.color.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled ? [] : [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon, color: disabled ? _C.textMuted : Colors.white, size: 18), const SizedBox(width: 10),
          Text(widget.label, style: _ts(size: 13, weight: FontWeight.w900, letterSpacing: 1.2, color: disabled ? _C.textMuted : Colors.white)),
        ]),
      )),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _MethodToggle({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: active ? _C.purpleGlowFaint : _C.surfaceCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? _C.purple : _C.border, width: active ? 1.5 : 1), boxShadow: active ? [BoxShadow(color: _C.purpleGlow.withValues(alpha: 0.4), blurRadius: 10)] : []),
        child: Center(child: Text(label, style: _ts(size: 13, weight: FontWeight.w700, color: active ? _C.purpleLight : _C.textSecondary))),
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller; final String hint; final TextInputType keyboardType; final String? prefixText; final List<TextInputFormatter>? inputFormatters; final String? Function(String?)? validator; final TextCapitalization textCapitalization;
  const _StyledField({required this.controller, required this.hint, this.keyboardType = TextInputType.text, this.prefixText, this.inputFormatters, this.validator, this.textCapitalization = TextCapitalization.none});
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, inputFormatters: inputFormatters,
      validator: validator, textCapitalization: textCapitalization,
      style: _ts(size: 14, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, prefixText: prefixText,
        hintStyle: _ts(size: 13, color: _C.textMuted),
        prefixStyle: _ts(size: 14, weight: FontWeight.w700, color: _C.textSecondary),
        filled: true, fillColor: _C.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.purple, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.live)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.live, width: 1.5)),
        errorStyle: _ts(size: 11, color: _C.live),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: _ts(size: 10, weight: FontWeight.w800, color: _C.textMuted, letterSpacing: 1.2)));
}

class _SupportButton extends StatefulWidget {
  final String label, sublabel; final Color color; final IconData icon; final VoidCallback onTap;
  const _SupportButton({required this.label, required this.sublabel, required this.color, required this.icon, required this.onTap});
  @override State<_SupportButton> createState() => _SupportButtonState();
}
class _SupportButtonState extends State<_SupportButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); _scale = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.color.withValues(alpha: 0.45)), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.icon, color: widget.color, size: 18), const SizedBox(width: 6),
            Expanded(child: Text(widget.label, style: _ts(size: 12, weight: FontWeight.w800, color: widget.color), overflow: TextOverflow.ellipsis)),
            Icon(Icons.open_in_new_rounded, color: widget.color.withValues(alpha: 0.6), size: 13),
          ]),
          const SizedBox(height: 4),
          Text(widget.sublabel, style: _ts(size: 10, color: _C.textMuted), overflow: TextOverflow.ellipsis),
        ]),
      )),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _InfoBanner({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 10),
        Expanded(child: Text(text, style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text; final bool isError;
  const _StatusBanner({required this.text, required this.isError});
  @override
  Widget build(BuildContext context) {
    final color = isError ? _C.live : _C.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: color, size: 17), const SizedBox(width: 10),
        Expanded(child: Text(text, style: _ts(size: 12, color: _C.textSecondary))),
      ]),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color color; final Animation<double> pulse;
  const _PulseDot({required this.color, required this.pulse});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: pulse, builder: (_, _) => Container(
      width: 6, height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.5 + 0.5 * pulse.value), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5 * pulse.value)]),
    ));
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  const _ShimmerBox({required this.width, required this.height});
  @override State<_ShimmerBox> createState() => _ShimmerBoxState();
}
class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true); _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _anim, builder: (_, _) => Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(color: _C.surfaceElevated.withValues(alpha: 0.5 + 0.4 * _anim.value), borderRadius: BorderRadius.circular(8)),
    ));
  }
}

class _HoloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF9D55FF).withValues(alpha: 0.04)..strokeWidth = 1;
    for (var i = 0; i < 8; i++) { final y = size.height * i / 7; canvas.drawLine(Offset(0, y), Offset(size.width, y), paint); }
    final diag = Paint()..color = const Color(0xFFB07EF8).withValues(alpha: 0.05)..strokeWidth = 0.5;
    for (var i = 0; i < 6; i++) { final x = size.width * (0.5 + i * 0.12); canvas.drawLine(Offset(x, 0), Offset(x - size.height * 0.6, size.height), diag); }
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────
// StreamZip helper — combines multiple streams
// into a stream of lists (one item per source stream).
// ─────────────────────────────────────────────
class StreamZip<T> extends Stream<List<T>> {
  final List<Stream<T>> _streams;
  const StreamZip(this._streams);

  @override
  StreamSubscription<List<T>> listen(
    void Function(List<T>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final latest   = List<T?>.filled(_streams.length, null);
    final hasValue = List<bool>.filled(_streams.length, false);
    final subs     = <StreamSubscription<T>>[];
    late StreamController<List<T>> ctrl;

    ctrl = StreamController<List<T>>(
      onCancel: () { for (final s in subs) {
        s.cancel();
      } },
    );

    for (var i = 0; i < _streams.length; i++) {
      final idx = i;
      subs.add(_streams[idx].listen(
        (value) {
          latest[idx]   = value;
          hasValue[idx] = true;
          if (hasValue.every((v) => v)) {
            ctrl.add(List<T>.from(latest.map((v) => v as T)));
          }
        },
        onError: ctrl.addError,
      ));
    }

    return ctrl.stream.listen(
      onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError,
    );
  }
}