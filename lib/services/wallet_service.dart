// lib/services/wallet_service.dart
// ─────────────────────────────────────────────
// WALLET SERVICE  — Shadow Storm  (v2)
//
// Architecture change from v1:
//   All sub-collections are now UNDER the user document:
//     users/{uid}/transactions/
//     users/{uid}/deposit_requests/
//     users/{uid}/withdraw_requests/
//
// Benefits:
//   • Simpler Firestore security rules (no uid field needed in docs)
//   • Admin can navigate directly to a user's financial data
//   • Subcollection queries are inherently scoped — no composite index on uid
//   • Easier to delete all user data (just delete the user doc tree)
//
// SECURITY:
//   Frontend NEVER modifies walletBalance directly.
//   All balance mutations happen via admin or Cloud Functions.
// ─────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────

/// Live wallet summary streamed from users/{uid}.
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

  static const empty = WalletData(
    balance: 0, totalEarnings: 0, totalDeposits: 0, totalWithdrawals: 0,
  );
}

/// users/{uid}/deposit_requests/{id}
class DepositRequest {
  final String   id;
  final double   amount;
  final String   utr;
  final String   status;    // pending | approved | rejected
  final String?  adminNote;
  final DateTime createdAt;

  const DepositRequest({
    required this.id,
    required this.amount,
    required this.utr,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  factory DepositRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DepositRequest(
      id:        doc.id,
      amount:    (d['amount']  ?? 0).toDouble(),
      utr:       d['utr']      as String? ?? '',
      status:    d['status']   as String? ?? 'pending',
      adminNote: d['adminNote'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// users/{uid}/withdraw_requests/{id}
class WithdrawRequest {
  final String   id;
  final double   amount;
  final String   method;          // upi | bank
  final String   upiId;
  final String   accountHolder;
  final String   bankName;
  final String   accountNumber;
  final String   ifscCode;
  final String   status;          // pending | approved | rejected
  final String?  adminNote;
  final DateTime createdAt;

  const WithdrawRequest({
    required this.id,
    required this.amount,
    required this.method,
    required this.upiId,
    required this.accountHolder,
    required this.bankName,
    required this.accountNumber,
    required this.ifscCode,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

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

/// users/{uid}/transactions/{id}
class WalletTransaction {
  final String   id;
  final double   amount;
  final String   type;     // deposit | withdrawal | tournament_entry | winnings | refund
  final String   status;   // pending | completed | failed
  final String?  description;
  final String?  tournamentId;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.status,
    this.description,
    this.tournamentId,
    required this.createdAt,
  });

  factory WalletTransaction.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id:           doc.id,
      amount:       (d['amount']   ?? 0).toDouble(),
      type:         d['type']      as String? ?? 'deposit',
      status:       d['status']    as String? ?? 'pending',
      description:  d['description'] as String?,
      tournamentId: d['tournamentId'] as String?,
      createdAt:    (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Credits: deposit, winnings, refund → money coming IN.
  bool get isCredit =>
      type == 'deposit' || type == 'winnings' || type == 'refund';
}

// ─────────────────────────────────────────────
// WALLET SERVICE
// ─────────────────────────────────────────────
class WalletService {
  WalletService._();
  static final WalletService instance = WalletService._();

  final FirebaseFirestore _db   = FirebaseFirestore.instance;
  final FirebaseAuth      _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── Subcollection references ───────────────

  CollectionReference _depositCol(String uid) =>
      _db.collection('users').doc(uid).collection('deposit_requests');

  CollectionReference _withdrawCol(String uid) =>
      _db.collection('users').doc(uid).collection('withdraw_requests');

  CollectionReference _txCol(String uid) =>
      _db.collection('users').doc(uid).collection('transactions');

  // ──────────────────────────────────────────
  // WALLET SUMMARY STREAM
  // ──────────────────────────────────────────

  /// Realtime stream of [WalletData] from users/{uid}.
  Stream<WalletData> walletDataStream() {
    final uid = _uid;
    if (uid == null) return Stream.value(WalletData.empty);
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return WalletData.empty;
      return WalletData.fromDoc(snap.data()!);
    });
  }

  // ──────────────────────────────────────────
  // DEPOSIT REQUESTS
  // Path: users/{uid}/deposit_requests/{id}
  // ──────────────────────────────────────────

  Future<void> submitDepositRequest({
    required double amount,
    required String utr,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not logged in.');

    final col = _depositCol(uid);

    // Reject duplicate UTR within this user's deposit history
    final dup = await col
        .where('utr', isEqualTo: utr.trim())
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw Exception(
          'A deposit request with this UTR already exists. '
          'Contact support on Discord or Telegram if this is a mistake.');
    }

    await col.add({
      'amount':    amount,
      'utr':       utr.trim(),
      'status':    'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Realtime stream of this user's deposit requests, newest-first.
  Stream<List<DepositRequest>> depositRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _depositCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DepositRequest.fromDoc).toList());
  }

  // ──────────────────────────────────────────
  // WITHDRAW REQUESTS
  // Path: users/{uid}/withdraw_requests/{id}
  // ──────────────────────────────────────────

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
    if (uid == null) throw Exception('Not logged in.');

    // Read-only balance guard (admin enforces server-side too)
    final snap = await _db.collection('users').doc(uid).get();
    final balance = (snap.data()?['walletBalance'] ?? 0).toDouble();
    if (amount > balance) {
      throw Exception(
          'Insufficient balance. Available: ₹${balance.toStringAsFixed(2)}');
    }

    final col = _withdrawCol(uid);

    // Prevent duplicate pending withdrawal
    final pending = await col
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (pending.docs.isNotEmpty) {
      throw Exception(
          'You already have a pending withdrawal. '
          'Wait for it to be processed before submitting a new one.');
    }

    await col.add({
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
  }

  /// Realtime stream of this user's withdrawal requests, newest-first.
  Stream<List<WithdrawRequest>> withdrawRequestsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _withdrawCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(WithdrawRequest.fromDoc).toList());
  }

  // ──────────────────────────────────────────
  // TRANSACTION HISTORY
  // Path: users/{uid}/transactions/{id}
  // ──────────────────────────────────────────

  /// Realtime stream of this user's transactions, newest-first.
  Stream<List<WalletTransaction>> transactionsStream() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _txCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(WalletTransaction.fromDoc).toList());
  }
}

// ─────────────────────────────────────────────
// FIRESTORE STRUCTURE REFERENCE
// ─────────────────────────────────────────────
//
// users/{uid}
//   uid              : string
//   name             : string
//   email            : string
//   photoUrl         : string
//   walletBalance    : number   ← BACKEND ONLY
//   totalEarnings    : number   ← BACKEND ONLY
//   totalDeposits    : number   ← BACKEND ONLY
//   totalWithdrawals : number   ← BACKEND ONLY
//   wins             : number
//   tournamentsPlayed: number
//
//   ├── deposit_requests/{id}
//   │     amount    : number
//   │     utr       : string
//   │     status    : 'pending' | 'approved' | 'rejected'
//   │     adminNote : string (optional, set by admin)
//   │     createdAt : timestamp
//   │
//   ├── withdraw_requests/{id}
//   │     amount        : number
//   │     method        : 'upi' | 'bank'
//   │     upiId         : string
//   │     accountHolder : string
//   │     bankName      : string
//   │     accountNumber : string
//   │     ifscCode      : string
//   │     status        : 'pending' | 'approved' | 'rejected'
//   │     adminNote     : string (optional)
//   │     createdAt     : timestamp
//   │
//   └── transactions/{id}
//         amount       : number
//         type         : 'deposit'|'withdrawal'|'tournament_entry'|'winnings'|'refund'
//         status       : 'pending' | 'completed' | 'failed'
//         description  : string (optional)
//         tournamentId : string (optional)
//         createdAt    : timestamp
//
// ─────────────────────────────────────────────
// REQUIRED FIRESTORE INDEXES
// ─────────────────────────────────────────────
// All subcollection queries are on a single field with orderBy createdAt DESC.
// Firestore auto-indexes single-field queries, so NO composite indexes needed
// for subcollections. The only indexes you may need:
//
// users/{uid}/deposit_requests — orderBy: createdAt DESC  (auto-indexed)
// users/{uid}/withdraw_requests — orderBy: createdAt DESC (auto-indexed)
// users/{uid}/transactions — orderBy: createdAt DESC      (auto-indexed)
//
// For leaderboard (ranks_screen):
// Collection: users
//   Fields: totalEarnings DESC    (for winnings leaderboard)
//   Fields: totalWithdrawals DESC (for withdrawals leaderboard)
// ─────────────────────────────────────────────