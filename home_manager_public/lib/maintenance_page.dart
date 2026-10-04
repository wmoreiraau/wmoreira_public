import 'package:flutter/material.dart';

import 'main.dart' show DetailActionCell, NotesDialog, formatDate;
import 'maintenance_lookup_page.dart';
import 'maintenance_reminder_editor.dart';
import 'maintenance_task.dart';

/// Suggested recurring tasks shown prefilled (white until configured) on the
/// Recurrent Maintenance list — appliances plus other recurring chores.
const List<String> kPrefilledAppliances = <String>[
  'Dishwasher',
  'Washing Machine',
  'Air conditioner',
  'Smoke alarm',
  'Lawn mower',
  'Water indoor plants',
  'Clean gutters',
  'Replace rat baits',
];

const Color _teal = Color(0xFF1F7A6B);
const Color _dark = Color(0xFF21312E);
const Color _body = Color(0xFF263331);
const Color _muted = Color(0xFF68706D);
const Color _border = Color(0xFFE5E0D6);

// Blue surface used for configured rows and the entry cell.
const Color _blueFill = Color(0xFFE2ECFB);
const Color _blueBorder = Color(0xFF6E97D6);
const Color _blueText = Color(0xFF234B86);

/// Recurrent Maintenance list: prefilled appliances plus any saved custom ones.
class RecurrentMaintenancePage extends StatefulWidget {
  const RecurrentMaintenancePage({
    required this.tasks,
    required this.onChanged,
    this.onTaskCreated,
    super.key,
  });

  /// Shared list of configured tasks, owned by the home page. Mutated here and
  /// persisted through [onChanged].
  final List<MaintenanceTask> tasks;
  final VoidCallback onChanged;

  /// Activity-feed hook: fired only when a brand-new task is saved.
  final void Function(MaintenanceTask task)? onTaskCreated;

  @override
  State<RecurrentMaintenancePage> createState() =>
      _RecurrentMaintenancePageState();
}

class _RecurrentMaintenancePageState extends State<RecurrentMaintenancePage> {
  MaintenanceTask? _configuredForSeed(String seedName) {
    for (final MaintenanceTask task in widget.tasks) {
      if ((task.seedName ?? '').toLowerCase() == seedName.toLowerCase()) {
        return task;
      }
    }
    return null;
  }

  List<MaintenanceTask> get _customTasks => widget.tasks
      .where((MaintenanceTask task) => task.seedName == null)
      .toList();

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _upsert(MaintenanceTask saved) {
    final int index = widget.tasks.indexWhere(
      (MaintenanceTask task) => task.id == saved.id,
    );
    setState(() {
      if (index >= 0) {
        widget.tasks[index] = saved;
      } else {
        widget.tasks.add(saved);
      }
    });
    widget.onChanged();
    if (index < 0) {
      widget.onTaskCreated?.call(saved);
    }
  }

  void _delete(MaintenanceTask task) {
    setState(() {
      widget.tasks.removeWhere((MaintenanceTask t) => t.id == task.id);
    });
    widget.onChanged();
  }

