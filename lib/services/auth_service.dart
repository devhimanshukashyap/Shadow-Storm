// lib/services/auth_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Auth Service (v3)
//
// Changes from v2:
//   • generateReadableId() — creates SS-XXXXXX human-readable player ID
//   • _uniqueReadableId() — collision-safe generation
//   • readableId stored in users/{uid} on first sign-in
//   • getUserByReadableId() — lookup by SS-XXXXXX across all users
// ─────────────────────────────────────────────

import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth    _auth        = FirebaseAuth.instance;
  final GoogleSignIn    _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  Future<void> _createUserDocumentIfNew(
    User user,
    AdditionalUserInfo? additionalUserInfo,
  ) async {
    final docRef      = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      // Generate a unique readable ID for this player
      final readableId = await _uniqueReadableId();

      await docRef.set({
        'uid':        user.uid,
        'name':       user.displayName ?? 'Player',
        'email':      user.email       ?? '',
        'photoUrl':   user.photoURL    ?? '',
        'readableId': readableId, // e.g. "SS-A7KX3M"

        'walletBalance':    0,
        'totalEarnings':    0,
        'totalDeposits':    0,
        'totalWithdrawals': 0,

        'wins':              0,
        'tournamentsPlayed': 0,

        'ign':       '',
        'gameUid':   '',
      });
    }
  }

  // ── Readable ID helpers ───────────────────────

  /// Characters chosen to avoid visual ambiguity:
  /// no I (vs 1), no O (vs 0), no 0, no 1.
  static const _idChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Generate a candidate SS-XXXXXX string.
  static String _generateReadableId() {
    final rand = Random.secure();
    final code = List.generate(
      6,
      (_) => _idChars[rand.nextInt(_idChars.length)],
    ).join();
    return 'SS-$code';
  }

  /// Keeps regenerating until a unique ID is found.
  /// Collision probability with 32^6 ≈ 1B combinations is negligible,
  /// but we check anyway for correctness.
  Future<String> _uniqueReadableId() async {
    while (true) {
      final candidate = _generateReadableId();
      final snap = await _firestore
          .collection('users')
          .where('readableId', isEqualTo: candidate)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return candidate;
      // collision — try again
    }
  }

  // ── Lookup by readable ID (used by admin + team invite) ──

  /// Returns the user document for a given readable ID (e.g. "SS-A7KX3M").
  /// Returns null if no user found.
  /// Requires Firestore index: users → readableId ASC.
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