import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_session.dart';
import 'auth_service.dart';
import 'finances_page.dart';
import 'firebase_options.dart';
import 'home_issue.dart';
import 'home_repository.dart';
import 'hub_page.dart';
import 'login_page.dart';
import 'lookup_result.dart';
import 'lookup_result_page.dart';
import 'maintenance_lookup_result.dart';
import 'maintenance_page.dart';
import 'maintenance_task.dart';
import 'manual_shopping_item.dart';
import 'setup_needed_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  runApp(const HomeManagerApp());
}

class HomeManagerApp extends StatelessWidget {
  const HomeManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A6B)),
        scaffoldBackgroundColor: const Color(0xFFF6F4EF),
        useMaterial3: true,
      ),
      home: DefaultFirebaseOptions.isConfigured
          ? const AuthGate()
          : const SetupNeededPage(),
    );
  }
}

/// Authentication gates the whole app: signed out shows the login screen,
/// signed in bootstraps the user's home and shows the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        final User? user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }
        // Key on uid + epoch: a different account, or a join/leave that
        // changed the user's homeId, gets a fresh session.
        return ValueListenableBuilder<int>(
          valueListenable: AppSession.epoch,
          builder: (BuildContext context, int epoch, _) {
            return _SessionLoader(
              key: ValueKey<String>('${user.uid}#$epoch'),
              user: user,
            );
          },
        );
      },
    );
  }
}

/// Ensures users/{uid} + the home exist, loads the home data, then shows the
/// app. Everything below this widget works on the per-home Firestore paths.
class _SessionLoader extends StatefulWidget {
  const _SessionLoader({required this.user, super.key});

  final User user;

  @override
  State<_SessionLoader> createState() => _SessionLoaderState();
}

