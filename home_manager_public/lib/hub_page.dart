import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_session.dart';
import 'auth_service.dart';
import 'home_repository.dart';
import 'home_sharing_service.dart';
import 'main.dart' show formatDate;

const Color _teal = Color(0xFF1F7A6B);
const Color _dark = Color(0xFF21312E);
const Color _body = Color(0xFF263331);
const Color _muted = Color(0xFF68706D);
const Color _border = Color(0xFFE5E0D6);
const Color _red = Color(0xFFD44747);

/// Household management hub: Account, Home & members, Activity.
class ManagementHubPage extends StatefulWidget {
  const ManagementHubPage({required this.repo, super.key});

  final HomeRepository repo;

  @override
  State<ManagementHubPage> createState() => _ManagementHubPageState();
}

class _ManagementHubPageState extends State<ManagementHubPage> {
  late Future<HomeInfo?> _homeFuture = widget.repo.loadHome();
  final TextEditingController _joinCodeController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
  }

  void _reloadHome() {
    setState(() {
      _homeFuture = widget.repo.loadHome();
    });
  }

  Future<void> _signOut() async {
    // Pop everything above the auth gate first so no stale routes remain,
    // then sign out; the gate swaps to the login screen.
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    await AuthService.signOut();
  }

  Future<void> _editHomeName(HomeInfo home) async {
    final TextEditingController controller = TextEditingController(
      text: home.name,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Home name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'Home name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final String trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || trimmed == home.name || !mounted) {
      return;
    }
    await widget.repo.updateHomeName(trimmed);
    _reloadHome();
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  Future<void> _joinHome() async {
    final String code = _joinCodeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-character invite code.')),
      );
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Join this home?'),
          content: const Text(
            'You will switch to the shared home. Data in your current home '
            'stays behind and will not be carried over.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _joining = true);
    try {
      final String homeName = await HomeSharingService.joinHomeWithCode(code);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            homeName.isEmpty ? 'Joined home!' : 'Joined "$homeName"!',
          ),
        ),
      );
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      AppSession.reloadSession();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _leaveHome() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Leave this home?'),
          content: const Text(
            'You will be removed from this home and get a fresh personal '
            'home. The shared data stays with the other members.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await HomeSharingService.leaveHome();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      AppSession.reloadSession();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = AuthService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Household'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: <Widget>[
                const _SectionHeader('Account'),
                _AccountCard(user: user),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                    ),
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader('Home & members'),
                FutureBuilder<HomeInfo?>(
                  future: _homeFuture,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<HomeInfo?> snapshot,
                      ) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(color: _teal),
                            ),
                          );
                        }
                        final HomeInfo? home = snapshot.data;
                        if (home == null) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Could not load home details.',
                              style: TextStyle(color: _muted),
                            ),
                          );
                        }
                        return _buildHomeSection(home, user);
                      },
                ),
                const SizedBox(height: 24),
                const _SectionHeader('Activity'),
                _ActivityFeed(repo: widget.repo),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeSection(HomeInfo home, User? user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.house_outlined, color: _teal),
                title: Text(
                  home.name,
                  style: const TextStyle(
                    color: _body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Tap to rename',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                trailing: const Icon(Icons.edit_outlined, color: _muted),
                onTap: () => _editHomeName(home),
              ),
              const Divider(height: 1, color: _border),
              for (final HomeMember member in home.members)
                ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFE3F1EE),
                    foregroundImage: member.photoUrl.isEmpty
                        ? null
                        : NetworkImage(member.photoUrl),
                    child: Text(
                      member.displayName.isEmpty
                          ? '?'
                          : member.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(
                    member.displayName.isEmpty
                        ? 'Member'
                        : member.displayName,
                    style: const TextStyle(
                      color: _body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Text(
                    member.uid == home.ownerId ? 'Owner' : 'Member',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              const Divider(height: 1, color: _border),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: _teal),
                title: Text(
                  home.inviteCode,
                  style: const TextStyle(
                    color: _body,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 4,
                  ),
                ),
                subtitle: const Text(
                  'Invite code — share it to invite someone',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, color: _teal),
                  tooltip: 'Copy invite code',
                  onPressed: () => _copyInviteCode(home.inviteCode),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Join another home',
          style: TextStyle(color: _dark, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _joinCodeController,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'Invite code',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _joining ? null : _joinHome,
                icon: _joining
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.group_add_outlined),
                label: const Text('Join'),
              ),
            ),
          ],
        ),
        if (home.members.length > 1) ...<Widget>[
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                side: const BorderSide(color: _red),
              ),
              onPressed: _leaveHome,
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Leave home'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Live shared activity feed, newest first.
class _ActivityFeed extends StatelessWidget {
  const _ActivityFeed({required this.repo});

  final HomeRepository repo;

  static String _phrase(ActivityEntry entry) {
    switch (entry.action) {
      case 'created_issue':
        return 'created issue';
      case 'completed_issue':
        return 'completed';
      case 'added_shopping_item':
        return 'added to shopping list';
      case 'confirmed_got_it':
        return 'got';
      case 'created_recurrent_task':
        return 'created recurrent task';
      default:
        return entry.action.replaceAll('_', ' ');
    }
  }

  static String _time(DateTime? timestamp) {
    if (timestamp == null) {
      return 'Just now';
    }
    final String hour = timestamp.hour.toString().padLeft(2, '0');
    final String minute = timestamp.minute.toString().padLeft(2, '0');
    return '${formatDate(timestamp)} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityEntry>>(
      stream: repo.activityStream(),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<ActivityEntry>> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: _teal)),
              );
            }
            final List<ActivityEntry> entries =
                snapshot.data ?? <ActivityEntry>[];
            if (entries.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No activity yet.',
                  style: TextStyle(color: _muted),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < entries.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1, color: _border),
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.bolt_outlined,
                        color: _teal,
                        size: 20,
                      ),
                      title: Text.rich(
                        TextSpan(
                          style: const TextStyle(color: _body, fontSize: 13.5),
                          children: <TextSpan>[
                            TextSpan(
                              text: entries[i].actorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: ' ${_phrase(entries[i])} '),
                            TextSpan(
                              text: entries[i].targetName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      subtitle: Text(
                        _time(entries[i].timestamp),
                        style: const TextStyle(color: _muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _dark,
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final User? user;

  String get _initials {
    final String name = (user?.displayName ?? '').trim();
    if (name.isEmpty) {
      return '?';
    }
    final List<String> parts = name.split(RegExp(r'\s+'));
    final String first = parts.first[0];
    final String last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String? photoUrl = user?.photoURL;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE3F1EE),
            foregroundImage: (photoUrl == null || photoUrl.isEmpty)
                ? null
                : NetworkImage(photoUrl),
            child: Text(
              _initials,
              style: const TextStyle(
                color: _teal,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (user?.displayName ?? '').trim().isEmpty
                      ? 'Signed in'
                      : user!.displayName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _body,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
