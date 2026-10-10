import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/audio.dart';

import 'walkie_layout.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool autoRecord;
  const HomeScreen({super.key, this.autoRecord = false});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _recording = false, _working = false, _held = false, _walkie = true;
  String _transcript = '';
  final String _mode = 'group';
  late AppController _app;
  int _captureToken = 0;
  bool _foreground = true;
  String _captureMode = 'device';
  String? _captureUser, _captureGroup, _captureRecipient;
  String _captureLanguage = 'ta';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = ref.read(appProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = ref.read(appProvider);
      if (!mounted ||
          state.user == null ||
          state.receiving ||
          state.receiveMode == 'silent') {
        return;
      }
      try {
        await _app.settings(receiveMode: 'automatic');
        if (mounted) await _app.setReceiving(true);
      } catch (e) {
        if (mounted) notice(context, AudioService.describeError(e));
      }
    });
    if (widget.autoRecord) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _begin();
      });
    }
  }

  @override
  void dispose() {
    ++_captureToken;
    WidgetsBinding.instance.removeObserver(this);
    _app.audio.cancel();
    _app.resumeAfterCapture();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _cancel();
  }

  Future<void> _begin({bool hold = false}) async {
    if (_working || _recording) return;
    final state = ref.read(appProvider);
    final app = ref.read(appProvider.notifier);
    if (state.group == null) {
      notice(context, 'Create or join a group to start a conversation.');
      return;
    }
    if (state.members.where((m) => m['userId'] != state.user?['id']).isEmpty) {
      notice(
        context,
        'Invite a team member before sending your first message.',
      );
      return;
    }
    setState(() {
      _working = true;
      _transcript = '';
    });
    final token = ++_captureToken;
    try {
      _captureMode = state.effectiveInputMode;
      _captureUser = state.user?['id'];
      _captureGroup = state.selectedGroupId;
      _captureRecipient = state.recipientId;
      _captureLanguage = state.language;
      await app.pauseForCapture();
      if (_captureMode == 'device') {
        await app.audio.startDictation(
          state.language,
          (text) {
            if (mounted && token == _captureToken) {
              setState(() => _transcript = text);
            }
          },
          () {
            if (mounted && token == _captureToken && _recording && !_working) {
              _finish();
            }
          },
          continuous: true,
        );
      } else {
        await app.audio.startRecording(() {
          if (mounted) _finish();
        });
      }
      if (!mounted ||
          token != _captureToken ||
          !_foreground ||
          (hold && !_held)) {
        await app.audio.cancel();
        app.resumeAfterCapture();
        return;
      }
      if (mounted) setState(() => _recording = true);
      if (_captureMode == 'device' && !app.audio.dictating) {
        if (mounted) setState(() => _working = false);
        await _finish();
      }
    } catch (e) {
      app.resumeAfterCapture();
      if (mounted) notice(context, AudioService.describeError(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _finish() async {
    if (_working || !_recording) return;
    setState(() {
      _working = true;
      _recording = false;
    });
    final app = ref.read(appProvider.notifier);
    final state = ref.read(appProvider);
    final token = _captureToken;
    final userId = state.user?['id'];
    bool canContinue() =>
        mounted &&
        _foreground &&
        token == _captureToken &&
        ref.read(appProvider).user?['id'] == userId &&
        userId == _captureUser &&
        ref.read(appProvider).selectedGroupId == _captureGroup &&
        ref.read(appProvider).recipientId == _captureRecipient &&
        ref.read(appProvider).language == _captureLanguage;
    try {
      Json payload;
      if (_captureMode == 'device') {
        payload = await app.audio.finishDictation();
      } else if (_captureMode == 'voice') {
        payload = await app.audio.finishRecording();
      } else {
        final audio = await app.audio.finishRecording();
        if (!canContinue()) return;
        Json result;
        try {
          result = Json.from(
            await app.api.post('/audio/transcribe', {
              ...audio,
              'groupId': state.selectedGroupId,
              'sourceLanguage': state.language,
            }),
          );
        } catch (e) {
          if (ApiClient.isConnectionError(e)) {
            if (!canContinue()) return;
            await app.send({...audio, 'requiresReview': true}, mode: _mode);
            if (mounted) {
              notice(
                context,
                'Audio saved to your outbox. Review its translation in History when you reconnect.',
              );
            }
            return;
          }
          rethrow;
        }
        payload = {
          'text': result['text'],
          'durationSeconds': audio['durationSeconds'],
          'idempotencyKey': const Uuid().v4(),
        };
      }
      payload['processing'] = _captureMode;
      if (mounted && canContinue()) {
        final result = await app.send(payload, mode: _mode);
        if (mounted) {
          notice(
            context,
            result == null ? 'Saved. Sending when connected.' : 'Message sent.',
          );
        }
      }
    } catch (e) {
      if (mounted) notice(context, AudioService.describeError(e));
    } finally {
      app.resumeAfterCapture();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    _held = false;
    ++_captureToken;
    await _app.audio.cancel();
    _app.resumeAfterCapture();
    if (mounted) {
      setState(() {
        _recording = false;
        _transcript = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    return WalkieLayout(
      state: state,
      app: app,
      recording: _recording,
      working: _working,
      walkie: _walkie,
      transcript: _transcript,
      onTap: () => _recording ? _finish() : _begin(),
      onCancel: _cancel,
      onManage: () => context.go('/manage-teams'),
      onSettings: () => context.go('/settings'),
      onHistory: () => context.go('/history'),
      onLanguages: () => context.go('/languages'),
      onWalkie: (value) => setState(() => _walkie = value),
      onSpeaker: (value) => runAction(context, () async {
        if (value) await app.settings(receiveMode: 'automatic');
        await app.setReceiving(value);
      }),
      onHold: !_walkie
          ? null
          : (_) {
              _held = true;
              _begin(hold: true);
            },
      onHoldCancel: () {
        if (_held) _cancel();
      },
      onRelease: !_walkie
          ? null
          : (_) {
              if (_held) {
                _held = false;
                _finish();
              }
            },
    );
  }
}

Future<void> reviewAndSend(
  BuildContext context,
  WidgetRef ref,
  Json payload, {
  String mode = 'group',
}) async {
  await runAction(context, () async {
    final result = await ref
        .read(appProvider.notifier)
        .send(payload, mode: mode);
    if (context.mounted) {
      notice(
        context,
        result == null ? 'Saved. Sending when connected.' : 'Message sent.',
      );
    }
  });
}
