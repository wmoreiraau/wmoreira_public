import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'lookup_service.dart' show LookupException, lookupApiUrl;

/// Client for the Worker's home-sharing endpoints. Membership changes happen
/// server-side (the Worker holds a Firebase service-account key), so clients
/// can never forge memberIds — the Firestore rules stay locked down.
class HomeSharingService {
  static Future<Map<String, String>> _headers() async {
    final User? user = AuthService.currentUser;
    final String? token = user == null ? null : await user.getIdToken();
    if (token == null) {
      throw LookupException('You are signed out. Sign in and try again.');
    }
    return <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final Map<String, String> headers = await _headers();
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$lookupApiUrl$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw LookupException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (response.statusCode != 200) {
      final String message = (json['error'] as String?)?.trim() ?? '';
      throw LookupException(
        message.isNotEmpty
            ? message
            : 'The server returned an error (${response.statusCode}).',
      );
    }
    return json;
  }

  /// Joins the home whose inviteCode matches [code]; switches this user's
  /// homeId to it. Returns the joined home's name (may be empty).
  static Future<String> joinHomeWithCode(String code) async {
    final Map<String, dynamic> result = await _post('/join', <String, String>{
      'code': code.trim().toUpperCase(),
    });
    return (result['homeName'] as String?) ?? '';
  }

  /// Leaves the current home and switches to a freshly created personal home.
  static Future<void> leaveHome() async {
    await _post('/leave', const <String, String>{});
  }
}
