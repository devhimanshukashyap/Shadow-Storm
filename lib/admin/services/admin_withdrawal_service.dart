// lib/admin/services/admin_withdrawal_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Withdrawal Service
// Atomic withdrawal approval/rejection + Discord webhooks
// NEVER import this from the main app — admin-only
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_secrets.dart';
import '../auth/admin_auth_service.dart';

class AdminWithdrawalService {
  AdminWithdrawalService._();
  static final AdminWithdrawalService instance = AdminWithdrawalService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────
  // APPROVE WITHDRAWAL
  // Atomic Firestore transaction:
  //   1. Validate status == 'pending'
  //   2. Validate walletBalance >= amount
  //   3. Set withdraw_requests/{id}.status = 'approved'
  //   4. Decrement users/{uid}.walletBalance
  //   5. Increment users/{uid}.totalWithdrawals
  //   6. Create users/{uid}/transactions/{id} type=withdrawal
  //   7. Create admin_logs/{id}
  //   8. Fire Discord webhook
  // ──────────────────────────────────────────────────────
  Future<void> approveWithdrawal({
    required String uid,
    required String requestId,
    required double amount,
    required String playerName,
    required String payoutReference,
    String? adminNote,
  }) async {
    final requestRef = _db
        .collection('users')
        .doc(uid)
        .collection('withdraw_requests')
        .doc(requestId);

    final userRef  = _db.collection('users').doc(uid);
    final txnRef   = userRef.collection('transactions').doc();
    final logRef   = _db.collection('admin_logs').doc();

    final adminUser  = AdminAuthService.instance.currentUser;
    final adminUid   = adminUser?.uid ?? 'unknown';
    final adminEmail = adminUser?.email ?? 'Unknown Admin';

    final resolvedNote = (adminNote == null || adminNote.trim().isEmpty)
        ? 'Withdrawal approved — payout ref: $payoutReference'
        : adminNote.trim();

    await _db.runTransaction((txn) async {
      final reqSnap  = await txn.get(requestRef);
      final userSnap = await txn.get(userRef);

      if (!reqSnap.exists) {
        throw Exception('Withdrawal request not found.');
      }

      final currentStatus = (reqSnap.data() ?? {})['status'] as String?;
      if (currentStatus != 'pending') {
        throw Exception('Cannot approve — request is already "$currentStatus".');
      }

      final currentBalance =
          ((userSnap.data() ?? {})['walletBalance'] as num?)?.toDouble() ?? 0.0;
      if (currentBalance < amount) {
        throw Exception(
            'Insufficient wallet balance. Current: ₹${currentBalance.toStringAsFixed(2)}, Required: ₹${amount.toStringAsFixed(2)}');
      }

      // 1 — Mark request approved
      txn.update(requestRef, {
        'status':          'approved',
        'adminNote':       resolvedNote,
        'payoutReference': payoutReference,
        'processedAt':     FieldValue.serverTimestamp(),
      });

      // 2 — Deduct wallet + increment totalWithdrawals
      txn.update(userRef, {
        'walletBalance':    FieldValue.increment(-amount),
        'totalWithdrawals': FieldValue.increment(amount),
      });

      // 3 — Create transaction record
      txn.set(txnRef, {
        'type':              'withdrawal',
        'amount':            amount,
        'status':            'completed',
        'description':       'Withdrawal approved — ref: $payoutReference',
        'withdrawRequestId': requestId,
        'payoutReference':   payoutReference,
        'createdAt':         FieldValue.serverTimestamp(),
      });

      // 4 — Create admin log
      txn.set(logRef, {
        'action':      'withdrawal_approved',
        'adminUid':    adminUid,
        'adminEmail':  adminEmail,
        'targetUid':   uid,
        'details': {
          'requestId':       requestId,
          'amount':          amount,
          'playerName':      playerName,
          'payoutReference': payoutReference,
          'adminNote':       resolvedNote,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    // Discord webhook (fire & forget)
    _fireWebhook(
      action:          'APPROVED',
      playerName:      playerName,
      uid:             uid,
      amount:          amount,
      requestId:       requestId,
      payoutReference: payoutReference,
      adminNote:       resolvedNote,
      adminEmail:      adminEmail,
      requestData:     null,
    );
  }

  // ──────────────────────────────────────────────────────
  // REJECT WITHDRAWAL
  // Atomic Firestore transaction:
  //   1. Validate status == 'pending'
  //   2. Mark rejected
  //   3. Refund walletBalance (was deducted at request creation)
  //   4. Create refund transaction record
  //   5. Create admin_logs entry
  //   6. Fire Discord webhook
  // ──────────────────────────────────────────────────────
  Future<void> rejectWithdrawal({
    required String uid,
    required String requestId,
    required double amount,
    required String playerName,
    required String adminNote,
  }) async {
    if (adminNote.trim().isEmpty) {
      throw Exception('Admin note (rejection reason) is required.');
    }

    final requestRef = _db
        .collection('users')
        .doc(uid)
        .collection('withdraw_requests')
        .doc(requestId);

    final userRef = _db.collection('users').doc(uid);
    final txnRef  = userRef.collection('transactions').doc();
    final logRef  = _db.collection('admin_logs').doc();

    final adminUser  = AdminAuthService.instance.currentUser;
    final adminUid   = adminUser?.uid ?? 'unknown';
    final adminEmail = adminUser?.email ?? 'Unknown Admin';

    await _db.runTransaction((txn) async {
      final reqSnap = await txn.get(requestRef);

      if (!reqSnap.exists) {
        throw Exception('Withdrawal request not found.');
      }

      final currentStatus = (reqSnap.data() ?? {})['status'] as String?;
      if (currentStatus != 'pending') {
        throw Exception('Cannot reject — request is already "$currentStatus".');
      }

      // 1 — Mark rejected
      txn.update(requestRef, {
        'status':      'rejected',
        'adminNote':   adminNote.trim(),
        'processedAt': FieldValue.serverTimestamp(),
      });

      // 2 — Refund wallet (main app deducts on creation)
      txn.update(userRef, {
        'walletBalance': FieldValue.increment(amount),
      });

      // 3 — Create refund transaction record
      txn.set(txnRef, {
        'type':              'refund',
        'amount':            amount,
        'status':            'completed',
        'description':       'Withdrawal rejected — refund: ${adminNote.trim()}',
        'withdrawRequestId': requestId,
        'createdAt':         FieldValue.serverTimestamp(),
      });

      // 4 — Create admin log
      txn.set(logRef, {
        'action':      'withdrawal_rejected',
        'adminUid':    adminUid,
        'adminEmail':  adminEmail,
        'targetUid':   uid,
        'details': {
          'requestId':  requestId,
          'amount':     amount,
          'playerName': playerName,
          'adminNote':  adminNote.trim(),
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    // Discord webhook (fire & forget)
    _fireWebhook(
      action:          'REJECTED',
      playerName:      playerName,
      uid:             uid,
      amount:          amount,
      requestId:       requestId,
      payoutReference: null,
      adminNote:       adminNote.trim(),
      adminEmail:      adminEmail,
      requestData:     null,
    );
  }

  // ──────────────────────────────────────────────────────
  // DISCORD WEBHOOK (internal)
  // ──────────────────────────────────────────────────────
  void _fireWebhook({
    required String  action,
    required String  playerName,
    required String  uid,
    required double  amount,
    required String  requestId,
    required String  adminEmail,
    String?          payoutReference,
    String?          adminNote,
    Map<String, dynamic>? requestData,
  }) {
    _sendWebhookAsync(
      action:          action,
      playerName:      playerName,
      uid:             uid,
      amount:          amount,
      requestId:       requestId,
      payoutReference: payoutReference,
      adminNote:       adminNote,
      adminEmail:      adminEmail,
      requestData:     requestData,
    ).catchError((dynamic e) {
      debugPrint('[AdminWithdrawalService] Discord webhook error: $e');
    });
  }

  Future<void> _sendWebhookAsync({
    required String  action,
    required String  playerName,
    required String  uid,
    required double  amount,
    required String  requestId,
    required String  adminEmail,
    String?          payoutReference,
    String?          adminNote,
    Map<String, dynamic>? requestData,
  }) async {
    final isApproved  = action == 'APPROVED';
    final shortUid    = uid.length > 12 ? '${uid.substring(0, 12)}...' : uid;
    final shortReqId  = requestId.length > 12 ? '${requestId.substring(0, 12)}...' : requestId;

    final fields = <Map<String, dynamic>>[
      {'name': '👤 Player',    'value': playerName,                     'inline': true},
      {'name': '🆔 UID',       'value': '`$shortUid`',                  'inline': true},
      {'name': '💸 Amount',    'value': '₹${amount.toStringAsFixed(2)}', 'inline': true},
      {'name': '📋 Request ID','value': '`$shortReqId`',                'inline': true},
      {'name': '👮 Admin',     'value': adminEmail,                      'inline': true},
    ];

    if (requestData != null) {
      final method = requestData['method'] as String? ?? 'upi';
      if (method == 'upi') {
        final upiId = requestData['upiId'] as String? ?? '—';
        fields.add({'name': '📱 UPI ID', 'value': upiId, 'inline': true});
      } else {
        final bank    = requestData['bankName']      as String? ?? '—';
        final account = requestData['accountNumber'] as String? ?? '—';
        fields.add({'name': '🏦 Bank',    'value': bank,        'inline': true});
        fields.add({'name': '🔢 Account', 'value': '`$account`','inline': true});
      }
    }

    if (isApproved && payoutReference != null) {
      fields.add({'name': '🧾 Payout Ref', 'value': payoutReference, 'inline': false});
    }

    if (adminNote != null && adminNote.isNotEmpty) {
      fields.add({'name': '📝 Note', 'value': adminNote, 'inline': false});
    }

    final payload = {
      'embeds': [
        {
          'title':     '${isApproved ? '✅' : '❌'}  Withdrawal $action',
          'color':     isApproved ? 0x44FF99 : 0xFF4466,
          'fields':    fields,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Withdrawal Management'},
        }
      ],
    };

    final response = await http.post(
      Uri.parse(AppSecrets.withdrawWebhook),
      headers: {'Content-Type': 'application/json'},
      body:    jsonEncode(payload),
    );

    debugPrint('[AdminWithdrawalService] Webhook status: ${response.statusCode}');
  }
}