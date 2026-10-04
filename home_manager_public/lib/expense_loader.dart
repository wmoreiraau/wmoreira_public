import 'dart:convert';

import 'package:flutter/services.dart';

import 'expense_data.dart';

/// Folder, relative to the project root and declared under `assets:` in
/// pubspec.yaml, that holds the bank-export CSV files. Every file in it is
/// bundled with the app and read on demand, whatever its name.
const String expensesAssetFolder = 'Finances Monitor/Expenses/';

/// Reads every bundled file from [expensesAssetFolder], keeps those in the
/// expected CSV format and caches the resulting summary for the session.
class ExpenseLoader {
  ExpenseLoader._();

  static ExpenseSummary? _cache;
  static Future<ExpenseSummary>? _inFlight;

  static Future<ExpenseSummary> load() {
    final ExpenseSummary? cached = _cache;
    if (cached != null) {
      return Future<ExpenseSummary>.value(cached);
    }
    return _inFlight ??= _loadFromAssets()
        .then((ExpenseSummary summary) {
          _cache = summary;
          return summary;
        })
        .whenComplete(() {
          _inFlight = null;
        });
  }

  /// Drops the cached summary and reads the files again.
  static Future<ExpenseSummary> reload() {
    _cache = null;
    return load();
  }

  static Future<ExpenseSummary> _loadFromAssets() async {
    final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
      rootBundle,
    );
    final List<String> keys = manifest
        .listAssets()
        .where((String key) => key.startsWith(expensesAssetFolder))
        .toList()
      ..sort();

    final Map<String, List<ExpenseTransaction>> byFile =
        <String, List<ExpenseTransaction>>{};
    for (final String key in keys) {
      final String name = key.substring(expensesAssetFolder.length);
      try {
        final ByteData data = await rootBundle.load(key);
        final String text = utf8.decode(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          allowMalformed: true,
        );
        byFile[name] = parseExpenseFile(text);
      } catch (_) {
        // Not readable as text: skip it, the other files still load.
      }
    }
    return ExpenseSummary.fromFiles(byFile);
  }
}
