import 'maintenance_lookup_result.dart';

/// Models for the AI "Look up" result returned by the Cloudflare Worker and
/// cached locally per issue.
class LookupResult {
  LookupResult({
    required this.summary,
    required this.steps,
    required this.shoppingList,
    this.safetyNote,
    this.isRecurrent = false,
    this.involvesEquipment = false,
    this.itemName = '',
    List<SuggestedRecurrence>? suggestedRecurrences,
    this.legacy = false,
  }) : suggestedRecurrences = suggestedRecurrences ?? <SuggestedRecurrence>[];

  final String summary;
  final List<String> steps;
  final List<ShoppingItem> shoppingList;
  final String? safetyNote;

  /// True when the AI identified this as a recurring task (e.g. cleaning
  /// gutters) rather than a one-off fix.
  final bool isRecurrent;

  /// True when the task involves an appliance/equipment that needs recurring
  /// maintenance (e.g. lawn mower), so the manufacturer/model cell is shown.
  final bool involvesEquipment;

  /// The appliance/item the recurring maintenance is for, without the action
  /// verb (e.g. "Oven" for "Clean oven"). Used to name the converted
  /// Recurrent Maintenance task. Empty when not recurrent/equipment.
  final String itemName;

  /// Suggested reminder cadences when [isRecurrent], longest interval first.
  final List<SuggestedRecurrence> suggestedRecurrences;

  /// True when parsed from a cache written before recurrence detection
  /// existed; triggers one refresh on the next look-up open. Not serialized —
  /// it is derived from the absence of the 'isRecurrent' key.
  final bool legacy;

  factory LookupResult.fromJson(Map<String, dynamic> json) {
    final List<dynamic> stepsJson =
        json['steps'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> listJson =
        json['shoppingList'] as List<dynamic>? ?? <dynamic>[];
    final String? safety = (json['safetyNote'] as String?)?.trim();

    final List<dynamic> recurrencesJson =
        json['suggestedRecurrences'] as List<dynamic>? ?? <dynamic>[];
    final List<SuggestedRecurrence> suggestions = recurrencesJson
        .whereType<Map<String, dynamic>>()
        .map(SuggestedRecurrence.fromJson)
        .toList();
    sortSuggestionsLongestFirst(suggestions);

    return LookupResult(
      summary: (json['summary'] as String?)?.trim() ?? '',
      steps: stepsJson
          .map((dynamic e) => e.toString().trim())
          .where((String s) => s.isNotEmpty)
          .toList(),
      shoppingList: listJson
          .whereType<Map<String, dynamic>>()
          .map(ShoppingItem.fromJson)
          .where((ShoppingItem item) => item.item.isNotEmpty)
          .toList(),
      safetyNote: (safety == null || safety.isEmpty) ? null : safety,
      isRecurrent: json['isRecurrent'] as bool? ?? false,
      involvesEquipment: json['involvesEquipment'] as bool? ?? false,
      itemName: (json['itemName'] as String?)?.trim() ?? '',
      suggestedRecurrences: suggestions,
      legacy: !json.containsKey('isRecurrent'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'summary': summary,
    'steps': steps,
    'shoppingList': shoppingList
        .map((ShoppingItem item) => item.toJson())
        .toList(),
    'safetyNote': safetyNote,
    'isRecurrent': isRecurrent,
    'involvesEquipment': involvesEquipment,
    'itemName': itemName,
    'suggestedRecurrences': suggestedRecurrences
        .map((SuggestedRecurrence s) => s.toJson())
        .toList(),
  };
}

class ShoppingItem {
  ShoppingItem({
    required this.item,
    required this.reason,
    required this.optional,
    this.checked = false,
  });

  final String item;
  final String reason;
  final bool optional;
  bool checked;

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      item: (json['item'] as String?)?.trim() ?? '',
      reason: (json['reason'] as String?)?.trim() ?? '',
      optional: json['optional'] as bool? ?? false,
      checked: json['checked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'item': item,
    'reason': reason,
    'optional': optional,
    'checked': checked,
  };
}
