// lib/services/wallet_service.dart
// ─────────────────────────────────────────────
// WALLET SERVICE  — Shadow Storm
// Handles all Firestore read/write for:
//   • wallet data (balance, earnings, deposits, withdrawals)
//   • deposit_requests/
//   • withdraw_requests/
//   • wallet_transactions/
//
// NOTE: Firebase Storage and image_picker removed.
//       Screenshot upload is no longer required.
//       Users send screenshots manually via Discord / Telegram.
//
// SECURITY RULE:
//   Frontend NEVER directly modifies walletBalance.
//   All balance updates happen via admin approval logic on backend.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

/// Wallet summary data for the Balance Overview card.
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

  factory WalletData.fromDoc(Map<String, dynamic> data) {
    return WalletData(
      balance:          (data['walletBalance']    ?? 0).toDouble(),
      totalEarnings:    (data['totalEarnings']    ?? 0).toDouble(),
      totalDeposits:    (data['totalDeposits']    ?? 0).toDouble(),
      totalWithdrawals: (data['totalWithdrawals'] ?? 0).toDouble(),
    );
  }

  static WalletData get empty => const WalletData(
    balance: 0, totalEarnings: 0, totalDeposits: 0, totalWithdrawals: 0,
  );
}

/// A single deposit request document.
/// screenshotUrl removed — users send screenshots manually via Discord/Telegram.
class DepositRequest {
  final String   id;
  final String   uid;
  final double   amount;
  final String   utr;
  final String   status;   // pending | approved | rejected
  final DateTime createdAt;

  const DepositRequest({
    required this.id,
    required this.uid,
    required this.amount,
    required this.utr,
    required this.status,
    required this.createdAt,
  });

  factory DepositRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DepositRequest(
      id:        doc.id,
      uid:       d['uid']      ?? '',
      amount:    (d['amount']  ?? 0).toDouble(),
      utr:       d['utr']      ?? '',
      status:    d['status']   ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// A single withdraw request document.
class WithdrawRequest {
  final String   id;
  final String   uid;
  final double   amount;
  final String   method;         // upi | bank
  final String   upiId;
  final String   accountHolder;
  final String   bankName;
  final String   accountNumber;
  final String   ifscCode;
  final String   status;         // pending | approved | rejected
  final DateTime createdAt;

  const WithdrawRequest({
    required this.id,
    required this.uid,
    required this.amount,
    required this.method,
    required this.upiId,
    required this.accountHolder,
    required this.bankName,
    required this.accountNumber,
    required this.ifscCode,
    required this.status,
    required this.createdAt,
  });

  factory WithdrawRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WithdrawRequest(
      id:            doc.id,
      uid:           d['uid']           ?? '',
      amount:        (d['amount']       ?? 0).toDouble(),
      method:        d['method']        ?? 'upi',
      upiId:         d['upiId']         ?? '',
      accountHolder: d['accountHolder'] ?? '',
      bankName:      d['bankName']      ?? '',
      accountNumber: d['accountNumber'] ?? '',
      ifscCode:      d['ifscCode']      ?? '',
      status:        d['status']        ?? 'pending',
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// A single transaction record.
class WalletTransaction {
  final String   id;
  final String   uid;
  final double   amount;
  final String   type;    // deposit | withdrawal | tournament_entry | winnings | refund
  final String   status;  // pending | completed | failed
  final String?  note;
  final String?  tournamentId;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.uid,
    required this.amount,
    required this.type,
    required this.status,
    this.note,
    this.tournamentId,
    required this.createdAt,
  });

  factory WalletTransaction.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id:           doc.id,
      uid:          d['uid']          ?? '',
      amount:       (d['amount']      ?? 0).toDouble(),
      type:         d['type']         ?? 'deposit',
      status:       d['status']       ?? 'pending',
      note:         d['note'],
      tournamentId: d['tournamentId'],
      createdAt:    (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// True for money coming IN (deposit, winnings, refund).
  bool get isCredit =>
      type == 'deposit' || type == 'winnings' || type == 'refund';
}

// ─────────────────────────────────────────────
// WALLET SERVICE
// ─────────────────────────────────────────────
class WalletService {
  // ── Singleton ─────────────────────────────
  WalletService._();
  static final WalletService instance = WalletService._();

  // ── Firebase ──────────────────────────────
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth      _auth      = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ──────────────────────────────────────────
  // WALLET DATA — realtime stream
  // ──────────────────────────────────────────

  /// Stream of [WalletData] from users/{uid}.
  /// Emits every time the user document changes.
  Stream<WalletData> walletDataStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(WalletData.empty);

    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return WalletData.empty;
          return WalletData.fromDoc(snap.data()!);
        });
  }

  // ──────────────────────────────────────────
  // DEPOSIT REQUEST
  // ──────────────────────────────────────────

