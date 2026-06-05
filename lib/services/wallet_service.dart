// lib/services/wallet_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Wallet Service (Phase F2.5 / PRE-F3)
//
// Changes from Phase F1 / v3:
//   • Added `currentUid` getter — exposed so WalletScreen._TransactionCenter
//     can check auth state without importing FirebaseAuth directly.
//   • Added `db` getter — exposed so _TransactionCenter can build its own
//     Firestore queries for the unified transaction stream (merges
//     deposit_requests + withdraw_requests + transactions subcollections).
//
//   All original v3 logic unchanged:
//     submitDepositRequest(), depositRequestsStream(),
//     submitWithdrawRequest(), withdrawRequestsStream(),
//     transactionsStream(), walletDataStream(), getCurrentBalance(),
//     Discord webhooks, UTR duplicate check, balance guard.
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

// ─────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────

const _kUpiId       = 'shadowstormpay@ibl';
const _kPayeeName   = 'Himanshu Kashyap';
const _kMinDeposit  = 50.0;
const _kMinWithdraw = 50.0;

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

class WalletData {
  final double balance;
  final double totalEarnings;
  final double totalDeposits;
  final double totalWithdrawals;

  const WalletData({
    required this.balance,
    required this.totalEarnings,
    required this.totalDeposits,
    required this.totalWithdrawals,
  });

  factory WalletData.fromDoc(Map<String, dynamic> d) => WalletData(
    balance:          (d['walletBalance']    ?? 0).toDouble(),
    totalEarnings:    (d['totalEarnings']    ?? 0).toDouble(),
    totalDeposits:    (d['totalDeposits']    ?? 0).toDouble(),
    totalWithdrawals: (d['totalWithdrawals'] ?? 0).toDouble(),
  );

  static const empty = WalletData(balance: 0, totalEarnings: 0, totalDeposits: 0, totalWithdrawals: 0);
}

class DepositRequest {
  final String   id;
  final double   amount;
  final String   utr;
  final String   status;
  final String?  adminNote;
  final DateTime createdAt;

  const DepositRequest({required this.id, required this.amount, required this.utr, required this.status, this.adminNote, required this.createdAt});

