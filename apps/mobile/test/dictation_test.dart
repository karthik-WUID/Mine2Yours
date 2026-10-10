import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class FakeRecognizer extends SpeechToText {
  FakeRecognizer() : super.withMethodChannel();
  SpeechErrorListener? errors;
  SpeechStatusListener? status;
  SpeechResultListener? results;
  String? requestedLocale;
  bool ready = false;
  int listens = 0;
  SpeechSoundLevelChange? sound;
  Completer<void>? initializeGate;
  List<LocaleName> reported = [];
  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    await initializeGate?.future;
    // Match the plugin: initialize keeps its original callbacks on later calls.
    if (!ready) {
      errors = onError;
      status = onStatus;
      ready = true;
    }
    return true;
  }

  @override
  Future<List<LocaleName>> locales() async => reported;
  @override
  Future<dynamic> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    dynamic cancelOnError = false,
    dynamic partialResults = true,
    dynamic onDevice = false,
    dynamic listenMode = ListenMode.confirmation,
    dynamic sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    listens++;
    sound = onSoundLevelChange;
    requestedLocale = listenOptions?.localeId;
    results = onResult;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  void words(String value) => results?.call(
    SpeechRecognitionResult.init([
      SpeechRecognitionWords(value, null, 1.0),
    ], ResultType.finalResult),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRecognizer recognizer;
  late AudioService audio;
  setUp(() {
    recognizer = FakeRecognizer();
    audio = AudioService(speechRecognizer: recognizer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, (_) async => true);
  });
  tearDown(() async {
    await audio.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null);
  });
  test(
    'an incomplete locale list does not block vendor online recognition',
    () async {
      await audio.startDictation('ta', (_) {}, () {});
      expect(recognizer.requestedLocale, 'ta-IN');
      expect(audio.dictating, true);
    },
  );
  test('notListening waits for final words before completing', () async {
    var completed = 0;
    await audio.startDictation('en', (_) {}, () => completed++);
    recognizer.status?.call('notListening');
    expect(completed, 0);
    expect(audio.dictating, true);
    recognizer.words('Check twelve boxes');
    recognizer.status?.call('done');
    final payload = await audio.finishDictation();
    expect(payload['text'], 'Check twelve boxes');
    expect(completed, 1);
  });
  test(
    'later attempts use their current callback and error language',
    () async {
      var oldDone = 0, newDone = 0;
      await audio.startDictation('ta', (_) {}, () => oldDone++);
      recognizer.words('வணக்கம்');
      recognizer.status?.call('done');
      await audio.finishDictation();
      await audio.startDictation('bn', (_) {}, () => newDone++);
      recognizer.errors?.call(
        SpeechRecognitionError('error_language_unavailable', true),
      );
      expect(oldDone, 1);
      expect(newDone, 1);
      await expectLater(
        audio.finishDictation(),
        throwsA(predicate((e) => e.toString().contains('Bengali'))),
      );
    },
  );
  test(
    'cancel discards callbacks and cannot turn late speech into a result',
    () async {
      var completed = 0;
      final words = <String>[];
      await audio.startDictation('en', words.add, () => completed++);
      await audio.cancel();
      recognizer.words('Late private words');
      recognizer.status?.call('done');
      expect(words, isEmpty);
      expect(completed, 0);
    },
  );
  testWidgets(
    'continuous dictation retains multiple utterances and only completes when stopped',
    (tester) async {
      var completed = 0;
      final texts = <String>[];
      await audio.startDictation(
        'ta',
        texts.add,
        () => completed++,
        continuous: true,
      );
      recognizer.words('முதல் வாக்கியம்');
      recognizer.status?.call('done');
      await tester.pump(const Duration(milliseconds: 500));
      expect(recognizer.listens, 2);
      expect(audio.dictating, true);
      expect(completed, 0);
      recognizer.words('இரண்டாவது வாக்கியம்');
      recognizer.sound?.call(8);
      expect(audio.inputLevel.value, greaterThan(0));
      final finishing = audio.finishDictation();
      recognizer.status?.call('done');
      final result = await finishing;
      expect(result['text'], 'முதல் வாக்கியம் இரண்டாவது வாக்கியம்');
      expect(completed, 1);
      expect(audio.inputLevel.value, 0);
    },
  );
  testWidgets(
    'silence resumes within the session; cancelling prevents a queued restart',
    (tester) async {
      var completed = 0;
      await audio.startDictation(
        'en',
        (_) {},
        () => completed++,
        continuous: true,
      );
      recognizer.errors?.call(
        SpeechRecognitionError('error_speech_timeout', false),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(recognizer.listens, 2);
      expect(completed, 0);
      recognizer.status?.call('done');
      await audio.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(recognizer.listens, 2);
      expect(completed, 0);
    },
  );
  testWidgets('continuous microphone session stops at sixty seconds', (
    tester,
  ) async {
    var completed = 0;
    await audio.startDictation(
      'en',
      (_) {},
      () => completed++,
      continuous: true,
    );
    await tester.pump(const Duration(seconds: 60));
    expect(audio.dictating, false);
    expect(completed, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(recognizer.listens, 1);
  });
  test('cancel during recognition initialization prevents a later microphone start', () async {
    recognizer.initializeGate = Completer<void>();
    final starting = audio.startDictation(
      'en',
      (_) {},
      () {},
      continuous: true,
    );
    final error = expectLater(
      starting,
      throwsA(predicate((e) => e.toString().contains('cancelled'))),
    );
    await audio.cancel();
    recognizer.initializeGate!.complete();
    await error;
    expect(recognizer.listens, 0);
    expect(audio.dictating, false);
  });
  test('preferred locale is selected without crossing languages', () {
    expect(AudioService.recognitionLocale('en', ['en_US', 'en_IN']), 'en_IN');
    expect(AudioService.recognitionLocale('ta', ['en_US']), 'ta-IN');
  });
}
