import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mine2yourlingo/core/api.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/local_store.dart';

Json message(String id) => {
  'id': id,
  'groupId': 'group',
  'senderId': 'sender',
  'state': 'READY',
  'translations': [
    {'language': 'en', 'text': 'Private $id'},
  ],
  'recipients': [
    {'userId': 'receiver', 'state': 'DELIVERED'},
  ],
};

class PlaybackApi extends ApiClient {
  final receipts = <String>[];
  final gets = <String>[];
  final delayed = <String, Completer<dynamic>>{};
  final messages = <String, Json>{};
  @override
  Future<dynamic> get(String path) async {
    gets.add(path);
    if (delayed.containsKey(path)) return delayed[path]!.future;
    final id = path.split('/').last;
    return messages[id] ?? message(id);
  }

  @override
  Future<dynamic> post(String path, [dynamic data]) async {
    receipts.add('$path:${data['state']}');
    return {};
  }
}

class PlaybackAudio extends AudioService {
  final requests = <({String message, String request})>[];
  int stops = 0;
  final spoken = <({String text, String language})>[];
  final translated = <({String text, String source, String target})>[];
  String? translationFailure;
  @override
  Future<String> translateOnDevice(
    String text,
    String source,
    String target,
  ) async {
    translated.add((text: text, source: source, target: target));
    if (translationFailure != null) {
      throw PlatformException(
        code: translationFailure!,
        message: 'Device model failure',
      );
    }
    return 'Come here';
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
    spoken.add((text: text, language: language));
    requests.add((message: id, request: playbackRequestId!));
  }

  int remoteCalls = 0;
  @override
  Future<void> playRemote(
    String id,
    String url,
    Map<String, String> headers, {
    bool headphonesOnly = false,
    int? stopAtEpochMillis,
    String? playbackRequestId,
  }) async {
    remoteCalls++;
    requests.add((message: id, request: playbackRequestId!));
  }

  void emit(int index, String event) {
    final request = requests[index];
    onPlayback?.call(request.message, event, null, request.request);
  }

  @override
  Future<void> stopPlayback() async => stops++;
  @override
  Future<void> receive(bool active) async {}
}

class PlaybackController extends AppController {
  PlaybackController(PlaybackApi api, PlaybackAudio audio, LocalStore db)
    : super(client: api, audioService: audio, localStore: db);
  void seed(Json message) => state = state.copy(messages: [message]);
  void listen(String language) =>
      state = state.copy(user: {...state.user!, 'listeningLanguage': language});
  AppState get snapshot => state;
  @override
  AppState build() => const AppState(
    loading: false,
    user: {'id': 'receiver', 'listeningLanguage': 'en'},
    receiving: true,
    receiveMode: 'automatic',
  );
}

