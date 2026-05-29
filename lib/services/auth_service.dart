// lib/services/auth_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Auth Service (Phase F1)
//
// Changes from v3:
//   • Readable ID format changed: SSP-000001 (sequential, zero-padded)
//     instead of SS-XXXXXX (random). Uses a Firestore counter document
//     at counters/user_counter to guarantee uniqueness and readability.
//   • createdAt: serverTimestamp() stored on FIRST document creation only.
//     Never overwritten on subsequent logins (existence check guards it).
//   • getUserByReadableId() updated to match new SSP-XXXXXX format.
//   • All original v3 methods kept intact.
// ─────────────────────────────────────────────

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth      _auth         = FirebaseAuth.instance;
  final GoogleSignIn      _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore    = FirebaseFirestore.instance;

  // ── Auth state ───────────────────────────────
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ── Google Sign-In ───────────────────────────
  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken:     googleAuth.idToken,
    );

    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);

    final User? user = userCredential.user;
    if (user != null) {
      await _createUserDocumentIfNew(user, userCredential.additionalUserInfo);
    }

    return user;
  }

  // ── Create Firestore user document on first login ──
  // PRIORITY 5 (F1): createdAt is stored ONLY on first creation.
  // PRIORITY 6 (F1): Readable ID format SSP-000001 using atomic counter.
  Future<void> _createUserDocumentIfNew(
    User user,
    AdditionalUserInfo? additionalUserInfo,
  ) async {
    final docRef      = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    // Guard: only run on first login — never overwrite existing doc.
    if (!docSnapshot.exists) {
      final readableId = await _generateSequentialReadableId();

      await docRef.set({
        'uid':        user.uid,
        'name':       user.displayName ?? 'Player',
        'email':      user.email       ?? '',
        'photoUrl':   user.photoURL    ?? '',
        'readableId': readableId, // e.g. "SSP-000001"

        // PRIORITY 5: createdAt stored once, never overwritten.
        'createdAt': FieldValue.serverTimestamp(),

        'walletBalance':    0,
        'totalEarnings':    0,
        'totalDeposits':    0,
        'totalWithdrawals': 0,

        'wins':              0,
        'tournamentsPlayed': 0,

        'ign':     '',
        'gameUid': '',
      });
    }
    // NOTE: If doc already exists, we do NOT update it.
    // This ensures createdAt is never overwritten on future logins.
  }

  // ── Sequential Readable ID (SSP-000001 format) ──────────
  //
  // Uses a Firestore transaction on counters/user_counter to atomically
  // increment a counter and generate collision-free sequential IDs.
  // Format: SSP-000001 through SSP-999999 (supports 999,999 users).
  //
  // Firestore path: counters/user_counter { lastUserId: number }
  //
  // PRIORITY 6 (F1): SSP prefix = Shadow Storm Player.
  Future<String> _generateSequentialReadableId() async {
    final counterRef = _firestore.collection('counters').doc('user_counter');

    int newId = 1;

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(counterRef);
      if (!snap.exists || snap.data() == null) {
        // First user ever — initialise counter at 1.
        txn.set(counterRef, {'lastUserId': 1});
        newId = 1;
      } else {
        final last = (snap.data()!['lastUserId'] as num?)?.toInt() ?? 0;
        newId = last + 1;
        txn.update(counterRef, {'lastUserId': newId});
      }
    });

    // Zero-pad to 6 digits: 1 → "000001"
    return 'SSP-${newId.toString().padLeft(6, '0')}';
  }

  // ── Lookup by readable ID ──────────────────────────────
  // Works for both old SS-XXXXXX and new SSP-000001 formats.
  // Admin search and team invite both use this.
  // Requires Firestore index: users → readableId ASC.
  Future<Map<String, dynamic>?> getUserByReadableId(String readableId) async {
    final snap = await _firestore
        .collection('users')
        .where('readableId', isEqualTo: readableId.trim().toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {'uid': snap.docs.first.id, ...snap.docs.first.data()};
  }

  // ── Sign out ─────────────────────────────────
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}