class _SessionLoaderState extends State<_SessionLoader> {
  late Future<SessionData> _sessionFuture = loadSession(widget.user);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionData>(
      future: _sessionFuture,
      builder: (BuildContext context, AsyncSnapshot<SessionData> snapshot) {
        if (snapshot.hasError) {
          return _SessionError(
            onRetry: () {
              setState(() {
                _sessionFuture = loadSession(widget.user);
              });
            },
          );
        }
        final SessionData? session = snapshot.data;
        if (session == null) {
          return const _Splash(message: 'Setting up your home…');
        }
        return HomeIssuePage(
          repo: session.repo,
          initialIssues: session.issues,
          initialMaintenanceTasks: session.maintenanceTasks,
          initialManualItems: session.manualItems,
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(color: Color(0xFF1F7A6B)),
            if (message != null) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                message!,
                style: const TextStyle(
                  color: Color(0xFF68706D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, size: 40, color: Color(0xFF68706D)),
              const SizedBox(height: 14),
              const Text(
                'Could not load your home. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF263331),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: AuthService.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeIssuePage extends StatefulWidget {
  const HomeIssuePage({
    required this.repo,
    required this.initialIssues,
    required this.initialMaintenanceTasks,
    required this.initialManualItems,
    super.key,
  });

  final HomeRepository repo;
  final List<HomeIssue> initialIssues;
  final List<MaintenanceTask> initialMaintenanceTasks;
  final List<ManualShoppingItem> initialManualItems;

  @override
  State<HomeIssuePage> createState() => _HomeIssuePageState();
}

class _HomeIssuePageState extends State<HomeIssuePage> {
  static const double cardHeight = 80;
  static const double cardGap = 12;
  static const int visibleCardCount = 8;

  late final List<HomeIssue> _issues = List<HomeIssue>.of(
    widget.initialIssues,
  );
  late final List<MaintenanceTask> _maintenanceTasks =
      List<MaintenanceTask>.of(widget.initialMaintenanceTasks);
  late final List<ManualShoppingItem> _manualItems =
      List<ManualShoppingItem>.of(widget.initialManualItems);
  final TextEditingController _issueController = TextEditingController();
  final FocusNode _issueFocusNode = FocusNode();
  bool _isAddingIssue = false;
  final List<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    _listenForHomeChanges();
  }

  /// Keeps the three lists in sync with Firestore so changes made by another
  /// member of the home appear without restarting the app.
  void _listenForHomeChanges() {
    void watch<T>(
      Stream<List<T>> stream,
      List<T> target,
      String Function(T item) idOf,
      Map<String, dynamic> Function(T item) toJson,
    ) {
      _subscriptions.add(
        stream.listen(
          (List<T> incoming) {
            final bool changed = mergeSnapshotInto<T>(
              target: target,
              incoming: incoming,
              idOf: idOf,
              toJson: toJson,
            );
            if (changed && mounted) {
              setState(() {});
            }
          },
          // A stream can fail after leaving a home (the rules stop allowing
          // reads). The session reload replaces this screen anyway.
          onError: (Object _) {},
        ),
      );
    }

    watch<HomeIssue>(
      widget.repo.issuesStream(),
      _issues,
      (HomeIssue i) => i.id,
      (HomeIssue i) => i.toJson(),
    );
    watch<MaintenanceTask>(
      widget.repo.maintenanceTasksStream(),
      _maintenanceTasks,
      (MaintenanceTask t) => t.id,
      (MaintenanceTask t) => t.toJson(),
    );
    watch<ManualShoppingItem>(
      widget.repo.manualItemsStream(),
      _manualItems,
      (ManualShoppingItem i) => i.id,
      (ManualShoppingItem i) => i.toJson(),
    );
  }

  // Fire-and-forget writes to homes/{homeId}/... — the in-memory lists stay
  // the source of truth for the UI, matching the previous local-store flow.
  void _persist() {
    widget.repo.saveIssues(_issues);
  }

  /// Appends to the shared activity feed. Called from the existing action
  /// handlers, so entries fire wherever those actions already happen.
  void _logActivity(String action, String targetType, String targetName) {
    final User? user = AuthService.currentUser;
    final String name = (user?.displayName ?? '').trim();
    widget.repo.addActivity(
      actorUid: user?.uid ?? '',
      actorName: name.isEmpty ? 'Someone' : name,
      action: action,
      targetType: targetType,
      targetName: targetName,
    );
  }

  void _persistMaintenance() {
    widget.repo.saveMaintenanceTasks(_maintenanceTasks);
  }

  void _persistManualItems() {
    widget.repo.saveManualItems(_manualItems);
  }

  int get _shoppingItemCount {
    int count = _manualItems.length;
    for (final HomeIssue issue in _issues) {
      final LookupResult? lookup = issue.lookup;
      if (lookup == null) {
        continue;
      }
      for (final ShoppingItem item in lookup.shoppingList) {
        if (item.checked) {
          count++;
        }
      }
    }
    for (final MaintenanceTask task in _maintenanceTasks) {
      final MaintenanceLookupResult? lookup = task.lookup;
      if (lookup == null) {
        continue;
      }
      for (final ShoppingItem item in lookup.shoppingList) {
        if (item.checked) {
          count++;
        }
      }
    }
    return count;
  }

  /// All reminders across all maintenance tasks, soonest due date first.
  List<(MaintenanceTask, MaintenanceReminder)> get _reminderEntries {
    final List<(MaintenanceTask, MaintenanceReminder)> entries =
        <(MaintenanceTask, MaintenanceReminder)>[];
    for (final MaintenanceTask task in _maintenanceTasks) {
      for (final MaintenanceReminder reminder in task.reminders) {
        entries.add((task, reminder));
      }
    }
    entries.sort(
      ((MaintenanceTask, MaintenanceReminder) a,
              (MaintenanceTask, MaintenanceReminder) b) =>
          a.$2.nextReminder.compareTo(b.$2.nextReminder),
    );
    return entries;
  }

  @override
  void dispose() {
    for (final StreamSubscription<void> subscription in _subscriptions) {
      subscription.cancel();
    }
    _issueController.dispose();
    _issueFocusNode.dispose();
    super.dispose();
  }

  List<HomeIssue> get _activeIssues {
    final List<HomeIssue> activeIssues = _issues
        .where((HomeIssue issue) => !issue.isComplete)
        .toList();
    activeIssues.sort((HomeIssue a, HomeIssue b) {
      final int priorityCompare = a.priority.sortOrder.compareTo(
        b.priority.sortOrder,
      );
      if (priorityCompare != 0) {
        return priorityCompare;
      }

      final int dateCompare = b.createdAt.compareTo(a.createdAt);
      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return activeIssues;
  }

  List<HomeIssue> get _doneIssues {
    final List<HomeIssue> doneIssues = _issues
        .where((HomeIssue issue) => issue.isComplete)
        .toList();
    doneIssues.sort((HomeIssue a, HomeIssue b) {
      final DateTime aDate =
          a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return doneIssues;
  }

  void _showIssueInput() {
    setState(() {
      _isAddingIssue = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _issueFocusNode.requestFocus();
      }
    });
  }

  void _addIssue() {
    final String issueTitle = _issueController.text.trim();
    if (issueTitle.isEmpty) {
      return;
    }

    setState(() {
      _issues.add(HomeIssue(title: issueTitle));
      _issueController.clear();
      _isAddingIssue = false;
    });
    _persist();
    _logActivity('created_issue', 'issue', issueTitle);
  }

  void _openIssue(HomeIssue issue) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return IssueDetailPage(
            issue: issue,
            onIssueChanged: () {
              setState(() {});
              _persist();
            },
            onCompleteIssue: _completeIssue,
            onDeleteIssue: _deleteIssue,
            onReminderCreated: (MaintenanceReminder reminder) =>
                _convertIssueToRecurrent(issue, reminder),
          );
        },
      ),
    );
  }

  /// Turns a recurrent issue into a Recurrent Maintenance task: the issue card
  /// is replaced by the recurrent reminder card(s) on the main screen.
  ///
  /// The task is named after the item identified by the AI ("Oven" for
  /// "Clean oven"). Reminders for the same item with the same model details
  /// join the existing task; the same item with different model details gets
  /// a numbered name ("Oven 2", "Oven 3", ...).
  void _convertIssueToRecurrent(HomeIssue issue, MaintenanceReminder reminder) {
    bool createdNewTask = false;
    String createdTaskName = '';
    setState(() {
      final LookupResult? lookup = issue.lookup;
      final String itemName = (lookup?.itemName ?? '').trim();
      final String baseName = itemName.isNotEmpty ? itemName : issue.title;
      final String issueDetails =
          '${issue.manufacturer.trim().toLowerCase()}|${issue.model.trim().toLowerCase()}';

      MaintenanceTask? task;
      String name = baseName;
      int suffix = 2;
      while (true) {
        MaintenanceTask? sameName;
        for (final MaintenanceTask t in _maintenanceTasks) {
          if (t.applianceName.trim().toLowerCase() ==
              name.trim().toLowerCase()) {
            sameName = t;
            break;
          }
        }
        if (sameName == null) {
          break;
        }
        final String taskDetails =
            '${sameName.manufacturer.trim().toLowerCase()}|${sameName.model.trim().toLowerCase()}';
        if (taskDetails == issueDetails) {
          task = sameName;
          break;
        }
        name = '$baseName ${suffix++}';
      }

      if (task == null) {
        task = MaintenanceTask(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          applianceName: name,
          manufacturer: issue.manufacturer,
          model: issue.model,
          notes: issue.notes,
          lookup: lookup == null
              ? null
              : MaintenanceLookupResult(
                  summary: lookup.summary,
                  suggestedRecurrence: lookup.suggestedRecurrences.isNotEmpty
                      ? lookup.suggestedRecurrences.first.recurrence
                      : MaintenanceRecurrence.monthly,
                  suggestedRecurrences: lookup.suggestedRecurrences,
                  shoppingList: lookup.shoppingList,
                  manufacturerDomain: '',
                ),
        );
        task.lookupKey = task.currentLookupKey;
        _maintenanceTasks.add(task);
        createdNewTask = true;
        createdTaskName = name;
      }
      task.reminders.add(reminder);
      _issues.remove(issue);
    });
    _persist();
    _persistMaintenance();
    if (createdNewTask) {
      _logActivity('created_recurrent_task', 'recurrentTask', createdTaskName);
    }
  }

  void _openMaintenanceTask(MaintenanceTask task) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return MaintenanceTaskDetailPage(
            task: task.copy(),
            isExisting: true,
            onSave: (MaintenanceTask saved) {
              setState(() {
                final int index = _maintenanceTasks.indexWhere(
                  (MaintenanceTask t) => t.id == saved.id,
                );
                if (index >= 0) {
                  _maintenanceTasks[index] = saved;
                } else {
                  _maintenanceTasks.add(saved);
                }
              });
              _persistMaintenance();
            },
            onDelete: (MaintenanceTask deleted) {
              setState(() {
                _maintenanceTasks.removeWhere(
                  (MaintenanceTask t) => t.id == deleted.id,
                );
              });
              _persistMaintenance();
            },
          );
        },
      ),
    );
  }

  void _completeIssue(HomeIssue issue) {
    setState(() {
      issue.completedAt = DateTime.now();
    });
    _persist();
    _logActivity('completed_issue', 'issue', issue.title);
  }

  void _deleteIssue(HomeIssue issue) {
    setState(() {
      _issues.remove(issue);
    });
    _persist();
  }

  void _openDoneIssues() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return DoneIssuesPage(issues: _doneIssues, onClearAll: _clearDoneIssues);
        },
      ),
    );
  }

  void _clearDoneIssues() {
    setState(() {
      _issues.removeWhere((HomeIssue issue) => issue.isComplete);
    });
    _persist();
  }

  void _openHub() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ManagementHubPage(repo: widget.repo),
      ),
    );
  }

  void _openFinances() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const FinancesPage(),
      ),
    );
  }

  void _openShoppingList() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return ShoppingListPage(
            issues: _issues,
            maintenanceTasks: _maintenanceTasks,
            manualItems: _manualItems,
            onIssuesChanged: () {
              setState(() {});
              _persist();
            },
            onMaintenanceChanged: () {
              setState(() {});
              _persistMaintenance();
            },
            onManualChanged: () {
              setState(() {});
              _persistManualItems();
            },
            onItemAdded: (String name) =>
                _logActivity('added_shopping_item', 'shoppingItem', name),
            onGotIt: (List<String> names) => _logActivity(
              'confirmed_got_it',
              'shoppingList',
              names.length == 1 ? names.first : '${names.length} items',
            ),
          );
        },
      ),
    );
  }

  void _openRecurrentMaintenance() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return RecurrentMaintenancePage(
            tasks: _maintenanceTasks,
            onChanged: () {
              setState(() {});
              _persistMaintenance();
            },
            onTaskCreated: (MaintenanceTask task) => _logActivity(
              'created_recurrent_task',
              'recurrentTask',
              task.applianceName,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<HomeIssue> activeIssues = _activeIssues;
    final List<(MaintenanceTask, MaintenanceReminder)> reminderEntries =
        _reminderEntries;
    final double maxListHeight =
        (cardHeight * visibleCardCount) + (cardGap * (visibleCardCount - 1));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 96),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Home Manager',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF21312E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tasks and issues',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF68706D),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isAddingIssue) ...<Widget>[
                    _IssueInput(
                      controller: _issueController,
                      focusNode: _issueFocusNode,
                      onSubmit: _addIssue,
                    ),
                    const SizedBox(height: 18),
                  ],
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxListHeight),
                        child: activeIssues.isEmpty && reminderEntries.isEmpty
                            ? const _EmptyActiveList()
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount:
                                    activeIssues.length +
                                    reminderEntries.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: cardGap),
                                itemBuilder: (BuildContext context, int index) {
                                  if (index < activeIssues.length) {
                                    final HomeIssue issue = activeIssues[index];
                                    return IssueCard(
                                      issue: issue,
                                      onTap: () => _openIssue(issue),
                                    );
                                  }
                                  final (
                                    MaintenanceTask task,
                                    MaintenanceReminder reminder,
                                  ) = reminderEntries[index -
                                      activeIssues.length];
                                  return _RecurrentReminderCard(
                                    task: task,
                                    reminder: reminder,
                                    onTap: () => _openMaintenanceTask(task),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _RecurrentMaintenanceCell(onTap: _openRecurrentMaintenance),
                  const SizedBox(height: 12),
                  _DoneCell(count: _doneIssues.length, onTap: _openDoneIssues),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Badge.count(
            count: _shoppingItemCount,
            isLabelVisible: _shoppingItemCount > 0,
            child: FloatingActionButton(
              heroTag: 'shopping-list',
              onPressed: _openShoppingList,
              tooltip: 'Shopping list',
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'management-hub',
            onPressed: _openHub,
            tooltip: 'Household',
            child: const Icon(Icons.people_outline),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'finances',
            onPressed: _openFinances,
            tooltip: 'Finances',
            child: const Icon(Icons.attach_money),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'add-issue',
            onPressed: _showIssueInput,
            tooltip: 'Add issue',
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// A recurrent maintenance reminder shown on the main screen, styled like a
/// low-priority task card and sorted by due date.
class _RecurrentReminderCard extends StatelessWidget {
  const _RecurrentReminderCard({
    required this.task,
    required this.reminder,
    required this.onTap,
  });

  final MaintenanceTask task;
  final MaintenanceReminder reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String taskName = task.applianceName.trim();
    final String reminderTitle = reminder.title.trim();
    final String label =
        reminderTitle.isEmpty ||
            reminderTitle.toLowerCase() == taskName.toLowerCase()
        ? taskName
        : '$taskName · $reminderTitle';

    return _CellSurface(
      onTap: onTap,
      backgroundColor: const Color(0xFFFFF1D8),
      borderColor: const Color(0xFFE7A23C),
      child: Row(
        children: <Widget>[
          const Icon(Icons.autorenew, color: Color(0xFFB9791F)),
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF263331),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Due ${formatDate(reminder.nextReminder)} · ${reminder.frequencyLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF68706D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF68706D)),
        ],
      ),
    );
  }
}

class _RecurrentMaintenanceCell extends StatelessWidget {
  const _RecurrentMaintenanceCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CellSurface(
      key: const ValueKey<String>('recurrent-maintenance-cell'),
      onTap: onTap,
      backgroundColor: const Color(0xFFE2ECFB),
      borderColor: const Color(0xFF6E97D6),
      child: Row(
        children: <Widget>[
          const Icon(Icons.autorenew, color: Color(0xFF234B86)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Recurrent Maintenance',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF234B86),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF234B86)),
        ],
      ),
    );
  }
}

class _IssueInput extends StatelessWidget {
  const _IssueInput({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            maxLength: 100,
            onSubmitted: (_) => onSubmit(),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'Add a home task or issue',
              filled: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.check),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

class _DoneCell extends StatelessWidget {
  const _DoneCell({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CellSurface(
      key: const ValueKey<String>('done-cell'),
      onTap: onTap,
      backgroundColor: const Color(0xFFE3F4E8),
      borderColor: const Color(0xFF7EC28D),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D46)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Done',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF1E5530),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF2E7D46),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Color(0xFF2E7D46)),
        ],
      ),
    );
  }
}

class IssueCard extends StatelessWidget {
  const IssueCard({required this.issue, required this.onTap, super.key});

  final HomeIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CellSurface(
      key: ValueKey<String>('issue-card-${issue.title}'),
      onTap: onTap,
      backgroundColor: _backgroundColor,
      borderColor: _borderColor,
      child: Row(
        children: <Widget>[
          _PriorityMarker(priority: issue.priority),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              issue.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF263331),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF68706D)),
        ],
      ),
    );
  }

  Color get _backgroundColor {
    return switch (issue.priority) {
      IssuePriority.low => const Color(0xFFFFF1D8),
      IssuePriority.medium => const Color(0xFFFFF1D8),
      IssuePriority.high => const Color(0xFFFFE3E3),
      IssuePriority.urgent => const Color(0xFFFFE3E3),
    };
  }

  Color get _borderColor {
    return switch (issue.priority) {
      IssuePriority.low => const Color(0xFFE7A23C),
      IssuePriority.medium => const Color(0xFFE7A23C),
      IssuePriority.high => const Color(0xFFD44747),
      IssuePriority.urgent => const Color(0xFFD44747),
    };
  }
}

