// lib/services/app_settings_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — App Settings Service (Phase P1)
//
// Player-app counterpart of admin_settings_service.dart.
// Reads config/admin_settings and exposes it to the player app.
//
// Features:
//   • Single realtime stream for admin settings (ONE listener for whole app)
//   • Lightweight cached one-time reads for non-critical settings
//   • maintenanceMode / walletFrozen signals exposed as ValueNotifiers
//     so any widget can react without StreamBuilder nesting
//   • NEVER writes to admin_settings — read-only from player side
//
// Architecture:
//   • Single Firestore listener cached at service level
//   • All widgets share the same stream (no duplicate listeners)
//   • CacheService integration for offline resilience
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart';
import 'cache_service.dart';

// ─────────────────────────────────────────────
// PLAYER-SIDE SETTINGS MODEL
// Only fields the player app needs — not the full AdminSettings model.
// ─────────────────────────────────────────────

class AppSettings {
  final bool   maintenanceMode;
  final String maintenanceMessage;
  final bool   walletFrozen;
  final String walletFreezeReason;
  final double minDepositAmount;
  final double maxDepositAmount;
  final double minWithdrawalAmount;
  final double maxWithdrawalAmount;
  final String platformName;
  final String appVersion;
  final String supportEmail;
  final String? discordInvite;
  final int    approvalWindowStart;
  final int    approvalWindowEnd;

  const AppSettings({
    this.maintenanceMode      = false,
    this.maintenanceMessage   = 'Platform is under maintenance. Please try again later.',
    this.walletFrozen         = false,
    this.walletFreezeReason   = '',
    this.minDepositAmount     = 100,
    this.maxDepositAmount     = 10000,
    this.minWithdrawalAmount  = 100,
    this.maxWithdrawalAmount  = 5000,
    this.platformName         = 'Shadow Storm',
    this.appVersion           = '1.0.0',
    this.supportEmail         = '',
    this.discordInvite,
    this.approvalWindowStart  = 9,
    this.approvalWindowEnd    = 22,
  });

  factory AppSettings.fromMap(Map<String, dynamic> d) {
    return AppSettings(
      maintenanceMode:     (d['maintenanceMode']     as bool?)   ?? false,
      maintenanceMessage:  (d['maintenanceMessage']  as String?) ?? 'Platform is under maintenance.',
      walletFrozen:        (d['walletFrozen']        as bool?)   ?? false,
      walletFreezeReason:  (d['walletFreezeReason']  as String?) ?? '',
      minDepositAmount:    (d['minDepositAmount']    as num?)?.toDouble() ?? 100,
      maxDepositAmount:    (d['maxDepositAmount']    as num?)?.toDouble() ?? 10000,
      minWithdrawalAmount: (d['minWithdrawalAmount'] as num?)?.toDouble() ?? 100,
      maxWithdrawalAmount: (d['maxWithdrawalAmount'] as num?)?.toDouble() ?? 5000,
      platformName:        (d['platformName']        as String?) ?? 'Shadow Storm',
      appVersion:          (d['appVersion']          as String?) ?? '1.0.0',
      supportEmail:        (d['supportEmail']        as String?) ?? '',
      discordInvite:        d['discordInvite']        as String?,
      approvalWindowStart: (d['approvalWindowStart'] as num?)?.toInt() ?? 9,
      approvalWindowEnd:   (d['approvalWindowEnd']   as num?)?.toInt() ?? 22,
    );
  }

  /// Whether wallet actions (deposit/withdraw) are allowed.
  bool get walletActionsAllowed => !walletFrozen && !maintenanceMode;

  /// Whether any player action should be blocked.
  bool get actionsBlocked => maintenanceMode;

  /// Human-readable approval window string.
  String get approvalWindowDisplay {
    String _fmt(int h) {
      final period = h >= 12 ? 'PM' : 'AM';
      final h12    = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h12 $period';
    }
    return '${_fmt(approvalWindowStart)} – ${_fmt(approvalWindowEnd)}';
  }
}

// ─────────────────────────────────────────────
// APP SETTINGS SERVICE
// ─────────────────────────────────────────────

class AppSettingsService {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _docPath = 'config/admin_settings';

  // ── Shared stream (one listener for the whole app) ──
  Stream<AppSettings>? _settingsStream;

