import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper around FirebaseAuth for the web sign-in flows.
///
/// Web-only for now: Google and Apple both go through Firebase browser
/// popups, so the google_sign_in / sign_in_with_apple packages are not
/// needed. Revisit when building for Android/iOS.
class AuthService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  static Future<UserCredential> signInWithGoogle() {
    final GoogleAuthProvider provider = GoogleAuthProvider()
      ..addScope('email');
    return _auth.signInWithPopup(provider);
  }

  static Future<UserCredential> signInWithApple() {
    final OAuthProvider provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    return _auth.signInWithPopup(provider);
  }

  static Future<void> signOut() => _auth.signOut();

  /// True for the errors a user causes by dismissing the popup — not worth
  /// showing an error message for.
  static bool isCancellation(Object error) {
    return error is FirebaseAuthException &&
        (error.code == 'popup-closed-by-user' ||
            error.code == 'cancelled-popup-request' ||
            error.code == 'user-cancelled');
  }
}