class _PriorityMarker extends StatelessWidget {
  const _PriorityMarker({required this.priority});

  final IssuePriority priority;

  @override
  Widget build(BuildContext context) {
    final Color color =
        priority == IssuePriority.high || priority == IssuePriority.urgent
        ? const Color(0xFFD44747)
        : const Color(0xFFDB8B46);
    final double size =
        priority == IssuePriority.low || priority == IssuePriority.medium
        ? 10
        : 12;

    return Container(
      key: ValueKey<String>('priority-marker-${priority.label}'),
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _CellSurface extends StatelessWidget {
  const _CellSurface({
    required this.child,
    this.onTap,
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFE5E0D6),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _HomeIssuePageState.cardHeight,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EmptyActiveList extends StatelessWidget {
  const _EmptyActiveList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No active issues',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF68706D),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class IssueDetailPage extends StatefulWidget {
  const IssueDetailPage({
    required this.issue,
    required this.onIssueChanged,
    required this.onCompleteIssue,
    required this.onDeleteIssue,
    required this.onReminderCreated,
    super.key,
  });

  final HomeIssue issue;
  final VoidCallback onIssueChanged;
  final void Function(HomeIssue issue) onCompleteIssue;
  final void Function(HomeIssue issue) onDeleteIssue;

  /// Forwarded to the look-up page: creating a reminder there converts this
  /// issue into a Recurrent Maintenance task.
  final void Function(MaintenanceReminder reminder) onReminderCreated;

  @override
  State<IssueDetailPage> createState() => _IssueDetailPageState();
}

class _IssueDetailPageState extends State<IssueDetailPage> {
  HomeIssue get issue => widget.issue;

  void _lookUpIssue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return LookupResultPage(
            issue: issue,
            onChanged: widget.onIssueChanged,
            onReminderCreated: widget.onReminderCreated,
          );
        },
      ),
    );
  }

  Future<void> _editNotes() async {
    final String? notes = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return NotesDialog(initialNotes: issue.notes);
      },
    );

