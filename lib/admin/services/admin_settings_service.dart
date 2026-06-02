// lib/admin/services/admin_settings_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Settings Service
// F2: Expanded settings — custom deposit/withdrawal limits, approval window,
//     custom messages, feature toggles, webhook config
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_secrets.dart';
import '../auth/admin_auth_service.dart';

// ─────────────────────────────────────────────
// SETTINGS MODEL
// ─────────────────────────────────────────────
class AdminSettings {
  // ── Payment ──────────────────────────────────
  final String upiId;
  final String upiPayeeName;
  final double minDepositAmount;
  final double maxDepositAmount;
  final double minWithdrawalAmount;
  final double maxWithdrawalAmount;

  // ── Deposit options ───────────────────────────
  final bool   depositRequiresScreenshot;
  final bool   depositAutoApprove;           // F2: auto-approve below threshold
  final double depositAutoApproveThreshold;  // F2: auto-approve if amount <= this
  final String depositInstructions;          // F2: custom instructions for players

  // ── Withdrawal options ────────────────────────
  final bool   withdrawalRequiresUpi;
  final bool   withdrawalAutoApprove;        // F2
  final double withdrawalAutoApproveThreshold;
  final String withdrawalInstructions;       // F2

  // ── Maintenance ───────────────────────────────
  final bool   maintenanceMode;
  final String maintenanceMessage;

  // ── Wallet ────────────────────────────────────
  final bool   walletFrozen;
  final String walletFreezeReason;

  // ── Tournament ───────────────────────────────
  final bool   tournamentRegistrationOpen;   // F2: global toggle
  final int    maxTournamentsPerUser;        // F2: limit simultaneous registrations
  final String tournamentRules;              // F2: default rules template

  // ── Security ─────────────────────────────────
  final int  sessionTimeoutMinutes;
  final bool require2FA;

  // ── Platform ─────────────────────────────────
  final String supportEmail;
  final String? discordInvite;
  final String appVersion;
  final String platformName;

  // ── Approval window ───────────────────────────
  final int approvalWindowStart;
  final int approvalWindowEnd;

  // ── Notifications (F2) ───────────────────────
  final bool notifyOnDeposit;
  final bool notifyOnWithdrawal;
  final bool notifyOnNewUser;
  final bool notifyOnTournamentFull;

  // ── Custom banners (F2) ──────────────────────
  final String? homeBannerMessage;           // shown to players on home screen
  final bool    homeBannerEnabled;

  const AdminSettings({
    this.upiId                       = '',
    this.upiPayeeName                = '',
    this.minDepositAmount            = 100,
    this.maxDepositAmount            = 10000,
    this.minWithdrawalAmount         = 100,
    this.maxWithdrawalAmount         = 5000,
    this.depositRequiresScreenshot   = true,
    this.depositAutoApprove          = false,
    this.depositAutoApproveThreshold = 500,
    this.depositInstructions         = '',
    this.withdrawalRequiresUpi       = true,
    this.withdrawalAutoApprove       = false,
    this.withdrawalAutoApproveThreshold = 500,
    this.withdrawalInstructions      = '',
    this.maintenanceMode             = false,
    this.maintenanceMessage          = 'Platform is under maintenance. Please try again later.',
    this.walletFrozen                = false,
    this.walletFreezeReason          = '',
    this.tournamentRegistrationOpen  = true,
    this.maxTournamentsPerUser       = 3,
    this.tournamentRules             = '',
    this.sessionTimeoutMinutes       = 60,
    this.require2FA                  = false,
    this.supportEmail                = '',
    this.discordInvite,
    this.appVersion                  = '1.0.0',
    this.platformName                = 'Shadow Storm',
    this.approvalWindowStart         = 9,
    this.approvalWindowEnd           = 22,
    this.notifyOnDeposit             = true,
    this.notifyOnWithdrawal          = true,
    this.notifyOnNewUser             = false,
    this.notifyOnTournamentFull      = true,
    this.homeBannerMessage,
    this.homeBannerEnabled           = false,
  });

