import 'package:flutter/material.dart';

import 'browser_launcher.dart';
import 'home_issue.dart';
import 'lookup_result.dart';
import 'lookup_service.dart';
import 'maintenance_lookup_result.dart';
import 'maintenance_reminder_editor.dart';
import 'maintenance_task.dart';

class LookupResultPage extends StatefulWidget {
  const LookupResultPage({
    required this.issue,
    required this.onChanged,
    required this.onReminderCreated,
    super.key,
  });

  final HomeIssue issue;

  /// Called after the cached result or a checkbox changes, so the parent can
  /// persist the issue.
  final VoidCallback onChanged;

  /// Called when the user creates a recurrent reminder from this look-up.
  /// The home page converts the issue into a Recurrent Maintenance task.
  final ValueChanged<MaintenanceReminder> onReminderCreated;

  @override
  State<LookupResultPage> createState() => _LookupResultPageState();
}

class _LookupResultPageState extends State<LookupResultPage> {
  static const Color _teal = Color(0xFF1F7A6B);
  static const Color _dark = Color(0xFF21312E);
  static const Color _body = Color(0xFF263331);
  static const Color _muted = Color(0xFF68706D);
  static const Color _border = Color(0xFFE5E0D6);

  bool _loading = false;
  String? _error;

  String get _title => widget.issue.title;
  LookupResult? get _result => widget.issue.lookup;

