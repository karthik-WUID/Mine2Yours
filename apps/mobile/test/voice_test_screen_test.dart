import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/features/voice/voice_test_screen.dart';

class LocalTestAudio extends AudioService {
  int spoken = 0;
  String? playedLanguage, playedText;
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'voices': [
      {'language': 'en-IN', 'offline': true},
    ],
  };
  @override
  Future<void> startDictation(
    String language,
    void Function(String) onText,
    VoidCallback onDone, {
    bool continuous = false,
  }) async {
    dictating = true;
  }

  @override
  Future<Map<String, dynamic>> finishDictation() async {
    dictating = false;
    return {'text': 'Hello voice check'};
  }

  @override
  Future<void> speak(
    String id,
    String text,
    String language, {
    bool headphonesOnly = false,
    int? stopAtEpochMillis,
    String? playbackRequestId,
  }) async {
    spoken++;
    playedText = text;
    playedLanguage = language;
  }

  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> cancel() async {
    dictating = false;
  }
}

void main() {
  testWidgets(
    'local voice test needs no account or group and reads actual words',
    (tester) async {
      final audio = LocalTestAudio();
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: VoiceTestScreen(audio: audio),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No group or app server is needed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tap to test speaking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and check my words'));
      await tester.pumpAndSettle();
      expect(audio.spoken, 1);
      expect(audio.playedText, 'Hello voice check');
      expect(audio.playedLanguage, 'en');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('read-back checkbox can prevent automatic test playback', (
    tester,
  ) async {
    final audio = LocalTestAudio();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: VoiceTestScreen(audio: audio),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read my words aloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to test speaking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop and check my words'));
    await tester.pumpAndSettle();
    expect(audio.spoken, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing Tamil voice offers an explicit English test', (
    tester,
  ) async {
    final audio = LocalTestAudio();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: VoiceTestScreen(audio: audio, language: 'ta'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Tamil reading voice is not installed'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try an English test'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Play test voice'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Play test voice'));
    await tester.pumpAndSettle();
    expect(audio.playedLanguage, 'en');
    expect(audio.playedText, 'Hello team.');
    await tester.pumpWidget(const SizedBox());
  });
}
