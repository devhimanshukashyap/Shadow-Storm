// lib/admin/pages/admin_pages.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Pages Barrel
// Phase 3: Withdrawals + Users are LIVE
// Tournaments, Logs, Settings remain as placeholders
// ─────────────────────────────────────────────

export 'admin_dashboard_page.dart';
export 'admin_deposits_page.dart';
export 'admin_withdrawals_page.dart';
export 'admin_users_page.dart';

import 'package:flutter/material.dart';
import '../widgets/admin_page_container.dart';
import '../theme/admin_theme.dart';

// ─────────────────────────────────────────────
// REUSABLE PLACEHOLDER SHELL
// ─────────────────────────────────────────────
class _AdminPlaceholderPage extends StatelessWidget {
  final String       title;
  final String       subtitle;
  final IconData     icon;
  final Color        color;
  final String       phase;
  final List<String> plannedFeatures;

  const _AdminPlaceholderPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.phase,
    required this.plannedFeatures,
  });

  @override
  Widget build(BuildContext context) {
    return AdminPageContainer(
      title:    title,
      subtitle: subtitle,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.10),
                  border: Border.all(
                      color: color.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.15),
                        blurRadius: 24),
                  ],
                ),
                child: Icon(icon, color: color, size: 36),
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AdminColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AdminColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.construction_rounded,
                        color: AdminColors.warning, size: 14),
                    const SizedBox(width: 7),
                    Text(
                      'Scheduled for $phase',
                      style: AdminTextStyles.labelMedium.copyWith(
                          color: AdminColors.warning, letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(title,
                  style: AdminTextStyles.titleLarge,
                  textAlign: TextAlign.center),

              const SizedBox(height: 8),

              Text(subtitle,
                  style: AdminTextStyles.bodyMedium,
                  textAlign: TextAlign.center),

              const SizedBox(height: 32),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color:        AdminColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border:       Border.all(color: AdminColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 3, height: 14,
                        decoration: BoxDecoration(
                          color:        color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PLANNED FEATURES',
                        style: AdminTextStyles.labelMedium.copyWith(
                            color: AdminColors.textSecondary,
                            letterSpacing: 1.5),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    ...plannedFeatures.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: color.withValues(alpha: 0.7), size: 14),
                          const SizedBox(width: 10),
                          Expanded(child: Text(f,
                              style: AdminTextStyles.bodyMedium)),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TOURNAMENTS PAGE (Phase 4 placeholder)
// ─────────────────────────────────────────────
class AdminTournamentsPage extends StatelessWidget {
  const AdminTournamentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AdminPlaceholderPage(
      title:    'Tournament Management',
      subtitle: 'Create, edit, and manage esports tournaments',
      icon:     Icons.emoji_events_rounded,
      color:    AdminColors.gold,
      phase:    'Phase 4',
      plannedFeatures: [
        'Create new tournaments with full configuration (title, mode, prize pool, entry fee, slots)',
        'Upload tournament banner image via Firebase Storage',
        'Set and update tournament status: upcoming → live → completed',
        'Feature / un-feature tournaments on the player home screen',
        'View full participant list per tournament with join timestamps',
        'Distribute prize pool to winners — atomic batch wallet credits',
        'Cancel tournaments with auto-refund to all registered players',
        'Tournament stats: fill rate, revenue, prize paid out',
      ],
    );
  }
}

// ─────────────────────────────────────────────
// LOGS PAGE (Phase 4 placeholder)
// ─────────────────────────────────────────────
class AdminLogsPage extends StatelessWidget {
  const AdminLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AdminPlaceholderPage(
      title:    'System Logs',
      subtitle: 'Audit trail for all admin actions',
      icon:     Icons.receipt_long_rounded,
      color:    AdminColors.warning,
      phase:    'Phase 4',
      plannedFeatures: [
        'Full real-time stream of admin_logs collection',
        'Every action logged: deposit_approved, withdrawal_approved, withdrawal_rejected, balance_adjusted, admin_promoted, admin_demoted, account_frozen',
        'Filter by action type, admin UID, target user UID, date range',
        'Color-coded action badges matching existing AdminColors tokens',
        'Click any log entry to view full details map',
        'Export filtered logs to CSV for accounting / compliance',
        'Log count statistics by action type',
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SETTINGS PAGE (Phase 4 placeholder)
// ─────────────────────────────────────────────
class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AdminPlaceholderPage(
      title:    'Admin Settings',
      subtitle: 'Platform configuration and operational settings',
      icon:     Icons.settings_rounded,
      color:    Color(0xFF9B8DC0),
      phase:    'Phase 4',
      plannedFeatures: [
        'Read/write config/admin_settings Firestore document',
        'UPI payment details: UPI ID + payee name shown to players',
        'Minimum and maximum deposit / withdrawal amount limits',
        'Maintenance mode toggle — blocks player actions in main app',
        'Discord webhook URL display (read-only from AppSecrets)',
        'Approval time window configuration (e.g. 8PM–8AM IST)',
        'View all admin accounts — promote/demote from settings',
        'Platform branding: app name, support contact',
      ],
    );
  }
}