  @override
  void initState() {
    super.initState();
    // Reuse the cache unless it predates recurrence detection (legacy) or the
    // manufacturer/model changed since it was fetched.
    final LookupResult? cached = widget.issue.lookup;
    if (cached == null ||
        cached.legacy ||
        widget.issue.lookupKey != widget.issue.currentLookupKey) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final LookupResult result = await fetchLookup(
        _title,
        manufacturer: widget.issue.manufacturer,
        model: widget.issue.model,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        widget.issue.lookup = result;
        widget.issue.lookupKey = widget.issue.currentLookupKey;
        _loading = false;
      });
      widget.onChanged();
    } on LookupException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  void _toggleItem(ShoppingItem item, bool value) {
    setState(() {
      item.checked = value;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Look up'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoading();
    }
    if (_error != null) {
      return _buildError(_error!);
    }
    final LookupResult? result = _result;
    if (result == null) {
      return _buildLoading();
    }
    return _buildContent(result);
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(color: _teal),
          const SizedBox(height: 18),
          Text(
            'Looking up "$_title"…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off, size: 40, color: _muted),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _body, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
            const SizedBox(height: 24),
            _WebFallback(issueTitle: _title),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(LookupResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 20),
              if (result.summary.isNotEmpty) ...<Widget>[
                _sectionTitle('How to fix'),
                const SizedBox(height: 8),
                Text(
                  result.summary,
                  style: const TextStyle(color: _body, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              if (result.steps.isNotEmpty) ...<Widget>[
                _buildSteps(result.steps),
                const SizedBox(height: 16),
              ],
              if (result.safetyNote != null) ...<Widget>[
                _buildSafetyNote(result.safetyNote!),
                const SizedBox(height: 16),
              ],
              if (result.involvesEquipment || _hasEquipmentDetails) ...<Widget>[
                _buildEquipmentCell(),
                const SizedBox(height: 16),
              ],
              if (result.isRecurrent &&
                  result.suggestedRecurrences.isNotEmpty) ...<Widget>[
                _sectionTitle(
                  result.suggestedRecurrences.length > 1
                      ? 'Suggested recurrent reminders'
                      : 'Suggested recurrent reminder',
                ),
                const SizedBox(height: 8),
                _buildSuggestionList(result.suggestedRecurrences),
                const SizedBox(height: 16),
              ],
              _sectionTitle('Suggested shopping list'),
              const SizedBox(height: 8),
              if (result.shoppingList.isEmpty)
                const Text('No items needed.', style: TextStyle(color: _muted))
              else
                _buildShoppingList(result.shoppingList),
              const SizedBox(height: 24),
              _WebFallback(issueTitle: _title),
              const SizedBox(height: 24),
              const _AiDisclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: _dark,
      ),
    );
  }

  bool get _hasEquipmentDetails =>
      widget.issue.manufacturer.trim().isNotEmpty ||
      widget.issue.model.trim().isNotEmpty;

  /// Manufacturer/model cell, shown when the AI identifies equipment in the
  /// task. Changing the values refreshes the look-up.
  Widget _buildEquipmentCell() {
    final String manufacturer = widget.issue.manufacturer.trim();
    final String model = widget.issue.model.trim();
    final List<String> parts = <String>[];
    if (manufacturer.isNotEmpty) {
      parts.add('Manufacturer: $manufacturer');
    }
    if (model.isNotEmpty) {
      parts.add('Model: $model');
    }
    final String subtitle = parts.isEmpty
        ? 'Add them to tailor this plan to your equipment'
        : parts.join('  ·  ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.tag_outlined, color: _teal),
        title: const Text(
          'Model',
          style: TextStyle(color: _body, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 12.5),
        ),
        trailing: const Icon(Icons.chevron_right, color: _muted),
        onTap: _editEquipment,
      ),
    );
  }

  Future<void> _editEquipment() async {
    final ({String manufacturer, String model})? result =
        await showDialog<({String manufacturer, String model})>(
          context: context,
          builder: (BuildContext context) {
            return _EquipmentDialog(
              manufacturer: widget.issue.manufacturer,
              model: widget.issue.model,
            );
          },
        );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      widget.issue.manufacturer = result.manufacturer.trim();
      widget.issue.model = result.model.trim();
    });
    widget.onChanged();
    // Manufacturer/model changed -> refresh the AI look-up.
    if (widget.issue.lookupKey != widget.issue.currentLookupKey) {
      await _fetch();
    }
  }

  /// One row per suggested cadence ("Yearly - Replace battery"), longest
  /// interval first, each with its own create-reminder button.
  Widget _buildSuggestionList(List<SuggestedRecurrence> suggestions) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < suggestions.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, color: _border),
            _buildSuggestionTile(suggestions[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionTile(SuggestedRecurrence suggestion) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: _body, height: 1.3),
                children: <TextSpan>[
                  TextSpan(
                    text: suggestion.recurrence.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (suggestion.description.isNotEmpty)
                    TextSpan(text: ' - ${suggestion.description}'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonalIcon(
            onPressed: () => _createReminder(suggestion),
            icon: const Icon(Icons.add_alert_outlined, size: 18),
            label: const Text('Create reminder'),
          ),
        ],
      ),
    );
  }

  Future<void> _createReminder(SuggestedRecurrence suggestion) async {
    final String description = suggestion.description.trim();
    final MaintenanceReminder? reminder = await showReminderEditor(
      context,
      fixedFrequency: suggestion.recurrence,
      presetTitle: description.isNotEmpty ? description : _title,
    );
    if (reminder == null || !mounted) {
      return;
    }
    widget.onReminderCreated(reminder);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added to Recurrent Maintenance: ${reminder.displayLabel}',
        ),
      ),
    );
  }

  Widget _buildSteps(List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F1EE),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: const TextStyle(color: _body, height: 1.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSafetyNote(String note) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1D8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE7A23C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB9791F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              note,
              style: const TextStyle(color: Color(0xFF7A5512), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingList(List<ShoppingItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 1, color: _border),
            _buildShoppingTile(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildShoppingTile(ShoppingItem item) {
    final bool checked = item.checked;
    return CheckboxListTile(
      value: checked,
      onChanged: (bool? value) => _toggleItem(item, value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: _teal,
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              item.item,
              style: TextStyle(
                color: _body,
                fontWeight: FontWeight.w700,
                decoration: checked
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: _muted,
              ),
            ),
          ),
          if (item.optional) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEE8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
          ],
        ],
      ),
      subtitle: item.reason.isEmpty
          ? null
          : Text(item.reason, style: const TextStyle(color: _muted)),
    );
  }
}

class _WebFallback extends StatelessWidget {
  const _WebFallback({required this.issueTitle});

  final String issueTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Prefer the web?',
          style: TextStyle(
            color: Color(0xFF68706D),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: <Widget>[
            TextButton.icon(
              onPressed: () => openSearchQuery('How to $issueTitle'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('How to'),
            ),
            TextButton.icon(
              onPressed: () => openSearchQuery('$issueTitle products'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Products'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EquipmentDialog extends StatefulWidget {
  const _EquipmentDialog({required this.manufacturer, required this.model});

  final String manufacturer;
  final String model;

  @override
  State<_EquipmentDialog> createState() => _EquipmentDialogState();
}

class _EquipmentDialogState extends State<_EquipmentDialog> {
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
              hintText: 'e.g. Honda',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'e.g. HRX217',
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

/// "AI can make mistakes" footer shown at the bottom of the look-up screen.
class _AiDisclaimer extends StatelessWidget {
  const _AiDisclaimer();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.info_outline, size: 14, color: Color(0xFF68706D)),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'AI can make mistakes, please double check responses',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF68706D), fontSize: 12),
          ),
        ),
      ],
    );
  }
}
