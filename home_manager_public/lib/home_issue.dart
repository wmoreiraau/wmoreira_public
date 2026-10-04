import 'lookup_result.dart';

enum IssuePriority {
  low('Low', 3),
  medium('Medium', 2),
  high('High', 1),
  urgent('Urgent', 0);

  const IssuePriority(this.label, this.sortOrder);

  final String label;
  final int sortOrder;
}

enum ReminderOption {
  everyThirdDay('Every third day'),
  everySecondDay('Every second day'),
  oneDayBefore('1 day before'),
  oneWeekBefore('1 week before'),
  onDueDate('On the due date');

  const ReminderOption(this.label);

  final String label;
}

class HomeIssue {
  HomeIssue({
    required this.title,
    String? id,
    DateTime? createdAt,
    this.notes = '',
    this.priority = IssuePriority.low,
    this.dueDate,
    this.reminderEnabled = false,
    this.reminderOption = ReminderOption.everyThirdDay,
    this.completedAt,
    this.lookup,
    this.manufacturer = '',
    this.model = '',
    this.lookupKey,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now();

  /// Stable identity, used as the Firestore document id.
  final String id;
  final String title;
  final DateTime createdAt;
  String notes;
  IssuePriority priority;
  DateTime? dueDate;
  bool reminderEnabled;
  ReminderOption reminderOption;
  DateTime? completedAt;

  /// Cached AI "Look up" result. Null until the user runs Look up once; then
  /// it is reused so repeat lookups show the same data.
  LookupResult? lookup;

  /// Equipment details for the look-up, shown when the AI identifies that the
  /// task involves an appliance/equipment. Changing them refreshes the lookup.
  String manufacturer;
  String model;

  /// The manufacturer|model the cached [lookup] was computed for.
  String? lookupKey;

  String get currentLookupKey =>
      '${manufacturer.trim().toLowerCase()}|${model.trim().toLowerCase()}';

  bool get isComplete => completedAt != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'priority': priority.name,
    'dueDate': dueDate?.toIso8601String(),
    'reminderEnabled': reminderEnabled,
    'reminderOption': reminderOption.name,
    'completedAt': completedAt?.toIso8601String(),
    'lookup': lookup?.toJson(),
    'manufacturer': manufacturer,
    'model': model,
    'lookupKey': lookupKey,
  };

  factory HomeIssue.fromJson(Map<String, dynamic> json) {
    return HomeIssue(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : null,
      title: (json['title'] as String?)?.trim() ?? '',
      createdAt: _parseDate(json['createdAt']),
      notes: json['notes'] as String? ?? '',
      priority: _priorityByName(json['priority'] as String?),
      dueDate: _parseDate(json['dueDate']),
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
      reminderOption: _reminderByName(json['reminderOption'] as String?),
      completedAt: _parseDate(json['completedAt']),
      lookup: json['lookup'] is Map<String, dynamic>
          ? LookupResult.fromJson(json['lookup'] as Map<String, dynamic>)
          : null,
      manufacturer: json['manufacturer'] as String? ?? '',
      model: json['model'] as String? ?? '',
      lookupKey: json['lookupKey'] as String?,
    );
  }
}

IssuePriority _priorityByName(String? name) {
  return IssuePriority.values.firstWhere(
    (IssuePriority value) => value.name == name,
    orElse: () => IssuePriority.low,
  );
}

ReminderOption _reminderByName(String? name) {
  return ReminderOption.values.firstWhere(
    (ReminderOption value) => value.name == name,
    orElse: () => ReminderOption.everyThirdDay,
  );
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
