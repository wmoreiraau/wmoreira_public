import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'app_session.dart';
import 'auth_service.dart';
import 'lookup_result.dart';

/// Base URL of the Cloudflare Worker proxy (see worker/README.md). Pass at
/// build/run time with `--dart-define=LOOKUP_API_URL=https://...` or via
/// dart_defines.json; AI look-ups report "not configured" while it is empty.
const String lookupApiUrl = String.fromEnvironment('LOOKUP_API_URL');

class LookupException implements Exception {
  LookupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Auth headers for Worker calls: the Firebase ID token lets the Worker
/// verify the caller and (with homeId in the body) check home membership.
Future<Map<String, String>> workerAuthHeaders() async {
  final User? user = AuthService.currentUser;
  final String? token = user == null ? null : await user.getIdToken();
  return <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

Future<LookupResult> fetchLookup(
  String issueTitle, {
  String manufacturer = '',
  String model = '',
}) async {
  if (lookupApiUrl.isEmpty) {
    throw LookupException(
      'Lookup service is not configured (LOOKUP_API_URL is empty).',
    );
  }

  final Uri uri = Uri.parse('$lookupApiUrl/lookup');
  final Map<String, String> headers = await workerAuthHeaders();

  http.Response response;
  try {
    response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, String>{
            'title': issueTitle,
            'manufacturer': manufacturer,
            'model': model,
            'homeId': AppSession.homeId ?? '',
          }),
        )
        .timeout(const Duration(seconds: 30));
  } catch (_) {
    throw LookupException(
      'Could not reach the lookup service. Check your connection and try again.',
    );
  }

  if (response.statusCode != 200) {
    throw LookupException(
      'The lookup service returned an error (${response.statusCode}). Please try again.',
    );
  }

  try {
    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    return LookupResult.fromJson(json);
  } catch (_) {
    throw LookupException('Got an unexpected response. Please try again.');
  }
}
