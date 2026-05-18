// lib/admin/auth/admin_auth_service.dart
// ─────────────────────────────────────────────
// SHADOW STORM — Admin Auth Service
// Firebase Google Auth + Firestore isAdmin check
// ─────────────────────────────────────────────

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// ADMIN AUTH RESULT
// ─────────────────────────────────────────────
enum AdminAuthStatus {
  loading,
  unauthenticated,
  authenticated,
  notAdmin,
  error,
}

class AdminAuthResult {
  final AdminAuthStatus status;
  final User?           user;
  final String?         errorMessage;

  const AdminAuthResult({
    required this.status,
    this.user,
    this.errorMessage,
  });

  bool get isAdmin       => status == AdminAuthStatus.authenticated;
  bool get isLoading     => status == AdminAuthStatus.loading;
  bool get isNotAdmin    => status == AdminAuthStatus.notAdmin;
  bool get isLoggedOut   => status == AdminAuthStatus.unauthenticated;
  bool get hasError      => status == AdminAuthStatus.error;
}

// ─────────────────────────────────────────────
// ADMIN AUTH SERVICE
// ─────────────────────────────────────────────
class AdminAuthService {
  AdminAuthService._();
  static final AdminAuthService instance = AdminAuthService._();

  final FirebaseAuth      _auth        = FirebaseAuth.instance;
  final GoogleSignIn      _googleSignIn = GoogleSignIn(
    clientId: '689631582174-hctslifoup3i879cjbjn4cp8t2doei3f.apps.googleusercontent.com',
  );
  final FirebaseFirestore _firestore   = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool  get isSignedIn  => currentUser != null;

  // ──────────────────────────────────────────
  // AUTH STATE STREAM (with admin check)
  // ──────────────────────────────────────────
  Stream<AdminAuthResult> get adminAuthStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) {
        return const AdminAuthResult(status: AdminAuthStatus.unauthenticated);
      }
      return await _verifyAdminStatus(user);
    });
  }

  // ──────────────────────────────────────────
  // VERIFY ADMIN STATUS
  // Checks users/{uid}.isAdmin == true
  // ──────────────────────────────────────────
  Future<AdminAuthResult> _verifyAdminStatus(User user) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        return AdminAuthResult(
          status: AdminAuthStatus.notAdmin,
          user: user,
          errorMessage: 'User record not found.',
        );
      }

      final data    = doc.data() as Map<String, dynamic>;
      final isAdmin = data['isAdmin'] == true;

      if (isAdmin) {
        return AdminAuthResult(
          status: AdminAuthStatus.authenticated,
          user: user,
        );
      } else {
        return AdminAuthResult(
          status: AdminAuthStatus.notAdmin,
          user: user,
          errorMessage: 'Access denied. Admin privileges required.',
        );
      }
    } catch (e) {
      return AdminAuthResult(
        status: AdminAuthStatus.error,
        user: user,
        errorMessage: 'Verification failed: ${e.toString()}',
      );
    }
  }

  // ──────────────────────────────────────────
  // GOOGLE SIGN IN
  // ──────────────────────────────────────────
  Future<AdminAuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const AdminAuthResult(
          status: AdminAuthStatus.unauthenticated,
          errorMessage: 'Sign-in cancelled.',
        );
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken:     googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        return const AdminAuthResult(
          status: AdminAuthStatus.error,
          errorMessage: 'Authentication failed.',
        );
      }

      return await _verifyAdminStatus(user);
    } catch (e) {
      return AdminAuthResult(
        status: AdminAuthStatus.error,
        errorMessage: 'Sign-in error: ${e.toString()}',
      );
    }
  }

  // ──────────────────────────────────────────
  // SIGN OUT
  // ──────────────────────────────────────────
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ──────────────────────────────────────────
  // CHECK CURRENT USER IS ADMIN (one-time)
  // ──────────────────────────────────────────
  Future<AdminAuthResult> checkCurrentAdminStatus() async {
    final user = currentUser;
    if (user == null) {
      return const AdminAuthResult(status: AdminAuthStatus.unauthenticated);
    }
    return await _verifyAdminStatus(user);
  }
}