import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/api.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/audio.dart';
import 'package:mine2yourlingo/core/local_store.dart';
import 'package:mine2yourlingo/core/member_state.dart';

Json user(
  String id,
  String name,
  String spoken,
  String listening,
  int version,
) => {
  'id': id,
  'userId': id,
  'displayName': name,
  'spokenLanguage': spoken,
  'listeningLanguage': listening,
  'version': version,
  'updatedAt': '2026-10-09T00:00:00Z',
};
final initialUser = user('a', 'Karthik', 'ta', 'ta', 1);
List<Json> teams() => [
  {
    'id': 'g',
    'members': [
      initialUser,
      user('b', 'Suresh', 'hi', 'hi', 1),
      user('c', 'Meena', 'en', 'en', 1),
    ],
  },
];

class ProfileApi extends ApiClient {
  Json remote = {...initialUser};
  final patches = <Json>[];
  bool offline = false, conflict = false;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<dynamic> patch(String path, dynamic data) async {
    patches.add(Json.from(data));
    if (!started.isCompleted) started.complete();
    await gate?.future;
    final req = RequestOptions(path: path);
    if (offline) {
      throw DioException(
        requestOptions: req,
        type: DioExceptionType.connectionError,
      );
    }
    if (conflict) {
      conflict = false;
      remote = {...remote, 'version': 3, 'listeningLanguage': 'hi'};
      throw DioException(
        requestOptions: req,
        response: Response(requestOptions: req, statusCode: 409),
      );
    }
    final changes = Json.from(data)..remove('expectedVersion');
    remote = {...remote, ...changes, 'version': remote['version'] + 1};
    return {...remote};
  }

  @override
  Future<dynamic> get(String path) async => switch (path) {
    '/users/me' => {...remote},
    '/groups' => [
      {'id': 'g'},
    ],
    '/groups/g' => teams().first,
    '/messages' => [],
    '/plans' => [],
    _ => <String, dynamic>{},
  };
}

class ProfileAudio extends AudioService {
  @override
  Future<void> prepareLanguage(String language, {bool retry = false}) async {}
  @override
  Future<void> prepareTranslationLanguage(String language) async {}
}

