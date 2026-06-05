// lib/services/app_settings_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — App Settings Service (Phase F2.5 / PRE-F3)
//
// Unchanged from Phase F1. Delivered as a complete standalone file.
//
// Provides:
//   • AppSettings model with all admin-controlled flags
//   • AppSettingsService singleton — shared stream + one-time reads
//   • MaintenanceGuard widget — wraps all 5 player screens
//   • WalletFreezeGuard widget — gates deposit/withdrawal actions
//   • _MaintenanceScreen and _WalletFrozenScreen UI
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'cache_service.dart';

// ─────────────────────────────────────────────
// APP SETTINGS MODEL
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

  bool get walletActionsAllowed  => !walletFrozen && !maintenanceMode;
  bool get depositAllowed        => !walletFrozen && !maintenanceMode;
  bool get withdrawalAllowed     => !walletFrozen && !maintenanceMode;
  bool get tournamentJoinAllowed => !walletFrozen && !maintenanceMode;
  bool get actionsBlocked        => maintenanceMode;

  String get blockReason {
    if (maintenanceMode) return maintenanceMessage;
    if (walletFrozen) {
      return walletFreezeReason.isNotEmpty
          ? walletFreezeReason
          : 'Wallet operations are temporarily suspended.';
    }
    return '';
  }

  String get approvalWindowDisplay {
    String fmt(int h) {
      final period = h >= 12 ? 'PM' : 'AM';
      final h12    = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h12 $period';
    }
    return '${fmt(approvalWindowStart)} – ${fmt(approvalWindowEnd)}';
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

  Stream<AppSettings>? _settingsStream;

  final ValueNotifier<bool>        maintenanceNotifier  = ValueNotifier(false);
  final ValueNotifier<bool>        walletFrozenNotifier = ValueNotifier(false);
  final ValueNotifier<AppSettings> settingsNotifier     = ValueNotifier(const AppSettings());

  Stream<AppSettings> get settingsStream {
    _settingsStream ??= _db
        .doc(_docPath)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) return const AppSettings();
          final settings = AppSettings.fromMap(snap.data()!);
          _updateNotifiers(settings);
          _updateCache(settings);
          return settings;
        })
        .asBroadcastStream();
    return _settingsStream!;
  }

  Future<AppSettings> getSettings({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = CacheService.instance.get<Map<String, dynamic>>(CacheKey.adminSettings);
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
      final cached = CacheService.instance.get<Map<String, dynamic>>(CacheKey.adminSettings);
      return cached != null ? AppSettings.fromMap(cached) : const AppSettings();
    }
  }

  Future<bool> isMaintenanceMode() async {
    final cached = CacheService.instance.get<bool>(CacheKey.maintenanceMode);
    if (cached != null) return cached;
    try {
      final snap = await _db.doc(_docPath).get(const GetOptions(source: Source.serverAndCache));
      final value = (snap.data()?['maintenanceMode'] as bool?) ?? false;
      CacheService.instance.set(CacheKey.maintenanceMode, value);
      return value;
    } catch (_) {
      return false;
    }
  }

  void _updateNotifiers(AppSettings settings) {
    maintenanceNotifier.value  = settings.maintenanceMode;
    walletFrozenNotifier.value = settings.walletFrozen;
    settingsNotifier.value     = settings;
  }

  void _updateCache(AppSettings settings) {
    CacheService.instance.set<bool>(CacheKey.maintenanceMode, settings.maintenanceMode, ttl: const Duration(minutes: 1));
    CacheService.instance.set<bool>(CacheKey.walletSettings,  settings.walletFrozen);
  }

  void dispose() {
    maintenanceNotifier.dispose();
    walletFrozenNotifier.dispose();
    settingsNotifier.dispose();
  }
}

// ─────────────────────────────────────────────
// MAINTENANCE GUARD WIDGET
// Wraps: HomeScreen, EventsScreen, WalletScreen, ProfileScreen,
//        TournamentDetailsScreen, RanksScreen.
// Does NOT wrap: LoginScreen.
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

// ─────────────────────────────────────────────
// WALLET FREEZE GUARD WIDGET
// ─────────────────────────────────────────────

class WalletFreezeGuard extends StatelessWidget {
  final Widget child;
  const WalletFreezeGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSettings>(
      stream: AppSettingsService.instance.settingsStream,
      builder: (context, snap) {
        final settings = snap.data ?? const AppSettings();
        if (settings.walletFrozen) {
          return _WalletFrozenScreen(reason: settings.walletFreezeReason);
        }
        return child;
      },
    );
  }
}

// ─────────────────────────────────────────────
// MAINTENANCE SCREEN
// ─────────────────────────────────────────────

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
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF9D55FF).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFF9D55FF).withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.construction_rounded, color: Color(0xFF9D55FF), size: 40),
              ),
              const SizedBox(height: 28),
              const Text('UNDER MAINTENANCE', style: TextStyle(color: Color(0xFFEDE0FF), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF130F22), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x337B3FE4))),
                child: Text(message, style: const TextStyle(color: Color(0xFF9B8DC0), fontSize: 14, height: 1.6), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF9D55FF).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF9D55FF).withValues(alpha: 0.3))),
                child: const Text('We\'ll be back shortly. Follow us on Discord for updates.', style: TextStyle(color: Color(0xFF9B8DC0), fontSize: 12, height: 1.5), textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WALLET FROZEN SCREEN
// ─────────────────────────────────────────────

class _WalletFrozenScreen extends StatelessWidget {
  final String reason;
  const _WalletFrozenScreen({required this.reason});

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
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFAA22).withValues(alpha: 0.12),
                  border: Border.all(color: const Color(0xFFFFAA22).withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.ac_unit_rounded, color: Color(0xFFFFAA22), size: 40),
              ),
              const SizedBox(height: 28),
              const Text('WALLET FROZEN', style: TextStyle(color: Color(0xFFEDE0FF), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF130F22), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFAA22).withValues(alpha: 0.3))),
                child: Text(reason.isNotEmpty ? reason : 'Wallet operations are temporarily suspended by the admin.', style: const TextStyle(color: Color(0xFF9B8DC0), fontSize: 14, height: 1.6), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 24),
              const Text('You can still browse tournaments and the app.\nDeposits, withdrawals, and tournament entry are disabled until the freeze is lifted.', style: TextStyle(color: Color(0xFF5A4E80), fontSize: 12, height: 1.6), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}