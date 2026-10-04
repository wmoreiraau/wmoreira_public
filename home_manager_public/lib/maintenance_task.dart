import 'maintenance_lookup_result.dart';

/// How often a recurring maintenance reminder should repeat. Mirrors the
/// options the AI look-up can suggest, plus a user-defined [custom] interval.
enum MaintenanceRecurrence {
  weekly('Weekly'),
  monthly('Monthly'),
  quarterly('Quarterly'),
  everySixMonths('Every 6 Months'),
  yearly('Yearly'),
  custom('Custom');

  const MaintenanceRecurrence(this.label);

  final String label;

  /// Maps a human label (as returned by the look-up) back to an enum value.
  /// Falls back to [monthly] for anything unrecognised.
  static MaintenanceRecurrence fromLabel(String? label) {
    final String normalized = (label ?? '').trim().toLowerCase();
    for (final MaintenanceRecurrence value in MaintenanceRecurrence.values) {
      if (value.label.toLowerCase() == normalized) {
        return value;
      }
    }
    return MaintenanceRecurrence.monthly;
  }

  static MaintenanceRecurrence byName(String? name) {
    return MaintenanceRecurrence.values.firstWhere(
      (MaintenanceRecurrence value) => value.name == name,
      orElse: () => MaintenanceRecurrence.monthly,
    );
  }

  /// Approximate interval length in days, used to sort suggestions so longer
  /// recurrences come first. [custom] sorts last (its length is per-reminder).
  int get approxDays {
    switch (this) {
      case MaintenanceRecurrence.weekly:
        return 7;
      case MaintenanceRecurrence.monthly:
        return 30;
      case MaintenanceRecurrence.quarterly:
        return 91;
      case MaintenanceRecurrence.everySixMonths:
        return 182;
      case MaintenanceRecurrence.yearly:
        return 365;
      case MaintenanceRecurrence.custom:
        return 0;
    }
  }

  /// The next date after [base] for this recurrence. [customMonths]/[customWeeks]
  /// are only used when this is [custom].
  DateTime nextDate(
    DateTime base, {
    int customMonths = 0,
    int customWeeks = 0,
  }) {
    switch (this) {
      case MaintenanceRecurrence.weekly:
        return base.add(const Duration(days: 7));
      case MaintenanceRecurrence.monthly:
        return addMonths(base, 1);
      case MaintenanceRecurrence.quarterly:
        return addMonths(base, 3);
      case MaintenanceRecurrence.everySixMonths:
        return addMonths(base, 6);
      case MaintenanceRecurrence.yearly:
        return addMonths(base, 12);
      case MaintenanceRecurrence.custom:
        return addMonths(
          base,
          customMonths,
        ).add(Duration(days: customWeeks * 7));
    }
  }
}

/// Adds [months] calendar months to [date], clamping the day to the last valid
/// day of the resulting month (so 31 Jan + 1 month -> 28/29 Feb).
DateTime addMonths(DateTime date, int months) {
  final int zeroBased = date.month - 1 + months;
  final int year = date.year + (zeroBased ~/ 12);
  final int month = (zeroBased % 12) + 1;
  final int lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final int day = date.day <= lastDayOfMonth ? date.day : lastDayOfMonth;
  return DateTime(year, month, day);
}

/// A single reminder on a maintenance task: a [title] (e.g. "Replace battery"),
/// the [date] of the latest maintenance for it, and a repeat [recurrence].
class MaintenanceReminder {
  MaintenanceReminder({
    required this.id,
    required this.title,
    required this.date,
    this.recurrence = MaintenanceRecurrence.monthly,
    this.customMonths = 0,
    this.customWeeks = 0,
  });

  String id;
  String title;

  /// Latest maintenance date for this reminder (its base/anchor date).
  DateTime date;

  MaintenanceRecurrence recurrence;
  int customMonths;
  int customWeeks;

  /// Next reminder = latest maintenance date + the recurrence interval.
  DateTime get nextReminder => recurrence.nextDate(
    date,
    customMonths: customMonths,
    customWeeks: customWeeks,
  );

  /// A custom interval of 0 months and 0 weeks is invalid.
  bool get hasValidInterval {
    if (recurrence != MaintenanceRecurrence.custom) {
      return true;
    }
    return customMonths > 0 || customWeeks > 0;
  }

  /// Human label for the frequency, e.g. "Yearly" or "Every 2 months 1 week".
  String get frequencyLabel {
    if (recurrence != MaintenanceRecurrence.custom) {
      return recurrence.label;
    }
    final List<String> parts = <String>[];
    if (customMonths > 0) {
      parts.add('$customMonths month${customMonths == 1 ? '' : 's'}');
    }
    if (customWeeks > 0) {
      parts.add('$customWeeks week${customWeeks == 1 ? '' : 's'}');
    }
    return parts.isEmpty ? 'Custom' : 'Every ${parts.join(' ')}';
  }

  /// Frequency next to title, e.g. "Yearly - Replace battery".
  String get displayLabel {
    final String t = title.trim();
    return t.isEmpty ? frequencyLabel : '$frequencyLabel - $t';
  }

