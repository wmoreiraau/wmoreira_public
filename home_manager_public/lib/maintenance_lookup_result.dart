import 'lookup_result.dart';
import 'maintenance_task.dart';

/// One suggested maintenance cadence from the AI look-up, e.g.
/// "Yearly - Replace battery".
class SuggestedRecurrence {
  SuggestedRecurrence({required this.recurrence, required this.description});

  final MaintenanceRecurrence recurrence;

  /// Short action label, e.g. "Replace battery". May be empty for results
  /// cached before multi-recurrence support.
  final String description;

  /// "Yearly - Replace battery" (or just "Yearly" without a description).
  String get displayLabel => description.isEmpty
      ? recurrence.label
      : '${recurrence.label} - $description';

  factory SuggestedRecurrence.fromJson(Map<String, dynamic> json) {
    return SuggestedRecurrence(
      recurrence: MaintenanceRecurrence.fromLabel(
        json['recurrence'] as String?,
      ),
      description: (json['description'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'recurrence': recurrence.label,
    'description': description,
  };
}

/// Sorts suggestions so longer recurrences stay at the top (Yearly before
/// Monthly). Stable for equal intervals, preserving the AI's order.
void sortSuggestionsLongestFirst(List<SuggestedRecurrence> suggestions) {
  final List<MapEntry<int, SuggestedRecurrence>> indexed = suggestions
      .asMap()
      .entries
      .toList();
  indexed.sort((
    MapEntry<int, SuggestedRecurrence> a,
    MapEntry<int, SuggestedRecurrence> b,
  ) {
    final int byLength = b.value.recurrence.approxDays.compareTo(
      a.value.recurrence.approxDays,
    );
    return byLength != 0 ? byLength : a.key.compareTo(b.key);
  });
  for (int i = 0; i < indexed.length; i++) {
    suggestions[i] = indexed[i].value;
  }
}

/// Structured result of the maintenance look-up, returned by the Cloudflare
/// Worker and cached on the task.
class MaintenanceLookupResult {
  MaintenanceLookupResult({
    required this.summary,
    required this.suggestedRecurrence,
    required this.manufacturerDomain,
    List<SuggestedRecurrence>? suggestedRecurrences,
    List<ShoppingItem>? shoppingList,
    this.link,
    this.linkType = 'details',
  }) : suggestedRecurrences =
           suggestedRecurrences == null || suggestedRecurrences.isEmpty
           ? <SuggestedRecurrence>[
               SuggestedRecurrence(
                 recurrence: suggestedRecurrence,
                 description: '',
               ),
             ]
           : suggestedRecurrences,
       shoppingList = shoppingList ?? <ShoppingItem>[];

  /// Short plain-language maintenance summary.
  final String summary;

  /// The single most important cadence (kept for older cached results; the
  /// UI renders [suggestedRecurrences]).
  final MaintenanceRecurrence suggestedRecurrence;

  /// All cadences mentioned in the summary, longest interval first. Never
  /// empty: falls back to [suggestedRecurrence] alone.
  final List<SuggestedRecurrence> suggestedRecurrences;

  /// Materials and tools needed for the routine maintenance. Checked items
  /// appear in the central shopping list, like issue look-up items.
  final List<ShoppingItem> shoppingList;

  /// The manufacturer's official registrable domain (e.g. "lg.com"). May be
  /// empty for a general (manufacturer-less) plan.
  final String manufacturerDomain;

  /// A validated HTTPS link from the Worker, retained for forward-
  /// compatibility; the app no longer renders it.
  final String? link;

  /// 'manual' when [link] points at a manual/support page, otherwise 'details'.
  final String linkType;

  factory MaintenanceLookupResult.fromJson(Map<String, dynamic> json) {
    final String? rawLink = (json['link'] as String?)?.trim();
    final String linkType = (json['linkType'] as String?)?.trim() == 'manual'
        ? 'manual'
        : 'details';

    final List<dynamic> recurrencesJson =
        json['suggestedRecurrences'] as List<dynamic>? ?? <dynamic>[];
    final List<SuggestedRecurrence> suggestions = recurrencesJson
        .whereType<Map<String, dynamic>>()
        .map(SuggestedRecurrence.fromJson)
        .toList();
    sortSuggestionsLongestFirst(suggestions);

    final List<dynamic> listJson =
        json['shoppingList'] as List<dynamic>? ?? <dynamic>[];

    return MaintenanceLookupResult(
      summary: (json['summary'] as String?)?.trim() ?? '',
      suggestedRecurrence: MaintenanceRecurrence.fromLabel(
        json['suggestedRecurrence'] as String?,
      ),
      suggestedRecurrences: suggestions,
      shoppingList: listJson
          .whereType<Map<String, dynamic>>()
          .map(ShoppingItem.fromJson)
          .where((ShoppingItem item) => item.item.isNotEmpty)
          .toList(),
      manufacturerDomain:
          (json['manufacturerDomain'] as String?)?.trim().toLowerCase() ?? '',
      link: (rawLink == null || rawLink.isEmpty) ? null : rawLink,
      linkType: linkType,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'summary': summary,
    'suggestedRecurrence': suggestedRecurrence.label,
    'suggestedRecurrences': suggestedRecurrences
        .map((SuggestedRecurrence s) => s.toJson())
        .toList(),
    'shoppingList': shoppingList
        .map((ShoppingItem item) => item.toJson())
        .toList(),
    'manufacturerDomain': manufacturerDomain,
    'link': link,
    'linkType': linkType,
  };
}
