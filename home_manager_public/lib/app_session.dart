import 'package:flutter/foundation.dart';

/// Process-wide session context.
///
/// [homeId] is set by loadSession so lower layers (the lookup services) can
/// send it to the Worker for membership checks without threading it through
/// every widget. [epoch] lets any screen force a full session reload (e.g.
/// after joining or leaving a home changes the user's homeId) — the auth gate
/// keys the session loader on it.
class AppSession {
  static String? homeId;

  static final ValueNotifier<int> epoch = ValueNotifier<int>(0);

  /// Rebuilds the session from scratch (re-reads users/{uid}.homeId and
  /// reloads all home data).
  static void reloadSession() {
    epoch.value++;
  }
}
