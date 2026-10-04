import 'package:flutter/material.dart';

import 'browser_launcher.dart';
import 'lookup_result.dart' show ShoppingItem;
import 'lookup_service.dart' show LookupException;
import 'maintenance_lookup_result.dart';
import 'maintenance_reminder_editor.dart';
import 'maintenance_service.dart';
import 'maintenance_task.dart';

/// In-app result screen for the appliance-maintenance look-up. Reuses the
/// cached result unless the manufacturer/model changed, mirroring the issue
/// "Look up" screen.
class MaintenanceLookupPage extends StatefulWidget {
  const MaintenanceLookupPage({
    required this.task,
    required this.onChanged,
    super.key,
  });

  final MaintenanceTask task;

  /// Called after the cached result or the task's reminders change, so the
  /// parent can refresh.
  final VoidCallback onChanged;

  @override
  State<MaintenanceLookupPage> createState() => _MaintenanceLookupPageState();
}

class _MaintenanceLookupPageState extends State<MaintenanceLookupPage> {
  static const Color _teal = Color(0xFF1F7A6B);
  static const Color _dark = Color(0xFF21312E);
  static const Color _body = Color(0xFF263331);
  static const Color _muted = Color(0xFF68706D);
  static const Color _border = Color(0xFFE5E0D6);

  bool _loading = false;
  String? _error;

  MaintenanceTask get _task => widget.task;
  MaintenanceLookupResult? get _result => _task.lookup;

  String get _heading {
    final String name = _task.applianceName.trim();
    return name.isEmpty ? 'Appliance' : name;
  }

  bool get _hasManufacturerAndModel =>
      _task.manufacturer.trim().isNotEmpty && _task.model.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Reuse the cache when it still matches the current manufacturer/model;
    // otherwise (first run, or manufacturer/model changed) make a fresh call.
    if (!_task.hasFreshLookup) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MaintenanceLookupResult result = await fetchMaintenanceLookup(
        appliance: _task.applianceName,
        manufacturer: _task.manufacturer,
        model: _task.model,
        notes: _task.notes,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _task.lookup = result;
        _task.lookupKey = _task.currentLookupKey;
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

  void _findManual() {
    openSearchQuery(
      '${_task.manufacturer.trim()} ${_task.model.trim()} manual',
    );
  }

  void _searchMaintenance() {
    openSearchQuery('$_heading Maintenance');
  }

  Future<void> _createReminder(SuggestedRecurrence suggestion) async {
    final String description = suggestion.description.trim();
    final MaintenanceReminder? reminder = await showReminderEditor(
      context,
      fixedFrequency: suggestion.recurrence,
      presetTitle: description.isNotEmpty ? description : _task.applianceName,
    );
    if (reminder == null || !mounted) {
      return;
    }
    setState(() => _task.reminders.add(reminder));
    widget.onChanged();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder added: ${reminder.displayLabel}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance look up'),
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
    final MaintenanceLookupResult? result = _result;
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
            'Finding maintenance details for "$_heading"…',
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
            _buildSearchButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MaintenanceLookupResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _heading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
              const SizedBox(height: 20),
              if (result.summary.isNotEmpty) ...<Widget>[
                _sectionTitle('Maintenance summary'),
                const SizedBox(height: 8),
                Text(
                  result.summary,
                  style: const TextStyle(color: _body, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              _sectionTitle(
                result.suggestedRecurrences.length > 1
                    ? 'Suggested recurrences'
                    : 'Suggested recurrence',
              ),
              const SizedBox(height: 8),
              _buildSuggestionList(result.suggestedRecurrences),
              const SizedBox(height: 16),
              _sectionTitle('Suggested shopping list'),
              const SizedBox(height: 8),
              if (result.shoppingList.isEmpty)
                const Text('No items needed.', style: TextStyle(color: _muted))
              else
                _buildShoppingList(result.shoppingList),
              const SizedBox(height: 20),
              _buildSearchButton(),
              const SizedBox(height: 24),
              const _AiDisclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleItem(ShoppingItem item, bool value) {
    setState(() {
      item.checked = value;
    });
    widget.onChanged();
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

  Widget _buildSearchButton() {
    if (_hasManufacturerAndModel) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _findManual,
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Find Manual'),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _searchMaintenance,
        icon: const Icon(Icons.search, size: 18),
        label: const Text('Search the web'),
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
}

/// Shared "AI can make mistakes" footer for the look-up screens.
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
