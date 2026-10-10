import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/core/receiving_policy.dart';
import 'package:mine2yourlingo/core/team_theme.dart';
import 'package:mine2yourlingo/features/communication/home_screen.dart';

class CaptureAudio extends AudioService {
  int phoneCalls = 0, cloudCalls = 0;
  Completer<void>? startGate;
  @override
  Future<void> startDictation(
    String language,
    void Function(String) onText,
    VoidCallback onDone, {
    bool continuous = false,
  }) async {
    phoneCalls++;
    if (startGate != null) await startGate!.future;
    dictating = true;
    onText('Bring the material');
  }

  @override
  Future<void> startRecording(VoidCallback onLimit) async {
    cloudCalls++;
    if (startGate != null) await startGate!.future;
    recording = true;
  }

  @override
  Future<Map<String, dynamic>> finishRecording() async {
    recording = false;
    return {
      'audioBase64': 'fixture-audio',
      'mimeType': 'audio/wav',
      'durationSeconds': 1,
      'idempotencyKey': 'fixture-key',
    };
  }

  @override
  Future<Map<String, dynamic>> finishDictation() async {
    dictating = false;
    return {'text': 'Bring the material'};
  }

  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> cancel() async {
    dictating = false;
    recording = false;
  }
}

class CaptureController extends AppController {
  CaptureController(CaptureAudio service) : super(audioService: service);
  final sent = <Json>[];
  @override
  Future<Json?> send(Json payload, {String mode = 'group'}) async {
    sent.add({...payload, 'recipientId': state.recipientId});
    return {'state': 'READY'};
  }

  @override
  Future<void> settings({
    String? receiveMode,
    bool? headphonesOnly,
    String? inputMode,
    String? uiLanguage,
    ReceivingPolicy? policy,
  }) async {}
  @override
  Future<void> setReceiving(bool active) async {}
  @override
  AppState build() => const AppState(
    loading: false,
    inputMode: 'cloud',
    user: {'id': 'a', 'spokenLanguage': 'ta'},
    selectedGroupId: 'g',
    recipientId: 'b',
    capabilities: {
      'ai': {'stt': false},
      'pricingValidated': false,
    },
    usage: {'cloudAiAllowed': false},
    groups: [
      {
        'id': 'g',
        'name': 'Team',
        'members': [
          {'userId': 'a', 'displayName': 'A'},
          {'userId': 'b', 'displayName': 'B', 'listeningLanguage': 'bn'},
        ],
      },
    ],
  );
}

void main() {
  testWidgets(
    'walkie stop sends recognized words for translation immediately without review',
    (tester) async {
      final audio = CaptureAudio();
      final controller = CaptureController(audio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      expect(audio.phoneCalls, 1);
      expect(audio.cloudCalls, 0);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Make sure it sounds right'), findsNothing);
      expect(find.text('Send message'), findsNothing);
      expect(controller.sent.single['processing'], 'device');
      expect(controller.sent.single['text'], 'Bring the material');
      expect(find.text('Recent Messages'), findsNothing);
      expect(controller.sent.single['recipientId'], 'b');
    },
  );
  testWidgets(
    'member cards select direct audience and hold release sends exactly once',
    (tester) async {
      final audio = CaptureAudio();
      final controller = CaptureController(audio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Everyone'));
      await tester.pump();
      await tester.tap(find.text('Everyone'));
      await tester.pump();
      expect(controller.state.recipientId, isNull);
      await tester.ensureVisible(find.text('B').last);
      await tester.pump();
      await tester.tap(find.text('B').last);
      await tester.pump();
      expect(controller.state.recipientId, 'b');
      final hold = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(audio.phoneCalls, 1);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await tester.ensureVisible(find.text('Everyone'));
      await tester.pump();
      await tester.tap(find.text('Everyone'));
      expect(
        controller.state.recipientId,
        'b',
        reason: 'Recording audience cannot change',
      );
      await hold.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Send message'), findsNothing);
      expect(controller.sent.length, 1);
      expect(controller.sent.single['recipientId'], 'b');
      expect(audio.cloudCalls, 0);
    },
  );
  testWidgets('releasing hold during microphone startup cancels the capture', (
    tester,
  ) async {
    final audio = CaptureAudio()..startGate = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith(() => CaptureController(audio))],
        child: MaterialApp(
          theme: appTheme(),
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    final hold = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(audio.phoneCalls, 1);
    await hold.up();
    audio.startGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(audio.recording, false);
    expect(audio.dictating, false);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.text('Send message'), findsNothing);
  });
  testWidgets(
    'equalizer responds to microphone input and rests when capture stops',
    (tester) async {
      final level = ValueNotifier<double>(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoiceEqualizer(active: true, level: level)),
        ),
      );
      final idle = tester
          .getSize(find.byKey(const ValueKey('voice-bar-3')))
          .height;
      level.value = 1;
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byKey(const ValueKey('voice-bar-3'))).height,
        greaterThan(idle),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoiceEqualizer(active: false, level: level)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('voice-bar-3'))).height,
        idle,
      );
      level.dispose();
    },
  );
}
