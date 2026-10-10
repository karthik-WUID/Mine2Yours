import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../../core/team_theme.dart';

class MemberAvatar extends StatelessWidget {
  final Json member;
  final double radius;
  const MemberAvatar({super.key, required this.member, this.radius = 25});
  @override
  Widget build(BuildContext context) {
    final photo = member['photoData']?.toString() ?? '';
    if (photo.startsWith('data:image/')) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(base64Decode(photo.split(',').last)),
        );
      } catch (_) {
        /* Fall back to initials for damaged cached photos. */
      }
    }
    return InitialAvatar(
      memberDisplayName(member['displayName']),
      radius: radius,
    );
  }
}

class TeamHomeScreen extends ConsumerWidget {
  final bool directory;
  const TeamHomeScreen({super.key, this.directory = false});
  void _speak(BuildContext context, AppController app, String? user) {
    app.selectRecipient(user);
    context.go('/speak');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider), app = ref.read(appProvider.notifier);
    final members = state.members
        .where((m) => m['userId'] != state.user?['id'])
        .toList();
    return RefreshIndicator(
      onRefresh: app.reconnect,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!directory)
                    const TeamHero()
                  else
                    Text(
                      'Your teams & members',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  const SizedBox(height: 10),
                  Surface(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.groups_rounded,
                              color: blue,
                              size: 30,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Choose your team',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Manage teams in Settings',
                              onPressed: () => context.go('/manage-teams'),
                              icon: const Icon(Icons.more_vert),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (state.groups.isEmpty)
                          FilledButton.tonalIcon(
                            onPressed: () => context.go('/manage-teams'),
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('Create or join a team'),
                          )
                        else ...[
                          DropdownButtonFormField<String>(
                            key: ValueKey(state.selectedGroupId),
                            initialValue: state.group?['id'],
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Team',
                            ),
                            items: state.groups
                                .map(
                                  (g) => DropdownMenuItem<String>(
                                    value: g['id'],
                                    child: Text(
                                      g['name'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              if (id != null) app.selectGroup(id);
                            },
                          ),
                          if (state.group != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              state.group?['description']
                                          ?.toString()
                                          .isNotEmpty ==
                                      true
                                  ? state.group!['description']
                                  : '${state.members.length} team members',
                              style: const TextStyle(color: muted),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Choose a member',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap a microphone to speak directly to one person.',
                              style: TextStyle(color: muted, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            if (members.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'Your team is ready. Add members using an invite token in Settings.',
                                ),
                              ),
                            for (final member in members)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: const Color(0xfff0f8ff),
                                  borderRadius: BorderRadius.circular(18),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 0,
                                    ),
                                    leading: MemberAvatar(member: member),
                                    title: Text(
                                      memberDisplayName(member['displayName']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${member['jobTitle']?.toString().isNotEmpty == true ? '${member['jobTitle']} · ' : ''}${AppLanguage.of(member['listeningLanguage']).name}',
                                    ),
                                    onTap: () =>
                                        _speak(context, app, member['userId']),
                                    onLongPress: () =>
                                        _details(context, member, app),
                                    trailing: IconButton.filled(
                                      tooltip:
                                          'Speak to ${memberDisplayName(member['displayName'])}',
                                      onPressed: () => _speak(
                                        context,
                                        app,
                                        member['userId'],
                                      ),
                                      icon: const Icon(
                                        Icons.mic_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff7e4),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.translate, color: blue),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'I speak',
                                          style: TextStyle(color: muted),
                                        ),
                                        Text(
                                          AppLanguage.of(state.language)
                                              .nativeName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => context.go('/languages'),
                                    child: const Text('Change'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            SpeakButton(
                              label: 'Speak to your team',
                              onPressed: members.isEmpty
                                  ? null
                                  : () => _speak(context, app, null),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _details(
    BuildContext context,
    Json member,
    AppController app,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: MemberAvatar(member: member, radius: 42)),
            const SizedBox(height: 12),
            Text(
              memberDisplayName(member['displayName']),
              style: Theme.of(ctx).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Speaks ${AppLanguage.of(member['spokenLanguage']).name} · Listens in ${AppLanguage.of(member['listeningLanguage']).name}',
            ),
            for (final field in [
              ('jobTitle', 'Work'),
              ('site', 'Site'),
              ('joinedDate', 'Joined'),
              ('workDetails', 'Work details'),
            ])
              if (member[field.$1]?.toString().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${field.$2}: ${member[field.$1]}'),
                ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _speak(context, app, member['userId']);
              },
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Speak to this member'),
            ),
          ],
        ),
      ),
    ),
  );
}