    if (notes == null) {
      return;
    }

    setState(() {
      issue.notes = notes.trim();
    });
    widget.onIssueChanged();
  }

  Future<void> _choosePriority() async {
    final IssuePriority? selectedPriority =
        await showModalBottomSheet<IssuePriority>(
          context: context,
          builder: (BuildContext context) {
            return _OptionSheet<IssuePriority>(
              title: 'Priority',
              options: IssuePriority.values,
              selectedOption: issue.priority,
              labelBuilder: (IssuePriority priority) => priority.label,
            );
          },
        );

    if (selectedPriority == null) {
      return;
    }

    setState(() {
      issue.priority = selectedPriority;
    });
    widget.onIssueChanged();
  }

  Future<void> _pickDueDate() async {
    final DateTime today = DateTime.now();
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: issue.dueDate ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
    );

    if (!mounted || selectedDate == null) {
      return;
    }

    setState(() {
      issue.dueDate = selectedDate;
      issue.reminderEnabled = true;
      issue.reminderOption = ReminderOption.everyThirdDay;
    });
    widget.onIssueChanged();

    await _showReminderOptions();
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    setState(() {
      issue.reminderEnabled = enabled;
      if (enabled) {
        issue.reminderOption = ReminderOption.everyThirdDay;
      }
    });
    widget.onIssueChanged();

    if (enabled) {
      await _showReminderOptions();
    }
  }

  Future<void> _openReminderCell() async {
    if (issue.reminderEnabled) {
      await _showReminderOptions();
      return;
    }

    await _setReminderEnabled(true);
  }

  Future<void> _showReminderOptions() async {
    final ReminderOption? selectedOption =
        await showModalBottomSheet<ReminderOption>(
          context: context,
          builder: (BuildContext context) {
            return _OptionSheet<ReminderOption>(
              title: 'Reminder',
              options: ReminderOption.values,
              selectedOption: issue.reminderOption,
              labelBuilder: (ReminderOption option) => option.label,
            );
          },
        );

    if (!mounted || selectedOption == null) {
      return;
    }

    setState(() {
      issue.reminderOption = selectedOption;
    });
    widget.onIssueChanged();
  }

  Future<void> _markDone() async {
    final bool confirmed = await _confirmAction(
      title: 'Mark as done?',
      message: 'Move this task to Done?',
      confirmLabel: 'Move',
    );

    if (!confirmed || !mounted) {
      return;
    }

    widget.onCompleteIssue(issue);
    Navigator.of(context).pop();
  }

  Future<void> _deleteIssue() async {
    final bool confirmed = await _confirmAction(
      title: 'Delete issue?',
      message: 'This issue will be removed permanently.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (!confirmed || !mounted) {
      return;
    }

    widget.onDeleteIssue(issue);
    Navigator.of(context).pop();
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: isDestructive
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD44747),
                    )
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Details'),
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
                    issue.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF21312E),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  DetailActionCell(
                    title: 'Look up',
                    subtitle: 'AI fix steps & shopping list',
                    icon: Icons.auto_awesome,
                    onTap: _lookUpIssue,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Notes',
                    subtitle: issue.notes.isEmpty
                        ? 'No notes added'
                        : issue.notes,
                    icon: Icons.notes,
                    onTap: _editNotes,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Priority',
                    subtitle: issue.priority.label,
                    icon: Icons.flag_outlined,
                    onTap: _choosePriority,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Due',
                    subtitle: issue.dueDate == null
                        ? 'No date selected'
                        : formatDate(issue.dueDate!),
                    icon: Icons.event_outlined,
                    onTap: _pickDueDate,
                  ),
                  const SizedBox(height: 12),
                  ReminderActionCell(
                    enabled: issue.reminderEnabled,
                    optionLabel: issue.reminderOption.label,
                    onTap: _openReminderCell,
                    onChanged: _setReminderEnabled,
                  ),
                  const SizedBox(height: 12),
                  DetailActionCell(
                    title: 'Done',
                    subtitle: 'Mark as Done',
                    icon: Icons.check_circle_outline,
                    onTap: _markDone,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD44747),
                      ),
                      onPressed: _deleteIssue,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Issue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotesDialog extends StatefulWidget {
  const NotesDialog({required this.initialNotes, super.key});

  final String initialNotes;

  @override
  State<NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<NotesDialog> {
  late final TextEditingController _notesController = TextEditingController(
    text: widget.initialNotes,
  );

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Notes'),
      content: TextField(
        controller: _notesController,
        autofocus: true,
        maxLines: 5,
        minLines: 3,
        decoration: const InputDecoration(
          hintText: 'Add extra details',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_notesController.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class DetailActionCell extends StatelessWidget {
  const DetailActionCell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CellSurface(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(icon, color: const Color(0xFF1F7A6B)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF263331),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF68706D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Color(0xFF68706D)),
        ],
      ),
    );
  }
}

