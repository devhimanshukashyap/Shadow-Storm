// lib/admin/pages/admin_pages.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Pages Barrel
// Phase 4: Tournaments LIVE ✓
// Logs, Settings remain as placeholders → Phase 5
// ─────────────────────────────────────────────

export 'admin_dashboard_page.dart';
export 'admin_deposits_page.dart';
export 'admin_withdrawals_page.dart';
export 'admin_users_page.dart';
export 'admin_tournaments_page.dart';

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
// LOGS PAGE (Phase 5 placeholder)
// ─────────────────────────────────────────────
class AdminLogsPage extends StatelessWidget {
  const AdminLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AdminPlaceholderPage(
      title:    'System Logs',
      subtitle: 'Full audit trail for all admin actions',
      icon:     Icons.receipt_long_rounded,
      color:    AdminColors.warning,
      phase:    'Phase 5',
      plannedFeatures: [
        'Real-time stream of admin_logs collection with infinite scroll',
        'Filter by action type, admin UID, target user UID, date range',
        'Color-coded action badges: deposit_approved, withdrawal_approved, prize_distributed, tournament_cancelled, etc.',
        'Click any log entry to expand full details payload',
        'Export filtered logs to CSV for accounting / compliance',
        'Log statistics dashboard: actions per day, most active admin, top action types',
        'Search by keyword across all log fields',
      ],
    );
  }
}

// ─────────────────────────────────────────────
// SETTINGS PAGE (Phase 5 placeholder)
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
      phase:    'Phase 5',
      plannedFeatures: [
        'Read/write config/admin_settings Firestore document in real-time',
        'UPI payment details editor: UPI ID + payee name shown to players',
        'Minimum and maximum deposit/withdrawal amount limits',
        'Maintenance mode toggle — blocks player actions across the main app',
        'Freeze system: freeze/unfreeze all wallet operations platform-wide',
        'Security controls: require 2FA, session timeout, IP whitelist',
        'View and promote/demote all admin accounts from one place',
        'Platform branding: app name, support contact, social links',
        'Discord webhook URL display (read-only from AppSecrets)',
      ],
    );
  }
}