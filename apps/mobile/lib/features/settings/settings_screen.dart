import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../voice/voice_test_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Your languages, your listening preferences, your privacy.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 24),
        Surface(
          child: Row(
            children: [
              InitialAvatar(
                memberDisplayName(state.user?['displayName']),
                radius: 30,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memberDisplayName(state.user?['displayName']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${AppLanguage.of(state.language).name} speaker',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit your name',
                onPressed: () async {
                  final name = await askText(
                    context,
                    title: 'Your display name',
                    initial: memberDisplayName(state.user?['displayName']),
                  );
                  if (name != null && context.mounted) {
                    await runAction(
                      context,
                      () => app.updateProfile({'displayName': name}),
                    );
                  }
                },
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Surface(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.groups_rounded, color: blue),
                title: const Text('Manage teams & invitations'),
                subtitle: const Text(
                  'Create, join, invite and manage team access',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/manage-teams'),
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: blue),
                title: const Text('Team member records'),
                subtitle: const Text(
                  'Photos, work, joining dates and salary · admins',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/personnel'),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined, color: blue),
                title: const Text('Languages & downloads'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/languages'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _section(
          context,
          'Languages',
          Icons.translate_rounded,
          Column(
            children: [
              LanguageSelect(
                key: ValueKey('speak-${state.language}'),
                value: state.language,
                label: 'You speak',
                onChanged: (v) => runAction(
                  context,
                  () => app.updateProfile({'spokenLanguage': v}),
                ),
              ),
              const SizedBox(height: 16),
              LanguageSelect(
                key: ValueKey('listen-${state.listeningLanguage}'),
                value: state.listeningLanguage,
                label: 'You listen in',
                onChanged: (v) => runAction(
                  context,
                  () => app.updateProfile({'listeningLanguage': v}),
                ),
              ),
              const SizedBox(height: 16),
              LanguageSelect(
                value: state.uiLanguage,
                label: 'Navigation language',
                onChanged: (v) => app.settings(uiLanguage: v),
              ),
              const SizedBox(height: 12),
              const Text(
                'Navigation labels are available in Tamil, Bengali, Hindi, Odia, and English. Other interface text uses English.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _section(
          context,
          'Voice & recording',
          Icons.mic_none_rounded,
          Column(
            children: [
              RadioGroup<String>(
                groupValue: state.inputMode,
                onChanged: (v) {
                  if (v != null) app.settings(inputMode: v);
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'device',
                      title: const Text(
                        'Device speech recognition',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Review recognized text. Device services may use a network.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'cloud',
                      enabled: state.cloudSpeechReady,
                      title: const Text(
                        'Diamond: cloud AI',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        state.cloudSpeechReady
                            ? 'Record up to 60 seconds with Diamond cloud speech.'
                            : 'Diamond plan and a configured provider are required. Phone speech works without this.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    showVoiceTest(context, app, language: state.language),
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Test voice on this phone'),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.mic_off_outlined, color: teal),
                title: Text(
                  'Microphone stays off until you record',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'Your phone keeps listening across short pauses while you record. Tap stop to review; maximum 60 seconds.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _section(
          context,
          'Receiving preferences',
          Icons.headset_mic_outlined,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: state.receiveMode,
                decoration: const InputDecoration(
                  labelText: 'When messages arrive',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'notification',
                    child: Text('Transcript only'),
                  ),
                  DropdownMenuItem(
                    value: 'automatic',
                    enabled: !kIsWeb,
                    child: Text('Automatic foreground playback'),
                  ),
                  DropdownMenuItem(
                    value: 'headphones',
                    enabled: false,
                    child: Text('Headphones only · limited support'),
                  ),
                  DropdownMenuItem(value: 'silent', child: Text('Silent')),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    await app.settings(receiveMode: v);
                    if (['silent', 'notification'].contains(v) &&
                        state.receiving) {
                      await app.setReceiving(false);
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.receiving,
                onChanged:
                    !kIsWeb &&
                        ['automatic', 'headphones'].contains(state.receiveMode)
                    ? (v) => runAction(context, () => app.setReceiving(v))
                    : null,
                title: const Text(
                  'Activate receiving session',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Explicit consent for playback. The microphone stays off.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.policy.quietHours,
                onChanged: (enabled) => runAction(
                  context,
                  () => app.settings(
                    policy: state.policy.copy(quietHours: enabled),
                  ),
                ),
                title: const Text(
                  'Quiet hours',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Pause automatic speech during these hours.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              if (state.policy.quietHours) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _quietTime(context, ref, true),
                        child: Text(
                          'From ${TimeOfDay(hour: state.policy.quietStart ~/ 60, minute: state.policy.quietStart % 60).format(context)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _quietTime(context, ref, false),
                        child: Text(
                          'Until ${TimeOfDay(hour: state.policy.quietEnd ~/ 60, minute: state.policy.quietEnd % 60).format(context)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  state.policy.quietStart == state.policy.quietEnd
                      ? 'Matching times pause automatic speech all day. Manual replay remains available.'
                      : 'Uses your device’s local time. Transcripts still arrive; manual replay remains available.',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
              if (state.policy.mutedGroups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${state.policy.mutedGroups.length} group(s) muted for automatic speech. Manage this in each group’s settings.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                kIsWeb
                    ? 'Automatic receiving requires the mobile app. Replay messages here using your browser voice. Browser playback receipts are unavailable.'
                    : 'The app receives live messages while open. Android can finish playback during its bounded session. Background network delivery and iOS locked-screen playback are unavailable in this build. Strict headphone playback is unavailable on Android; iOS requires a verified wired headphone route.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final capabilities = await app.audio.capabilities();
                    if (context.mounted) {
                      await _details(
                        context,
                        'This device’s audio capabilities',
                        capabilities,
                      );
                    }
                  } catch (e) {
                    if (context.mounted) notice(context, ApiClient.describe(e));
                  }
                },
                icon: const Icon(Icons.phone_android_outlined, size: 18),
                label: const Text('Check device capabilities'),
              ),
              TextButton.icon(
                onPressed: () => runAction(context, app.audio.stopPlayback),
                icon: const Icon(Icons.stop_circle_outlined, size: 17),
                label: const Text('Stop audio playback'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _section(
          context,
          'Privacy & data',
          Icons.shield_outlined,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.user?['providerConsent'] == true,
                onChanged: (v) => runAction(
                  context,
                  () => app.updateProfile({'providerConsent': v}),
                ),
                title: const Text(
                  'Allow configured AI providers to process messages',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Speech and transcripts may leave your device. Voice recordings are retained with your messages. Server processing is not end-to-end encryption.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: const Text(
                  'Export my data',
                  style: TextStyle(fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  try {
                    final data = await app.exportData();
                    if (context.mounted) {
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Your data export'),
                          content: SizedBox(
                            width: 500,
                            child: SingleChildScrollView(
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ')
                                    .convert(data),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                            FilledButton(
                              onPressed: () => copyText(ctx, jsonEncode(data)),
                              child: const Text('Copy export'),
                            ),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) notice(context, ApiClient.describe(e));
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Delete my account',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  if (await confirmAction(
                        context,
                        'Delete your account?',
                        'Eligible personal data and authored messages will be removed. Pseudonymized financial usage and audit records remain under retention policies. Backups follow the server deletion schedule. You will lose group access. This cannot be undone.',
                        action: 'Delete my account',
                      ) &&
                      context.mounted) {
                    await runAction(context, app.deleteAccount);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _section(
          context,
          'Silver / Gold / Diamond',
          Icons.donut_large_rounded,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Tag(
                'Silver is free · Gold / Diamond pricing pending',
                color: Color(0xffb77700),
                icon: Icons.info_outline_rounded,
              ),
              const SizedBox(height: 16),
              Text('Current plan: ${state.usage?['planName'] ?? 'Silver'}'),
              const SizedBox(height: 10),
              const Text(
                'Silver: free, 1 site, up to 5 members.\nGold: multiple sites and more than 5 members.\nDiamond: Gold features plus cloud AI.',
              ),
              const SizedBox(height: 16),
              if (state.usage != null)
                _dataRows(state.usage!)
              else
                const Text(
                  'Connect to see your usage.',
                  style: TextStyle(color: muted),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  await app.sync();
                  if (context.mounted) {
                    await _details(context, 'Available plans', {
                      'plans': ref.read(appProvider).plans,
                      'purchase': 'Not configured. No paid entitlements can be unlocked from this device.',
                    });
                  }
                },
                child: const Text('View plan allowances'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _section(
          context,
          'Support',
          Icons.settings_outlined,
          Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text(
                  'About Mine2YourLingo',
                  style: TextStyle(fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'Mine2YourLingo',
                  applicationVersion: '1.0.0 · pilot development',
                  applicationIcon: const Icon(
                    Icons.record_voice_over_rounded,
                    color: blue,
                  ),
                  children: [
                    const Text(
                      'My Voice. Your Language.\n\nPrivate multilingual communication. This build requires live provider configuration and device testing before production release. It is not a certified emergency communication system.',
                    ),
                  ],
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text(
                  'Help & permissions',
                  style: TextStyle(fontSize: 14),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('A little help'),
                    content: const SingleChildScrollView(
                      child: Text(
                        '1. Create or join a private group.\n2. Invite a person who speaks another language.\n3. Set your spoken and listening languages.\n4. Enable provider processing only after reviewing privacy information.\n5. Record, then stop to send directly. Enable Speaker on the receiver.\n6. Open History to review translations and delivery.\n\nMicrophone access is requested only when recording. If you denied it, enable it in your device’s app permissions. Install a voice for your language in the device text-to-speech settings.\n\nFree Android translation uses Google Translate models on your phone. Some languages require Diamond cloud translation. Translation notices: https://cloud.google.com/translate/attribution. Missing provider configuration requires your server administrator. Force-stopped apps cannot receive live messages in this build.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _quietTime(
    BuildContext context,
    WidgetRef ref,
    bool start,
  ) async {
    final policy = ref.read(appProvider).policy;
    final minute = start ? policy.quietStart : policy.quietEnd;
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (chosen == null || !context.mounted) return;
    final current = ref.read(appProvider).policy;
    await runAction(
      context,
      () => ref
          .read(appProvider.notifier)
          .settings(
            policy: current.copy(
              quietStart: start ? chosen.hour * 60 + chosen.minute : null,
              quietEnd: start ? null : chosen.hour * 60 + chosen.minute,
            ),
          ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    Widget child,
  ) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: blue, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
  Widget _dataRows(Json values) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: values.entries
        .where((e) => e.value is num)
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    e.key.replaceAllMapped(
                      RegExp(r'[A-Z]'),
                      (m) => ' ${m[0]!.toLowerCase()}',
                    ),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Text(
                  e.value.toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
  Future<void> _details(BuildContext context, String title, Json data) =>
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(data),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
}