class ReminderActionCell extends StatelessWidget {
  const ReminderActionCell({
    required this.enabled,
    required this.optionLabel,
    required this.onTap,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final String optionLabel;
  final VoidCallback onTap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _CellSurface(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          const Icon(Icons.notifications_outlined, color: Color(0xFF1F7A6B)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Reminder',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF263331),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  enabled ? optionLabel : 'Off',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF68706D),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selectedOption,
    required this.labelBuilder,
  });

  final String title;
  final List<T> options;
  final T selectedOption;
  final String Function(T option) labelBuilder;

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final T option in options)
                ListTile(
                  title: Text(labelBuilder(option)),
                  trailing: option == selectedOption
                      ? const Icon(Icons.check, color: Color(0xFF1F7A6B))
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

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({
    required this.issues,
    required this.maintenanceTasks,
    required this.manualItems,
    required this.onIssuesChanged,
    required this.onMaintenanceChanged,
    required this.onManualChanged,
    this.onItemAdded,
    this.onGotIt,
    super.key,
  });

  final List<HomeIssue> issues;
  final List<MaintenanceTask> maintenanceTasks;
  final List<ManualShoppingItem> manualItems;

  /// Persist the issues (lookup items are "removed" by clearing their checked
  /// flag).
  final VoidCallback onIssuesChanged;

  /// Persist the maintenance tasks (same clearing-checked mechanism).
  final VoidCallback onMaintenanceChanged;

  /// Persist the manually-added items.
  final VoidCallback onManualChanged;

  /// Activity-feed hooks: a manual item was added / "Got it" was confirmed.
  final void Function(String name)? onItemAdded;
  final void Function(List<String> names)? onGotIt;

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  static const Color _dark = Color(0xFF21312E);
  static const Color _body = Color(0xFF263331);
  static const Color _muted = Color(0xFF68706D);
  static const Color _border = Color(0xFFE5E0D6);
  static const Color _green = Color(0xFF2E7D46);

  // "Got it" selection is intentionally in-memory only: it is never persisted,
  // so it does not survive an app restart. Only the deletion on confirm is
  // persisted.
  final Set<Object> _gotIt = <Object>{};

  void _toggle(Object item, bool selected) {
    setState(() {
      if (selected) {
        _gotIt.add(item);
      } else {
        _gotIt.remove(item);
      }
    });
  }

  void _confirmGotIt() {
    // Same ShoppingItem class backs issue and maintenance lookups, so tell
    // them apart by membership to persist the right store.
    final Set<ShoppingItem> maintenanceItems = <ShoppingItem>{
      for (final MaintenanceTask task in widget.maintenanceTasks)
        ...?task.lookup?.shoppingList,
    };

    bool issuesChanged = false;
    bool maintenanceChanged = false;
    bool manualChanged = false;
    final List<String> confirmedNames = <String>[];
    for (final Object obj in _gotIt) {
      if (obj is ShoppingItem) {
        obj.checked = false;
        confirmedNames.add(obj.item);
        if (maintenanceItems.contains(obj)) {
          maintenanceChanged = true;
        } else {
          issuesChanged = true;
        }
      } else if (obj is ManualShoppingItem) {
        widget.manualItems.remove(obj);
        confirmedNames.add(obj.name);
        manualChanged = true;
      }
    }
    setState(_gotIt.clear);
    if (issuesChanged) {
      widget.onIssuesChanged();
    }
    if (maintenanceChanged) {
      widget.onMaintenanceChanged();
    }
    if (manualChanged) {
      widget.onManualChanged();
    }
    if (confirmedNames.isNotEmpty) {
      widget.onGotIt?.call(confirmedNames);
    }
  }

  Future<void> _addManualItem() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _AddShoppingItemDialog(),
    );
    if (name == null) {
      return;
    }
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    setState(() {
      widget.manualItems.add(
        ManualShoppingItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: trimmed,
        ),
      );
    });
    widget.onManualChanged();
    widget.onItemAdded?.call(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final List<HomeIssue> groups = widget.issues.where((HomeIssue issue) {
      final LookupResult? lookup = issue.lookup;
      return lookup != null &&
          lookup.shoppingList.any((ShoppingItem item) => item.checked);
    }).toList();
    final List<MaintenanceTask> taskGroups = widget.maintenanceTasks.where((
      MaintenanceTask task,
    ) {
      final MaintenanceLookupResult? lookup = task.lookup;
      return lookup != null &&
          lookup.shoppingList.any((ShoppingItem item) => item.checked);
    }).toList();
    final bool hasItems =
        groups.isNotEmpty ||
        taskGroups.isNotEmpty ||
        widget.manualItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add item',
            onPressed: _addManualItem,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: hasItems
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: <Widget>[
                            for (final HomeIssue issue in groups)
                              _buildIssueGroup(issue),
                            for (final MaintenanceTask task in taskGroups)
                              _buildMaintenanceGroup(task),
                            if (widget.manualItems.isNotEmpty)
                              _buildManualGroup(),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        'Your shopping list is empty',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
            if (hasItems)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _green),
                      onPressed: _gotIt.isEmpty ? null : _confirmGotIt,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        _gotIt.isEmpty
                            ? 'Got it'
                            : 'Got it (${_gotIt.length})',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueGroup(HomeIssue issue) {
    final List<ShoppingItem> items = issue.lookup!.shoppingList
        .where((ShoppingItem item) => item.checked)
        .toList();
    return _group(
      title: issue.title,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, color: _border),
          _itemTile(
            object: items[i],
            label: items[i].item,
            reason: items[i].reason,
          ),
        ],
      ],
    );
  }

  Widget _buildMaintenanceGroup(MaintenanceTask task) {
    final List<ShoppingItem> items = task.lookup!.shoppingList
        .where((ShoppingItem item) => item.checked)
        .toList();
    return _group(
      title: task.applianceName.trim().isEmpty
          ? 'Recurrent maintenance'
          : task.applianceName,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, color: _border),
          _itemTile(
            object: items[i],
            label: items[i].item,
            reason: items[i].reason,
          ),
        ],
      ],
    );
  }

  Widget _buildManualGroup() {
    final List<ManualShoppingItem> items = widget.manualItems;
    return _group(
      title: 'Added items',
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1, color: _border),
          _itemTile(object: items[i], label: items[i].name, reason: ''),
        ],
      ],
    );
  }

  Widget _group({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _itemTile({
    required Object object,
    required String label,
    required String reason,
  }) {
    final bool checked = _gotIt.contains(object);
    return CheckboxListTile(
      value: checked,
      onChanged: (bool? value) => _toggle(object, value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: _green,
      title: Text(
        label,
        style: TextStyle(
          color: _body,
          fontWeight: FontWeight.w700,
          decoration: checked
              ? TextDecoration.lineThrough
              : TextDecoration.none,
          decorationColor: _muted,
        ),
      ),
      subtitle: reason.isEmpty
          ? null
          : Text(reason, style: const TextStyle(color: _muted)),
    );
  }
}

class _AddShoppingItemDialog extends StatefulWidget {
  const _AddShoppingItemDialog();

  @override
  State<_AddShoppingItemDialog> createState() => _AddShoppingItemDialogState();
}

class _AddShoppingItemDialogState extends State<_AddShoppingItemDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add item'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textInputAction: TextInputAction.done,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
        decoration: const InputDecoration(
          counterText: '',
          labelText: 'Item name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class DoneIssuesPage extends StatefulWidget {
  const DoneIssuesPage({
    required this.issues,
    required this.onClearAll,
    super.key,
  });

  final List<HomeIssue> issues;

  /// Removes all completed issues from the home list and persists.
  final VoidCallback onClearAll;

  @override
  State<DoneIssuesPage> createState() => _DoneIssuesPageState();
}

class _DoneIssuesPageState extends State<DoneIssuesPage> {
  late List<HomeIssue> _issues = widget.issues;

  Future<void> _confirmClear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Clear Done list?'),
          content: Text(
            'This permanently removes ${_issues.length} completed '
            'task${_issues.length == 1 ? '' : 's'}.',
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
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    widget.onClearAll();
    setState(() {
      _issues = <HomeIssue>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Done'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: <Widget>[
          if (_issues.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear Done list',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _issues.isEmpty
                  ? Center(
                      child: Text(
                        'No completed tasks yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF68706D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _issues.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final HomeIssue issue = _issues[index];
                        return _DoneIssueCell(issue: issue);
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneIssueCell extends StatelessWidget {
  const _DoneIssueCell({required this.issue});

  final HomeIssue issue;

  @override
  Widget build(BuildContext context) {
    final DateTime? completedAt = issue.completedAt;

    return _CellSurface(
      backgroundColor: const Color(0xFFE3F4E8),
      borderColor: const Color(0xFF7EC28D),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: Color(0xFF2E7D46)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF1E5530),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (completedAt != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    'Completed ${formatDate(completedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF2E7D46),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatDate(DateTime date) {
  final String day = date.day.toString().padLeft(2, '0');
  final String month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