  Future<void> _openDetail({
    MaintenanceTask? existing,
    String prefillName = '',
    String? seedName,
  }) async {
    final MaintenanceTask working =
        existing?.copy() ??
        MaintenanceTask(
          id: _newId(),
          applianceName: prefillName,
          seedName: seedName,
        );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return MaintenanceTaskDetailPage(
            task: working,
            isExisting: existing != null,
            onSave: _upsert,
            onDelete: _delete,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<MaintenanceTask> customTasks = _customTasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurrent Maintenance'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: <Widget>[
                const Text(
                  'Register recurring maintenance.',
                  style: TextStyle(color: _muted, height: 1.35),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => _openDetail(),
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                  ),
                ),
                const SizedBox(height: 16),
                for (final String name in kPrefilledAppliances) ...<Widget>[
                  _buildPrefilledRow(name),
                  const SizedBox(height: 12),
                ],
                for (final MaintenanceTask task in customTasks) ...<Widget>[
                  _buildCustomRow(task),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrefilledRow(String name) {
    final MaintenanceTask? configured = _configuredForSeed(name);
    final bool isConfigured = configured != null;
    final String label =
        configured != null && configured.applianceName.trim().isNotEmpty
        ? configured.applianceName
        : name;
    return _MaintenanceRow(
      label: label,
      subtitle: configured != null
          ? _rowSubtitle(configured)
          : 'Not configured yet',
      configured: isConfigured,
      trailing: IconButton(
        icon: Icon(Icons.add, color: isConfigured ? _blueText : _teal),
        tooltip: 'Configure $name',
        onPressed: () =>
            _openDetail(existing: configured, prefillName: name, seedName: name),
      ),
      onTap: () =>
          _openDetail(existing: configured, prefillName: name, seedName: name),
    );
  }

  Widget _buildCustomRow(MaintenanceTask task) {
    return _MaintenanceRow(
      label: task.applianceName.trim().isEmpty
          ? 'Unnamed task'
          : task.applianceName,
      subtitle: _rowSubtitle(task),
      configured: true,
      trailing: const Icon(Icons.chevron_right, color: _blueText),
      onTap: () => _openDetail(existing: task),
    );
  }

  String _rowSubtitle(MaintenanceTask task) {
    if (task.reminders.isEmpty) {
      return 'Configured';
    }
    final int n = task.reminders.length;
    final String count = '$n reminder${n == 1 ? '' : 's'}';
    final DateTime? next = task.nextReminder;
    return next != null ? '$count · next ${formatDate(next)}' : count;
  }
}

class _MaintenanceRow extends StatelessWidget {
  const _MaintenanceRow({
    required this.label,
    required this.subtitle,
    required this.configured,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool configured;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: configured ? _blueFill : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: configured ? _blueBorder : _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.autorenew, color: configured ? _blueText : _teal),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: configured ? _blueText : _body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Task Details pane for a single recurring maintenance task. Edits a working
/// copy and only commits to the store via [onSave].
class MaintenanceTaskDetailPage extends StatefulWidget {
  const MaintenanceTaskDetailPage({
    required this.task,
    required this.isExisting,
    required this.onSave,
    required this.onDelete,
    super.key,
  });

  final MaintenanceTask task;
  final bool isExisting;
  final ValueChanged<MaintenanceTask> onSave;
  final ValueChanged<MaintenanceTask> onDelete;

  @override
  State<MaintenanceTaskDetailPage> createState() =>
      _MaintenanceTaskDetailPageState();
}

class _MaintenanceTaskDetailPageState extends State<MaintenanceTaskDetailPage> {
  MaintenanceTask get _task => widget.task;

  bool get _canSave =>
      _task.applianceName.trim().isNotEmpty && _task.hasValidReminders;

  Future<void> _editApplianceName() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _SingleFieldDialog(
        title: 'Name or Description',
        label: 'Name or description',
        initial: _task.applianceName,
      ),
    );
    if (name == null) {
      return;
    }
    setState(() => _task.applianceName = name.trim());
  }

  Future<void> _editNotes() async {
    final String? notes = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return NotesDialog(initialNotes: _task.notes);
      },
    );
    if (notes == null) {
      return;
    }
    setState(() => _task.notes = notes.trim());
  }

  Future<void> _editModel() async {
    final ({String manufacturer, String model})? result =
        await showDialog<({String manufacturer, String model})>(
          context: context,
          builder: (BuildContext context) => _ModelDialog(
            manufacturer: _task.manufacturer,
            model: _task.model,
          ),
        );
    if (result == null) {
      return;
    }
    setState(() {
      _task.manufacturer = result.manufacturer.trim();
      _task.model = result.model.trim();
    });
  }

