// lib/admin/services/admin_user_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin User Service
// F2: readableId field, search by readable ID, expanded AdminUserData
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_secrets.dart';
import '../auth/admin_auth_service.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────
class AdminUserData {
  final String  uid;
  final String  name;
  final String  email;
  final String? photoUrl;
  final String? ign;
  final String? gameUid;
  final String? readableId;          // F2: SSP-000001 format
  final bool    isAdmin;
  final bool    isFrozen;
  final double  walletBalance;
  final double  totalDeposits;
  final double  totalWithdrawals;
  final double  totalEarnings;
  final int     wins;
  final int     tournamentsPlayed;
  final Timestamp? createdAt;
  final String? adminNote;

  AdminUserData({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.ign,
    this.gameUid,
    this.readableId,
    required this.isAdmin,
    required this.isFrozen,
    required this.walletBalance,
    required this.totalDeposits,
    required this.totalWithdrawals,
    required this.totalEarnings,
    required this.wins,
    required this.tournamentsPlayed,
    this.createdAt,
    this.adminNote,
  });

  factory AdminUserData.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminUserData(
      uid:              doc.id,
      name:             (d['name']        as String?) ?? 'Unknown',
      email:            (d['email']       as String?) ?? '',
      photoUrl:         d['photoUrl']     as String?,
      ign:              d['ign']          as String?,
      gameUid:          d['gameUid']      as String?,
      readableId:       d['readableId']   as String?,
      isAdmin:          (d['isAdmin']     as bool?) ?? false,
      isFrozen:         (d['isFrozen']    as bool?) ?? false,
      walletBalance:    (d['walletBalance']    as num?)?.toDouble() ?? 0.0,
      totalDeposits:    (d['totalDeposits']    as num?)?.toDouble() ?? 0.0,
      totalWithdrawals: (d['totalWithdrawals'] as num?)?.toDouble() ?? 0.0,
      totalEarnings:    (d['totalEarnings']    as num?)?.toDouble() ?? 0.0,
      wins:             (d['wins']             as num?)?.toInt()    ?? 0,
      tournamentsPlayed:(d['tournamentsPlayed'] as num?)?.toInt()   ?? 0,
      createdAt:        d['createdAt'] as Timestamp?,
      adminNote:        d['adminNote'] as String?,
    );
  }

  /// Display label shown in tables: "Name · SSP-000001"
  String get displayLabel {
    if (readableId != null && readableId!.isNotEmpty) {
      return '$name · $readableId';
    }
    return name;
  }
}

class AdminTransactionRecord {
  final String    id;
  final String    type;
  final double    amount;
  final String    status;
  final String    description;
  final Timestamp createdAt;

  AdminTransactionRecord({
    required this.id,
    required this.type,
    required this.amount,
    required this.status,
    required this.description,
    required this.createdAt,
  });

  factory AdminTransactionRecord.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminTransactionRecord(
      id:          doc.id,
      type:        (d['type']        as String?) ?? 'unknown',
      amount:      (d['amount']      as num?)?.toDouble() ?? 0.0,
      status:      (d['status']      as String?) ?? 'unknown',
      description: (d['description'] as String?) ?? '—',
      createdAt:   (d['createdAt']   as Timestamp?) ?? Timestamp.now(),
    );
  }
}

class AdminUserWithHistory {
  final AdminUserData                user;
  final List<AdminTransactionRecord> transactions;

  AdminUserWithHistory({required this.user, required this.transactions});
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────
class AdminUserService {
  AdminUserService._();
  static final AdminUserService instance = AdminUserService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _adminUid   => AdminAuthService.instance.currentUser?.uid   ?? 'unknown';
  String get _adminEmail => AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';

