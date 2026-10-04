import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_session.dart';
import 'home_issue.dart';
import 'maintenance_task.dart';
import 'manual_shopping_item.dart';

/// Everything the signed-in app needs: the per-home repository plus the data
/// loaded from it. Built once per sign-in by [loadSession].
class SessionData {
  SessionData({
    required this.repo,
    required this.issues,
    required this.maintenanceTasks,
    required this.manualItems,
  });

  final HomeRepository repo;
  final List<HomeIssue> issues;
  final List<MaintenanceTask> maintenanceTasks;
  final List<ManualShoppingItem> manualItems;
}

/// Ensures the user profile + home exist, then loads all home data.
Future<SessionData> loadSession(User user) async {
  final String homeId = await ensureUserAndHome(user);
  AppSession.homeId = homeId;
  final HomeRepository repo = HomeRepository(homeId: homeId);
  final List<Object> results = await Future.wait(<Future<Object>>[
    repo.loadIssues(),
    repo.loadMaintenanceTasks(),
    repo.loadManualItems(),
  ]);
  return SessionData(
    repo: repo,
    issues: results[0] as List<HomeIssue>,
    maintenanceTasks: results[1] as List<MaintenanceTask>,
    manualItems: results[2] as List<ManualShoppingItem>,
  );
}

