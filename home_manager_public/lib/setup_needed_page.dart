import 'package:flutter/material.dart';

/// Shown instead of the login screen while no Firebase config has been
/// supplied (see lib/firebase_options.dart), so the app stays runnable during
/// first-time Firebase setup.
class SetupNeededPage extends StatelessWidget {
  const SetupNeededPage({super.key});

  static const Color _dark = Color(0xFF21312E);
  static const Color _body = Color(0xFF263331);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.settings_suggest_outlined,
                    size: 56,
                    color: Color(0xFF1F7A6B),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Firebase setup needed',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This app now uses Firebase for sign-in and shared home '
                    'data, but it has not been connected to a Firebase '
                    'project yet.\n\n'
                    '1. Create a project at console.firebase.google.com\n'
                    '2. Add a Web app to it (the </> icon)\n'
                    '3. Copy dart_defines.example.json to dart_defines.json '
                    'and fill in the firebaseConfig values\n'
                    '4. Enable the Google (and Apple) sign-in providers under '
                    'Authentication\n'
                    '5. Create a Firestore database and publish the security '
                    'rules from firestore.rules\n\n'
                    'Then restart the app with '
                    '--dart-define-from-file=dart_defines.json.',
                    style: TextStyle(color: _body, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
