import 'package:flutter/material.dart';

import 'main.dart' show formatDate;
import 'maintenance_task.dart';

const Color _teal = Color(0xFF1F7A6B);
const Color _muted = Color(0xFF68706D);

/// Runs the full reminder flow and returns a new/edited [MaintenanceReminder],
/// or null if the user cancels.
///
/// Flow: the user first sets the title and the latest-maintenance date, then
/// the frequency. When [fixedFrequency] is provided (e.g. creating a reminder
/// from a suggested recurrence), the frequency step is skipped.
Future<MaintenanceReminder?> showReminderEditor(
  BuildContext context, {
  MaintenanceReminder? existing,
  MaintenanceRecurrence? fixedFrequency,
  String? presetTitle,
}) async {
  final ({String title, DateTime date})? titleDate =
      await showDialog<({String title, DateTime date})>(
        context: context,
        builder: (BuildContext context) {
          return _ReminderTitleDateDialog(
            initialTitle: existing?.title ?? presetTitle ?? '',
            initialDate: existing?.date ?? DateTime.now(),
          );
        },
      );
  if (titleDate == null || !context.mounted) {
    return null;
  }

  MaintenanceRecurrence recurrence;
  int months = existing?.customMonths ?? 0;
  int weeks = existing?.customWeeks ?? 0;

  if (fixedFrequency != null) {
    recurrence = fixedFrequency;
    months = 0;
    weeks = 0;
  } else {
    final ({MaintenanceRecurrence recurrence, int months, int weeks})? freq =
        await pickFrequency(
          context,
          initial: existing?.recurrence ?? MaintenanceRecurrence.monthly,
          initialMonths: months,
          initialWeeks: weeks,
        );
    if (freq == null) {
      return null;
    }
    recurrence = freq.recurrence;
    months = freq.months;
    weeks = freq.weeks;
  }

  return MaintenanceReminder(
    id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    title: titleDate.title,
    date: titleDate.date,
    recurrence: recurrence,
    customMonths: months,
    customWeeks: weeks,
  );
}

/// Shows the frequency picker (and the custom interval dialog when needed).
/// Returns null on cancel, or when a custom interval is left at 0 months /
/// 0 weeks (which is invalid).
Future<({MaintenanceRecurrence recurrence, int months, int weeks})?>
pickFrequency(
  BuildContext context, {
  required MaintenanceRecurrence initial,
  int initialMonths = 0,
  int initialWeeks = 0,
}) async {
  final MaintenanceRecurrence? selected =
      await showModalBottomSheet<MaintenanceRecurrence>(
        context: context,
        builder: (BuildContext context) => _FrequencySheet(selected: initial),
      );
  if (selected == null || !context.mounted) {
    return null;
  }
  if (selected != MaintenanceRecurrence.custom) {
    return (recurrence: selected, months: 0, weeks: 0);
  }

  final ({int months, int weeks})? custom = await showDialog<({int months, int weeks})>(
    context: context,
    builder: (BuildContext context) =>
        _CustomIntervalDialog(months: initialMonths, weeks: initialWeeks),
  );
  if (custom == null) {
    return null;
  }
  if (custom.months <= 0 && custom.weeks <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A custom interval needs at least 1 month or 1 week.'),
        ),
      );
    }
    return null;
  }
  return (
    recurrence: MaintenanceRecurrence.custom,
    months: custom.months,
    weeks: custom.weeks,
  );
}

class _ReminderTitleDateDialog extends StatefulWidget {
  const _ReminderTitleDateDialog({
    required this.initialTitle,
    required this.initialDate,
  });

  final String initialTitle;
  final DateTime initialDate;

  @override
  State<_ReminderTitleDateDialog> createState() =>
      _ReminderTitleDateDialogState();
}

class _ReminderTitleDateDialogState extends State<_ReminderTitleDateDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialTitle,
  );
  late DateTime _date = widget.initialDate;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime initial = _date.isAfter(today) ? today : _date;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      helpText: 'Latest maintenance date',
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _titleController.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _titleController,
            autofocus: true,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'Reminder title',
              hintText: 'e.g. Replace battery',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Latest maintenance date',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  formatDate(_date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event, size: 18),
                label: const Text('Change'),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop((
                  title: _titleController.text.trim(),
                  date: _date,
                ))
              : null,
          child: const Text('Next'),
        ),
      ],
    );
  }
}

class _FrequencySheet extends StatelessWidget {
  const _FrequencySheet({required this.selected});

  final MaintenanceRecurrence selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Frequency',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              for (final MaintenanceRecurrence option
                  in MaintenanceRecurrence.values)
                ListTile(
                  title: Text(option.label),
                  trailing: option == selected
                      ? const Icon(Icons.check, color: _teal)
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomIntervalDialog extends StatefulWidget {
  const _CustomIntervalDialog({required this.months, required this.weeks});

  final int months;
  final int weeks;

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final TextEditingController _monthsController = TextEditingController(
    text: widget.months > 0 ? widget.months.toString() : '',
  );
  late final TextEditingController _weeksController = TextEditingController(
    text: widget.weeks > 0 ? widget.weeks.toString() : '',
  );

  @override
  void dispose() {
    _monthsController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  int _parse(TextEditingController controller) {
    final int value = int.tryParse(controller.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Leave a field blank to count it as 0.',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _monthsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Months',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weeksController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Weeks',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            months: _parse(_monthsController),
            weeks: _parse(_weeksController),
          )),
          child: const Text('Set'),
        ),
      ],
    );
  }
}