  // ── ValueNotifiers for lightweight widget reactions ──
  final ValueNotifier<bool>        maintenanceNotifier = ValueNotifier(false);
  final ValueNotifier<bool>        walletFrozenNotifier = ValueNotifier(false);
  final ValueNotifier<AppSettings> settingsNotifier =
      ValueNotifier(const AppSettings());

  // ─────────────────────────────────────────────
  // REALTIME STREAM (shared across app)
  // Call this once and subscribe multiple widgets to the same stream.
  // ─────────────────────────────────────────────

  Stream<AppSettings> get settingsStream {
    _settingsStream ??= _db
        .doc(_docPath)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) {
            return const AppSettings();
          }
          final settings = AppSettings.fromMap(snap.data()!);
          _updateNotifiers(settings);
          _updateCache(settings);
          return settings;
        })
        .asBroadcastStream(); // shared — no duplicate Firestore reads

    return _settingsStream!;
  }

  // ─────────────────────────────────────────────
  // ONE-TIME READ (cache-first)
  // ─────────────────────────────────────────────

  Future<AppSettings> getSettings({bool forceRefresh = false}) async {
    // Return from cache if available and not forcing refresh
    if (!forceRefresh) {
      final cached = CacheService.instance.get<Map<String, dynamic>>(
        CacheKey.adminSettings,
      );
      if (cached != null) return AppSettings.fromMap(cached);
    }

    try {
      final snap = await _db.doc(_docPath).get();
      if (!snap.exists || snap.data() == null) return const AppSettings();
      final settings = AppSettings.fromMap(snap.data()!);
      _updateNotifiers(settings);
      _updateCache(settings);
      return settings;
    } catch (e) {
      debugPrint('[AppSettingsService] getSettings error: $e');
      // Return cached or defaults on error
      final cached = CacheService.instance.get<Map<String, dynamic>>(
        CacheKey.adminSettings,
      );
      return cached != null ? AppSettings.fromMap(cached) : const AppSettings();
    }
  }

  // ─────────────────────────────────────────────
  // MAINTENANCE CHECK (very lightweight)
  // ─────────────────────────────────────────────

  /// Fast maintenance check — uses cache if available, falls back to Firestore.
  Future<bool> isMaintenanceMode() async {
    final cached = CacheService.instance.get<bool>(CacheKey.maintenanceMode);
    if (cached != null) return cached;

    try {
      final snap = await _db.doc(_docPath).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final value = (snap.data()?['maintenanceMode'] as bool?) ?? false;
      CacheService.instance.set(CacheKey.maintenanceMode, value);
      return value;
    } catch (_) {
      return false; // default: allow access on error
    }
  }

  // ─────────────────────────────────────────────
  // INTERNAL HELPERS
  // ─────────────────────────────────────────────

  void _updateNotifiers(AppSettings settings) {
    maintenanceNotifier.value  = settings.maintenanceMode;
    walletFrozenNotifier.value = settings.walletFrozen;
    settingsNotifier.value     = settings;
  }

  void _updateCache(AppSettings settings) {
    CacheService.instance.set<bool>(
      CacheKey.maintenanceMode,
      settings.maintenanceMode,
      ttl: const Duration(minutes: 1),
    );
    CacheService.instance.set<bool>(
      CacheKey.walletSettings,
      settings.walletFrozen,
    );
  }

  void dispose() {
    maintenanceNotifier.dispose();
    walletFrozenNotifier.dispose();
    settingsNotifier.dispose();
  }
}

// ─────────────────────────────────────────────
// MAINTENANCE GUARD WIDGET
// Wrap any screen with this to auto-show maintenance UI
// when admin enables maintenanceMode.
// ─────────────────────────────────────────────


class MaintenanceGuard extends StatelessWidget {
  final Widget child;

  const MaintenanceGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.instance.settingsStream,
      builder: (context, snap) {
        final settings = snap.data ?? const AppSettings();
        if (settings.maintenanceMode) {
          return _MaintenanceScreen(message: settings.maintenanceMessage);
        }
        return child;
      },
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
  final String message;
  const _MaintenanceScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06040E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated icon
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF9D55FF).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF9D55FF).withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  color: Color(0xFF9D55FF),
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'UNDER MAINTENANCE',
                style: TextStyle(
                  color: Color(0xFFEDE0FF),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF130F22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x337B3FE4)),
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF9B8DC0),
                    fontSize: 14,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF9D55FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF9D55FF).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'We\'ll be back shortly. Follow us on Discord for updates.',
                  style: TextStyle(
                    color: Color(0xFF9B8DC0),
                    fontSize: 12,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}