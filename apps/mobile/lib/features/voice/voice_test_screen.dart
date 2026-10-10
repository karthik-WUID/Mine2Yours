import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_controller.dart';
import '../../core/audio.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../settings/languages_screen.dart' show LanguageDownloadStatus;

Future<void> showVoiceTest(
  BuildContext context,
  AppController app, {
  String? language,
}) async {
  await app.pauseForCapture();
  if (!context.mounted) {
    app.resumeAfterCapture();
    return;
  }
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VoiceTestScreen(audio: app.audio, language: language ?? 'en'),
      ),
    );
  } finally {
    await app.audio.cancel();
    await app.audio.stopPlayback();
    app.resumeAfterCapture();
  }
}

/// A device-only check. No API client, group, send action, outbox or receipt.
class VoiceTestScreen extends StatefulWidget {
  final AudioService audio;
  final String language;
  const VoiceTestScreen({super.key, required this.audio, this.language = 'en'});
  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen>
    with WidgetsBindingObserver {
  late String _language;
  late final TextEditingController _words;
  bool _readBack = true, _recording = false, _busy = false, _playing = false;
  String? _error, _requestId;
  String _status = '';
  Map<String, dynamic> _capabilities = {};
  StreamSubscription<Map<String, dynamic>>? _events;
  int _generation = 0;
  String sample(String code) => switch (code) {
    'ta' => 'வணக்கம்.',
    'bn' => 'নমস্কার।',
    'hi' => 'नमस्ते।',
    'or' => 'ନମସ୍କାର।',
    'en' => 'Hello team.',
    'te' => 'నమస్కారం.',
    'kn' => 'ನಮಸ್ಕಾರ.',
    'ml' => 'നമസ്കാരം.',
    'mr' => 'नमस्कार.',
    'gu' => 'નમસ્તે.',
    'pa' => 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ।',
    'ur' => 'سلام۔',
    _ => '',
  };
  bool get _voiceAvailable => (_capabilities['voices'] as List? ?? []).any(
    (v) =>
        v is Map &&
        v['language']?.toString().replaceAll('_', '-').split('-').first ==
            _language,
  );

  @override
  void initState() {
    super.initState();
    _language = widget.language;
    _words = TextEditingController(text: sample(_language));
    WidgetsBinding.instance.addObserver(this);
    _events = widget.audio.playbackEvents.listen((event) {
      if (!mounted ||
          event['playbackRequestId'] != _requestId ||
          _requestId == null) {
        return;
      }
      setState(() {
        if (event['event'] == 'playbackCompleted') {
          _playing = false;
          _status = 'Voice test finished.';
          _requestId = null;
        } else if (event['event'] == 'playbackError') {
          _playing = false;
          _requestId = null;
          _error = 'Your phone could not play this voice. Check the installed voice and media volume.';
        }
      });
    });
    _check();
  }

  Future<void> _check() async {
    try {
      final value = await widget.audio.capabilities();
      if (mounted) setState(() => _capabilities = value);
    } catch (e) {
      if (mounted) setState(() => _error = AudioService.describeError(e));
    }
  }

  Future<void> _listen() async {
    if (_busy) return;
    if (_recording) {
      await _finish();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _status = '';
      _requestId = null;
    });
    try {
      await widget.audio.stopPlayback();
      await widget.audio.startDictation(
        _language,
        (text) {
          if (mounted && generation == _generation) _words.text = text;
        },
        () {
          if (mounted && generation == _generation && _recording && !_busy) {
            _finish();
          }
        },
        continuous: true,
      );
      if (!mounted || generation != _generation) {
        await widget.audio.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _busy = false;
        _playing = false;
      });
      if (!widget.audio.dictating) await _finish();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = AudioService.describeError(e);
          _recording = false;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_busy || !_recording) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _recording = false;
    });
    try {
      final result = await widget.audio.finishDictation();
      if (!mounted || generation != _generation) return;
      _words.text = result['text'] as String;
      setState(() {
        _busy = false;
        _status = 'These are the words your phone recognized.';
      });
      if (_readBack) await _play();
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = AudioService.describeError(e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _play() async {
    if (_busy || _recording || _words.text.trim().isEmpty) return;
    final generation = _generation;
    final request = const Uuid().v4();
    setState(() {
      _busy = true;
      _playing = true;
      _error = null;
      _status = 'Playing test voice…';
      _requestId = request;
    });
    try {
      await widget.audio.speak(
        'voice-test',
        _words.text.trim(),
        _language,
        playbackRequestId: request,
      );
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = AudioService.describeError(e);
          _playing = false;
          _requestId = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    ++_generation;
    _requestId = null;
    await widget.audio.cancel();
    await widget.audio.stopPlayback();
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
        _playing = false;
        _status = '';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stop();
    } else {
      _check();
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    widget.audio.cancel();
    widget.audio.stopPlayback();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Test voice')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Try speaking on this phone',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nothing is sent to your team. No group or app server is needed. Your phone’s speech service may use the internet.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
            LanguageSelect(
              value: _language,
              label: 'Test language',
              onChanged: (value) async {
                await _stop();
                if (!mounted) return;
                setState(() {
                  _language = value;
                  _words.text = sample(value);
                  _error = null;
                });
                await widget.audio.prepareLanguage(value);
                await _check();
              },
            ),
            LanguageDownloadStatus(audio: widget.audio, language: _language),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _voiceAvailable
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: _voiceAvailable ? teal : muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _voiceAvailable
                        ? '${AppLanguage.of(_language).name} reading voice is installed.'
                        : '${AppLanguage.of(_language).name} reading voice is not installed or is still loading.',
                  ),
                ),
              ],
            ),
            if (!_voiceAvailable &&
                _language != 'en' &&
                (_capabilities['voices'] as List? ?? []).any(
                  (v) =>
                      v is Map &&
                      v['language']?.toString().startsWith('en') == true,
                ))
              TextButton(
                onPressed: () async {
                  await _stop();
                  if (mounted) {
                    setState(() {
                      _language = 'en';
                      _words.text = sample('en');
                      _error = null;
                    });
                  }
                },
                child: const Text('Try an English test'),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _listen,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
              ),
              icon: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_rounded,
                size: 28,
              ),
              label: Text(
                _recording ? 'Stop and check my words' : 'Tap to test speaking',
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _readBack,
              onChanged: _busy || _recording
                  ? null
                  : (value) => setState(() => _readBack = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Read my words aloud'),
              subtitle: const Text(
                'Uses the selected language’s installed voice.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _words,
              maxLines: 3,
              maxLength: 500,
              readOnly: _busy || _recording,
              decoration: const InputDecoration(
                labelText: 'My test words',
                helperText: 'You can type words here to test playback.',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy || _recording ? null : _play,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Play test voice'),
            ),
            if (_recording || _playing)
              TextButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_status),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Surface(
                  color: const Color(0xfffff4e6),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xff794c0b)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Missing a language?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Speaking and reading use separate phone services. Install the language in the relevant settings, then return and test again.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => runAction(
                context,
                () => widget.audio.openVoiceSettings(speechInput: true),
              ),
              icon: const Icon(Icons.mic_none),
              label: const Text('Speech input settings'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  runAction(context, () => widget.audio.openVoiceSettings()),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Reading voice settings'),
            ),
            TextButton.icon(
              onPressed: _check,
              icon: const Icon(Icons.refresh),
              label: const Text('Check voices again'),
            ),
          ],
        ),
      ),
    ),
  );
}
