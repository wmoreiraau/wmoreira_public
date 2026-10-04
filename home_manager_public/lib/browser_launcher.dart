import 'browser_launcher_stub.dart'
    if (dart.library.html) 'browser_launcher_web.dart';

Uri buildSearchUri(String query) {
  return Uri.https('www.google.com', '/search', <String, String>{'q': query});
}

Future<void> openSearchQuery(String query) {
  return openExternalUrl(buildSearchUri(query));
}

/// Opens an already-built absolute URL in a new browser tab. Used for links
/// that have already been validated (e.g. the maintenance manual link).
Future<void> openUrl(Uri uri) {
  return openExternalUrl(uri);
}