  void _openLookup() {
    if (_task.applianceName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a name or description first.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return MaintenanceLookupPage(
            task: _task,
            onChanged: () => setState(() {}),
          );
        },
      ),
    );
  }

  Future<void> _addReminder() async {
    final MaintenanceReminder? reminder = await showReminderEditor(context);
    if (reminder == null || !mounted) {
      return;
    }
    setState(() => _task.reminders.add(reminder));
  }

  Future<void> _editReminder(MaintenanceReminder existing) async {
    final MaintenanceReminder? reminder = await showReminderEditor(
      context,
      existing: existing,
    );
    if (reminder == null || !mounted) {
      return;
    }
    setState(() {
      final int i = _task.reminders.indexWhere(
        (MaintenanceReminder r) => r.id == existing.id,
      );
      if (i >= 0) {
        _task.reminders[i] = reminder;
      } else {
        _task.reminders.add(reminder);
      }
    });
  }

  void _deleteReminder(MaintenanceReminder reminder) {
    setState(() {
      _task.reminders.removeWhere(
        (MaintenanceReminder r) => r.id == reminder.id,
      );
    });
  }

  void _save() {
    if (!_canSave) {
      return;
    }
    widget.onSave(_task);
    Navigator.of(context).pop();
  }

  Future<void> _deleteTask() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: const Text(
            'This recurring maintenance task will be removed.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD44747),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    widget.onDelete(_task);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _task.applianceName.trim().isEmpty
                        ? 'New task'
                        : _task.applianceName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 22),
                  DetailActionCell(
                    title: 'Name or Description',
                    subtitle: _task.applianceName.trim().isEmpty
                        ? 'Tap to set a name or description'
                        : _task.applianceName,
                    icon: Icons.label_outlined,
                    onTap: _editApplianceName,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Model',
                    subtitle: _modelSubtitle(),
                    icon: Icons.tag_outlined,
                    onTap: _editModel,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Notes',
                    subtitle: _task.notes.isEmpty
                        ? 'Optional details, e.g. plant type'
                        : _task.notes,
                    icon: Icons.notes,
                    onTap: _editNotes,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Look up',
                    subtitle: _task.lookup == null
                        ? 'AI maintenance details'
                        : 'View maintenance details',
                    icon: Icons.auto_awesome,
                    onTap: _openLookup,
                  ),
                  const SizedBox(height: 20),
                  _buildRemindersSection(),
                  const SizedBox(height: 24),
                  if (!_canSave) ...<Widget>[
                    Text(
                      _saveBlockedReason(),
                      style: const TextStyle(color: _muted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _canSave ? _save : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Save task'),
                    ),
                  ),
                  if (widget.isExisting) ...<Widget>[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD44747),
                          side: const BorderSide(color: Color(0xFFD44747)),
                        ),
                        onPressed: _deleteTask,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete task'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRemindersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Reminders',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: _addReminder,
              icon: const Icon(Icons.add),
              tooltip: 'Add reminder',
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_task.reminders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No reminders yet — tap + to add one.',
              style: TextStyle(color: _muted),
            ),
          )
        else
          for (final MaintenanceReminder reminder in _task.reminders)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReminderRow(
                reminder: reminder,
                onTap: () => _editReminder(reminder),
                onDelete: () => _deleteReminder(reminder),
              ),
            ),
      ],
    );
  }

  String _modelSubtitle() {
    final String manufacturer = _task.manufacturer.trim();
    final String model = _task.model.trim();
    if (manufacturer.isEmpty && model.isEmpty) {
      return 'For appliances and equipment only';
    }
    final List<String> parts = <String>[];
    if (manufacturer.isNotEmpty) {
      parts.add('Manufacturer: $manufacturer');
    }
    if (model.isNotEmpty) {
      parts.add('Model: $model');
    }
    return parts.join('  ·  ');
  }

  String _saveBlockedReason() {
    if (_task.applianceName.trim().isEmpty) {
      return 'Add a name or description to save.';
    }
    if (!_task.hasValidReminders) {
      return 'A custom reminder needs at least 1 month or 1 week.';
    }
    return '';
  }
}

/// Compact reminder row showing "Frequency - Title" with its next date.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onTap,
    required this.onDelete,
  });

  final MaintenanceReminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.notifications_outlined,
                color: _teal,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      reminder.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Next ${formatDate(reminder.nextReminder)}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 20),
                color: _muted,
                tooltip: 'Remove reminder',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog({required this.manufacturer, required this.model});

  final String manufacturer;
  final String model;

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  late final TextEditingController _manufacturerController =
      TextEditingController(text: widget.manufacturer);
  late final TextEditingController _modelController = TextEditingController(
    text: widget.model,
  );

  @override
  void dispose() {
    _manufacturerController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Model'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _manufacturerController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Manufacturer',
              hintText: 'e.g. LG',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'e.g. DFB424FP',
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
            manufacturer: _manufacturerController.text,
            model: _modelController.text,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SingleFieldDialog extends StatefulWidget {
  const _SingleFieldDialog({
    required this.title,
    required this.label,
    required this.initial,
  });

  final String title;
  final String label;
  final String initial;

  @override
  State<_SingleFieldDialog> createState() => _SingleFieldDialogState();
}

class _SingleFieldDialogState extends State<_SingleFieldDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(
          counterText: '',
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
