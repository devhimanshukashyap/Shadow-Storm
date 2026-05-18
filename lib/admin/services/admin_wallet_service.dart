// lib/admin/services/admin_wallet_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Wallet Service
// Atomic deposit approval/rejection + Discord webhooks
// NEVER import this from the main app — admin-only
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/app_secrets.dart';
import '../auth/admin_auth_service.dart';

class AdminWalletService {
  AdminWalletService._();
  static final AdminWalletService instance = AdminWalletService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────────────
  // APPROVE DEPOSIT
  // Single atomic Firestore transaction:
  //   1. Set deposit_requests/{id}.status = 'approved'
  //   2. Increment users/{uid}.walletBalance
  //   3. Increment users/{uid}.totalDeposits
  //   4. Create users/{uid}/transactions/{id}
  // ──────────────────────────────────────────────────────
  Future<void> approveDeposit({
    required String uid,
    required String requestId,
    required double amount,
    required String utr,
    required String playerName,
    String? adminNote,
  }) async {
    final requestRef = _db
        .collection('users')
        .doc(uid)
        .collection('deposit_requests')
        .doc(requestId);

    final userRef = _db.collection('users').doc(uid);
    final txnRef  = userRef.collection('transactions').doc();

    final resolvedNote = (adminNote == null || adminNote.trim().isEmpty)
        ? 'Approved by admin'
        : adminNote.trim();

    // ── Atomic transaction ────────────────────
    await _db.runTransaction((txn) async {
      final snap = await txn.get(requestRef);

      if (!snap.exists) {
        throw Exception('Deposit request not found.');
      }

      final currentStatus = (snap.data() ?? {})['status'] as String?;
      if (currentStatus != 'pending') {
        throw Exception('Cannot approve — request is already "$currentStatus".');
      }

      // 1 — Mark request approved
      txn.update(requestRef, {
        'status':      'approved',
        'adminNote':   resolvedNote,
        'processedAt': FieldValue.serverTimestamp(),
      });

      // 2 — Credit wallet
      txn.update(userRef, {
        'walletBalance': FieldValue.increment(amount),
        'totalDeposits': FieldValue.increment(amount),
      });

      // 3 — Create transaction record
      txn.set(txnRef, {
        'type':               'deposit',
        'amount':             amount,
        'status':             'completed',
        'description':        'Deposit approved — UTR: $utr',
        'utr':                utr,
        'depositRequestId':   requestId,
        'createdAt':          FieldValue.serverTimestamp(),
      });
    });

    // ── Discord webhook (fire & forget, never throws) ──
    _fireWebhook(
      action:      'APPROVED',
      playerName:  playerName,
      uid:         uid,
      amount:      amount,
      utr:         utr,
      requestId:   requestId,
      adminNote:   resolvedNote,
    );
  }

  // ──────────────────────────────────────────────────────
  // REJECT DEPOSIT
  // Simple write — wallet is NOT touched on rejection.
  //   1. Set deposit_requests/{id}.status = 'rejected'
  //   2. Set deposit_requests/{id}.adminNote = reason
  // ──────────────────────────────────────────────────────
  Future<void> rejectDeposit({
    required String uid,
    required String requestId,
    required double amount,
    required String utr,
    required String playerName,
    required String adminNote,
  }) async {
    if (adminNote.trim().isEmpty) {
      throw Exception('Admin note is required for rejection.');
    }

    final requestRef = _db
        .collection('users')
        .doc(uid)
        .collection('deposit_requests')
        .doc(requestId);

    final snap = await requestRef.get();
    if (!snap.exists) throw Exception('Deposit request not found.');

    final currentStatus = (snap.data() ?? {})['status'] as String?;
    if (currentStatus != 'pending') {
      throw Exception('Cannot reject — request is already "$currentStatus".');
    }

    await requestRef.update({
      'status':      'rejected',
      'adminNote':   adminNote.trim(),
      'processedAt': FieldValue.serverTimestamp(),
    });

    _fireWebhook(
      action:      'REJECTED',
      playerName:  playerName,
      uid:         uid,
      amount:      amount,
      utr:         utr,
      requestId:   requestId,
      adminNote:   adminNote.trim(),
    );
  }

  // ──────────────────────────────────────────────────────
  // DISCORD WEBHOOK (internal)
  // ──────────────────────────────────────────────────────
  void _fireWebhook({
    required String action,
    required String playerName,
    required String uid,
    required double amount,
    required String utr,
    required String requestId,
    String? adminNote,
  }) {
    _sendWebhookAsync(
      action:     action,
      playerName: playerName,
      uid:        uid,
      amount:     amount,
      utr:        utr,
      requestId:  requestId,
      adminNote:  adminNote,
    ).catchError((dynamic e) {
      debugPrint('[AdminWalletService] Discord webhook error: $e');
    });
  }

  Future<void> _sendWebhookAsync({
    required String action,
    required String playerName,
    required String uid,
    required double amount,
    required String utr,
    required String requestId,
    String? adminNote,
  }) async {
    final isApproved   = action == 'APPROVED';
    final adminEmail   = AdminAuthService.instance.currentUser?.email ?? 'Unknown Admin';
    final shortUid     = uid.length > 12 ? '${uid.substring(0, 12)}...' : uid;
    final shortReqId   = requestId.length > 12 ? '${requestId.substring(0, 12)}...' : requestId;

    final fields = <Map<String, dynamic>>[
      {'name': '👤 Player',     'value': playerName,                    'inline': true},
      {'name': '🆔 UID',        'value': '`$shortUid`',                 'inline': true},
      {'name': '💰 Amount',     'value': '₹${amount.toStringAsFixed(2)}','inline': true},
      {'name': '🔖 UTR',        'value': '`$utr`',                      'inline': true},
      {'name': '📋 Request ID', 'value': '`$shortReqId`',               'inline': true},
      {'name': '👮 Admin',      'value': adminEmail,                     'inline': true},
    ];

    if (adminNote != null && adminNote.isNotEmpty) {
      fields.add({'name': '📝 Note', 'value': adminNote, 'inline': false});
    }

    final payload = {
      'embeds': [
        {
          'title':     '${isApproved ? '✅' : '❌'}  Deposit $action',
          'color':     isApproved ? 0x44FF99 : 0xFF4466,
          'fields':    fields,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'footer':    {'text': 'Shadow Storm Admin Panel  •  Deposit Management'},
        }
      ],
    };

    final response = await http.post(
      Uri.parse(AppSecrets.depositWebhook),
      headers: {'Content-Type': 'application/json'},
      body:    jsonEncode(payload),
    );

    debugPrint('[AdminWalletService] Webhook status: ${response.statusCode}');
  }
}