/// Creates/refreshes `users/{uid}` and, on first sign-in, creates the user's
/// home (`ownerId` = user, sole member, 6-char invite code). Returns the
/// user's homeId. The invite code is stored now but only used in Phase 2.
Future<String> ensureUserAndHome(User user) async {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final DocumentReference<Map<String, dynamic>> userRef = db
      .collection('users')
      .doc(user.uid);

  final DocumentSnapshot<Map<String, dynamic>> snapshot = await userRef.get();
  String? homeId = snapshot.data()?['homeId'] as String?;

  if (homeId == null || homeId.isEmpty) {
    final DocumentReference<Map<String, dynamic>> homeRef = db
        .collection('homes')
        .doc();
    homeId = homeRef.id;
    final String displayName = (user.displayName ?? '').trim();
    await homeRef.set(<String, dynamic>{
      'name': displayName.isEmpty ? 'My Home' : "$displayName's Home",
      'ownerId': user.uid,
      'inviteCode': generateInviteCode(),
      'memberIds': <String>[user.uid],
      'members': <String, dynamic>{
        user.uid: <String, dynamic>{
          'displayName': displayName,
          'photoUrl': user.photoURL ?? '',
          'role': 'owner',
          'joinedAt': FieldValue.serverTimestamp(),
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Create/refresh the profile on every sign-in.
  await userRef.set(<String, dynamic>{
    'displayName': user.displayName ?? '',
    'email': user.email ?? '',
    'photoUrl': user.photoURL ?? '',
    'homeId': homeId,
  }, SetOptions(merge: true));

  return homeId;
}

/// 6 characters from an unambiguous alphabet (no I/O/0/1).
String generateInviteCode() {
  const String chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final Random random = Random.secure();
  return List<String>.generate(
    6,
    (_) => chars[random.nextInt(chars.length)],
  ).join();
}

/// Applies a server snapshot to a list the UI already holds, **in place**.
///
/// Two properties matter for this app:
/// * The [target] list object is mutated rather than replaced, because open
///   screens (the shopping list, the maintenance list) hold a reference to it.
/// * An item whose content is unchanged keeps its existing instance, so an open
///   detail page editing that object is not silently orphaned. Since Firestore
///   echoes our own writes back locally, our own edits land here unchanged and
///   preserve identity; only a genuine remote change swaps an instance out
///   (last write wins, which is fine for a two-person home).
///
/// Returns whether anything changed, so the caller can skip a rebuild.
bool mergeSnapshotInto<T>({
  required List<T> target,
  required List<T> incoming,
  required String Function(T item) idOf,
  required Map<String, dynamic> Function(T item) toJson,
}) {
  String signature(T item) => '${idOf(item)}:${jsonEncode(toJson(item))}';

  final String before = target.map(signature).join('|');
  final String after = incoming.map(signature).join('|');
  if (before == after) {
    return false;
  }

  final Map<String, T> existing = <String, T>{
    for (final T item in target) idOf(item): item,
  };
  final List<T> merged = <T>[
    for (final T item in incoming)
      if (existing[idOf(item)] case final T current
          when signature(current) == signature(item))
        current
      else
        item,
  ];

  target
    ..clear()
    ..addAll(merged);
  return true;
}

/// One member of a home, from the home doc's `members` map.
class HomeMember {
  HomeMember({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.role,
  });

  final String uid;
  final String displayName;
  final String photoUrl;
  final String role;
}

/// The home document, for the management hub.
class HomeInfo {
  HomeInfo({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    required this.members,
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final List<HomeMember> members;
}

/// One entry of the shared activity feed.
class ActivityEntry {
  ActivityEntry({
    required this.actorUid,
    required this.actorName,
    required this.action,
    required this.targetType,
    required this.targetName,
    this.timestamp,
  });

  final String actorUid;
  final String actorName;
  final String action;
  final String targetType;
  final String targetName;

  /// Null while the local write is still pending the server timestamp.
  final DateTime? timestamp;
}

/// Firestore persistence for one home. All data lives under
/// `homes/{homeId}/...` so Phase 2 can share the home between members;
/// access is enforced by the Firestore Security Rules (see firestore.rules).
///
/// Keeps the app's existing "in-memory list + persist()" pattern: the UI owns
/// the lists, each save writes the whole list as one batch (set changed docs +
/// delete removed ones). On top of that, `*Stream()` exposes live snapshots so
/// members see each other's changes without restarting.
class HomeRepository {
  HomeRepository({required this.homeId, FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String homeId;
  final FirebaseFirestore _db;

  /// Last known document JSON per id, per collection. Serves two purposes:
  /// the keys are the docs we know exist (so a save can delete the ones that
  /// disappeared from the list), and the values let a save skip documents whose
  /// content did not change — which keeps write volume and the resulting
  /// snapshot churn down.
  final Map<String, Map<String, String>> _docJson =
      <String, Map<String, String>>{
        'issues': <String, String>{},
        'recurrentMaintenance': <String, String>{},
        'shoppingList': <String, String>{},
      };

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection('homes').doc(homeId).collection(name);

  /// Records what we now believe the server holds, so later saves can diff
  /// against it.
  List<T> _track<T>(
    String collection,
    List<T> items,
    String Function(T item) idOf,
    Map<String, dynamic> Function(T item) toJson,
  ) {
    final Map<String, String> cache = _docJson[collection]!..clear();
    for (final T item in items) {
      cache[idOf(item)] = jsonEncode(toJson(item));
    }
    return items;
  }

  List<HomeIssue> _issuesFrom(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<HomeIssue> issues = snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              HomeIssue.fromJson(<String, dynamic>{'id': d.id, ...d.data()}),
        )
        .toList();
    // Stable order so snapshots don't reshuffle the UI; the home screen
    // applies its own priority/date sorting on top.
    issues.sort((HomeIssue a, HomeIssue b) => a.id.compareTo(b.id));
    return _track<HomeIssue>(
      'issues',
      issues,
      (HomeIssue i) => i.id,
      (HomeIssue i) => i.toJson(),
    );
  }

  Future<List<HomeIssue>> loadIssues() async {
    return _issuesFrom(await _col('issues').get());
  }

  Stream<List<HomeIssue>> issuesStream() {
    return _col('issues').snapshots().map(_issuesFrom);
  }

  Future<void> saveIssues(List<HomeIssue> issues) {
    return _saveAll<HomeIssue>(
      collection: 'issues',
      items: issues,
      idOf: (HomeIssue issue) => issue.id,
      toJson: (HomeIssue issue) => issue.toJson(),
    );
  }

  List<MaintenanceTask> _tasksFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<MaintenanceTask> tasks = snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              MaintenanceTask.fromJson(<String, dynamic>{
                'id': d.id,
                ...d.data(),
              }),
        )
        .toList();
    // Creation order keeps the custom rows on the Recurrent Maintenance list
    // from jumping around.
    tasks.sort((MaintenanceTask a, MaintenanceTask b) {
      final int byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return _track<MaintenanceTask>(
      'recurrentMaintenance',
      tasks,
      (MaintenanceTask t) => t.id,
      (MaintenanceTask t) => t.toJson(),
    );
  }

  Future<List<MaintenanceTask>> loadMaintenanceTasks() async {
    return _tasksFrom(await _col('recurrentMaintenance').get());
  }

  Stream<List<MaintenanceTask>> maintenanceTasksStream() {
    return _col('recurrentMaintenance').snapshots().map(_tasksFrom);
  }

  Future<void> saveMaintenanceTasks(List<MaintenanceTask> tasks) {
    return _saveAll<MaintenanceTask>(
      collection: 'recurrentMaintenance',
      items: tasks,
      idOf: (MaintenanceTask task) => task.id,
      toJson: (MaintenanceTask task) => task.toJson(),
    );
  }

  List<ManualShoppingItem> _manualFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final List<ManualShoppingItem> items = snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              ManualShoppingItem.fromJson(<String, dynamic>{
                'id': d.id,
                ...d.data(),
              }),
        )
        .where((ManualShoppingItem item) => item.name.isNotEmpty)
        .toList();
    // Ids are creation timestamps, so this is oldest-first.
    items.sort(
      (ManualShoppingItem a, ManualShoppingItem b) => a.id.compareTo(b.id),
    );
    return _track<ManualShoppingItem>(
      'shoppingList',
      items,
      (ManualShoppingItem i) => i.id,
      (ManualShoppingItem i) => i.toJson(),
    );
  }

  Future<List<ManualShoppingItem>> loadManualItems() async {
    return _manualFrom(await _col('shoppingList').get());
  }

  Stream<List<ManualShoppingItem>> manualItemsStream() {
    return _col('shoppingList').snapshots().map(_manualFrom);
  }

  Future<void> saveManualItems(List<ManualShoppingItem> items) {
    return _saveAll<ManualShoppingItem>(
      collection: 'shoppingList',
      items: items,
      idOf: (ManualShoppingItem item) => item.id,
      toJson: (ManualShoppingItem item) => item.toJson(),
    );
  }

  /// Writes the documents whose content changed and deletes the ones whose
  /// items left the list, in a single batch. Documents added by another member
  /// are untouched because they are not in [items] and not yet known here —
  /// only ids this repository has seen are eligible for deletion.
  Future<void> _saveAll<T>({
    required String collection,
    required List<T> items,
    required String Function(T item) idOf,
    required Map<String, dynamic> Function(T item) toJson,
  }) async {
    final Map<String, String> cache = _docJson[collection]!;
    final WriteBatch batch = _db.batch();
    final Set<String> currentIds = <String>{};
    int writes = 0;

    for (final T item in items) {
      final String id = idOf(item);
      currentIds.add(id);
      final Map<String, dynamic> data = toJson(item);
      final String encoded = jsonEncode(data);
      if (cache[id] == encoded) {
        continue;
      }
      batch.set(_col(collection).doc(id), data);
      cache[id] = encoded;
      writes++;
    }

    for (final String removed
        in cache.keys.toSet().difference(currentIds)) {
      batch.delete(_col(collection).doc(removed));
      cache.remove(removed);
      writes++;
    }

    if (writes == 0) {
      return;
    }
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> get _homeDoc =>
      _db.collection('homes').doc(homeId);

  Future<HomeInfo?> loadHome() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _homeDoc
        .get();
    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      return null;
    }
    final Map<String, dynamic> membersMap =
        (data['members'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final List<HomeMember> members = <HomeMember>[];
    membersMap.forEach((String uid, dynamic value) {
      final Map<String, dynamic> member = value is Map<String, dynamic>
          ? value
          : <String, dynamic>{};
      members.add(
        HomeMember(
          uid: uid,
          displayName: (member['displayName'] as String?)?.trim() ?? '',
          photoUrl: member['photoUrl'] as String? ?? '',
          role: member['role'] as String? ?? 'member',
        ),
      );
    });
    // Owner first, then by name.
    final String ownerId = data['ownerId'] as String? ?? '';
    members.sort((HomeMember a, HomeMember b) {
      if ((a.uid == ownerId) != (b.uid == ownerId)) {
        return a.uid == ownerId ? -1 : 1;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return HomeInfo(
      id: homeId,
      name: (data['name'] as String?)?.trim() ?? 'My Home',
      ownerId: ownerId,
      inviteCode: data['inviteCode'] as String? ?? '',
      members: members,
    );
  }

  /// Rules allow members to update the home as long as memberIds/ownerId are
  /// unchanged — a name-only update qualifies.
  Future<void> updateHomeName(String name) {
    return _homeDoc.update(<String, dynamic>{'name': name.trim()});
  }

  /// Appends one entry to the shared activity feed. Fire-and-forget from the
  /// existing action handlers.
  Future<void> addActivity({
    required String actorUid,
    required String actorName,
    required String action,
    required String targetType,
    required String targetName,
  }) {
    return _col('activity').add(<String, dynamic>{
      'actorUid': actorUid,
      'actorName': actorName,
      'action': action,
      'targetType': targetType,
      'targetName': targetName,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Live activity feed, newest first.
  Stream<List<ActivityEntry>> activityStream({int limit = 50}) {
    return _col('activity')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
          return snapshot.docs.map((
            QueryDocumentSnapshot<Map<String, dynamic>> doc,
          ) {
            final Map<String, dynamic> data = doc.data();
            final Object? rawTimestamp = data['timestamp'];
            return ActivityEntry(
              actorUid: data['actorUid'] as String? ?? '',
              actorName: (data['actorName'] as String?)?.trim() ?? '',
              action: data['action'] as String? ?? '',
              targetType: data['targetType'] as String? ?? '',
              targetName: data['targetName'] as String? ?? '',
              timestamp: rawTimestamp is Timestamp ? rawTimestamp.toDate() : null,
            );
          }).toList();
        });
  }
}