  factory DepositRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DepositRequest(
      id:        doc.id,
      amount:    (d['amount']    ?? 0).toDouble(),
      utr:       d['utr']        as String? ?? '',
      status:    d['status']     as String? ?? 'pending',
      adminNote: d['adminNote']  as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class WithdrawRequest {
  final String   id;
  final double   amount;
  final String   method;
  final String   upiId;
  final String   accountHolder;
  final String   bankName;
  final String   accountNumber;
  final String   ifscCode;
  final String   status;
  final String?  adminNote;
  final DateTime createdAt;

  const WithdrawRequest({required this.id, required this.amount, required this.method, required this.upiId, required this.accountHolder, required this.bankName, required this.accountNumber, required this.ifscCode, required this.status, this.adminNote, required this.createdAt});

  factory WithdrawRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WithdrawRequest(
      id:            doc.id,
      amount:        (d['amount']       ?? 0).toDouble(),
      method:        d['method']        as String? ?? 'upi',
      upiId:         d['upiId']         as String? ?? '',
      accountHolder: d['accountHolder'] as String? ?? '',
      bankName:      d['bankName']      as String? ?? '',
      accountNumber: d['accountNumber'] as String? ?? '',
      ifscCode:      d['ifscCode']      as String? ?? '',
      status:        d['status']        as String? ?? 'pending',
      adminNote:     d['adminNote']     as String?,
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class WalletTransaction {
  final String   id;
  final double   amount;
  final String   type;
  final String   status;
  final String?  description;
  final String?  tournamentId;
  final DateTime createdAt;

  const WalletTransaction({required this.id, required this.amount, required this.type, required this.status, this.description, this.tournamentId, required this.createdAt});

  factory WalletTransaction.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id:           doc.id,
      amount:       (d['amount']     ?? 0).toDouble(),
      type:         d['type']        as String? ?? 'deposit',
      status:       d['status']      as String? ?? 'pending',
      description:  d['description'] as String?,
      tournamentId: d['tournamentId'] as String?,
      createdAt:    (d['createdAt']  as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isCredit => type == 'deposit' || type == 'winnings' || type == 'refund';
}

// ─────────────────────────────────────────────
// UPI UTILITIES
// ─────────────────────────────────────────────

String buildUpiDeepLink(double amount) {
  final encoded = Uri.encodeComponent(_kPayeeName);
  return 'upi://pay?pa=$_kUpiId&pn=$encoded&am=${amount.toStringAsFixed(2)}&cu=INR&tn=Shadow+Storm+Deposit';
}

String get upiId => _kUpiId;

// ─────────────────────────────────────────────
// WALLET SERVICE
// ─────────────────────────────────────────────
class WalletService {
  WalletService._();
  static final WalletService instance = WalletService._();

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;

  // ── F2.5: Exposed getters for TransactionCenter ──

  /// Current user's Firebase UID. Null if not logged in.
  String? get currentUid => _auth.currentUser?.uid;

  /// Firestore instance for building subcollection queries in wallet_screen.
  FirebaseFirestore get db => _db;

  // ── Private helpers ──────────────────────────

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference _depositCol(String uid)  => _db.collection('users').doc(uid).collection('deposit_requests');
  CollectionReference _withdrawCol(String uid) => _db.collection('users').doc(uid).collection('withdraw_requests');
  CollectionReference _txCol(String uid)       => _db.collection('users').doc(uid).collection('transactions');

  // ─────────────────────────────────────────────
  // WALLET SUMMARY STREAM
  // ─────────────────────────────────────────────

  Stream<WalletData> walletDataStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(WalletData.empty);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return WalletData.empty;
      return WalletData.fromDoc(snap.data()!);
    });
  }

  // ─────────────────────────────────────────────
  // CURRENT BALANCE (one-time read for validation)
  // ─────────────────────────────────────────────

  Future<double> getCurrentBalance() async {
    final uid = _uid;
    if (uid == null) return 0.0;
    final snap = await _db.collection('users').doc(uid).get();
    return (snap.data()?['walletBalance'] ?? 0).toDouble();
  }

  // ─────────────────────────────────────────────
  // DEPOSIT REQUESTS
  // ─────────────────────────────────────────────

  Future<void> submitDepositRequest({required double amount, required String utr}) async {
    final uid  = _uid;
    final user = _auth.currentUser;
    if (uid == null || user == null) throw Exception('Not logged in.');

    if (amount < _kMinDeposit) throw Exception('Minimum deposit is ₹${_kMinDeposit.toStringAsFixed(0)}.');

    final utrTrimmed = utr.trim();
    if (utrTrimmed.isEmpty || utrTrimmed.length < 6) throw Exception('Invalid UTR number. Please check and try again.');

    final col = _depositCol(uid);

    final dup = await col.where('utr', isEqualTo: utrTrimmed).limit(1).get();
    if (dup.docs.isNotEmpty) throw Exception('A deposit request with this UTR already exists. Contact support if this is a mistake.');

    final now = DateTime.now();
    final ref = await col.add({
      'amount':    amount,
      'utr':       utrTrimmed,
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _sendDepositWebhook(requestId: ref.id, playerName: user.displayName ?? 'Unknown', uid: uid, amount: amount, utr: utrTrimmed, createdAt: now);
  }

  Stream<List<DepositRequest>> depositRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _depositCol(uid).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(DepositRequest.fromDoc).toList());
  }

  // ─────────────────────────────────────────────
  // WITHDRAW REQUESTS
  // ─────────────────────────────────────────────

  Future<void> submitWithdrawRequest({
    required double amount,
    required String method,
    required String upiId,
    required String accountHolder,
    required String bankName,
    required String accountNumber,
    required String ifscCode,
  }) async {
    final uid  = _uid;
    final user = _auth.currentUser;
    if (uid == null || user == null) throw Exception('Not logged in.');

    if (amount < _kMinWithdraw) throw Exception('Minimum withdrawal is ₹${_kMinWithdraw.toStringAsFixed(0)}.');
    if (amount <= 0) throw Exception('Invalid withdrawal amount.');

    final snap    = await _db.collection('users').doc(uid).get();
    final balance = (snap.data()?['walletBalance'] ?? 0).toDouble();

    if (amount > balance) throw Exception('Insufficient wallet balance. Available: ₹${balance.toStringAsFixed(2)}. Requested: ₹${amount.toStringAsFixed(2)}.');

    final col = _withdrawCol(uid);

    final pending = await col.where('status', isEqualTo: 'pending').limit(1).get();
    if (pending.docs.isNotEmpty) throw Exception('You already have a pending withdrawal request. Wait for it to be processed first.');

    final now = DateTime.now();
    final ref = await col.add({
      'amount':        amount,
      'method':        method,
      'upiId':         upiId.trim(),
      'accountHolder': accountHolder.trim(),
      'bankName':      bankName.trim(),
      'accountNumber': accountNumber.trim(),
      'ifscCode':      ifscCode.trim().toUpperCase(),
      'status':        'pending',
      'createdAt':     FieldValue.serverTimestamp(),
    });

    await _sendWithdrawWebhook(requestId: ref.id, playerName: user.displayName ?? 'Unknown', uid: uid, amount: amount, upiId: upiId.trim(), accountHolder: accountHolder.trim(), method: method, createdAt: now);
  }

  Stream<List<WithdrawRequest>> withdrawRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _withdrawCol(uid).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(WithdrawRequest.fromDoc).toList());
  }