Future<void> settleAsync() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackApi api;
  late PlaybackAudio audio;
  late LocalStore db;
  late PlaybackController controller;
  late ProviderContainer container;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = PlaybackApi();
    audio = PlaybackAudio();
    db = LocalStore(NativeDatabase.memory());
    controller = PlaybackController(api, audio, db);
    container = ProviderContainer(
      overrides: [appProvider.overrideWith(() => controller)],
    );
    container.read(appProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('receipt bursts update history without fetching, replaying or regressing status', () async {
    controller.seed(message('receipt'));
    for (var i = 0; i < 30; i++) {
      await controller.applyReceipt({
        'messageId': 'receipt',
        'userId': 'receiver',
        'state': 'PLAYBACK_STARTED',
      });
      await controller.applyReceipt({
        'messageId': 'receipt',
        'userId': 'receiver',
        'state': 'PLAYBACK_COMPLETED',
      });
    }
    await controller.applyReceipt({
      'messageId': 'receipt',
      'userId': 'receiver',
      'state': 'DELIVERED',
    });
    expect(api.gets, isEmpty);
    expect(api.receipts, isEmpty);
    expect(audio.requests, isEmpty);
    final stored = await db.read('messages') as List;
    expect(stored.single['recipients'].single['state'], 'PLAYBACK_COMPLETED');
  });
  test(
    'simultaneous duplicate message events share authorization fetch',
    () async {
      final delayed = Completer<dynamic>();
      api.delayed['/messages/burst'] = delayed;
      final first = controller.receiveMessageEvent('burst');
      final second = controller.receiveMessageEvent('burst');
      expect(identical(first, second), isTrue);
      expect(api.gets, ['/messages/burst']);
      delayed.complete({...message('burst'), 'senderId': 'receiver'});
      await Future.wait([first, second]);
      expect(api.gets, ['/messages/burst']);
      expect(audio.requests, isEmpty);
    },
  );
  test(
    'Tamil incoming message speaks translated English, never original audio',
    () async {
      api.messages['translated'] = {
        ...message('translated'),
        'processing': 'device',
        'sourceLanguage': 'ta',
        'sourceText': 'இங்கே வா',
        'translations': [
          {'language': 'en', 'text': '', 'needsDeviceTranslation': true},
        ],
      };
      await controller.receiveMessageEvent('translated');
      await settleAsync();
      expect(audio.translated.single, (
        text: 'இங்கே வா',
        source: 'ta',
        target: 'en',
      ));
      expect(audio.spoken.single, (text: 'Come here', language: 'en'));
      expect(audio.remoteCalls, 0);
      expect(api.receipts.any((r) => r.contains('PLAYBACK_COMPLETED')), false);
      audio.emit(0, 'playbackStarted');
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(
        api.receipts,
        contains('/messages/translated/ack:PLAYBACK_COMPLETED'),
      );
    },
  );

  test('incoming speech waits for explicit replay to finish', () async {
    await controller.playTranslation('manual', 'en');
    await controller.receiveMessageEvent('automatic');
    await settleAsync();
    expect(audio.requests.map((r) => r.message), ['manual']);
    expect(audio.stops, 0);
    audio.emit(0, 'playbackStarted');
    audio.emit(0, 'playbackCompleted');
    await settleAsync();
    expect(audio.requests.map((r) => r.message), ['manual', 'automatic']);
    expect(api.receipts.where((r) => r.contains('PLAYBACK_')), [
      '/messages/manual/ack:PLAYBACK_STARTED',
      '/messages/manual/ack:PLAYBACK_COMPLETED',
    ]);
  });

  test(
    'stale same-message completion cannot release replay or claim hearing',
    () async {
      await controller.playTranslation('manual', 'en');
      await controller.playTranslation('manual', 'en');
      expect(audio.requests[0].request, isNot(audio.requests[1].request));
      await controller.receiveMessageEvent('automatic');
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests, hasLength(2));
      expect(api.receipts.where((r) => r.contains('PLAYBACK_')), isEmpty);
      audio.emit(1, 'playbackStarted');
      audio.emit(1, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests.map((r) => r.message), [
        'manual',
        'manual',
        'automatic',
      ]);
      expect(api.receipts.where((r) => r.contains('PLAYBACK_')), [
        '/messages/manual/ack:PLAYBACK_STARTED',
        '/messages/manual/ack:PLAYBACK_COMPLETED',
      ]);
    },
  );

  test(
    'replaced authorization cannot start or release the new playback',
    () async {
      final pending = Completer<dynamic>();
      api.delayed['/messages/slow'] = pending;
      final slow = controller.playTranslation('slow', 'en', automatic: true);
      final cancelled = expectLater(slow, throwsA(isA<Exception>()));
      await controller.playTranslation('manual', 'en');
      await controller.receiveMessageEvent('automatic');
      pending.complete(message('slow'));
      await cancelled;
      await settleAsync();
      expect(audio.requests.map((r) => r.message), ['manual']);
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests.map((r) => r.message), ['manual', 'automatic']);
    },
  );

  test(
    'automatic events wait while manual replay is still authorizing',
    () async {
      final pending = Completer<dynamic>();
      api.delayed['/messages/manual'] = pending;
      final replay = controller.playTranslation('manual', 'en');
      await controller.receiveMessageEvent('automatic');
      await settleAsync();
      expect(audio.requests, isEmpty);
      pending.complete(message('manual'));
      await replay;
      expect(audio.requests.map((r) => r.message), ['manual']);
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests.map((r) => r.message), ['manual', 'automatic']);
    },
  );

  test(
    'recording interruption clears ownership and ignores late receipts',
    () async {
      await controller.playTranslation('manual', 'en');
      await controller.pauseForCapture();
      await controller.receiveMessageEvent('automatic');
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests, hasLength(1));
      expect(api.receipts.where((r) => r.contains('PLAYBACK_')), isEmpty);
      controller.resumeAfterCapture();
      await settleAsync();
      expect(audio.requests.map((r) => r.message), ['manual', 'automatic']);
    },
  );

  test(
    'phrase preview owns playback without sending message receipts',
    () async {
      await controller.playLocalText('phrase', 'Hello', 'en');
      await controller.receiveMessageEvent('automatic');
      audio.emit(0, 'playbackStarted');
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(audio.requests.map((r) => r.message), ['phrase', 'automatic']);
      expect(api.receipts.where((r) => r.contains('/phrase/')), isEmpty);
    },
  );

  test(
    'previously played incoming events are never automatically replayed',
    () async {
      for (final state in [
        'PLAYBACK_STARTED',
        'PLAYBACK_COMPLETED',
        'FAILED',
      ]) {
        final id = 'old-$state';
        api.messages[id] = {
          ...message(id),
          'recipients': [
            {'userId': 'receiver', 'state': state},
          ],
        };
        await controller.receiveMessageEvent(id);
      }
      await settleAsync();
      expect(audio.requests, isEmpty);
      expect(api.receipts, isEmpty);
    },
  );

  test(
    'completion without a matching start creates no completed receipt',
    () async {
      await controller.playTranslation('manual', 'en');
      audio.emit(0, 'playbackCompleted');
      await settleAsync();
      expect(api.receipts.where((r) => r.contains('PLAYBACK_')), isEmpty);
    },
  );

  test(
    'callbacks lacking the request identity never advance the queue',
    () async {
      await controller.playTranslation('manual', 'en');
      await controller.receiveMessageEvent('automatic');
      audio.onPlayback?.call('manual', 'playbackCompleted', null, null);
      await settleAsync();
      expect(audio.requests, hasLength(1));
      expect(api.receipts.where((r) => r.contains('PLAYBACK_')), isEmpty);
    },
  );
  test('Tamil to Hindi invokes the local translator with the current receiver preference, not the message snapshot', () async {
    controller.listen('hi');
    api.messages['regional'] = {
      ...message('regional'),
      'processing': 'device',
      'sourceLanguage': 'ta',
      'sourceText': 'வணக்கம்',
    };
    await controller.playTranslation('regional', 'en');
    expect(audio.translated.single.source, 'ta');
    expect(audio.translated.single.target, 'hi');
    expect(audio.spoken.single.language, 'hi');
    expect(api.receipts.every((r) => r.contains('/ack:')), isTrue);
    expect(audio.remoteCalls, 0);
  });
  test('missing model/offline/initialization/inference errors propagate without cloud or original-audio fallback', () async {
    api.messages['failure'] = {
      ...message('failure'),
      'processing': 'device',
      'sourceLanguage': 'ta',
      'sourceText': 'வணக்கம்',
    };
    for (final code in [
      'device_language_unsupported',
      'model_download_offline',
      'model_download_failed',
      'translation_initialization_failed',
      'device_translation_failed',
    ]) {
      audio.translationFailure = code;
      await expectLater(
        controller.playTranslation('failure', 'en'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    }
    expect(audio.spoken, isEmpty);
    expect(audio.remoteCalls, 0);
    expect(api.receipts.every((r) => r.contains('/ack:DELIVERED')), isTrue);
  });
  test('active speaker uses stable sender identity and safe name; a completed playback clears it', () async {
    controller.seed({...message('speaker'), 'senderDisplayName': 'Suresh'});
    await controller.playTranslation('speaker', 'en');
    audio.emit(0, 'playbackStarted');
    expect(controller.snapshot.activeSpeakerId, 'sender');
    expect(controller.snapshot.activeSpeakerName, 'Suresh');
    audio.emit(0, 'playbackCompleted');
    expect(controller.snapshot.activeSpeakerId, isNull);
  });
  test('incoming original voice automatically uses remote playback', () async {
    api.messages['voice'] = {
      ...message('voice'),
      'processing': 'voice',
      'durationSeconds': 1,
      'translations': [
        {'language': 'en', 'text': '', 'audioUrl': '/v1/audio/fixture'},
      ],
    };
    await controller.receiveMessageEvent('voice');
    await settleAsync();
    await settleAsync();
    expect(audio.remoteCalls, 1);
    expect(audio.requests.single.message, 'voice');
    expect(api.receipts.any((v) => v.endsWith('PLAYBACK_COMPLETED')), false);
    audio.emit(0, 'playbackStarted');
    audio.emit(0, 'playbackCompleted');
    await settleAsync();
    await settleAsync();
    expect(api.receipts.any((v) => v.endsWith('PLAYBACK_COMPLETED')), true);
  });
}
