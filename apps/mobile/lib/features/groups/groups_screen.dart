import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/languages.dart';

Future<void> createGroupDialog(BuildContext context, AppController app) async {
  final name = await askText(
    context,
    title: 'Create a private group',
    hint: 'e.g. Green Valley Team',
    action: 'Create group',
  );
  if (name != null && context.mounted) {
    await runAction(
      context,
      () => app.createGroup(name, ''),
      success: 'Your private group is ready. Invite your team to join.',
    );
  }
}

Future<void> joinGroupDialog(BuildContext context, AppController app) async {
  final token = await askText(
    context,
    title: 'Join your team',
    hint: 'Paste an invitation token or link',
    action: 'Join group',
  );
  if (token != null && context.mounted) {
    final parsed = Uri.tryParse(token);
    final value = parsed?.queryParameters['token'] ?? token;
    await runAction(
      context,
      () => app.joinGroup(value),
      success: 'Invitation accepted.',
    );
  }
}

Future<void> inviteDialog(
  BuildContext context,
  AppController app,
  String groupId,
) async {
  try {
    final invite = await app.invite(groupId);
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite your team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this private invitation. It expires in 24 hours.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              invite['token'].toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Only share it with people you want in this group.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () => copyText(ctx, invite['token'].toString()),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy invitation'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) notice(context, ApiClient.describe(e));
  }
}

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    return RefreshIndicator(
      onRefresh: app.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your people. Your groups.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'A shared space for every language.',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh groups',
                onPressed: app.sync,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => createGroupDialog(context, app),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create group'),
              ),
              OutlinedButton.icon(
                onPressed: () => joinGroupDialog(context, app),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Join with invitation'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (state.groups.isEmpty)
            const Surface(
              child: EmptyState(
                icon: Icons.groups_outlined,
                title: 'Bring your team together',
                description: 'Create a private group, then invite people. Everyone can speak and listen in their own language.',
              ),
            ),
          ...state.groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                padding: const EdgeInsets.all(6),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: InitialAvatar(
                    group['name'],
                    radius: 27,
                    color: teal,
                  ),
                  title: Text(
                    group['name'],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${jsonList(group['members']).length} members · Private group',
                      style: const TextStyle(color: muted),
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: muted,
                  ),
                  onTap: () {
                    app.selectGroup(group['id']);
                    context.go('/group/${group['id']}');
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: teal, size: 17),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only group members can access its conversations.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GroupDetailScreen extends ConsumerWidget {
  final String id;
  const GroupDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    final group = state.groups.where((g) => g['id'] == id).firstOrNull;
    if (group == null) {
      return Center(
        child: TextButton(
          onPressed: () => context.go('/team'),
          child: const Text('Group unavailable. Return to your groups.'),
        ),
      );
    }
    final members = jsonList(group['members']);
    final own = members
        .where((m) => m['userId'] == state.user?['id'])
        .firstOrNull;
    final admin = ['ADMIN', 'OWNER', 'admin', 'owner'].contains(own?['role']);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go('/team'),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('All groups'),
          ),
        ),
        const SizedBox(height: 10),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialAvatar(group['name'], radius: 30, color: teal),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group['name'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${members.length} members · Private',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  if (admin)
                    IconButton(
                      tooltip: 'Rename group',
                      onPressed: () async {
                        final name = await askText(
                          context,
                          title: 'Group name',
                          initial: group['name'],
                        );
                        if (name != null && context.mounted) {
                          await runAction(
                            context,
                            () => app.renameGroup(
                              id,
                              name,
                              group['description'] ?? '',
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              if ((group['description'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(group['description']),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.policy.mutedGroups.contains(id),
                onChanged: (muted) =>
                    runAction(context, () => app.muteGroup(id, muted)),
                title: const Text(
                  'Pause automatic playback',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Messages stay in History. You can replay them when you choose.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      app.selectGroup(id);
                      context.go('/speak');
                    },
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Talk to group'),
                  ),
                  if (admin)
                    OutlinedButton.icon(
                      onPressed: () => inviteDialog(context, app, id),
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: const Text('Invite members'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Text(
          'Everyone has a voice',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...members.map(
          (member) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Surface(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: InitialAvatar(
                  memberDisplayName(member['displayName']),
                  color: member['userId'] == state.user?['id'] ? blue : teal,
                ),
                title: Text(
                  '${memberDisplayName(member['displayName'])}${member['userId'] == state.user?['id'] ? ' (you)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${AppLanguage.of(member['listeningLanguage']).name} · ${(member['role'] ?? 'member').toString().toLowerCase()}',
                ),
                trailing: member['userId'] != state.user?['id']
                    ? PopupMenuButton<String>(
                        tooltip: 'Member actions',
                        onSelected: (action) async {
                          if (action == 'talk') {
                            app.selectGroup(id);
                            app.selectRecipient(member['userId']);
                            context.go('/speak');
                          }
                          if (action == 'remove' &&
                              await confirmAction(
                                context,
                                'Remove ${memberDisplayName(member['displayName'])}?',
                                'They will lose access to this group and its messages.',
                                action: 'Remove',
                              ) &&
                              context.mounted) {
                            await runAction(
                              context,
                              () => app.removeMember(id, member['userId']),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'talk',
                            child: Text('Talk privately'),
                          ),
                          if (admin)
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove member'),
                            ),
                        ],
                      )
                    : const Tag('You', color: blue),
              ),
            ),
          ),
        ),
        const SizedBox(height: 25),
        if (!admin)
          OutlinedButton(
            onPressed: () async {
              if (await confirmAction(
                    context,
                    'Leave this group?',
                    'You will need a new invitation to rejoin.',
                    action: 'Leave',
                  ) &&
                  context.mounted) {
                await runAction(context, () => app.leaveGroup(id));
                if (context.mounted) context.go('/team');
              }
            },
            child: const Text('Leave group'),
          ),
        if (admin)
          TextButton(
            onPressed: () async {
              if (await confirmAction(
                    context,
                    'Delete this group?',
                    'This removes access for all members and deletes the group conversations.',
                    action: 'Delete group',
                  ) &&
                  context.mounted) {
                await runAction(context, () => app.deleteGroup(id));
                if (context.mounted) context.go('/team');
              }
            },
            child: const Text(
              'Delete group',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }
}
