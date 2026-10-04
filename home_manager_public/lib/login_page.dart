import 'package:flutter/material.dart';

import 'auth_service.dart';

/// Signed-out landing screen. Signing in flips the auth gate in main.dart to
/// the app automatically via authStateChanges.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color _dark = Color(0xFF21312E);
  static const Color _muted = Color(0xFF68706D);

  bool _busy = false;
  String? _error;

  Future<void> _signIn(Future<Object?> Function() method) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await method();
      // Success: the auth gate rebuilds into the app.
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = AuthService.isCancellation(e)
            ? null
            : 'Sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.house_outlined, size: 64, color: Color(0xFF1F7A6B)),
                  const SizedBox(height: 16),
                  Text(
                    'Home Manager',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to manage your home',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _signIn(AuthService.signInWithGoogle),
                      icon: const _GoogleGlyph(),
                      label: const Text('Continue with Google'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy
                          ? null
                          : () => _signIn(AuthService.signInWithApple),
                      icon: const Icon(Icons.apple, size: 24),
                      label: const Text('Continue with Apple'),
                    ),
                  ),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 20),
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFD44747),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple "G" mark so we don't need a bundled asset for the Google button.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}
