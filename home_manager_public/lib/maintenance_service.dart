import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_session.dart';
import 'lookup_service.dart'
    show LookupException, lookupApiUrl, workerAuthHeaders;
import 'maintenance_lookup_result.dart';

/// Calls the same Cloudflare Worker proxy as the issue look-up, but the
/// `/maintenance` endpoint, which returns a structured maintenance plan with a
/// server-validated manual/details link.
Future<MaintenanceLookupResult> fetchMaintenanceLookup({
  required String appliance,
  required String manufacturer,
  required String model,
  String notes = '',
}) async {
  if (lookupApiUrl.isEmpty) {
    throw LookupException(
      'Lookup service is not configured (LOOKUP_API_URL is empty).',
    );
  }

  final Uri uri = Uri.parse('$lookupApiUrl/maintenance');
  final Map<String, String> headers = await workerAuthHeaders();

  http.Response response;
  try {
    response = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(<String, String>{
            'appliance': appliance,
            'manufacturer': manufacturer,
            'model': model,
            'notes': notes,
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
    return MaintenanceLookupResult.fromJson(json);
  } catch (_) {
    throw LookupException('Got an unexpected response. Please try again.');
  }
}