  // ─────────────────────────────────────────────
  // TRANSACTION HISTORY
  // ─────────────────────────────────────────────

  Stream<List<WalletTransaction>> transactionsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _txCol(uid).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(WalletTransaction.fromDoc).toList());
  }

  // ─────────────────────────────────────────────
  // DISCORD WEBHOOKS
  // ─────────────────────────────────────────────

  Future<void> _sendDepositWebhook({required String requestId, required String playerName, required String uid, required double amount, required String utr, required DateTime createdAt}) async {
    final url = AppSecrets.depositWebhook;
    if (url.isEmpty) return;
    try {
      await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'embeds': [{
          'title': '💰 NEW DEPOSIT REQUEST',
          'color': 0x44FF99,
          'fields': [
            {'name': '👤 Player', 'value': playerName, 'inline': true},
            {'name': '🆔 UID',    'value': '`$uid`',   'inline': true},
            {'name': '💵 Amount', 'value': '**₹${amount.toStringAsFixed(2)}**', 'inline': true},
            {'name': '🔢 UTR',    'value': '`$utr`',   'inline': true},
            {'name': '🗂️ ID',     'value': '`$requestId`', 'inline': true},
            {'name': '📌 Status', 'value': '🟡 **PENDING**', 'inline': true},
          ],
          'timestamp': createdAt.toUtc().toIso8601String(),
          'footer': {'text': 'Shadow Storm Wallet  •  Deposit'},
        }],
      }));
    } catch (_) {}
  }

  Future<void> _sendWithdrawWebhook({required String requestId, required String playerName, required String uid, required double amount, required String upiId, required String accountHolder, required String method, required DateTime createdAt}) async {
    final url = AppSecrets.withdrawWebhook;
    if (url.isEmpty) return;
    try {
      await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'embeds': [{
          'title': '📤 NEW WITHDRAWAL REQUEST',
          'color': 0xFF4466,
          'fields': [
            {'name': '👤 Player',      'value': playerName, 'inline': true},
            {'name': '🆔 UID',         'value': '`$uid`',   'inline': true},
            {'name': '💸 Amount',      'value': '**₹${amount.toStringAsFixed(2)}**', 'inline': true},
            {'name': '💳 Method',      'value': method == 'upi' ? '📱 UPI' : '🏦 Bank', 'inline': true},
            {'name': '🏦 Destination', 'value': method == 'upi' ? '`$upiId`' : '`$accountHolder`', 'inline': true},
            {'name': '🗂️ ID',          'value': '`$requestId`', 'inline': true},
          ],
          'timestamp': createdAt.toUtc().toIso8601String(),
          'footer': {'text': 'Shadow Storm Wallet  •  Withdrawal'},
        }],
      }));
    } catch (_) {}
  }
}