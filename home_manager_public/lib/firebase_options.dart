import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase configuration for this app, supplied at build/run time so no
/// project values are committed to the repository.
///
/// HOW TO FILL THIS IN (one-time setup):
/// 1. Go to https://console.firebase.google.com and create a project.
/// 2. Add a **Web app** to the project (</> icon on the project overview).
/// 3. Copy `dart_defines.example.json` to `dart_defines.json` (gitignored) and
///    fill in the values from the console's `firebaseConfig` snippet.
/// 4. Run with `flutter run --dart-define-from-file=dart_defines.json`.
/// Until then the app shows a "setup needed" screen instead of the login.
class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
  );

  /// True once the Firebase values have been supplied via --dart-define.
  static bool get isConfigured => web.apiKey.isNotEmpty;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are only configured for web. Add the other '
      'platforms when building for Android/iOS.',
    );
  }
}
