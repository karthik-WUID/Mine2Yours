import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/languages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, (call) async {
          calls.add(call);
          if (call.method == 'getCapabilities') {
            return {
              'voices': [
                {'language': 'te-IN', 'offline': true},
              ],
            };
          }
          return {'phase': 'queued'};
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null),
  );
  test('five default languages prepare real translation models without requesting speech or voice installers', () async {
    final audio = AudioService();
    for (final code in AppLanguage.defaults) {
      await audio.prepareLanguage(code);
    }
    expect(calls.map((c) => c.method).toSet(), {'prepareTranslation'});
    expect(
      calls.map((c) => c.arguments['language']).toSet(),
      AppLanguage.defaults,
    );
    expect(AppLanguage.all.length, 23);
  });
  test('extra language requests only its locale; pending is not installed; real callbacks update progress', () async {
    final audio = AudioService();
    var playbackCalls = 0;
    audio.onPlayback = (_, _, _, _) => playbackCalls++;
    await audio.prepareLanguage('te');
    expect(calls.first.method, 'prepareTranslation');
    expect(calls.first.arguments, {'language': 'te'});
    expect(calls[1].method, 'prepareLanguage');
    expect(calls[1].arguments, {'language': 'te', 'locale': 'te-IN'});
    expect(calls.where((call) => call.method == 'installVoiceData'), isEmpty);
    expect(audio.languageStatus.value['te']!['phase'], 'queued');
    Future<void> event(Map<String, dynamic> payload) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              AudioService.channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('languageDownload', payload),
              ),
              (_) {},
            );
    await event({'language': 'te', 'phase': 'downloading', 'progress': 37});
    expect(audio.languageStatus.value['te']!['progress'], 37);
    expect(audio.languageStatus.value['te']!['phase'], 'downloading');
    await audio.prepareLanguage('te');
    expect(calls.where((c) => c.method == 'prepareLanguage').length, 1);
    await event({'language': 'te', 'phase': 'scheduled'});
    expect(audio.languageStatus.value['te']!['phase'], 'scheduled');
    await event({'language': 'te', 'phase': 'installed'});
    expect(audio.languageStatus.value['te']!['phase'], 'installed');
    expect(playbackCalls, 0);
  });
  test('missing reading voice opens the engine installer without claiming readiness', () async {
    final audio = AudioService();
    await audio.prepareLanguage('gu');
    expect(calls.map((c) => c.method), [
      'prepareTranslation',
      'prepareLanguage',
      'getCapabilities',
      'installVoiceData',
    ]);
    expect(audio.languageStatus.value['gu']!['phase'], 'queued');
    expect(
      audio.languageStatus.value['gu']!['voiceMessage'],
      contains('Confirm the voice installer'),
    );
  });
}
