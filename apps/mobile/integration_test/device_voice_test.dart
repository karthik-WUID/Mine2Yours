import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mine2yourlingo/core/api.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/features/voice/voice_test_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Wi-Fi API and real installed English reading voice', (
    tester,
  ) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final response = await dio.get('${ApiClient.defaultBase}/health');
      expect(response.statusCode, 200);
      debugPrint(
        'DEVICE_REVIEW: Wi-Fi API health 200 at ${ApiClient.defaultBase}',
      );
    } finally {
      dio.close();
    }
    final audio = AudioService();
    try {
      final capabilities = await audio.capabilities();
      final languages =
          (capabilities['voices'] as List? ?? [])
              .map((voice) => (voice as Map)['language'].toString())
              .toSet()
              .toList()
            ..sort();
      debugPrint(
        'DEVICE_REVIEW: installed offline reading languages ${jsonEncode(languages)}',
      );
      expect(
        languages.any((language) => language.startsWith('en')),
        true,
        reason:
            'Install an English reading voice before this playback smoke test.',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: VoiceTestScreen(audio: audio),
        ),
      );
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
      final finished = audio.playbackEvents.firstWhere(
        (event) =>
            event['messageId'] == 'voice-test' &&
            (event['event'] == 'playbackCompleted' ||
                event['event'] == 'playbackError'),
      );
      await tester.tap(find.text('Play test voice'));
      await tester.pumpAndSettle();
      final event = await tester.runAsync(
        () => finished.timeout(const Duration(seconds: 25)),
      );
      expect(event?['event'], 'playbackCompleted', reason: event.toString());
      debugPrint(
        'DEVICE_REVIEW: native English TTS engine completed (audibility requires human check)',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    } finally {
      await audio.dispose();
    }
  });
}
