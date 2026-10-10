import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_controller.dart';
import '../../core/audio.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../voice/voice_test_screen.dart';

class LanguageDownloadStatus extends StatelessWidget {
  final AudioService audio;
  final String language;
  const LanguageDownloadStatus({
    super.key,
    required this.audio,
    required this.language,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: audio.languageStatus,
    builder: (context, values, _) {
      final data = values[language];
      if (data == null) return const SizedBox.shrink();
      final phase = data['phase'];
      final label = switch (phase) {
        'permission' => 'Allow speech-service permission to download',
        'queued' => 'Waiting to download…',
        'checking' => 'Checking speech language…',
        'downloading' => 'Downloading speech model…',
        'installed' => 'Speech model installed',
        'scheduled' => 'Download requested · waiting for confirmation',
        'manual' => 'Install in your speech service',
        _ => 'Download could not finish',
      };
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phase != null)
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: phase == 'installed' ? teal : muted,
                ),
              ),
            if (phase == 'downloading' || phase == 'checking') ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: data['progress'] is num
                    ? (data['progress'] as num) / 100
                    : null,
              ),
            ],
            if (data['translationPhase'] != null)
              Text(switch (data['translationPhase']) {
                'ready' => 'Free device translation ready',
                'downloading' =>
                  'Downloading free translation model over Wi-Fi…',
                'unsupported' => 'This language needs Pro cloud translation',
                _ =>
                  data['translationMessage']?.toString() ??
                      'Translation download could not finish. Retry on Wi-Fi.',
              }, style: const TextStyle(fontSize: 12, color: muted)),
            if (data['message'] != null)
              Text(
                data['message'],
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            if (data['voiceMessage'] != null)
              Text(
                data['voiceMessage'],
                style: const TextStyle(fontSize: 12, color: muted),
              ),
          ],
        ),
      );
    },
  );
}

class LanguagesScreen extends ConsumerStatefulWidget {
  const LanguagesScreen({super.key});
  @override
  ConsumerState<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends ConsumerState<LanguagesScreen>
    with WidgetsBindingObserver {
  Json caps = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  Future<void> _check() async {
    final value = await ref.read(appProvider.notifier).audio.capabilities();
    if (mounted) setState(() => caps = value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool voice(String code) => (caps['voices'] as List? ?? []).any(
    (v) =>
        v['language']?.toString().replaceAll('_', '-').split('-').first == code,
  );
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider), app = ref.read(appProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Languages & downloads',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Surface(
          child: Column(
            children: [
              LanguageSelect(
                value: state.language,
                label: 'I speak',
                onChanged: (v) => runAction(
                  context,
                  () => app.updateProfile({'spokenLanguage': v}),
                ),
              ),
              const SizedBox(height: 16),
              LanguageSelect(
                value: state.listeningLanguage,
                label: 'I listen in',
                onChanged: (v) => runAction(
                  context,
                  () => app.updateProfile({'listeningLanguage': v}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'The first five languages are the default set. Other Indian languages request a speech download when selected. Voice packs depend on your phone’s speech engine; confirm any installer prompt.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 18),
        for (final language in AppLanguage.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Surface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${language.name} · ${language.nativeName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${AppLanguage.defaults.contains(language.code) ? 'Default language · ' : 'On demand · '}${voice(language.code) ? 'Reading voice ready' : 'Reading voice not detected'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Use ${language.name}',
                        onPressed: () => runAction(
                          context,
                          () => app.updateProfile({
                            'spokenLanguage': language.code,
                          }),
                        ),
                        icon: Icon(
                          state.language == language.code
                              ? Icons.check_circle
                              : Icons.download_outlined,
                          color: blue,
                        ),
                      ),
                    ],
                  ),
                  LanguageDownloadStatus(
                    audio: app.audio,
                    language: language.code,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => showVoiceTest(
                          context,
                          app,
                          language: language.code,
                        ),
                        child: const Text('Test'),
                      ),
                      if (!AppLanguage.defaults.contains(language.code))
                        TextButton(
                          onPressed: () => app.audio.prepareLanguage(
                            language.code,
                            retry: true,
                          ),
                          child: const Text('Check / retry'),
                        ),
                      if (!voice(language.code))
                        TextButton(
                          onPressed: () =>
                              runAction(context, app.audio.installVoiceData),
                          child: const Text('Install voice'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => runAction(
            context,
            () => app.audio.openVoiceSettings(speechInput: true),
          ),
          icon: const Icon(Icons.settings_voice),
          label: const Text('Speech settings'),
        ),
        TextButton(
          onPressed: _check,
          child: const Text('Refresh installed voices'),
        ),
      ],
    );
  }
}
