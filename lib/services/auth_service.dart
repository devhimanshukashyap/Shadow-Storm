import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// AuthService handles all authentication and Firestore user logic.
/// Keep this class focused: no UI code here.
class AuthService {
  // Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Google Sign-In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────
  // Stream: listen to auth state changes (logged in / logged out)
  // Used by SplashScreen to redirect automatically
  // ─────────────────────────────────────────────
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─────────────────────────────────────────────
  // Returns the currently logged-in user (or null if not logged in)
  // ─────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;

  // ─────────────────────────────────────────────
  // Google Sign-In flow
  // Returns the FirebaseUser on success, null on cancel, throws on error
  // ─────────────────────────────────────────────
  Future<User?> signInWithGoogle() async {
    // Step 1: Trigger the Google Sign-In dialog
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    // User cancelled the sign-in dialog
    if (googleUser == null) return null;

    // Step 2: Get authentication tokens from Google
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    // Step 3: Create a Firebase credential using those tokens
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Step 4: Sign in to Firebase with the Google credential
    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);

    final User? user = userCredential.user;

    if (user != null) {
      // Step 5: Create/update the Firestore user document
      await _createUserDocumentIfNew(user, userCredential.additionalUserInfo);
    }

    return user;
  }

  // ─────────────────────────────────────────────
  // Creates a Firestore user doc on FIRST login only
  // On subsequent logins, the existing doc is left untouched
  // ─────────────────────────────────────────────
  Future<void> _createUserDocumentIfNew(
    User user,
    AdditionalUserInfo? additionalUserInfo,
  ) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    // Only create the document if it doesn't already exist
    if (!docSnapshot.exists) {
      await docRef.set({
        'uid': user.uid,
        'name': user.displayName ?? 'Player',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'walletBalance': 0,
        'wins': 0,
        'tournamentsPlayed': 0,
        'rankPoints': 0,
      });
    }
  }

  // ─────────────────────────────────────────────
  // Sign out from both Firebase and Google
  // ─────────────────────────────────────────────
  Future<void> signOut() async {
    await _googleSignIn.signOut(); // Clear Google session
    await _auth.signOut();         // Clear Firebase session
  }
}