class ProfileController extends AppController {
  ProfileController(ProfileApi api, LocalStore db)
    : super(client: api, audioService: ProfileAudio(), localStore: db);
  @override
  AppState build() => AppState(
    loading: false,
    user: {...initialUser},
    groups: teams(),
    selectedGroupId: 'g',
  );
  AppState get snapshot => state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProfileApi api;
  late LocalStore db;
  late ProfileController app;
  late ProviderContainer container;
  setUp(() {
    api = ProfileApi();
    db = LocalStore(NativeDatabase.memory());
    app = ProfileController(api, db);
    container = ProviderContainer(
      overrides: [appProvider.overrideWith(() => app)],
    );
    container.read(appProvider);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });
  test('language UI changes immediately; omitted fields survive; pending offline updates persist and reconnect flushes', () async {
    api.offline = true;
    final change = app.updateProfile({'spokenLanguage': 'en'});
    expect(app.snapshot.language, 'en');
    expect(app.snapshot.listeningLanguage, 'ta');
    expect(app.snapshot.user!['displayName'], 'Karthik');
    await change;
    final saved = await db.read('pendingProfile');
    expect(saved['userId'], 'a');
    expect(saved['changes'], {'spokenLanguage': 'en'});
    api.offline = false;
    await app.sync();
    expect(api.remote['spokenLanguage'], 'en');
    expect(api.remote['listeningLanguage'], 'ta');
    expect((await db.read('pendingProfile'))['changes'], isEmpty);
  });
  test('remote changes patch the correct stable identity; duplicate/stale/out-of-order events never revert preferences', () async {
    await app.applyMemberState({
      'groupId': 'g',
      'member': user('b', 'Suresh', 'en', 'ta', 5),
    });
    for (final version in [5, 2, 4]) {
      await app.applyMemberState({
        'groupId': 'g',
        'member': user('b', 'Stale name', 'hi', 'hi', version),
      });
    }
    final member = app.snapshot.members.firstWhere((m) => m['userId'] == 'b');
    expect(member['spokenLanguage'], 'en');
    expect(member['listeningLanguage'], 'ta');
    expect(member['displayName'], 'Suresh');
    expect(member['version'], 5);
    expect(app.snapshot.language, 'ta');
    expect(app.snapshot.listeningLanguage, 'ta');
    expect(app.snapshot.members.last['listeningLanguage'], 'en');
    await app.sync();
    expect(
      app.snapshot.members.firstWhere((m) => m['userId'] == 'b')['version'],
      5,
    );
  });
  test('full reconnect snapshot merges independent versions while retaining newer local state', () async {
    await app.applyMemberState({
      'groupId': 'g',
      'members': [
        user('b', 'Suresh', 'ta', 'ta', 2),
        user('c', 'Meena', 'hi', 'hi', 4),
      ],
    });
    await app.applyMemberState({
      'groupId': 'g',
      'members': [
        user('b', 'Suresh', 'en', 'en', 3),
        user('c', 'Old', 'en', 'en', 2),
      ],
    });
    expect(
      app.snapshot.members.firstWhere(
        (m) => m['userId'] == 'b',
      )['listeningLanguage'],
      'en',
    );
    expect(
      app.snapshot.members.firstWhere(
        (m) => m['userId'] == 'c',
      )['listeningLanguage'],
      'hi',
    );
    expect(app.snapshot.user!['id'], 'a');
  });
  test('simultaneous local edits serialize with current server versions and preserve the newest optimistic values', () async {
    api.gate = Completer<void>();
    final first = app.updateProfile({'spokenLanguage': 'en'});
    await api.started.future;
    final second = app.updateProfile({'listeningLanguage': 'hi'});
    expect(app.snapshot.language, 'en');
    expect(app.snapshot.listeningLanguage, 'hi');
    api.gate!.complete();
    await Future.wait([first, second]);
    expect(api.patches.length, 2);
    expect(api.patches.first['expectedVersion'], 1);
    expect(api.patches.last['expectedVersion'], 2);
    expect(api.remote['spokenLanguage'], 'en');
    expect(api.remote['listeningLanguage'], 'hi');
    expect(app.snapshot.user!['version'], 3);
  });
  test('own remote event does not erase pending edits; optimistic conflict rebases against authenticated profile', () async {
    api.conflict = true;
    await app.updateProfile({'spokenLanguage': 'en'});
    expect(api.patches.map((p) => p['expectedVersion']), [1, 3]);
    expect(app.snapshot.language, 'en');
    expect(app.snapshot.listeningLanguage, 'hi');
    expect(app.snapshot.user!['version'], 4);
    api.offline = true;
    await app.updateProfile({'listeningLanguage': 'ta'});
    await app.applyMemberState({
      'groupId': 'g',
      'member': user('a', 'Karthik', 'hi', 'en', 5),
    });
    expect(app.snapshot.listeningLanguage, 'ta');
    expect(app.snapshot.language, 'hi');
    expect((await db.read('pendingProfile'))['changes'], {
      'listeningLanguage': 'ta',
    });
  });
  test('missing names are safe across member projections and locale tags canonicalize', () {
    for (final value in [null, '', ' ', 'null', ' NULL ', 'undefined']) {
      expect(memberDisplayName(value), 'Team Member');
    }
    expect(memberDisplayName('  Suresh  '), 'Suresh');
    final legacy = normalizeMember({
      'userId': 'legacy',
      'spokenLanguage': 'TA_in',
      'displayName': 'null',
    });
    expect(legacy['userId'], 'legacy');
    expect(legacy['displayName'], 'Team Member');
    expect(legacy['listeningLanguage'], 'ta');
  });
}