  factory AdminSettings.fromMap(Map<String, dynamic> d) {
    return AdminSettings(
      upiId:                        (d['upiId']                        as String?) ?? '',
      upiPayeeName:                 (d['upiPayeeName']                 as String?) ?? '',
      minDepositAmount:             (d['minDepositAmount']             as num?)?.toDouble() ?? 100,
      maxDepositAmount:             (d['maxDepositAmount']             as num?)?.toDouble() ?? 10000,
      minWithdrawalAmount:          (d['minWithdrawalAmount']          as num?)?.toDouble() ?? 100,
      maxWithdrawalAmount:          (d['maxWithdrawalAmount']          as num?)?.toDouble() ?? 5000,
      depositRequiresScreenshot:    (d['depositRequiresScreenshot']    as bool?) ?? true,
      depositAutoApprove:           (d['depositAutoApprove']           as bool?) ?? false,
      depositAutoApproveThreshold:  (d['depositAutoApproveThreshold']  as num?)?.toDouble() ?? 500,
      depositInstructions:          (d['depositInstructions']          as String?) ?? '',
      withdrawalRequiresUpi:        (d['withdrawalRequiresUpi']        as bool?) ?? true,
      withdrawalAutoApprove:        (d['withdrawalAutoApprove']        as bool?) ?? false,
      withdrawalAutoApproveThreshold:(d['withdrawalAutoApproveThreshold'] as num?)?.toDouble() ?? 500,
      withdrawalInstructions:       (d['withdrawalInstructions']       as String?) ?? '',
      maintenanceMode:              (d['maintenanceMode']              as bool?) ?? false,
      maintenanceMessage:           (d['maintenanceMessage']           as String?) ?? 'Platform is under maintenance.',
      walletFrozen:                 (d['walletFrozen']                 as bool?) ?? false,
      walletFreezeReason:           (d['walletFreezeReason']           as String?) ?? '',
      tournamentRegistrationOpen:   (d['tournamentRegistrationOpen']   as bool?) ?? true,
      maxTournamentsPerUser:        (d['maxTournamentsPerUser']        as num?)?.toInt() ?? 3,
      tournamentRules:              (d['tournamentRules']              as String?) ?? '',
      sessionTimeoutMinutes:        (d['sessionTimeoutMinutes']        as num?)?.toInt() ?? 60,
      require2FA:                   (d['require2FA']                   as bool?) ?? false,
      supportEmail:                 (d['supportEmail']                 as String?) ?? '',
      discordInvite:                 d['discordInvite']                as String?,
      appVersion:                   (d['appVersion']                   as String?) ?? '1.0.0',
      platformName:                 (d['platformName']                 as String?) ?? 'Shadow Storm',
      approvalWindowStart:          (d['approvalWindowStart']          as num?)?.toInt() ?? 9,
      approvalWindowEnd:            (d['approvalWindowEnd']            as num?)?.toInt() ?? 22,
      notifyOnDeposit:              (d['notifyOnDeposit']              as bool?) ?? true,
      notifyOnWithdrawal:           (d['notifyOnWithdrawal']           as bool?) ?? true,
      notifyOnNewUser:              (d['notifyOnNewUser']              as bool?) ?? false,
      notifyOnTournamentFull:       (d['notifyOnTournamentFull']       as bool?) ?? true,
      homeBannerMessage:             d['homeBannerMessage']            as String?,
      homeBannerEnabled:            (d['homeBannerEnabled']            as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'upiId':                        upiId,
    'upiPayeeName':                 upiPayeeName,
    'minDepositAmount':             minDepositAmount,
    'maxDepositAmount':             maxDepositAmount,
    'minWithdrawalAmount':          minWithdrawalAmount,
    'maxWithdrawalAmount':          maxWithdrawalAmount,
    'depositRequiresScreenshot':    depositRequiresScreenshot,
    'depositAutoApprove':           depositAutoApprove,
    'depositAutoApproveThreshold':  depositAutoApproveThreshold,
    'depositInstructions':          depositInstructions,
    'withdrawalRequiresUpi':        withdrawalRequiresUpi,
    'withdrawalAutoApprove':        withdrawalAutoApprove,
    'withdrawalAutoApproveThreshold': withdrawalAutoApproveThreshold,
    'withdrawalInstructions':       withdrawalInstructions,
    'maintenanceMode':              maintenanceMode,
    'maintenanceMessage':           maintenanceMessage,
    'walletFrozen':                 walletFrozen,
    'walletFreezeReason':           walletFreezeReason,
    'tournamentRegistrationOpen':   tournamentRegistrationOpen,
    'maxTournamentsPerUser':        maxTournamentsPerUser,
    'tournamentRules':              tournamentRules,
    'sessionTimeoutMinutes':        sessionTimeoutMinutes,
    'require2FA':                   require2FA,
    'supportEmail':                 supportEmail,
    if (discordInvite != null) 'discordInvite': discordInvite,
    'appVersion':                   appVersion,
    'platformName':                 platformName,
    'approvalWindowStart':          approvalWindowStart,
    'approvalWindowEnd':            approvalWindowEnd,
    'notifyOnDeposit':              notifyOnDeposit,
    'notifyOnWithdrawal':           notifyOnWithdrawal,
    'notifyOnNewUser':              notifyOnNewUser,
    'notifyOnTournamentFull':       notifyOnTournamentFull,
    if (homeBannerMessage != null) 'homeBannerMessage': homeBannerMessage,
    'homeBannerEnabled':            homeBannerEnabled,
  };

  AdminSettings copyWith({
    String? upiId, String? upiPayeeName,
    double? minDepositAmount, double? maxDepositAmount,
    double? minWithdrawalAmount, double? maxWithdrawalAmount,
    bool? depositRequiresScreenshot, bool? depositAutoApprove,
    double? depositAutoApproveThreshold, String? depositInstructions,
    bool? withdrawalRequiresUpi, bool? withdrawalAutoApprove,
    double? withdrawalAutoApproveThreshold, String? withdrawalInstructions,
    bool? maintenanceMode, String? maintenanceMessage,
    bool? walletFrozen, String? walletFreezeReason,
    bool? tournamentRegistrationOpen, int? maxTournamentsPerUser,
    String? tournamentRules, int? sessionTimeoutMinutes, bool? require2FA,
    String? supportEmail, String? discordInvite,
    String? appVersion, String? platformName,
    int? approvalWindowStart, int? approvalWindowEnd,
    bool? notifyOnDeposit, bool? notifyOnWithdrawal,
    bool? notifyOnNewUser, bool? notifyOnTournamentFull,
    String? homeBannerMessage, bool? homeBannerEnabled,
  }) => AdminSettings(
    upiId:                        upiId                        ?? this.upiId,
    upiPayeeName:                 upiPayeeName                 ?? this.upiPayeeName,
    minDepositAmount:             minDepositAmount             ?? this.minDepositAmount,
    maxDepositAmount:             maxDepositAmount             ?? this.maxDepositAmount,
    minWithdrawalAmount:          minWithdrawalAmount          ?? this.minWithdrawalAmount,
    maxWithdrawalAmount:          maxWithdrawalAmount          ?? this.maxWithdrawalAmount,
    depositRequiresScreenshot:    depositRequiresScreenshot    ?? this.depositRequiresScreenshot,
    depositAutoApprove:           depositAutoApprove           ?? this.depositAutoApprove,
    depositAutoApproveThreshold:  depositAutoApproveThreshold  ?? this.depositAutoApproveThreshold,
    depositInstructions:          depositInstructions          ?? this.depositInstructions,
    withdrawalRequiresUpi:        withdrawalRequiresUpi        ?? this.withdrawalRequiresUpi,
    withdrawalAutoApprove:        withdrawalAutoApprove        ?? this.withdrawalAutoApprove,
    withdrawalAutoApproveThreshold: withdrawalAutoApproveThreshold ?? this.withdrawalAutoApproveThreshold,
    withdrawalInstructions:       withdrawalInstructions       ?? this.withdrawalInstructions,
    maintenanceMode:              maintenanceMode              ?? this.maintenanceMode,
    maintenanceMessage:           maintenanceMessage           ?? this.maintenanceMessage,
    walletFrozen:                 walletFrozen                 ?? this.walletFrozen,
    walletFreezeReason:           walletFreezeReason           ?? this.walletFreezeReason,
    tournamentRegistrationOpen:   tournamentRegistrationOpen   ?? this.tournamentRegistrationOpen,
    maxTournamentsPerUser:        maxTournamentsPerUser        ?? this.maxTournamentsPerUser,
    tournamentRules:              tournamentRules              ?? this.tournamentRules,
    sessionTimeoutMinutes:        sessionTimeoutMinutes        ?? this.sessionTimeoutMinutes,
    require2FA:                   require2FA                   ?? this.require2FA,
    supportEmail:                 supportEmail                 ?? this.supportEmail,
    discordInvite:                discordInvite                ?? this.discordInvite,
    appVersion:                   appVersion                   ?? this.appVersion,
    platformName:                 platformName                 ?? this.platformName,
    approvalWindowStart:          approvalWindowStart          ?? this.approvalWindowStart,
    approvalWindowEnd:            approvalWindowEnd            ?? this.approvalWindowEnd,
    notifyOnDeposit:              notifyOnDeposit              ?? this.notifyOnDeposit,
    notifyOnWithdrawal:           notifyOnWithdrawal           ?? this.notifyOnWithdrawal,
    notifyOnNewUser:              notifyOnNewUser              ?? this.notifyOnNewUser,
    notifyOnTournamentFull:       notifyOnTournamentFull       ?? this.notifyOnTournamentFull,
    homeBannerMessage:            homeBannerMessage            ?? this.homeBannerMessage,
    homeBannerEnabled:            homeBannerEnabled            ?? this.homeBannerEnabled,
  );
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────
class AdminSettingsService {
  AdminSettingsService._();
  static final AdminSettingsService instance = AdminSettingsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _docPath = 'config/admin_settings';

  String get _adminUid   => AdminAuthService.instance.currentUser?.uid   ?? 'unknown';
  String get _adminEmail => AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';

  DocumentReference<Map<String, dynamic>> get _ref => _db.doc(_docPath);

  // ── Realtime stream ────────────────────────────
  Stream<AdminSettings> settingsStream() {
    return _ref.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return const AdminSettings();
      return AdminSettings.fromMap(snap.data()!);
    });
  }

  // ── One-time read ──────────────────────────────
  Future<AdminSettings> getSettings() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.data() == null) return const AdminSettings();
    return AdminSettings.fromMap(snap.data()!);
  }

  // ── Generic partial update (merges any fields) ─
  Future<void> _updateAndLog({
    required Map<String, dynamic> fields,
    required String logAction,
    required Map<String, dynamic> logDetails,
  }) async {
    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    fields['updatedAt'] = FieldValue.serverTimestamp();
    fields['updatedBy'] = _adminEmail;

    batch.set(_ref, fields, SetOptions(merge: true));
    batch.set(logRef, {
      'action':     logAction,
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'config/admin_settings',
      'details':    logDetails,
      'createdAt':  FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // UPDATE PAYMENT SETTINGS
  // ──────────────────────────────────────────────────────
  Future<void> updatePaymentSettings({
    required String upiId,
    required String upiPayeeName,
    required double minDeposit,
    required double maxDeposit,
    required double minWithdrawal,
    required double maxWithdrawal,
  }) async {
    if (upiId.trim().isEmpty) throw Exception('UPI ID cannot be empty.');
    if (minDeposit >= maxDeposit) throw Exception('Min deposit must be less than max.');
    if (minWithdrawal >= maxWithdrawal) throw Exception('Min withdrawal must be less than max.');

    await _updateAndLog(
      fields: {
        'upiId':              upiId.trim(),
        'upiPayeeName':       upiPayeeName.trim(),
        'minDepositAmount':   minDeposit,
        'maxDepositAmount':   maxDeposit,
        'minWithdrawalAmount': minWithdrawal,
        'maxWithdrawalAmount': maxWithdrawal,
      },
      logAction: 'settings_updated',
      logDetails: {
        'section':          'payment',
        'upiId':            upiId.trim(),
        'minDepositAmount': minDeposit,
        'maxDepositAmount': maxDeposit,
      },
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE DEPOSIT OPTIONS  (F2)
  // ──────────────────────────────────────────────────────
  Future<void> updateDepositOptions({
    required bool   requiresScreenshot,
    required bool   autoApprove,
    required double autoApproveThreshold,
    required String instructions,
  }) async {
    await _updateAndLog(
      fields: {
        'depositRequiresScreenshot':   requiresScreenshot,
        'depositAutoApprove':          autoApprove,
        'depositAutoApproveThreshold': autoApproveThreshold,
        'depositInstructions':         instructions.trim(),
      },
      logAction: 'settings_updated',
      logDetails: {
        'section':                     'deposit_options',
        'requiresScreenshot':          requiresScreenshot,
        'autoApprove':                 autoApprove,
        'autoApproveThreshold':        autoApproveThreshold,
      },
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE WITHDRAWAL OPTIONS  (F2)
  // ──────────────────────────────────────────────────────
  Future<void> updateWithdrawalOptions({
    required bool   requiresUpi,
    required bool   autoApprove,
    required double autoApproveThreshold,
    required String instructions,
  }) async {
    await _updateAndLog(
      fields: {
        'withdrawalRequiresUpi':             requiresUpi,
        'withdrawalAutoApprove':             autoApprove,
        'withdrawalAutoApproveThreshold':    autoApproveThreshold,
        'withdrawalInstructions':            instructions.trim(),
      },
      logAction: 'settings_updated',
      logDetails: {
        'section':               'withdrawal_options',
        'requiresUpi':           requiresUpi,
        'autoApprove':           autoApprove,
        'autoApproveThreshold':  autoApproveThreshold,
      },
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE TOURNAMENT OPTIONS  (F2)
  // ──────────────────────────────────────────────────────
  Future<void> updateTournamentOptions({
    required bool   registrationOpen,
    required int    maxPerUser,
    required String defaultRules,
  }) async {
    await _updateAndLog(
      fields: {
        'tournamentRegistrationOpen': registrationOpen,
        'maxTournamentsPerUser':      maxPerUser,
        'tournamentRules':            defaultRules.trim(),
      },
      logAction: 'settings_updated',
      logDetails: {
        'section':           'tournament_options',
        'registrationOpen':  registrationOpen,
        'maxPerUser':        maxPerUser,
      },
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE HOME BANNER  (F2)
  // ──────────────────────────────────────────────────────
  Future<void> updateHomeBanner({
    required bool   enabled,
    required String message,
  }) async {
    await _updateAndLog(
      fields: {
        'homeBannerEnabled': enabled,
        'homeBannerMessage': message.trim(),
      },
      logAction: 'settings_updated',
      logDetails: {'section': 'home_banner', 'enabled': enabled},
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE NOTIFICATION PREFERENCES  (F2)
  // ──────────────────────────────────────────────────────
  Future<void> updateNotificationPreferences({
    required bool onDeposit,
    required bool onWithdrawal,
    required bool onNewUser,
    required bool onTournamentFull,
  }) async {
    await _updateAndLog(
      fields: {
        'notifyOnDeposit':        onDeposit,
        'notifyOnWithdrawal':     onWithdrawal,
        'notifyOnNewUser':        onNewUser,
        'notifyOnTournamentFull': onTournamentFull,
      },
      logAction: 'settings_updated',
      logDetails: {'section': 'notifications'},
    );
  }

  // ──────────────────────────────────────────────────────
  // TOGGLE MAINTENANCE MODE
  // ──────────────────────────────────────────────────────
  Future<void> setMaintenanceMode(bool enabled, {String? message}) async {
    await _updateAndLog(
      fields: {
        'maintenanceMode': enabled,
        if (message != null) 'maintenanceMessage': message.trim(),
      },
      logAction: enabled ? 'maintenance_enabled' : 'maintenance_disabled',
      logDetails: {'enabled': enabled, if (message != null) 'message': message.trim()},
    );
    if (enabled) {
      _fireDangerWebhook(
        title:   '🔴  Maintenance Mode ENABLED',
        color:   0xFF4466,
        message: 'Platform is now in maintenance mode. All player actions blocked.',
        admin:   _adminEmail,
      );
    }
  }

  // ──────────────────────────────────────────────────────
  // TOGGLE WALLET FREEZE
  // ──────────────────────────────────────────────────────
  Future<void> setWalletFreeze(bool frozen, {String? reason}) async {
    await _updateAndLog(
      fields: {
        'walletFrozen':       frozen,
        'walletFreezeReason': reason?.trim() ?? '',
      },
      logAction: frozen ? 'wallets_frozen' : 'wallets_unfrozen',
      logDetails: {'frozen': frozen, if (reason != null) 'reason': reason.trim()},
    );
    if (frozen) {
      _fireDangerWebhook(
        title:   '❄️  All Wallets FROZEN',
        color:   0xFFAA22,
        message: 'All wallet operations are now frozen. No deposits or withdrawals.',
        admin:   _adminEmail,
      );
    }
  }

  // ──────────────────────────────────────────────────────
  // UPDATE SECURITY SETTINGS
  // ──────────────────────────────────────────────────────
  Future<void> updateSecuritySettings({
    required int  sessionTimeoutMinutes,
    required bool require2FA,
  }) async {
    await _updateAndLog(
      fields: {
        'sessionTimeoutMinutes': sessionTimeoutMinutes,
        'require2FA':            require2FA,
      },
      logAction: 'settings_updated',
      logDetails: {'section': 'security', 'sessionTimeoutMinutes': sessionTimeoutMinutes, 'require2FA': require2FA},
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE PLATFORM INFO
  // ──────────────────────────────────────────────────────
  Future<void> updatePlatformInfo({
    required String supportEmail,
    String?  discordInvite,
    required String appVersion,
  }) async {
    await _updateAndLog(
      fields: {
        'supportEmail':  supportEmail.trim(),
        'discordInvite': discordInvite?.trim(),
        'appVersion':    appVersion.trim(),
      },
      logAction: 'settings_updated',
      logDetails: {'section': 'platform', 'supportEmail': supportEmail.trim(), 'appVersion': appVersion.trim()},
    );
  }

  // ──────────────────────────────────────────────────────
  // UPDATE APPROVAL WINDOW
  // ──────────────────────────────────────────────────────
  Future<void> updateApprovalWindow(int startHour, int endHour) async {
    await _ref.set({
      'approvalWindowStart': startHour,
      'approvalWindowEnd':   endHour,
      'updatedAt':           FieldValue.serverTimestamp(),
      'updatedBy':           _adminEmail,
    }, SetOptions(merge: true));
  }

  // ──────────────────────────────────────────────────────
  // PROMOTE / DEMOTE ADMIN
  // ──────────────────────────────────────────────────────
  Future<void> setAdminRole(String uid, String playerName, bool isAdmin) async {
    final batch   = _db.batch();
    final userRef = _db.collection('users').doc(uid);
    final logRef  = _db.collection('admin_logs').doc();

    batch.update(userRef, {'isAdmin': isAdmin});
    batch.set(logRef, {
      'action':     isAdmin ? 'admin_promoted' : 'admin_demoted',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details':    {'playerName': playerName, 'isAdmin': isAdmin, 'source': 'settings_page'},
      'createdAt':  FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // SEND TEST DISCORD WEBHOOK
  // ──────────────────────────────────────────────────────
  Future<bool> sendTestWebhook() async {
    try {
      final response = await http.post(
        Uri.parse(AppSecrets.depositWebhook),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'embeds': [{
          'title':       '🧪  Test Webhook — Shadow Storm Admin',
          'color':       0x9D55FF,
          'description': 'This is a test message sent from the admin panel.',
          'fields': [
            {'name': '👮 Sent by', 'value': _adminEmail,                          'inline': true},
            {'name': '⏰ Time',    'value': DateTime.now().toLocal().toString(), 'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Webhook Test'},
        }]}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AdminSettingsService] Test webhook error: $e');
      return false;
    }
  }

  // ── Danger webhook ────────────────────────────
  void _fireDangerWebhook({
    required String title, required int color,
    required String message, required String admin,
  }) {
    http.post(
      Uri.parse(AppSecrets.depositWebhook),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'embeds': [{
        'title':       title,
        'color':       color,
        'description': message,
        'fields': [
          {'name': '👮 Admin',    'value': admin,  'inline': true},
          {'name': '⚠️ Severity', 'value': 'HIGH', 'inline': true},
        ],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'footer':    {'text': 'Shadow Storm Admin Panel  •  Danger Action'},
      }]}),
    ).catchError((e) => debugPrint('[AdminSettingsService] webhook error: $e'));
  }
}