  MaintenanceReminder copy() => MaintenanceReminder(
    id: id,
    title: title,
    date: date,
    recurrence: recurrence,
    customMonths: customMonths,
    customWeeks: customWeeks,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'recurrence': recurrence.name,
    'customMonths': customMonths,
    'customWeeks': customWeeks,
  };

  factory MaintenanceReminder.fromJson(Map<String, dynamic> json) {
    return MaintenanceReminder(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?)?.trim() ?? '',
      date: _parseDate(json['date']) ?? DateTime.now(),
      recurrence: MaintenanceRecurrence.byName(json['recurrence'] as String?),
      customMonths: (json['customMonths'] as num?)?.toInt() ?? 0,
      customWeeks: (json['customWeeks'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A recurring appliance-maintenance task. Persisted via the maintenance store
/// once it has been configured/saved.
class MaintenanceTask {
  MaintenanceTask({
    required this.id,
    required this.applianceName,
    this.manufacturer = '',
    this.model = '',
    this.notes = '',
    List<MaintenanceReminder>? reminders,
    this.lookup,
    this.lookupKey,
    this.seedName,
    DateTime? createdAt,
  }) : reminders = reminders ?? <MaintenanceReminder>[],
       createdAt = createdAt ?? DateTime.now();

  String id;
  String applianceName;

  /// Two separate fields for the "Model" cell (appliances/equipment only).
  String manufacturer;
  String model;

  /// Free-form details, e.g. plant type. Fed into the AI look-up.
  String notes;

  /// Zero or more reminders, each with its own title, date and frequency.
  List<MaintenanceReminder> reminders;

  /// Cached AI maintenance look-up, reused until manufacturer/model change.
  MaintenanceLookupResult? lookup;

  /// The manufacturer|model the cached [lookup] was computed for, so we know
  /// when to make a fresh AI call.
  String? lookupKey;

  /// The original prefilled appliance name this task was created from (e.g.
  /// "Dishwasher"), or null for a fully custom appliance.
  String? seedName;

  final DateTime createdAt;

  /// Key identifying the inputs the cached look-up was computed for. The
  /// version prefix invalidates older caches (v3 added notes + shopping list),
  /// forcing one fresh AI call per already-configured task.
  static String lookupKeyFor(String manufacturer, String model, String notes) {
    return 'v3|${manufacturer.trim().toLowerCase()}|${model.trim().toLowerCase()}|${notes.trim().toLowerCase()}';
  }

  String get currentLookupKey => lookupKeyFor(manufacturer, model, notes);

  /// Whether the cached [lookup] still matches the current manufacturer/model.
  bool get hasFreshLookup => lookup != null && lookupKey == currentLookupKey;

  /// The soonest upcoming reminder date across all reminders, or null if none.
  DateTime? get nextReminder {
    if (reminders.isEmpty) {
      return null;
    }
    final List<DateTime> dates = reminders
        .map((MaintenanceReminder r) => r.nextReminder)
        .toList()
      ..sort();
    return dates.first;
  }

  bool get hasValidReminders =>
      reminders.every((MaintenanceReminder r) => r.hasValidInterval);

  MaintenanceTask copy() {
    return MaintenanceTask(
      id: id,
      applianceName: applianceName,
      manufacturer: manufacturer,
      model: model,
      notes: notes,
      reminders: reminders
          .map((MaintenanceReminder r) => r.copy())
          .toList(),
      lookup: lookup,
      lookupKey: lookupKey,
      seedName: seedName,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'applianceName': applianceName,
    'manufacturer': manufacturer,
    'model': model,
    'notes': notes,
    'reminders': reminders
        .map((MaintenanceReminder r) => r.toJson())
        .toList(),
    'lookup': lookup?.toJson(),
    'lookupKey': lookupKey,
    'seedName': seedName,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MaintenanceTask.fromJson(Map<String, dynamic> json) {
    return MaintenanceTask(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      applianceName: (json['applianceName'] as String?)?.trim() ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      model: json['model'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      reminders: _parseReminders(json),
      lookup: json['lookup'] is Map<String, dynamic>
          ? MaintenanceLookupResult.fromJson(
              json['lookup'] as Map<String, dynamic>,
            )
          : null,
      lookupKey: json['lookupKey'] as String?,
      seedName: json['seedName'] as String?,
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

/// Parses the reminders list, migrating the old single-reminder shape
/// (latestMaintenance + reminderEnabled + recurrence) when present.
List<MaintenanceReminder> _parseReminders(Map<String, dynamic> json) {
  if (json['reminders'] is List) {
    return (json['reminders'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(MaintenanceReminder.fromJson)
        .toList();
  }
  if (json['reminderEnabled'] == true) {
    final DateTime? date = _parseDate(json['latestMaintenance']);
    if (date != null) {
      return <MaintenanceReminder>[
        MaintenanceReminder(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: 'Maintenance',
          date: date,
          recurrence: MaintenanceRecurrence.byName(json['recurrence'] as String?),
          customMonths: (json['customMonths'] as num?)?.toInt() ?? 0,
          customWeeks: (json['customWeeks'] as num?)?.toInt() ?? 0,
        ),
      ];
    }
  }
  return <MaintenanceReminder>[];
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
