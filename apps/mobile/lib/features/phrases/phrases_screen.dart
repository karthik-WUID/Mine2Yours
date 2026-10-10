import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../communication/home_screen.dart';

class PhrasesScreen extends ConsumerStatefulWidget {
  const PhrasesScreen({super.key});
  @override
  ConsumerState<PhrasesScreen> createState() => _PhrasesScreenState();
}

class _PhrasesScreenState extends ConsumerState<PhrasesScreen> {
  List<Json> _phrases = [], _custom = [];
  String _category = 'All', _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phrases = jsonList(
      jsonDecode(await rootBundle.loadString('assets/phrases.json')),
    );
    final custom = jsonList(
      await ref.read(appProvider.notifier).db.read('customPhrases'),
    );
    if (mounted) {
      setState(() {
        _phrases = phrases;
        _custom = custom;
      });
    }
  }

  Future<void> _add() async {
    final text = await askText(
      context,
      title: 'Add your own phrase',
      hint: 'Write it in your spoken language',
      action: 'Save phrase',
    );
    if (text == null) return;
    final state = ref.read(appProvider);
    final phrase = {
      'id': const Uuid().v4(),
      'category': 'Custom',
      'text': text,
      'language': state.language,
      'icon': 'chat',
    };
    setState(() => _custom = [..._custom, phrase]);
    await ref.read(appProvider.notifier).db.write('customPhrases', _custom);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.read(appProvider.notifier);
    final phrases = [..._phrases, ..._custom]
        .where(
          (p) =>
              (_category == 'All' || p['category'] == _category) &&
              p['text'].toString().toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A few words go a long way.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Useful phrases, ready when you need them.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Add custom phrase',
              onPressed: _add,
              icon: const Icon(Icons.add_circle_outline_rounded, color: blue),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search phrases',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (q) => setState(() => _query = q),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['All', 'Everyday', 'Safety', 'Work', 'Machinery', 'Custom']
              .map(
                (category) => ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          'These are source phrases. Sending translates them through your configured provider.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 20),
        if (phrases.isEmpty)
          const Surface(
            child: EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No matching phrases',
              description: 'Try another search, or add a phrase of your own.',
            ),
          ),
        ...phrases.map(
          (phrase) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Surface(
              padding: const EdgeInsets.all(6),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: phrase['category'] == 'Safety'
                        ? const Color(0xfffff5dd)
                        : const Color(0xffedf5ff),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    switch (phrase['icon']) {
                      'safety' => Icons.health_and_safety_outlined,
                      'machine' => Icons.precision_manufacturing_outlined,
                      'work' => Icons.engineering_outlined,
                      _ => Icons.chat_bubble_outline_rounded,
                    },
                    color: phrase['category'] == 'Safety'
                        ? const Color(0xffbd8b14)
                        : blue,
                  ),
                ),
                title: Text(
                  phrase['text'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${phrase['category']} · ${AppLanguage.of(phrase['language']).name}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Phrase actions',
                  onSelected: (action) async {
                    if (action == 'send') {
                      await reviewAndSend(context, ref, {
                        'text': phrase['text'],
                        'sourceLanguage': phrase['language'],
                        'idempotencyKey': const Uuid().v4(),
                        'requiresReview': phrase['requiresReview'] ?? false,
                      });
                    }
                    if (action == 'play') {
                      try {
                        await app.playLocalText(
                          'phrase-${phrase['id']}',
                          phrase['text'],
                          phrase['language'],
                        );
                      } catch (e) {
                        if (context.mounted) {
                          notice(context, ApiClient.describe(e));
                        }
                      }
                    }
                    if (action == 'delete') {
                      setState(
                        () =>
                            _custom.removeWhere((p) => p['id'] == phrase['id']),
                      );
                      await app.db.write('customPhrases', _custom);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'send',
                      child: Text('Review & send'),
                    ),
                    const PopupMenuItem(
                      value: 'play',
                      child: Text('Listen to original'),
                    ),
                    if (phrase['category'] == 'Custom')
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete phrase'),
                      ),
                  ],
                ),
                onTap: () => reviewAndSend(context, ref, {
                  'text': phrase['text'],
                  'sourceLanguage': phrase['language'],
                  'durationSeconds': 0,
                  'idempotencyKey': const Uuid().v4(),
                  'requiresReview': phrase['requiresReview'] ?? false,
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
