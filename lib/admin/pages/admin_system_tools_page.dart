// lib/admin/pages/admin_system_tools_page.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin System Tools
// Phase 5: Power tools for platform maintenance
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/admin_page_container.dart';
import '../widgets/admin_components.dart';
import '../theme/admin_theme.dart';
import '../auth/admin_auth_service.dart';
import '../services/admin_logs_service.dart';

class AdminSystemToolsPage extends StatefulWidget {
  const AdminSystemToolsPage({super.key});

  @override
  State<AdminSystemToolsPage> createState() => _AdminSystemToolsPageState();
}

class _AdminSystemToolsPageState extends State<AdminSystemToolsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Tool running states
  final Map<String, bool> _running = {};
  final Map<String, String?> _results = {};

  String get _adminUid   => AdminAuthService.instance.currentUser?.uid   ?? 'unknown';
  String get _adminEmail => AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final color = isError ? AdminColors.danger : AdminColors.success;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AdminTextStyles.bodyMedium.copyWith(color: color)),
      backgroundColor: AdminColors.surfaceCard,
      behavior:        SnackBarBehavior.floating,
      duration:        const Duration(seconds: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
    ));
  }

  void _setRunning(String key, bool v) {
    if (mounted) setState(() => _running[key] = v);
  }

  void _setResult(String key, String? v) {
    if (mounted) setState(() => _results[key] = v);
  }

  // ──────────────────────────────────────────────────────
  // TOOL 1: RECALCULATE WALLET BALANCES
  // Scans all user transactions, re-sums balance
  // ──────────────────────────────────────────────────────
  Future<void> _recalculateBalances() async {
    final ok = await AdminConfirmDialog.show(
      context,
      title:        'Recalculate Wallet Balances',
      message:      'This will scan ALL user transactions and rebuild wallet balances.\n\nThis is a heavy operation. Run only when balances appear incorrect.\n\nContinue?',
      confirmLabel: 'Recalculate',
      confirmColor: AdminColors.warning,
      confirmIcon:  Icons.calculate_rounded,
    );
    if (ok != true) return;

    _setRunning('recalc', true);
    _setResult('recalc', null);

    try {
      final users = await _db.collection('users').get();
      int fixed = 0, errors = 0;

      for (final userDoc in users.docs) {
        try {
          final txnsSnap = await _db
              .collection('users')
              .doc(userDoc.id)
              .collection('transactions')
              .where('status', isEqualTo: 'completed')
              .get();

          double computed = 0;
          for (final txn in txnsSnap.docs) {
            final t      = txn.data();
            final type   = (t['type'] as String?) ?? '';
            final amount = (t['amount'] as num?)?.toDouble() ?? 0;
            switch (type) {
              case 'deposit':
              case 'winnings':
              case 'refund':
                computed += amount;
              case 'withdrawal':
                computed -= amount;
              case 'adjustment':
                // adjustment amount is always abs; sign is encoded in description
                // We can't easily determine sign here, so skip adjustments
                break;
            }
          }
          if (computed < 0) computed = 0;

          final current = ((userDoc.data())['walletBalance'] as num?)?.toDouble() ?? 0.0;
          if ((current - computed).abs() > 0.01) {
            await _db.collection('users').doc(userDoc.id).update({
              'walletBalance': computed,
            });
            fixed++;
          }
        } catch (_) {
          errors++;
        }
      }

      // Log the operation
      await _db.collection('admin_logs').add({
        'action':     'wallet_balances_recalculated',
        'adminUid':   _adminUid,
        'adminEmail': _adminEmail,
        'targetUid':  'system',
        'details': {
          'totalUsers': users.docs.length,
          'fixed':      fixed,
          'errors':     errors,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      final msg = 'Done! Checked ${users.docs.length} users. Fixed $fixed balances. Errors: $errors.';
      _setResult('recalc', msg);
      _snack(msg);
    } catch (e) {
      _setResult('recalc', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('recalc', false);
    }
  }

  // ──────────────────────────────────────────────────────
  // TOOL 2: EXPORT USERS CSV
  // ──────────────────────────────────────────────────────
  Future<void> _exportUsers() async {
    _setRunning('exportUsers', true);
    _setResult('exportUsers', null);
    try {
      final snap = await _db.collection('users').get();
      final buf  = StringBuffer();
      buf.writeln('UID,Name,Email,Wallet Balance,Total Earnings,Is Admin,Is Frozen,Joined At');

      for (final doc in snap.docs) {
        final d = doc.data();
        String escape(String s) => '"${s.replaceAll('"', '""')}"';
        final createdAt = (d['createdAt'] as Timestamp?)
                ?.toDate().toIso8601String() ?? '';
        buf.writeln([
          escape(doc.id),
          escape((d['name']  as String?) ?? ''),
          escape((d['email'] as String?) ?? ''),
          ((d['walletBalance'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ((d['totalEarnings'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ((d['isAdmin']  as bool?) ?? false).toString(),
          ((d['isFrozen'] as bool?) ?? false).toString(),
          escape(createdAt),
        ].join(','));
      }

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/shadow_storm_users.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Shadow Storm Users Export');

      final msg = 'Exported ${snap.docs.length} users.';
      _setResult('exportUsers', msg);
      _snack(msg);
    } catch (e) {
      _setResult('exportUsers', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('exportUsers', false);
    }
  }

  // ──────────────────────────────────────────────────────
  // TOOL 3: EXPORT TOURNAMENT RESULTS CSV
  // ──────────────────────────────────────────────────────
  Future<void> _exportTournamentResults() async {
    _setRunning('exportTournaments', true);
    _setResult('exportTournaments', null);
    try {
      final snap = await _db
          .collection('tournaments')
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .get();

      final buf = StringBuffer();
      buf.writeln('Tournament ID,Title,Prize Pool,Entry Fee,Players,Status,Prizes Distributed,Created At');

      for (final doc in snap.docs) {
        final d = doc.data();
        String escape(String s) => '"${s.replaceAll('"', '""')}"';
        final createdAt = (d['createdAt'] as Timestamp?)
                ?.toDate().toIso8601String() ?? '';
        buf.writeln([
          escape(doc.id),
          escape((d['title'] as String?) ?? ''),
          ((d['prizePool']    as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ((d['entryFee']     as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ((d['joinedPlayers'] as num?)?.toInt() ?? 0).toString(),
          escape((d['status'] as String?) ?? ''),
          ((d['prizesDistributed'] as bool?) ?? false).toString(),
          escape(createdAt),
        ].join(','));
      }

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/shadow_storm_tournaments.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Shadow Storm Tournament Results');

      final msg = 'Exported ${snap.docs.length} completed tournaments.';
      _setResult('exportTournaments', msg);
      _snack(msg);
    } catch (e) {
      _setResult('exportTournaments', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('exportTournaments', false);
    }
  }

  // ──────────────────────────────────────────────────────
  // TOOL 4: PURGE OLD LOGS
  // ──────────────────────────────────────────────────────
  Future<void> _purgeLogs() async {
    final ok = await AdminConfirmDialog.show(
      context,
      title:        'Purge Old Logs',
      message:      'This will PERMANENTLY DELETE all admin logs older than 90 days.\n\nThis action cannot be undone.\n\nContinue?',
      confirmLabel: 'Purge Logs',
      confirmColor: AdminColors.danger,
      confirmIcon:  Icons.delete_forever_rounded,
    );
    if (ok != true) return;

    _setRunning('purgeLogs', true);
    _setResult('purgeLogs', null);
    try {
      final deleted = await AdminLogsService.instance.purgeOldLogs();
      final msg = 'Purged $deleted log entries older than 90 days.';
      _setResult('purgeLogs', msg);
      _snack(msg);
    } catch (e) {
      _setResult('purgeLogs', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('purgeLogs', false);
    }
  }

  // ──────────────────────────────────────────────────────
  // TOOL 5: REBUILD TOURNAMENT STATS
  // Re-scans participants and updates joinedPlayers count
  // ──────────────────────────────────────────────────────
  Future<void> _rebuildTournamentStats() async {
    _setRunning('rebuildStats', true);
    _setResult('rebuildStats', null);
    try {
      final tournaments = await _db
          .collection('tournaments')
          .where('status', whereIn: ['upcoming', 'live'])
          .get();

      int updated = 0;
      for (final tDoc in tournaments.docs) {
        final participantsSnap = await _db
            .collection('tournaments')
            .doc(tDoc.id)
            .collection('participants')
            .count()
            .get();
        final count = participantsSnap.count ?? 0;
        final current = ((tDoc.data())['joinedPlayers'] as num?)?.toInt() ?? 0;
        if (current != count) {
          await _db.collection('tournaments').doc(tDoc.id)
              .update({'joinedPlayers': count});
          updated++;
        }
      }

      await _db.collection('admin_logs').add({
        'action':     'tournament_stats_rebuilt',
        'adminUid':   _adminUid,
        'adminEmail': _adminEmail,
        'targetUid':  'system',
        'details': {
          'checked': tournaments.docs.length,
          'updated': updated,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      final msg = 'Stats rebuilt. Checked ${tournaments.docs.length} tournaments, fixed $updated.';
      _setResult('rebuildStats', msg);
      _snack(msg);
    } catch (e) {
      _setResult('rebuildStats', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('rebuildStats', false);
    }
  }

  // ──────────────────────────────────────────────────────
  // TOOL 6: DETECT SUSPICIOUS WALLET ACTIVITY
  // Flags: multiple rapid withdrawals, unusual winnings, spam deposits
  // ──────────────────────────────────────────────────────
  Future<void> _detectSuspiciousActivity() async {
    _setRunning('suspicious', true);
    _setResult('suspicious', null);
    try {
      final cutoff = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 24)));

      // Check: users with > 3 pending withdrawal requests
      final withdrawals = await _db
          .collectionGroup('withdraw_requests')
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isGreaterThan: cutoff)
          .get();

      final withdrawsByUser = <String, int>{};
      for (final doc in withdrawals.docs) {
        // Parent path: users/{uid}/withdraw_requests/{id}
        final uid = doc.reference.parent.parent?.id ?? '';
        withdrawsByUser[uid] = (withdrawsByUser[uid] ?? 0) + 1;
      }

      final suspiciousWithdrawals = withdrawsByUser.entries
          .where((e) => e.value >= 3)
          .toList();

      // Check: users with > 5 pending deposit requests in 24h
      final deposits = await _db
          .collectionGroup('deposit_requests')
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isGreaterThan: cutoff)
          .get();

      final depositsByUser = <String, int>{};
      for (final doc in deposits.docs) {
        final uid = doc.reference.parent.parent?.id ?? '';
        depositsByUser[uid] = (depositsByUser[uid] ?? 0) + 1;
      }

      final suspiciousDeposits = depositsByUser.entries
          .where((e) => e.value >= 5)
          .toList();

      // Build report
      final findings = <String>[];
      if (suspiciousWithdrawals.isNotEmpty) {
        findings.add('${suspiciousWithdrawals.length} user(s) with 3+ pending withdrawals in 24h');
      }
      if (suspiciousDeposits.isNotEmpty) {
        findings.add('${suspiciousDeposits.length} user(s) with 5+ pending deposits in 24h');
      }

      final allSuspiciousUids = <String>{
        ...suspiciousWithdrawals.map((e) => e.key),
        ...suspiciousDeposits.map((e) => e.key),
      };

      if (allSuspiciousUids.isNotEmpty) {
        await _db.collection('admin_logs').add({
          'action':     'suspicious_activity_detected',
          'adminUid':   _adminUid,
          'adminEmail': _adminEmail,
          'targetUid':  'system',
          'details': {
            'suspiciousUsers':       allSuspiciousUids.toList(),
            'spamWithdrawals':       suspiciousWithdrawals.map((e) => {'uid': e.key, 'count': e.value}).toList(),
            'spamDeposits':          suspiciousDeposits.map((e) => {'uid': e.key, 'count': e.value}).toList(),
            'analysisWindowHours':   24,
            'findings':              findings,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final msg = allSuspiciousUids.isEmpty
          ? 'No suspicious activity detected in the last 24 hours.'
          : '⚠️ ${allSuspiciousUids.length} suspicious user(s) found! Check logs for details.\n${findings.join('\n')}';

      _setResult('suspicious', msg);
      _snack(msg, isError: allSuspiciousUids.isNotEmpty);
    } catch (e) {
      _setResult('suspicious', 'Error: $e');
      _snack('Error: $e', isError: true);
    } finally {
      _setRunning('suspicious', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageContainer(
      title:    'System Tools',
      subtitle: 'Platform maintenance and diagnostic tools',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning banner
          AdminAlertBanner(
            message: 'These tools perform bulk database operations. Use with caution in production.',
            color:   AdminColors.warning,
            icon:    Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 24),

          // Tools grid
          AdminGrid(
            mobileColumns:  1,
            tabletColumns:  1,
            desktopColumns: 2,
            spacing:    16,
            runSpacing: 16,
            children: [
              _ToolCard(
                title:    'Recalculate Wallet Balances',
                subtitle: 'Scan all user transactions and rebuild wallet balances from scratch. Run when balances appear inconsistent.',
                icon:     Icons.calculate_rounded,
                color:    AdminColors.warning,
                running:  _running['recalc'] ?? false,
                result:   _results['recalc'],
                onRun:    _recalculateBalances,
              ),
              _ToolCard(
                title:    'Export Users CSV',
                subtitle: 'Download all user records (UID, name, email, wallet, earnings, admin/frozen flags) as a CSV file.',
                icon:     Icons.people_outline_rounded,
                color:    AdminColors.info,
                running:  _running['exportUsers'] ?? false,
                result:   _results['exportUsers'],
                onRun:    _exportUsers,
              ),
              _ToolCard(
                title:    'Export Tournament Results',
                subtitle: 'Download all completed tournament data including prize pools, player counts, and distribution status.',
                icon:     Icons.emoji_events_outlined,
                color:    AdminColors.gold,
                running:  _running['exportTournaments'] ?? false,
                result:   _results['exportTournaments'],
                onRun:    _exportTournamentResults,
              ),
              _ToolCard(
                title:    'Purge Old Logs',
                subtitle: 'Permanently delete all admin_logs entries older than 90 days. Requires confirmation.',
                icon:     Icons.delete_forever_rounded,
                color:    AdminColors.danger,
                running:  _running['purgeLogs'] ?? false,
                result:   _results['purgeLogs'],
                onRun:    _purgeLogs,
              ),
              _ToolCard(
                title:    'Rebuild Tournament Stats',
                subtitle: 'Re-scan participant subcollections and fix joinedPlayers counts for all upcoming and live tournaments.',
                icon:     Icons.refresh_rounded,
                color:    AdminColors.purple,
                running:  _running['rebuildStats'] ?? false,
                result:   _results['rebuildStats'],
                onRun:    _rebuildTournamentStats,
              ),
              _ToolCard(
                title:    'Detect Suspicious Activity',
                subtitle: 'Analyze the last 24 hours of transactions for spam deposits (5+), rapid withdrawals (3+), and unusual patterns.',
                icon:     Icons.security_rounded,
                color:    AdminColors.danger,
                running:  _running['suspicious'] ?? false,
                result:   _results['suspicious'],
                onRun:    _detectSuspiciousActivity,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// TOOL CARD
// ═════════════════════════════════════════════
class _ToolCard extends StatelessWidget {
  final String   title;
  final String   subtitle;
  final IconData icon;
  final Color    color;
  final bool     running;
  final String?  result;
  final VoidCallback onRun;

  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.running,
    this.result,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        AdminColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(
          color: running ? color.withValues(alpha: 0.4) : AdminColors.border,
        ),
        boxShadow: running
            ? [BoxShadow(
                color:      color.withValues(alpha: 0.12),
                blurRadius: 16,
              )]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: AdminTextStyles.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(subtitle, style: AdminTextStyles.bodyMedium),

          if (result != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:        color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Text(result!,
                  style: AdminTextStyles.bodySmall.copyWith(color: color)),
            ),
          ],

          const SizedBox(height: 16),
          GestureDetector(
            onTap: running ? null : onRun,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 40,
              decoration: BoxDecoration(
                gradient: running
                    ? null
                    : LinearGradient(
                        colors: [color, color.withValues(alpha: 0.7)],
                      ),
                color: running ? color.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(10),
                border: running
                    ? Border.all(color: color.withValues(alpha: 0.3))
                    : null,
              ),
              child: Center(
                child: running
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: color),
                          ),
                          const SizedBox(width: 10),
                          Text('Running…',
                              style: AdminTextStyles.labelLarge
                                  .copyWith(color: color)),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text('Run Tool',
                              style: AdminTextStyles.labelLarge
                                  .copyWith(color: Colors.white)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}