  /// Creates a deposit request in Firestore.
  /// No screenshot upload — user sends proof manually via Discord/Telegram.
  /// Throws on any error.
  Future<void> submitDepositRequest({
    required double amount,
    required String utr,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in.');

    // Prevent duplicate UTR submissions within the last 24 hours
    final existing = await _firestore
        .collection('deposit_requests')
        .where('uid', isEqualTo: uid)
        .where('utr', isEqualTo: utr.trim())
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception(
          'A deposit request with this UTR already exists. '
          'If this is a mistake, contact support on Discord or Telegram.');
    }

    await _firestore.collection('deposit_requests').add({
      'uid':       uid,
      'amount':    amount,
      'utr':       utr.trim(),
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream of this user's deposit requests, newest-first.
  Stream<List<DepositRequest>> depositRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('deposit_requests')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(DepositRequest.fromDoc).toList());
  }

  // ──────────────────────────────────────────
  // WITHDRAW REQUEST
  // ──────────────────────────────────────────

  /// Creates a document in withdraw_requests/.
  /// Does NOT touch walletBalance — admin approves and deducts server-side.
  Future<void> submitWithdrawRequest({
    required double amount,
    required String method,
    required String upiId,
    required String accountHolder,
    required String bankName,
    required String accountNumber,
    required String ifscCode,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in.');

    // Read-only balance check (admin enforces server-side)
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final balance = (userDoc.data()?['walletBalance'] ?? 0).toDouble();
    if (amount > balance) {
      throw Exception(
          'Insufficient balance. Available: ₹${balance.toStringAsFixed(2)}');
    }

    // Prevent pending duplicate withdrawal
    final pending = await _firestore
        .collection('withdraw_requests')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (pending.docs.isNotEmpty) {
      throw Exception(
          'You already have a pending withdrawal request. '
          'Please wait for it to be processed before submitting a new one.');
    }

    await _firestore.collection('withdraw_requests').add({
      'uid':           uid,
      'amount':        amount,
      'method':        method,
      'upiId':         upiId,
      'accountHolder': accountHolder,
      'bankName':      bankName,
      'accountNumber': accountNumber,
      'ifscCode':      ifscCode,
      'status':        'pending',
      'createdAt':     FieldValue.serverTimestamp(),
    });
  }

  /// Stream of this user's withdrawal requests, newest-first.
  Stream<List<WithdrawRequest>> withdrawRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('withdraw_requests')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(WithdrawRequest.fromDoc).toList());
  }

  // ──────────────────────────────────────────
  // TRANSACTION HISTORY
  // ──────────────────────────────────────────

  /// Stream of this user's wallet transactions, newest-first.
  Stream<List<WalletTransaction>> transactionsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('wallet_transactions')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(WalletTransaction.fromDoc).toList());
  }
}

// ─────────────────────────────────────────────
// FIRESTORE COLLECTIONS — STRUCTURE REFERENCE
// ─────────────────────────────────────────────
//
// users/{uid}
//   uid              : string   (set on first login)
//   name             : string
//   email            : string
//   photoUrl         : string
//   walletBalance    : number   ← MANAGED BY ADMIN/BACKEND ONLY
//   totalEarnings    : number   ← MANAGED BY ADMIN/BACKEND ONLY
//   totalDeposits    : number   ← MANAGED BY ADMIN/BACKEND ONLY
//   totalWithdrawals : number   ← MANAGED BY ADMIN/BACKEND ONLY
//   wins             : number
//   tournamentsPlayed: number
//   rankPoints       : number
//
// deposit_requests/{id}
//   uid       : string
//   amount    : number
//   utr       : string
//   status    : 'pending' | 'approved' | 'rejected'
//   createdAt : timestamp
//   [adminNote: string]  ← optional, set by admin on approval/rejection
//
// withdraw_requests/{id}
//   uid          : string
//   amount       : number
//   method       : 'upi' | 'bank'
//   upiId        : string
//   accountHolder: string
//   bankName     : string
//   accountNumber: string
//   ifscCode     : string
//   status       : 'pending' | 'approved' | 'rejected'
//   createdAt    : timestamp
//   [adminNote: string]  ← optional, set by admin
//
// wallet_transactions/{id}
//   uid          : string
//   amount       : number
//   type         : 'deposit' | 'withdrawal' | 'tournament_entry' | 'winnings' | 'refund'
//   status       : 'pending' | 'completed' | 'failed'
//   note         : string  (optional)
//   tournamentId : string  (optional)
//   createdAt    : timestamp
//
// ─────────────────────────────────────────────
// REQUIRED FIRESTORE INDEXES (create in Firebase Console)
// ─────────────────────────────────────────────
// Collection: deposit_requests
//   Fields: uid ASC, createdAt DESC
//
// Collection: withdraw_requests
//   Fields: uid ASC, createdAt DESC
//   Fields: uid ASC, status ASC  (for pending-duplicate check)
//
// Collection: wallet_transactions
//   Fields: uid ASC, createdAt DESC
// ─────────────────────────────────────────────