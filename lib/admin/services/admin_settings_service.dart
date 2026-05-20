// lib/admin/services/admin_settings_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Settings Service
// Phase 5: Read/write config/admin_settings, maintenance, freeze, danger actions
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
  // Payment
  final String upiId;
  final String upiPayeeName;
  final double minDepositAmount;
  final double maxDepositAmount;
  final double minWithdrawalAmount;
  final double maxWithdrawalAmount;

  // Maintenance
  final bool maintenanceMode;
  final String maintenanceMessage;

  // Wallet
  final bool walletFrozen;
  final String walletFreezeReason;

  // Security
  final int sessionTimeoutMinutes; // 15 | 30 | 60 | 240 | 0=never
  final bool require2FA;

  // Platform
  final String supportEmail;
  final String? discordInvite;
  final String appVersion;
  final String platformName;

  // Approval window
  final int approvalWindowStart;
  final int approvalWindowEnd;

  const AdminSettings({
    this.upiId                 = '',
    this.upiPayeeName          = '',
    this.minDepositAmount      = 100,
    this.maxDepositAmount      = 10000,
    this.minWithdrawalAmount   = 100,
    this.maxWithdrawalAmount   = 5000,
    this.maintenanceMode       = false,
    this.maintenanceMessage    = 'Platform is under maintenance. Please try again later.',
    this.walletFrozen          = false,
    this.walletFreezeReason    = '',
    this.sessionTimeoutMinutes = 60,
    this.require2FA            = false,
    this.supportEmail          = '',
    this.discordInvite,
    this.appVersion            = '1.0.0',
    this.platformName          = 'Shadow Storm',
    this.approvalWindowStart   = 9,
    this.approvalWindowEnd     = 22,
  });

  factory AdminSettings.fromMap(Map<String, dynamic> d) {
    return AdminSettings(
      upiId:                  (d['upiId']                  as String?) ?? '',
      upiPayeeName:           (d['upiPayeeName']           as String?) ?? '',
      minDepositAmount:       (d['minDepositAmount']       as num?)?.toDouble() ?? 100,
      maxDepositAmount:       (d['maxDepositAmount']       as num?)?.toDouble() ?? 10000,
      minWithdrawalAmount:    (d['minWithdrawalAmount']    as num?)?.toDouble() ?? 100,
      maxWithdrawalAmount:    (d['maxWithdrawalAmount']    as num?)?.toDouble() ?? 5000,
      maintenanceMode:        (d['maintenanceMode']        as bool?) ?? false,
      maintenanceMessage:     (d['maintenanceMessage']     as String?) ?? 'Platform is under maintenance.',
      walletFrozen:           (d['walletFrozen']           as bool?) ?? false,
      walletFreezeReason:     (d['walletFreezeReason']     as String?) ?? '',
      sessionTimeoutMinutes:  (d['sessionTimeoutMinutes']  as num?)?.toInt() ?? 60,
      require2FA:             (d['require2FA']             as bool?) ?? false,
      supportEmail:           (d['supportEmail']           as String?) ?? '',
      discordInvite:           d['discordInvite']           as String?,
      appVersion:             (d['appVersion']             as String?) ?? '1.0.0',
      platformName:           (d['platformName']           as String?) ?? 'Shadow Storm',
      approvalWindowStart:    (d['approvalWindowStart']    as num?)?.toInt() ?? 9,
      approvalWindowEnd:      (d['approvalWindowEnd']      as num?)?.toInt() ?? 22,
    );
  }

  Map<String, dynamic> toMap() => {
    'upiId':                 upiId,
    'upiPayeeName':          upiPayeeName,
    'minDepositAmount':      minDepositAmount,
    'maxDepositAmount':      maxDepositAmount,
    'minWithdrawalAmount':   minWithdrawalAmount,
    'maxWithdrawalAmount':   maxWithdrawalAmount,
    'maintenanceMode':       maintenanceMode,
    'maintenanceMessage':    maintenanceMessage,
    'walletFrozen':          walletFrozen,
    'walletFreezeReason':    walletFreezeReason,
    'sessionTimeoutMinutes': sessionTimeoutMinutes,
    'require2FA':            require2FA,
    'supportEmail':          supportEmail,
    if (discordInvite != null) 'discordInvite': discordInvite,
    'appVersion':            appVersion,
    'platformName':          platformName,
    'approvalWindowStart':   approvalWindowStart,
    'approvalWindowEnd':     approvalWindowEnd,
  };

  AdminSettings copyWith({
    String? upiId,
    String? upiPayeeName,
    double? minDepositAmount,
    double? maxDepositAmount,
    double? minWithdrawalAmount,
    double? maxWithdrawalAmount,
    bool? maintenanceMode,
    String? maintenanceMessage,
    bool? walletFrozen,
    String? walletFreezeReason,
    int? sessionTimeoutMinutes,
    bool? require2FA,
    String? supportEmail,
    String? discordInvite,
    String? appVersion,
    String? platformName,
    int? approvalWindowStart,
    int? approvalWindowEnd,
  }) {
    return AdminSettings(
      upiId:                  upiId                  ?? this.upiId,
      upiPayeeName:           upiPayeeName           ?? this.upiPayeeName,
      minDepositAmount:       minDepositAmount       ?? this.minDepositAmount,
      maxDepositAmount:       maxDepositAmount       ?? this.maxDepositAmount,
      minWithdrawalAmount:    minWithdrawalAmount    ?? this.minWithdrawalAmount,
      maxWithdrawalAmount:    maxWithdrawalAmount    ?? this.maxWithdrawalAmount,
      maintenanceMode:        maintenanceMode        ?? this.maintenanceMode,
      maintenanceMessage:     maintenanceMessage     ?? this.maintenanceMessage,
      walletFrozen:           walletFrozen           ?? this.walletFrozen,
      walletFreezeReason:     walletFreezeReason     ?? this.walletFreezeReason,
      sessionTimeoutMinutes:  sessionTimeoutMinutes  ?? this.sessionTimeoutMinutes,
      require2FA:             require2FA             ?? this.require2FA,
      supportEmail:           supportEmail           ?? this.supportEmail,
      discordInvite:          discordInvite          ?? this.discordInvite,
      appVersion:             appVersion             ?? this.appVersion,
      platformName:           platformName           ?? this.platformName,
      approvalWindowStart:    approvalWindowStart    ?? this.approvalWindowStart,
      approvalWindowEnd:      approvalWindowEnd      ?? this.approvalWindowEnd,
    );
  }
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

  DocumentReference<Map<String, dynamic>> get _ref =>
      _db.doc(_docPath);

  // ──────────────────────────────────────────────────────
  // REALTIME STREAM
  // ──────────────────────────────────────────────────────
  Stream<AdminSettings> settingsStream() {
    return _ref.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return const AdminSettings();
      }
      return AdminSettings.fromMap(snap.data()!);
    });
  }

  // ──────────────────────────────────────────────────────
  // ONE-TIME READ
  // ──────────────────────────────────────────────────────
  Future<AdminSettings> getSettings() async {
    final snap = await _ref.get();
    if (!snap.exists || snap.data() == null) return const AdminSettings();
    return AdminSettings.fromMap(snap.data()!);
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

    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    batch.set(_ref, {
      'upiId':              upiId.trim(),
      'upiPayeeName':       upiPayeeName.trim(),
      'minDepositAmount':   minDeposit,
      'maxDepositAmount':   maxDeposit,
      'minWithdrawalAmount': minWithdrawal,
      'maxWithdrawalAmount': maxWithdrawal,
      'updatedAt':          FieldValue.serverTimestamp(),
      'updatedBy':          _adminEmail,
    }, SetOptions(merge: true));

    batch.set(logRef, {
      'action':     'settings_updated',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'config/admin_settings',
      'details': {
        'section':          'payment',
        'upiId':            upiId.trim(),
        'minDepositAmount': minDeposit,
        'maxDepositAmount': maxDeposit,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // TOGGLE MAINTENANCE MODE
  // ──────────────────────────────────────────────────────
  Future<void> setMaintenanceMode(bool enabled, {String? message}) async {
    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    batch.set(_ref, {
      'maintenanceMode':    enabled,
      if (message != null) 'maintenanceMessage': message.trim(),
      'updatedAt':          FieldValue.serverTimestamp(),
      'updatedBy':          _adminEmail,
    }, SetOptions(merge: true));

    batch.set(logRef, {
      'action':     enabled ? 'maintenance_enabled' : 'maintenance_disabled',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'system',
      'details': {
        'enabled': enabled,
        if (message != null) 'message': message.trim(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

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
    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    batch.set(_ref, {
      'walletFrozen':      frozen,
      'walletFreezeReason': reason?.trim() ?? '',
      'updatedAt':          FieldValue.serverTimestamp(),
      'updatedBy':          _adminEmail,
    }, SetOptions(merge: true));

    batch.set(logRef, {
      'action':     frozen ? 'wallets_frozen' : 'wallets_unfrozen',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'system',
      'details': {
        'frozen': frozen,
        if (reason != null) 'reason': reason.trim(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    if (frozen) {
      _fireDangerWebhook(
        title:   '❄️  All Wallets FROZEN',
        color:   0xFFAA22,
        message: 'All wallet operations are now frozen. No deposits or withdrawals can be processed.',
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
    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    batch.set(_ref, {
      'sessionTimeoutMinutes': sessionTimeoutMinutes,
      'require2FA':            require2FA,
      'updatedAt':             FieldValue.serverTimestamp(),
      'updatedBy':             _adminEmail,
    }, SetOptions(merge: true));

    batch.set(logRef, {
      'action':     'settings_updated',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'config/admin_settings',
      'details': {
        'section':               'security',
        'sessionTimeoutMinutes': sessionTimeoutMinutes,
        'require2FA':            require2FA,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // UPDATE PLATFORM INFO
  // ──────────────────────────────────────────────────────
  Future<void> updatePlatformInfo({
    required String supportEmail,
    String? discordInvite,
    required String appVersion,
  }) async {
    final batch  = _db.batch();
    final logRef = _db.collection('admin_logs').doc();

    batch.set(_ref, {
      'supportEmail':  supportEmail.trim(),
      'discordInvite': discordInvite?.trim(),
      'appVersion':    appVersion.trim(),
      'updatedAt':     FieldValue.serverTimestamp(),
      'updatedBy':     _adminEmail,
    }, SetOptions(merge: true));

    batch.set(logRef, {
      'action':     'settings_updated',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  'config/admin_settings',
      'details': {
        'section':      'platform',
        'supportEmail': supportEmail.trim(),
        'appVersion':   appVersion.trim(),
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
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
      'details': {
        'playerName': playerName,
        'isAdmin':    isAdmin,
        'source':     'settings_page',
      },
      'createdAt': FieldValue.serverTimestamp(),
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
        body: jsonEncode({
          'embeds': [{
            'title': '🧪  Test Webhook — Shadow Storm Admin',
            'color': 0x9D55FF,
            'description': 'This is a test message sent from the admin panel.',
            'fields': [
              {'name': '👮 Sent by', 'value': _adminEmail, 'inline': true},
              {'name': '⏰ Time',    'value': DateTime.now().toLocal().toString(), 'inline': true},
            ],
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'footer':    {'text': 'Shadow Storm Admin Panel  •  Webhook Test'},
          }],
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[AdminSettingsService] Test webhook error: $e');
      return false;
    }
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
  // DANGER WEBHOOK (internal)
  // ──────────────────────────────────────────────────────
  void _fireDangerWebhook({
    required String title,
    required int    color,
    required String message,
    required String admin,
  }) {
    _sendWebhookAsync(title: title, color: color, message: message, admin: admin)
        .catchError((e) => debugPrint('[AdminSettingsService] webhook error: $e'));
  }

  Future<void> _sendWebhookAsync({
    required String title,
    required int    color,
    required String message,
    required String admin,
  }) async {
    await http.post(
      Uri.parse(AppSecrets.depositWebhook),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'embeds': [{
          'title':       title,
          'color':       color,
          'description': message,
          'fields': [
            {'name': '👮 Admin',    'value': admin, 'inline': true},
            {'name': '⚠️ Severity', 'value': 'HIGH', 'inline': true},
          ],
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Danger Action'},
        }],
      }),
    );
  }
}