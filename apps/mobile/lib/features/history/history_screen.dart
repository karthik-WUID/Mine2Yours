import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/translated_message_text.dart';
import '../../core/design.dart';
import '../../core/languages.dart';

String messageStatus(String? value) => switch (value) {
  'READY' => 'Ready for delivery',
  'PROCESSING' => 'Processing',
  'REVIEW_REQUIRED' => 'Needs review',
  'FAILED' => 'Processing failed',
  'DELIVERED' => 'Delivered',
  'PLAYBACK_STARTED' => 'Playback started',
  'PLAYBACK_COMPLETED' => 'Playback completed',
  'CANCELLED' => 'Cancelled',
  'EXPIRED' => 'Expired',
  _ => value?.replaceAll('_', ' ').toLowerCase() ?? 'Created',
};
Color statusColor(String? value) => value == 'FAILED'
    ? const Color(0xffc14c47)
    : value == 'REVIEW_REQUIRED'
    ? const Color(0xffb77700)
    : ['READY', 'DELIVERED', 'PLAYBACK_COMPLETED'].contains(value)
    ? teal
    : muted;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '', _filter = 'All';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    final messages = state.messages.where((m) {
      final date = DateTime.tryParse(m['createdAt'] ?? '');
      return '${m['sourceText']} ${m['translations']}'.toLowerCase().contains(
            _query.toLowerCase(),
          ) &&
          (_filter != 'Today' ||
              (date != null &&
                  DateUtils.isSameDay(date.toLocal(), DateTime.now()))) &&
          (_filter != 'Needs review' || m['state'] == 'REVIEW_REQUIRED') &&
          (_filter != 'Failed' || m['state'] == 'FAILED');
    }).toList();
    return RefreshIndicator(
      onRefresh: app.sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
        children: [
          Text(
            'Conversation history',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your spoken words, translations and delivery.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Search your conversations',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['All', 'Today', 'Needs review', 'Failed']
                .map(
                  (v) => ChoiceChip(
                    label: Text(v),
                    selected: _filter == v,
                    onSelected: (_) => setState(() => _filter = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          if (state.outbox.isNotEmpty) ...[
            Surface(
              color: const Color(0xfffff8eb),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        color: Color(0xffb77700),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${state.outbox.length} messages in your outbox',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Retry outgoing messages',
                        onPressed: () => runAction(
                          context,
                          () => app.flushOutbox(manual: true),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  ...state.outbox.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (entry['payload'] as Map)['text'] ?? 'Voice message',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry['error'] ?? 'Waiting for connection',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      trailing: IconButton(
                        tooltip: 'Discard pending message',
                        onPressed: () => app.discardOutgoing(entry['id']),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (messages.isEmpty)
            const Surface(
              child: EmptyState(
                icon: Icons.history_rounded,
                title: 'A fresh start',
                description: 'Your messages will appear here. Pull down to refresh, or start a conversation from Home.',
              ),
            ),
          ...messages.map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(7),
                child: MessageTile(message: message),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageTile extends ConsumerWidget {
  final Json message;
  final bool compact;
  const MessageTile({super.key, required this.message, this.compact = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateTime.tryParse(message['createdAt'] ?? '');
    final state = ref.watch(appProvider);
    final own = message['senderId'] == state.user?['id'];
    return ListTile(
      contentPadding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (own ? blue : teal).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          own ? Icons.mic_none_rounded : Icons.hearing_rounded,
          color: own ? blue : teal,
          size: 22,
        ),
      ),
      title: Text(
        message['processing'] == 'voice'
            ? 'Voice message'
            : (message['sourceText'] ?? 'Voice message'),
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            '${own ? 'You' : state.memberName(message['senderId'], fallback: message['senderDisplayName'])} · ${date == null ? '' : DateFormat('d MMM · h:mm a').format(date.toLocal())}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 4),
          Text(
            messageStatus(message['state']),
            style: TextStyle(
              fontSize: 11,
              color: statusColor(message['state']),
            ),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: muted),
      onTap: () => showMessageDetails(context, ref, message),
    );
  }
}

Future<void> showMessageDetails(
  BuildContext context,
  WidgetRef ref,
  Json message,
) async {
  final app = ref.read(appProvider.notifier);
  final state = ref.read(appProvider);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your conversation',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              Tag(
                messageStatus(message['state']),
                color: statusColor(message['state']),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Surface(
            color: canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Original · ${AppLanguage.of(message['sourceLanguage']).name}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  message['processing'] == 'voice'
                      ? 'Original voice recording · ${message['durationSeconds']?.round() ?? 0}s'
                      : (message['sourceText'] ?? 'Transcript unavailable'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...jsonList(message['translations']).map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                color: const Color(0xffeef9f5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppLanguage.of(t['language']).name,
                            style: const TextStyle(
                              color: teal,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Play translation',
                          onPressed: () async {
                            try {
                              await app.playTranslation(
                                message['id'],
                                t['language'],
                              );
                            } catch (e) {
                              if (ctx.mounted) {
                                notice(ctx, ApiClient.describe(e));
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.play_circle_outline_rounded,
                            color: teal,
                          ),
                        ),
                      ],
                    ),
                    TranslatedMessageText(
                      app: app,
                      message: message,
                      translation: t,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Translation: ${t['provider'] ?? 'provider not reported'}',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (message['error'] != null) ...[
            const SizedBox(height: 10),
            Text(
              message['error'] is Map
                  ? message['error']['message']?.toString() ??
                        'Processing failed'
                  : message['error'].toString(),
              style: const TextStyle(color: Color(0xffbc514a)),
            ),
          ],
          const SizedBox(height: 20),
          Text('Delivery details', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...jsonList(message['recipients']).map((r) {
            final member = state.members
                .where((m) => m['userId'] == r['userId'])
                .firstOrNull;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: InitialAvatar(
                memberDisplayName(
                  member?['displayName'],
                  fallback: memberDisplayName(r['displayName']),
                ),
                radius: 18,
                color: teal,
              ),
              title: Text(
                memberDisplayName(
                  member?['displayName'],
                  fallback: memberDisplayName(r['displayName']),
                ),
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Text(
                messageStatus(r['state']),
                style: TextStyle(fontSize: 11, color: statusColor(r['state'])),
              ),
            );
          }),
          const SizedBox(height: 15),
          const Text(
            'Playback completion records device playback. It does not prove that a person heard or understood the message.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (message['senderId'] != state.user?['id']) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                app.selectGroup(message['groupId']);
                app.selectRecipient(message['senderId']);
                Navigator.pop(ctx);
                context.go('/speak?record=true');
              },
              icon: const Icon(Icons.mic_rounded),
              label: Text('Reply in ${AppLanguage.of(state.language).name}'),
            ),
          ],
          if (message['senderId'] == state.user?['id']) ...[
            const SizedBox(height: 20),
            if (message['state'] == 'REVIEW_REQUIRED')
              FilledButton.icon(
                onPressed: () => runAction(ctx, () async {
                  await app.confirmMessage(message['id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirm translation & deliver'),
              ),
            if (message['state'] == 'FAILED')
              FilledButton.icon(
                onPressed: () => runAction(ctx, () async {
                  await app.retryMessage(message['id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry processing'),
              ),
            if ([
              'REVIEW_REQUIRED',
              'FAILED',
              'PROCESSING',
              'CREATED',
            ].contains(message['state']))
              TextButton(
                onPressed: () => runAction(ctx, () async {
                  await app.cancelMessage(message['id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
                child: const Text('Cancel message'),
              ),
          ],
          TextButton.icon(
            onPressed: () => copyText(ctx, message['sourceText'] ?? ''),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy transcript'),
          ),
        ],
      ),
    ),
  );
}