  // ──────────────────────────────────────────────────────
  // SEARCH BY READABLE ID
  // ──────────────────────────────────────────────────────
  Future<AdminUserData?> getUserByReadableId(String readableId) async {
    final snap = await _db
        .collection('users')
        .where('readableId', isEqualTo: readableId.trim().toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AdminUserData.fromDoc(snap.docs.first);
  }

  // ──────────────────────────────────────────────────────
  // SEARCH BY FIREBASE UID
  // ──────────────────────────────────────────────────────
  Future<AdminUserData?> getUserByUid(String uid) async {
    final doc = await _db.collection('users').doc(uid.trim()).get();
    if (!doc.exists) return null;
    return AdminUserData.fromDoc(doc);
  }

  // ──────────────────────────────────────────────────────
  // ADJUST BALANCE (atomic)
  // ──────────────────────────────────────────────────────
  Future<void> adjustBalance({
    required String uid,
    required String playerName,
    required double delta,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw Exception('Adjustment reason is required.');

    final userRef = _db.collection('users').doc(uid);
    final txnRef  = userRef.collection('transactions').doc();
    final logRef  = _db.collection('admin_logs').doc();

    await _db.runTransaction((txn) async {
      final snap    = await txn.get(userRef);
      final current = ((snap.data() ?? {})['walletBalance'] as num?)?.toDouble() ?? 0.0;
      final newBal  = current + delta;

      if (newBal < 0) {
        throw Exception(
            'Adjustment would result in negative balance. '
            'Current: ₹${current.toStringAsFixed(2)}, Delta: ₹${delta.toStringAsFixed(2)}');
      }

      final isCredit = delta >= 0;

      txn.update(userRef, {'walletBalance': FieldValue.increment(delta)});

      txn.set(txnRef, {
        'type':        isCredit ? 'deposit' : 'withdrawal',
        'amount':      delta.abs(),
        'status':      'completed',
        'description': 'Admin adjustment: ${reason.trim()}',
        'isCredit':    isCredit,
        'createdAt':   FieldValue.serverTimestamp(),
      });

      txn.set(logRef, {
        'action':     'balance_adjusted',
        'adminUid':   _adminUid,
        'adminEmail': _adminEmail,
        'targetUid':  uid,
        'details': {
          'playerName': playerName,
          'delta':      delta,
          'before':     current,
          'after':      newBal,
          'reason':     reason.trim(),
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    _fireAdjustWebhook(
        playerName: playerName, uid: uid,
        delta: delta, reason: reason.trim(), adminEmail: _adminEmail);
  }

  // ──────────────────────────────────────────────────────
  // SET ADMIN FLAG
  // ──────────────────────────────────────────────────────
  Future<void> setAdminFlag({
    required String uid,
    required String playerName,
    required bool   isAdmin,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final logRef  = _db.collection('admin_logs').doc();
    final batch   = _db.batch();

    batch.update(userRef, {'isAdmin': isAdmin});

    batch.set(logRef, {
      'action':     isAdmin ? 'admin_promoted' : 'admin_demoted',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details': {'playerName': playerName, 'isAdmin': isAdmin},
      'createdAt':  FieldValue.serverTimestamp(),
    });

    await batch.commit();
    _fireAdminToggleWebhook(
        playerName: playerName, uid: uid,
        promoted: isAdmin, adminEmail: _adminEmail);
  }

  // ──────────────────────────────────────────────────────
  // SET FROZEN STATE
  // ──────────────────────────────────────────────────────
  Future<void> setFrozen({
    required String uid,
    required String playerName,
    required bool   frozen,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final logRef  = _db.collection('admin_logs').doc();
    final batch   = _db.batch();

    batch.update(userRef, {'isFrozen': frozen});

    batch.set(logRef, {
      'action':     frozen ? 'account_frozen' : 'account_unfrozen',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details': {'playerName': playerName, 'frozen': frozen},
      'createdAt':  FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // GET USER WITH HISTORY
  // ──────────────────────────────────────────────────────
  Future<AdminUserWithHistory> getUserWithHistory(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final txnRef  = userRef.collection('transactions')
        .orderBy('createdAt', descending: true)
        .limit(20);

    final results = await Future.wait([userRef.get(), txnRef.get()]);

    final userDoc = results[0] as DocumentSnapshot;
    final txnSnap = results[1] as QuerySnapshot;

    return AdminUserWithHistory(
      user:         AdminUserData.fromDoc(userDoc),
      transactions: txnSnap.docs
          .map((d) => AdminTransactionRecord.fromDoc(d))
          .toList(),
    );
  }

  // ──────────────────────────────────────────────────────
  // ADD ADMIN NOTE
  // ──────────────────────────────────────────────────────
  Future<void> addAdminNote({required String uid, required String note}) async {
    final userRef = _db.collection('users').doc(uid);
    final logRef  = _db.collection('admin_logs').doc();
    final batch   = _db.batch();

    batch.update(userRef, {
      'adminNote':   note.trim(),
      'adminNoteBy': _adminEmail,
      'adminNoteAt': FieldValue.serverTimestamp(),
    });

    batch.set(logRef, {
      'action':     'admin_note_added',
      'adminUid':   _adminUid,
      'adminEmail': _adminEmail,
      'targetUid':  uid,
      'details':    {'note': note.trim()},
      'createdAt':  FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ──────────────────────────────────────────────────────
  // DISCORD WEBHOOKS
  // ──────────────────────────────────────────────────────
  void _fireAdjustWebhook({
    required String playerName,
    required String uid,
    required double delta,
    required String reason,
    required String adminEmail,
  }) {
    _sendAdjustWebhookAsync(
      playerName: playerName, uid: uid,
      delta: delta, reason: reason, adminEmail: adminEmail,
    ).catchError((e) => debugPrint('[AdminUserService] Adjust webhook error: $e'));
  }

  Future<void> _sendAdjustWebhookAsync({
    required String playerName, required String uid,
    required double delta,      required String reason,
    required String adminEmail,
  }) async {
    final isCredit = delta >= 0;
    final shortUid = uid.length > 12 ? '${uid.substring(0, 12)}...' : uid;
    await http.post(
      Uri.parse(AppSecrets.depositWebhook),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'embeds': [{
        'title':  '${isCredit ? '➕' : '➖'}  Balance ${isCredit ? 'Credited' : 'Debited'} by Admin',
        'color':   isCredit ? 0x44FF99 : 0xFF9944,
        'fields': [
          {'name': '👤 Player', 'value': playerName,                           'inline': true},
          {'name': '🆔 UID',    'value': '`$shortUid`',                        'inline': true},
          {'name': '💰 Amount', 'value': '₹${delta.abs().toStringAsFixed(2)}', 'inline': true},
          {'name': '👮 Admin',  'value': adminEmail,                            'inline': true},
          {'name': '📝 Reason', 'value': reason,                                'inline': false},
        ],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'footer':    {'text': 'Shadow Storm Admin Panel  •  User Management'},
      }]}),
    );
  }

  void _fireAdminToggleWebhook({
    required String playerName, required String uid,
    required bool   promoted,   required String adminEmail,
  }) {
    _sendAdminToggleWebhookAsync(
      playerName: playerName, uid: uid,
      promoted: promoted, adminEmail: adminEmail,
    ).catchError((e) => debugPrint('[AdminUserService] Admin toggle webhook error: $e'));
  }

  Future<void> _sendAdminToggleWebhookAsync({
    required String playerName, required String uid,
    required bool   promoted,   required String adminEmail,
  }) async {
    final shortUid = uid.length > 12 ? '${uid.substring(0, 12)}...' : uid;
    await http.post(
      Uri.parse(AppSecrets.depositWebhook),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'embeds': [{
        'title':  '${promoted ? '🛡️' : '👤'}  Admin ${promoted ? 'Promoted' : 'Demoted'}',
        'color':   promoted ? 0x9D55FF : 0xFF9944,
        'fields': [
          {'name': '👤 Player',  'value': playerName,   'inline': true},
          {'name': '🆔 UID',     'value': '`$shortUid`','inline': true},
          {'name': '🔑 Status',  'value': promoted ? 'ADMIN' : 'USER', 'inline': true},
          {'name': '👮 By Admin','value': adminEmail,    'inline': true},
        ],
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'footer':    {'text': 'Shadow Storm Admin Panel  •  User Management'},
      }]}),
    );
  }
}