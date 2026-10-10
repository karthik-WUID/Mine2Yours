import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null);
  });
  test(
    'automatic-speech quiet deadline reaches both native audio paths',
    () async {
      final audio = AudioService();
      final deadline = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await audio.speak('speech', 'Hello', 'en', stopAtEpochMillis: deadline);
      await audio.playRemote('file', 'https://api.example.test/audio', {
        'Authorization': 'Bearer test-only-session',
      }, stopAtEpochMillis: deadline);
      expect(calls.map((call) => call.method), ['speak', 'playAudio']);
      expect(calls.map((call) => call.arguments['stopAtEpochMillis']), [
        deadline,
        deadline,
      ]);
      expect(calls.first.arguments['language'], 'en-IN');
    },
  );
  test(
    'playback request identity reaches both native paths and callbacks',
    () async {
      final audio = AudioService();
      await audio.speak(
        'replay',
        'Hello',
        'en',
        playbackRequestId: 'request_a',
      );
      await audio.playRemote(
        'replay',
        'https://api.example.test/audio',
        {},
        playbackRequestId: 'request_b',
      );
      expect(calls.map((call) => call.arguments['playbackRequestId']), [
        'request_a',
        'request_b',
      ]);
      final events = <String?>[];
      audio.onPlayback = (_, _, _, request) => events.add(request);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            AudioService.channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('playbackCompleted', {
                'messageId': 'replay',
                'playbackRequestId': 'request_a',
              }),
            ),
            (_) {},
          );
      expect(events, ['request_a']);
    },
  );
  test('expired speech deadline never reaches the native channel', () async {
    final audio = AudioService();
    await expectLater(
      audio.speak(
        'expired',
        'Hello',
        'en',
        stopAtEpochMillis: DateTime.now().millisecondsSinceEpoch - 1,
      ),
      throwsA(isA<Exception>()),
    );
    expect(calls, isEmpty);
  });
  test('device translation number checks normalize Indian digits without ignoring changes', () {
    expect(AudioService.quantitiesChanged('12 boxes', '১২ বাক্স'), false);
    expect(AudioService.quantitiesChanged('12 boxes', '১৩ বাক্স'), true);
  });
}
