import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'audio.dart';
import 'local_store.dart';
import 'receiving_policy.dart';
import 'member_state.dart';
export 'member_state.dart' show memberDisplayName;

typedef Json = Map<String, dynamic>;
List<Json> jsonList(dynamic value) =>
    (value as List? ?? []).map((e) => Json.from(e as Map)).toList();

class AppState {
  final bool loading, busy, online, connected, receiving, headphonesOnly;
  final Json? user, capabilities, usage;
  final List<Json> groups, messages, outbox, plans;
  final String? error, selectedGroupId, recipientId, activeSpeakerId;
  final String inputMode, receiveMode, uiLanguage;
  final ReceivingPolicy policy;
  const AppState({
    this.loading = true,
    this.busy = false,
    this.online = true,
    this.connected = false,
    this.receiving = false,
    this.headphonesOnly = false,
    this.user,
    this.capabilities,
    this.usage,
    this.groups = const [],
    this.messages = const [],
    this.outbox = const [],
    this.plans = const [],
    this.error,
    this.selectedGroupId,
    this.recipientId,
    this.activeSpeakerId,
    this.inputMode = 'device',
    this.receiveMode = 'notification',
    this.uiLanguage = 'en',
    this.policy = const ReceivingPolicy(),
  });
  bool get cloudSpeechReady =>
      usage?['cloudAiAllowed'] == true &&
      capabilities?['ai']?['stt'] == true &&
      capabilities?['pricingValidated'] == true;
  String get effectiveInputMode =>
      inputMode == 'cloud' && cloudSpeechReady ? 'cloud' : 'device';
  String get language =>
      preferenceLanguage(user?['spokenLanguage'], fallback: 'ta');
  String get listeningLanguage =>
      preferenceLanguage(user?['listeningLanguage'], fallback: language);
  Json? get group =>
      groups.where((g) => g['id'] == selectedGroupId).firstOrNull;
  List<Json> get members =>
      jsonList(group?['members']).map(normalizeMember).toList();
  Json? get recipient =>
      members.where((m) => m['userId'] == recipientId).firstOrNull;
  String memberName(String? id, {dynamic fallback}) {
    if (id == user?['id']) return memberDisplayName(user?['displayName']);
    final member = groups
        .expand((g) => jsonList(g['members']))
        .where((m) => m['userId'] == id)
        .firstOrNull;
    return memberDisplayName(
      member?['displayName'],
      fallback: memberDisplayName(fallback),
    );
  }

  String get activeSpeakerName => memberName(
    activeSpeakerId,
    fallback: messages
        .where((m) => m['senderId'] == activeSpeakerId)
        .firstOrNull?['senderDisplayName'],
  );
  AppState copy({
    bool? loading,
    bool? busy,
    bool? online,
    bool? connected,
    bool? receiving,
    bool? headphonesOnly,
    Json? user,
    Json? capabilities,
    Json? usage,
    List<Json>? groups,
    List<Json>? messages,
    List<Json>? outbox,
    List<Json>? plans,
    String? error,
    String? selectedGroupId,
    String? recipientId,
    String? activeSpeakerId,
    bool clearSpeaker = false,
    String? inputMode,
    String? receiveMode,
    String? uiLanguage,
    ReceivingPolicy? policy,
    bool clearError = false,
    bool clearRecipient = false,
  }) => AppState(
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    online: online ?? this.online,
    connected: connected ?? this.connected,
    receiving: receiving ?? this.receiving,
    headphonesOnly: headphonesOnly ?? this.headphonesOnly,
    user: user ?? this.user,
    capabilities: capabilities ?? this.capabilities,
    usage: usage ?? this.usage,
    groups: groups ?? this.groups,
    messages: messages ?? this.messages,
    outbox: outbox ?? this.outbox,
    plans: plans ?? this.plans,
    error: clearError ? null : (error ?? this.error),
    selectedGroupId: selectedGroupId ?? this.selectedGroupId,
    recipientId: clearRecipient ? null : (recipientId ?? this.recipientId),
    activeSpeakerId: clearSpeaker
        ? null
        : (activeSpeakerId ?? this.activeSpeakerId),
    inputMode: inputMode ?? this.inputMode,
    receiveMode: receiveMode ?? this.receiveMode,
    uiLanguage: uiLanguage ?? this.uiLanguage,
    policy: policy ?? this.policy,
  );
}

final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class _PlaybackRequest {
  _PlaybackRequest(this.messageId, this.sessionGeneration, this.automatic);
  final String id = const Uuid().v4();
  final String messageId;
  final int sessionGeneration;
  final bool automatic;
  bool incoming = false;
  bool started = false;
}

class _PlaybackCancelled implements Exception {
  @override
  String toString() => 'Playback was cancelled.';
}

class AppController extends Notifier<AppState> with WidgetsBindingObserver {
  AppController({
    ApiClient? client,
    AudioService? audioService,
    LocalStore? localStore,
  }) : api = client ?? ApiClient(),
       audio = audioService ?? AudioService(),
       _providedDb = localStore {
    audio.onPlayback = _onPlayback;
  }
  final ApiClient api;
  final LocalStore? _providedDb;
  late final db = _providedDb ?? LocalStore();
  final secure = const FlutterSecureStorage();
  final AudioService audio;
  WebSocketChannel? _socket;
  StreamSubscription? _network;
  Timer? _retry, _queueTimer, _quietTimer, _syncTimer;
  bool _flushing = false;
  Json _profilePending = {};
  Json? _profileBase;
  Future<void>? _profileFlush;
  Future<void> _profileCache = Future.value();
  final _messageFetches = <String, Future<void>>{};
  int _reconnections = 0,
      _socketGeneration = 0,
      _sessionGeneration = 0,
      _audioGeneration = 0;
  Future<void> _secureOperations = Future.value();
  bool _foreground = true, _disposed = false;
  bool _connecting = false;
  int? _syncGeneration;
  bool _resyncRequested = false;
  final _played = <String>{};
  final _playQueue = <Json>[];
  final _receipts = <String, Future<void>>{};
  bool _capturing = false;
  _PlaybackRequest? _playback;
  bool _current(int generation) =>
      !_disposed && generation == _sessionGeneration;
  void _requireCurrent(int generation) {
    if (!_current(generation) || state.user == null) {
      throw Exception('Your session changed. Please try again.');
    }
  }

  Future<void> _storeTokens(String access, String refresh, int generation) {
    return _secureOperations = _secureOperations.catchError((_) {}).then((
      _,
    ) async {
      if (!_current(generation)) return;
      await secure.write(key: 'accessToken', value: access);
      await secure.write(key: 'refreshToken', value: refresh);
    });
  }

  @override
  AppState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _retry?.cancel();
      _queueTimer?.cancel();
      _quietTimer?.cancel();
      _syncTimer?.cancel();
      _network?.cancel();
      _socket?.sink.close();
      audio.dispose();
      db.close();
    });
    Future.microtask(_initialize);
    return const AppState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lifecycle = state;
    _foreground = lifecycle == AppLifecycleState.resumed;
    if (_foreground && this.state.user != null) {
      _checkQuietHours();
      _connect();
      sync();
    }
    if (!_foreground) {
      // Dart lifecycle cannot guarantee background delivery. Native playback may
      // finish an explicit Android receiving session, but no fake realtime claim.
      _retry?.cancel();
      audio.cancel();
      _capturing = false;
      _socket?.sink.close();
      this.state = this.state.copy(connected: false);
    }
  }

  Future<void> _initialize() async {
    try {
      final settings = await db.read('settings') as Map?;
      if (settings != null) {
        api.dio.options.baseUrl = ApiClient.restoreBase(
          settings['baseUrl'] as String?,
        );
        state = state.copy(
          receiveMode: settings['receiveMode'] ?? 'notification',
          headphonesOnly: settings['headphonesOnly'] ?? false,
          inputMode: settings['inputMode'] ?? 'device',
          uiLanguage: settings['uiLanguage'] ?? 'en',
          policy: ReceivingPolicy.fromJson(settings['receivingPolicy'] as Map?),
        );
        if (api.dio.options.baseUrl != settings['baseUrl']) {
          await _saveSettings();
        }
      }
      api.token = await secure.read(key: 'accessToken');
      api.refreshToken = await secure.read(key: 'refreshToken');
      api.onTokens = (access, refresh) async {
        await _storeTokens(access, refresh, _sessionGeneration);
      };
      final user = await db.read('user');
      await _configureDeviceRecovery(
        user is Map ? user['id'] as String? : null,
      );
      if (api.token != null && user is Map) {
        state = state.copy(
          user: normalizeMember(Json.from(user)),
          groups: mergeTeamSnapshot(jsonList(await db.read('groups')), []),
          messages: jsonList(await db.read('messages')),
        );
        if (state.groups.isNotEmpty) {
          state = state.copy(selectedGroupId: state.groups.first['id']);
        }
      }
      final pending = await db.read('pendingProfile');
      _profileBase = state.user;
      if (pending is Map && pending['userId'] == state.user?['id']) {
        _profilePending = Json.from(pending['changes'] as Map? ?? {});
        _profileBase = normalizeMember(
          Json.from(pending['base'] as Map? ?? state.user!),
        );
        _applyOwnProfile();
      }
      await _loadOutbox();
      _scheduleQuietHours();
      _network = Connectivity().onConnectivityChanged.listen((result) {
        state = state.copy(online: !result.contains(ConnectivityResult.none));
        if (state.online && state.user != null) {
          sync();
          _connect();
        } else {
          state = state.copy(connected: false);
        }
      });
      await fetchCapabilities();
      if (state.user == null) await startWithoutLogin();
      if (state.user != null) {
        await _bindCurrentDevice();
        await sync();
        _connect();
      }
    } catch (e) {
      state = state.copy(error: ApiClient.describe(e));
    } finally {
      state = state.copy(loading: false);
    }
  }

  void _onPlayback(String id, String event, String? reason, String? requestId) {
    if (_disposed || state.user == null) return;
    if (event == 'receivingStopped') {
      state = state.copy(receiving: false);
      _playQueue.clear();
      if (_playback?.automatic == true) {
        ++_audioGeneration;
        _playback = null;
        state = state.copy(clearSpeaker: true);
      }
      return;
    }
    final request = _playback;
    // Message IDs can repeat during replay. Only this playback request owns
    // the queue and its receipts; delayed callbacks cannot release a new one.
    if (request == null ||
        request.id != requestId ||
        request.messageId != id ||
        !_current(request.sessionGeneration)) {
      return;
    }
    if (event == 'playbackStarted') {
      if (request.started) return;
      request.started = true;
      final message = state.messages.where((m) => m['id'] == id).firstOrNull;
      state = state.copy(
        activeSpeakerId: message?['senderId'],
        clearSpeaker: message?['senderId'] == null,
      );
    }
    if (!kIsWeb &&
        request.incoming &&
        (event == 'playbackStarted' ||
            (event == 'playbackCompleted' && request.started))) {
      final pending = _receipts[id] ?? Future.value();
      _receipts[id] = pending.catchError((_) {}).then((_) async {
        if (!_current(request.sessionGeneration)) return;
        try {
          await api.post('/messages/$id/ack', {
            'state': event == 'playbackStarted'
                ? 'PLAYBACK_STARTED'
                : 'PLAYBACK_COMPLETED',
          });
        } catch (_) {
          /* No successful receipt is invented. */
        }
      });
    }
    if (event == 'playbackError') {
      state = state.copy(error: reason ?? 'Audio playback failed.');
    }
    if (event == 'playbackCompleted' || event == 'playbackError') {
      _playback = null;
      state = state.copy(clearSpeaker: true);
      _playNext();
    }
  }

  Future<String> _deviceSecret() async {
    final existing = await secure.read(key: 'deviceSecret');
    if (existing != null) return existing;
    final random = Random.secure();
    final value = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await secure.write(key: 'deviceSecret', value: value);
    return value;
  }

  Future<void> _configureDeviceRecovery(String? userId) async {
    final secret = await _deviceSecret();
    final bound = await secure.read(key: 'deviceBoundUser');
    api.recoverSession = bound == userId && userId != null
        ? () async {
            final result = Json.from(
              await api.post('/auth/device', {
                'deviceSecret': secret,
                'language': state.language,
              }),
            );
            if (result['user']?['id'] != userId) {
              throw Exception('The device profile changed. Please reconnect.');
            }
            return result;
          }
        : null;
  }

  Future<void> _bindCurrentDevice() async {
    final userId = state.user?['id'] as String?;
    if (userId == null) return;
    final generation = _sessionGeneration;
    final secret = await _deviceSecret();
    await api.ensureSession();
    _requireCurrent(generation);
    await api.post('/auth/device/link', {
      'deviceSecret': secret,
      'language': state.language,
    });
    _requireCurrent(generation);
    await secure.write(key: 'deviceBoundUser', value: userId);
    await _configureDeviceRecovery(userId);
  }

  Future<void> startWithoutLogin() async {
    final result = Json.from(
      await api.post('/auth/device', {
        'deviceSecret': await _deviceSecret(),
        'language': state.language,
      }),
    );
    await _acceptSession(result);
    await _bindCurrentDevice();
  }

  Future<void> fetchCapabilities() async {
    final generation = _sessionGeneration;
    try {
      final capabilities = Json.from(await api.get('/capabilities'));
      if (!_current(generation)) return;
      state = state.copy(capabilities: capabilities, clearError: true);
    } catch (e) {
      if (!_current(generation)) return;
      state = state.copy(error: ApiClient.describe(e));
    }
  }

  Future<void> configureServer(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !['https', 'http'].contains(uri.scheme)) {
      throw Exception(
        'Enter a valid HTTPS server URL, or HTTP for local development.',
      );
    }
    if (state.user != null) await logout();
    ++_sessionGeneration;
    api.clearSession();
    api.dio.options.baseUrl = url.replaceFirst(RegExp(r'/$'), '');
    await _saveSettings();
    await fetchCapabilities();
  }

  Future<void> reconnect() async {
    _retry?.cancel();
    ++_socketGeneration;
    await _socket?.sink.close();
    state = state.copy(connected: false);
    await fetchCapabilities();
    if (state.user != null && _foreground && !_disposed) {
      await sync();
      _connect();
    }
  }

  Future<void> loginDev(String name, String language) async {
    final generation = _sessionGeneration;
    state = state.copy(busy: true, clearError: true);
    try {
      final result = Json.from(
        await api.post('/auth/dev', {
          'displayName': name.trim(),
          'language': language,
        }),
      );
      if (!_current(generation)) return;
      await _acceptSession(result);
    } catch (e) {
      if (_current(generation)) {
        state = state.copy(error: ApiClient.describe(e));
      }
      rethrow;
    } finally {
      if (_current(generation)) state = state.copy(busy: false);
    }
  }

  Future<Json> requestOtp(String phone) async =>
      Json.from(await api.post('/auth/otp/request', {'phone': phone}));

  Future<Json> requestPhoneLogin(String phone) async =>
      Json.from(await api.post('/auth/phone/request', {'phone': phone}));
  Future<void> verifyPhoneLogin(
    String phone,
    String code,
    String name,
    String language,
  ) async {
    final generation = _sessionGeneration;
    state = state.copy(busy: true, clearError: true);
    try {
      final result = Json.from(
        await api.post('/auth/phone/verify', {
          'phone': phone,
          'code': code,
          'language': language,
          if (name.trim().isNotEmpty) 'displayName': name.trim(),
        }),
      );
      if (!_current(generation)) return;
      await _acceptSession(result);
    } catch (e) {
      if (_current(generation)) {
        state = state.copy(error: ApiClient.describe(e));
      }
      rethrow;
    } finally {
      if (_current(generation)) state = state.copy(busy: false);
    }
  }

  Future<void> verifyOtp(
    String phone,
    String code,
    String name,
    String language,
  ) async {
    final generation = _sessionGeneration;
    state = state.copy(busy: true, clearError: true);
    try {
      final result = Json.from(
        await api.post('/auth/otp/verify', {
          'phone': phone,
          'code': code,
          'displayName': name,
          'language': language,
        }),
      );
      if (!_current(generation)) return;
      await _acceptSession(result);
    } catch (e) {
      if (_current(generation)) {
        state = state.copy(error: ApiClient.describe(e));
      }
      rethrow;
    } finally {
      if (_current(generation)) state = state.copy(busy: false);
    }
  }

  Future<void> _acceptSession(Json result) async {
    final generation = ++_sessionGeneration;
    ++_socketGeneration;
    _retry?.cancel();
    _queueTimer?.cancel();
    _quietTimer?.cancel();
    _syncTimer?.cancel();
    _messageFetches.clear();
    _profilePending = {};
    _resyncRequested = false;
    _profileBase = null;
    _profileFlush = null;
    _socket?.sink.close();
    await _profileCache.catchError((_) {});
    await db.clear();
    if (!_current(generation)) return;
    _played.clear();
    _receipts.clear();
    _playQueue.clear();
    _playback = null;
    await audio.stopPlayback();
    if (!_current(generation)) return;
    api.acceptSession(result['accessToken'], result['refreshToken']);
    await _storeTokens(api.token!, api.refreshToken!, generation);
    if (!_current(generation)) return;
    final user = Json.from(result['user']);
    await db.write('user', user);
    if (!_current(generation)) return;
    state = AppState(
      loading: false,
      user: user,
      capabilities: state.capabilities,
      uiLanguage: state.uiLanguage,
    );
    await _saveSettings();
    await sync();
    _connect();
  }

  Future<void> sync() async {
    if (state.user == null || _disposed) return;
    if (_syncGeneration == _sessionGeneration) {
      _resyncRequested = true;
      return;
    }
    final generation = _sessionGeneration;
    _syncGeneration = generation;
    try {
      final groups = jsonList(await api.get('/groups'));
      if (!_current(generation)) return;
      final detailed = <Json>[];
      for (final group in groups) {
        detailed.add(Json.from(await api.get('/groups/${group['id']}')));
        if (!_current(generation)) return;
      }
      final messages = jsonList(await api.get('/messages'));
      final user = Json.from(await api.get('/users/me'));
      final usage = Json.from(await api.get('/usage'));
      final plans = jsonList(await api.get('/plans'));
      if (!_current(generation)) return;
      final mergedGroups = mergeTeamSnapshot(detailed, state.groups);
      _acceptProfile(user);
      state = state.copy(groups: _withOwnProfile(mergedGroups));
      await db.write('groups', state.groups);
      if (!_current(generation)) return;
      await db.write('messages', messages);
      if (!_current(generation)) return;
      await _cacheProfile();
      if (!_current(generation)) return;
      state = state.copy(
        groups: state.groups,
        messages: messages,
        user: state.user,
        usage: usage,
        plans: plans,
        online: true,
        clearError: true,
      );
      if (!detailed.any((g) => g['id'] == state.selectedGroupId)) {
        state = state.copy(
          selectedGroupId: detailed.isEmpty ? '' : detailed.first['id'],
          clearRecipient: true,
        );
      }
      unawaited(audio.prepareTranslationLanguage(state.language));
      unawaited(audio.prepareTranslationLanguage(state.listeningLanguage));
      await flushProfile();
      await flushOutbox();
    } catch (e) {
      if (!_current(generation)) return;
      state = state.copy(
        error: ApiClient.describe(e),
        online: ApiClient.isConnectionError(e) ? false : state.online,
      );
      if (ApiClient.isRateLimited(e) && _foreground) {
        _syncTimer?.cancel();
        _syncTimer = Timer(ApiClient.retryAfter(e), sync);
      }
    } finally {
      if (_syncGeneration == generation) _syncGeneration = null;
      if (_resyncRequested && _current(generation)) {
        _resyncRequested = false;
        unawaited(sync());
      }
    }
  }

  void selectGroup(String id) {
    state = state.copy(selectedGroupId: id, clearRecipient: true);
  }

  void selectRecipient(String? id) {
    state = state.copy(recipientId: id, clearRecipient: id == null);
  }

  Future<void> createGroup(String name, String description) async {
    await api.post('/groups', {
      'name': name.trim(),
      'description': description.trim(),
    });
    await sync();
    if (state.groups.isNotEmpty) selectGroup(state.groups.last['id']);
  }

  Future<void> joinGroup(String token) async {
    await api.post('/groups/join', {'token': token.trim()});
    await sync();
  }

  Future<Json> invite(String groupId) async => Json.from(
    await api.post('/groups/$groupId/invitations', {'expiresInHours': 24}),
  );
  Future<void> renameGroup(String id, String name, String description) async {
    await api.patch('/groups/$id', {'name': name, 'description': description});
    await sync();
  }

  Future<void> removeMember(String group, String user) async {
    await api.delete('/groups/$group/members/$user');
    await sync();
  }

  Future<void> leaveGroup(String id) async {
    await api.post('/groups/$id/leave');
    await sync();
  }

  Future<void> deleteGroup(String id) async {
    await api.delete('/groups/$id');
    await sync();
  }

  Future<void> linkPhoneLogin(String phone, String code) async {
    final generation = _sessionGeneration;
    final user = Json.from(
      await api.post('/auth/phone/link', {
        'phone': phone,
        'code': code,
        'language': state.language,
      }),
    );
    _requireCurrent(generation);
    state = state.copy(user: user);
    await db.write('user', user);
  }

  List<Json> _withOwnProfile(List<Json> groups) => groups
      .map(
        (group) => {
          ...group,
          'members': jsonList(group['members'])
              .map(
                (member) => member['userId'] == state.user?['id']
                    ? {
                        ...member,
                        ...{
                          for (final key in [
                            'displayName',
                            'spokenLanguage',
                            'listeningLanguage',
                            'version',
                            'updatedAt',
                          ])
                            key: state.user?[key],
                        },
                      }
                    : member,
              )
              .toList(),
        },
      )
      .toList();

  void _applyOwnProfile() {
    if (_profileBase == null) return;
    state = state.copy(
      user: normalizeMember({..._profileBase!, ..._profilePending}),
    );
    state = state.copy(groups: _withOwnProfile(state.groups));
  }

  void _acceptProfile(Json incoming) {
    if (incoming['id'] != state.user?['id']) return;
    final base = _profileBase ?? state.user!;
    if (memberVersion(incoming) >= memberVersion(base)) {
      _profileBase = normalizeMember(incoming);
    }
    _applyOwnProfile();
  }

  Future<void> _cacheProfile() {
    final generation = _sessionGeneration;
    final user = state.user, groups = state.groups;
    final pending = {
      'userId': user?['id'],
      'base': _profileBase,
      'changes': {..._profilePending},
    };
    return _profileCache = _profileCache.catchError((_) {}).then((_) async {
      if (!_current(generation)) return;
      await db.write('user', user);
      if (!_current(generation)) return;
      await db.write('pendingProfile', pending);
      if (!_current(generation)) return;
      await db.write('groups', groups);
    });
  }

  Future<void> updateProfile(Json data) async {
    if (state.user == null) throw Exception('Your session is unavailable.');
    _profileBase ??= normalizeMember(state.user!);
    _profilePending = {..._profilePending, ...data};
    _applyOwnProfile(); // Optimistic own UI, while authoritative version stays unchanged.
    for (final key in ['spokenLanguage', 'listeningLanguage']) {
      if (data[key] is String) unawaited(audio.prepareLanguage(data[key]));
    }
    await _cacheProfile();
    await flushProfile();
  }

  Future<void> flushProfile() async {
    if (_profileFlush != null) return _profileFlush!;
    if (_profilePending.isEmpty || state.user == null) return;
    final generation = _sessionGeneration;
    final operation = _persistProfile(generation);
    _profileFlush = operation;
    try {
      await operation;
    } finally {
      if (identical(_profileFlush, operation)) _profileFlush = null;
    }
  }

  Future<void> _persistProfile(int generation) async {
    var conflicts = 0;
    while (_current(generation) && _profilePending.isNotEmpty) {
      final changes = {..._profilePending};
      try {
        final result = Json.from(
          await api.patch('/users/me', {
            ...changes,
            if (memberVersion(_profileBase ?? state.user!) > 0)
              'expectedVersion': memberVersion(_profileBase ?? state.user!),
          }),
        );
        _requireCurrent(generation);
        for (final entry in changes.entries) {
          if (_profilePending[entry.key] == entry.value) {
            _profilePending.remove(entry.key);
          }
        }
        _acceptProfile(result);
        await _cacheProfile();
        conflicts = 0;
      } catch (e) {
        if (!_current(generation)) return;
        if (e is DioException &&
            e.response?.statusCode == 409 &&
            conflicts++ < 3) {
          _acceptProfile(Json.from(await api.get('/users/me')));
          _requireCurrent(generation);
          continue;
        }
        if (ApiClient.isRetryable(e)) {
          state = state.copy(
            error: 'Language/profile changes saved on this device. They will sync when the connection returns.',
          );
          await _cacheProfile();
          return; // No polling; reconnect/resume explicitly retries the saved changes.
        }
        for (final entry in changes.entries) {
          if (_profilePending[entry.key] == entry.value) {
            _profilePending.remove(entry.key);
          }
        }
        _applyOwnProfile();
        await _cacheProfile();
        rethrow;
      }
    }
  }

  Future<void> applyMemberState(Json event) async {
    final generation = _sessionGeneration;
    final groupId = event['groupId'];
    if (groupId is! String || !state.groups.any((g) => g['id'] == groupId)) {
      return;
    }
    final members = event['members'] is List
        ? jsonList(event['members'])
        : [Json.from(event['member'] as Map)];
    var changed = false;
    for (final member in members) {
      if (member['userId'] is! String || memberVersion(member) <= 0) continue;
      final group = state.groups.firstWhere((g) => g['id'] == groupId);
      final previous = jsonList(group['members'])
          .where((m) => m['userId'] == member['userId'])
          .firstOrNull;
      if (previous == null ||
          memberVersion(member) <= memberVersion(previous)) {
        continue;
      }
      changed = true;
      state = state.copy(groups: patchMember(state.groups, groupId, member));
      if (member['userId'] == state.user?['id'] &&
          memberVersion(member) > memberVersion(_profileBase ?? state.user!)) {
        _acceptProfile({
          ...(_profileBase ?? state.user!),
          ...member,
          'id': member['userId'],
        });
      }
    }
    if (changed) await _cacheProfile();
    if (!_current(generation)) return;
  }

  Future<Json?> send(Json payload, {String mode = 'group'}) async {
    final generation = _sessionGeneration;
    if (state.selectedGroupId == null || state.selectedGroupId!.isEmpty) {
      throw Exception('Create or join a group before sending.');
    }
    final outgoing = {
      ...payload,
      'processing': payload['processing'] ?? state.effectiveInputMode,
      'groupId': state.selectedGroupId,
      'sourceLanguage': payload['sourceLanguage'] ?? state.language,
      'mode': state.recipientId != null ? 'direct' : mode,
      if (state.recipientId != null) 'recipientId': state.recipientId,
    };
    if (outgoing['text'] != null) outgoing.remove('durationSeconds');
    await db.enqueue(outgoing);
    _requireCurrent(generation);
    await _loadOutbox();
    try {
      final result = Json.from(await api.post('/messages', outgoing));
      _requireCurrent(generation);
      await db.remove(outgoing['idempotencyKey']);
      await _loadOutbox();
      await sync();
      return result;
    } catch (e) {
      if (!_current(generation)) rethrow;
      if (ApiClient.isRetryable(e)) {
        if (ApiClient.isConnectionError(e)) state = state.copy(online: false);
        final delay = ApiClient.isRateLimited(e)
            ? ApiClient.retryAfter(e)
            : const Duration(seconds: 10);
        await db.retryLater(
          outgoing['idempotencyKey'],
          0,
          DateTime.now().add(delay).millisecondsSinceEpoch,
          ApiClient.describe(e),
        );
        await _loadOutbox();
        _queueTimer?.cancel();
        _queueTimer = Timer(delay, flushOutbox);
        return null;
      }
      await db.retryLater(
        outgoing['idempotencyKey'],
        99,
        0,
        ApiClient.describe(e),
      );
      await _loadOutbox();
      rethrow;
    }
  }

  Future<void> _loadOutbox() async {
    final generation = _sessionGeneration;
    final pending = await db.pending();
    if (_current(generation)) state = state.copy(outbox: pending);
  }

  Future<void> flushOutbox({bool manual = false}) async {
    if (state.user == null || _flushing) return;
    _flushing = true;
    try {
      final generation = _sessionGeneration;
      _queueTimer?.cancel();
      for (final item in await db.pending()) {
        if (!_current(generation)) return;
        final attempts = item['attempts'] as int;
        if (!manual &&
            (attempts >= 5 ||
                (item['retry_at'] as int) >
                    DateTime.now().millisecondsSinceEpoch)) {
          continue;
        }
        try {
          await api.post('/messages', item['payload']);
          if (!_current(generation)) return;
          await db.remove(item['id']);
        } catch (e) {
          if (!_current(generation)) return;
          final rateLimited = ApiClient.isRateLimited(e);
          final next = rateLimited
              ? attempts
              : ApiClient.isConnectionError(e)
              ? min(attempts + 1, 5)
              : 99;
          await db.retryLater(
            item['id'],
            next,
            DateTime.now().millisecondsSinceEpoch +
                (rateLimited
                    ? ApiClient.retryAfter(e).inMilliseconds
                    : (pow(2, min(next, 5)) * 2000).toInt()) +
                Random().nextInt(1000),
            ApiClient.describe(e),
          );
          break;
        }
      }
      await _loadOutbox();
      if (state.outbox.any((e) => (e['attempts'] as int) < 5) && _foreground) {
        _queueTimer = Timer(const Duration(seconds: 10), () => flushOutbox());
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> discardOutgoing(String id) async {
    await db.remove(id);
    await _loadOutbox();
  }

  Future<void> retryMessage(String id) async {
    await api.post('/messages/$id/retry');
    await sync();
  }

  Future<void> confirmMessage(String id) async {
    await api.post('/messages/$id/confirm');
    await sync();
  }

  Future<void> cancelMessage(String id) async {
    await api.post('/messages/$id/cancel');
    await sync();
  }

  Future<void> _connect() async {
    if (api.token == null ||
        !_foreground ||
        _disposed ||
        _connecting ||
        state.connected) {
      return;
    }
    _connecting = true;
    final session = _sessionGeneration;
    try {
      await api.ensureSession();
    } catch (e) {
      _connecting = false;
      if (_current(session)) {
        state = state.copy(error: ApiClient.describe(e));
        _disconnected();
      }
      return;
    }
    _connecting = false;
    if (!_current(session) || !_foreground || state.connected) return;
    final generation = ++_socketGeneration;
    _retry?.cancel();
    _socket?.sink.close();
    final uri = Uri.parse(api.dio.options.baseUrl);
    _socket = WebSocketChannel.connect(
      uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '${uri.path}/realtime',
      ),
    );
    final socket = _socket!;
    socket.ready
        .then((_) {
          if (generation != _socketGeneration || _disposed) return;
          socket.sink.add(
            jsonEncode({'type': 'authenticate', 'accessToken': api.token}),
          );
        })
        .catchError((_) {
          if (generation == _socketGeneration) _disconnected();
        });
    socket.stream.listen(
      (event) async {
        if (generation != _socketGeneration || _disposed) return;
        try {
          final data = Json.from(jsonDecode(event));
          if (data['type'] == 'authenticated') {
            state = state.copy(connected: true);
            _reconnections = 0;
            if (_syncGeneration == _sessionGeneration) {
              _resyncRequested = true;
            } else {
              unawaited(sync());
            }
          }
          if (data['type'] == 'member.language.updated' ||
              data['type'] == 'team.members.snapshot') {
            await applyMemberState(Json.from(data['data']));
          }
          if (data['type'] == 'message.ready' ||
              data['type'] == 'message.updated') {
            final eventData = Json.from(data['data']);
            final id = eventData['messageId'] ?? eventData['id'];
            if (id == null) return;
            await receiveMessageEvent(id.toString());
            if (generation != _socketGeneration || _disposed) return;
          }
          if (data['type'] == 'message.receipt') {
            await applyReceipt(Json.from(data['data']));
          }
          if (data['type'] == 'group.updated') {
            _syncTimer?.cancel();
            _syncTimer = Timer(const Duration(milliseconds: 500), sync);
          }
        } catch (e) {
          if (generation == _socketGeneration && !_disposed) {
            state = state.copy(error: ApiClient.describe(e));
          }
        }
      },
      onError: (_) {
        if (generation == _socketGeneration) _disconnected();
      },
      onDone: () {
        if (generation == _socketGeneration) _disconnected();
      },
      cancelOnError: true,
    );
  }

  void _disconnected() {
    if (_disposed) return;
    state = state.copy(connected: false);
    if (_foreground && state.user != null) {
      final seconds = min(30, pow(2, min(_reconnections++, 5)).toInt());
      _retry?.cancel();
      _retry = Timer(
        Duration(milliseconds: seconds * 1000 + Random().nextInt(1000)),
        () async {
          await sync();
          if (!_disposed && state.user != null && _foreground) _connect();
        },
      );
    }
  }

  // An event contains only an ID. Always fetch and authorize the message on
  // the server, including when a future native notification calls this entry.
  Future<void> applyReceipt(Json receipt) async {
    final generation = _sessionGeneration;
    const order = [
      'PENDING',
      'DELIVERED',
      'PLAYBACK_STARTED',
      'PLAYBACK_COMPLETED',
    ];
    if (!order.contains(receipt['state']) && receipt['state'] != 'FAILED') {
      return;
    }
    bool changed = false;
    final messages = state.messages.map((message) {
      if (message['id'] != receipt['messageId']) return message;
      final recipients = jsonList(message['recipients']).map((recipient) {
        if (recipient['userId'] != receipt['userId']) return recipient;
        final previous = recipient['state'];
        final incoming = receipt['state'];
        if (previous == incoming ||
            previous == 'PLAYBACK_COMPLETED' ||
            (incoming != 'FAILED' &&
                previous != 'FAILED' &&
                order.indexOf(incoming) < order.indexOf(previous))) {
          return recipient;
        }
        changed = true;
        return {...recipient, 'state': incoming};
      }).toList();
      return {...message, 'recipients': recipients};
    }).toList();
    if (!changed || !_current(generation)) return;
    state = state.copy(messages: messages);
    await db.write('messages', messages);
  }

  Future<void> receiveMessageEvent(String id) {
    final existing = _messageFetches[id];
    if (existing != null) return existing;
    final pending = _receiveMessageEvent(id);
    _messageFetches[id] = pending;
    pending.whenComplete(() {
      if (identical(_messageFetches[id], pending)) _messageFetches.remove(id);
    }).ignore();
    return pending;
  }

  Future<void> _receiveMessageEvent(String id) async {
    final generation = _sessionGeneration;
    _requireCurrent(generation);
    final message = Json.from(await api.get('/messages/$id'));
    _requireCurrent(generation);
    final messages = [...state.messages];
    final index = messages.indexWhere((m) => m['id'] == id);
    if (index < 0) {
      messages.insert(0, message);
    } else {
      messages[index] = message;
    }
    state = state.copy(messages: messages);
    await db.write('messages', messages);
    _requireCurrent(generation);
    final me = state.user!['id'];
    final recipient = jsonList(message['recipients'])
        .where((r) => r['userId'] == me)
        .firstOrNull;
    if (message['state'] != 'READY' ||
        message['senderId'] == me ||
        recipient == null) {
      return;
    }
    if (recipient['state'] == 'PENDING') {
      try {
        await api.post('/messages/$id/ack', {'state': 'DELIVERED'});
      } catch (_) {
        // Delivery acknowledgement can fail; playback receipts never stand in
        // for this event, and playback will reauthorize/ack before starting.
      }
    }
    _requireCurrent(generation);
    if (['PENDING', 'DELIVERED'].contains(recipient['state']) &&
        _allowsAutomatic(message) &&
        !_played.contains(id)) {
      _played.add(id);
      _playQueue.add(message);
      _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_disposed ||
        _playback != null ||
        _playQueue.isEmpty ||
        !_foreground ||
        !state.receiving ||
        !['automatic', 'headphones'].contains(state.receiveMode) ||
        _capturing ||
        audio.recording ||
        audio.dictating) {
      return;
    }
    final generation = _sessionGeneration;
    final message = _playQueue.removeAt(0);
    if (!_allowsAutomatic(message)) {
      _playNext();
      return;
    }
    try {
      await playTranslation(
        message['id'],
        state.listeningLanguage,
        automatic: true,
      );
    } catch (e) {
      if (!_current(generation)) return;
      if (e is! _PlaybackCancelled) {
        state = state.copy(error: ApiClient.describe(e));
      }
    }
  }

  Future<String> translationText(Json message, Json translation) async {
    if (message['processing'] == 'voice') {
      return 'Original voice · ${message['durationSeconds']?.round() ?? 0}s';
    }
    final generation = _sessionGeneration;
    _requireCurrent(generation);
    if (translation['needsDeviceTranslation'] != true) {
      return translation['text']?.toString() ?? '';
    }
    final text = await audio.translateOnDevice(
      message['sourceText']?.toString() ?? '',
      message['sourceLanguage'],
      translation['language'],
    );
    _requireCurrent(generation);
    return text;
  }

  Future<void> playMessage(Json message) async {
    await playTranslation(message['id'], state.listeningLanguage);
  }

  Future<void> playLocalText(String id, String text, String language) async {
    final generation = _sessionGeneration;
    final audioGeneration = _audioGeneration;
    _requireCurrent(generation);
    final previous = _playback;
    final request = _PlaybackRequest(id, generation, false);
    _playback = request;
    state = state.copy(clearSpeaker: true);
    try {
      if (previous != null) await audio.stopPlayback();
      _requireCurrent(generation);
      if (!identical(_playback, request) ||
          audioGeneration != _audioGeneration) {
        throw _PlaybackCancelled();
      }
      if (!_foreground || _capturing || audio.recording || audio.dictating) {
        throw Exception(
          'Open the app and finish recording before playing audio.',
        );
      }
      await audio.speak(
        id,
        text,
        language,
        headphonesOnly:
            state.receiveMode == 'headphones' || state.headphonesOnly,
        playbackRequestId: request.id,
      );
    } catch (_) {
      if (identical(_playback, request)) {
        _playback = null;
        state = state.copy(clearSpeaker: true);
        _playNext();
      }
      rethrow;
    }
  }

  Future<void> playTranslation(
    String id,
    String language, {
    bool automatic = false,
  }) async {
    final generation = _sessionGeneration;
    final audioGeneration = _audioGeneration;
    _requireCurrent(generation);
    if (automatic && _playback != null) throw _PlaybackCancelled();
    final previous = _playback;
    final request = _PlaybackRequest(id, generation, automatic);
    // Reserve before authorization so an arriving message waits even while
    // manual replay is fetching data. Explicit replay replaces old playback.
    _playback = request;
    state = state.copy(clearSpeaker: true);
    void checkCurrent() {
      _requireCurrent(generation);
      if (!identical(_playback, request) ||
          audioGeneration != _audioGeneration) {
        throw _PlaybackCancelled();
      }
    }

    try {
      if (previous != null) await audio.stopPlayback();
      checkCurrent();
      // Reauthorize at playback time. Membership may have changed since delivery.
      final authorized = Json.from(await api.get('/messages/$id'));
      checkCurrent();
      if (automatic && !_allowsAutomatic(authorized)) {
        throw _PlaybackCancelled();
      }
      if (authorized['state'] != 'READY' &&
          authorized['senderId'] != state.user?['id']) {
        throw Exception('The sender has not released this translation yet.');
      }
      final available = jsonList(authorized['translations']);
      final target = authorized['senderId'] == state.user?['id']
          ? language
          : state.listeningLanguage;
      final translation = authorized['processing'] == 'voice'
          ? available.firstOrNull
          : authorized['processing'] == 'device'
          ? <String, dynamic>{
              'language': target,
              'text': authorized['sourceText'],
              'needsDeviceTranslation': authorized['sourceLanguage'] != target,
            }
          : available.where((t) => t['language'] == target).firstOrNull;
      if (translation == null) {
        throw Exception('No translation in your listening language is ready.');
      }
      if (authorized['senderId'] != state.user?['id']) {
        await api.post('/messages/$id/ack', {'state': 'DELIVERED'});
        checkCurrent();
        request.incoming = true;
      }
      if (automatic && !_allowsAutomatic(authorized)) {
        throw _PlaybackCancelled();
      }
      if (!_foreground || _capturing || audio.recording || audio.dictating) {
        throw Exception(
          'Open the app and finish recording before playing audio.',
        );
      }
      await api.ensureSession();
      checkCurrent();
      final spokenText = authorized['processing'] == 'voice'
          ? ''
          : await translationText(authorized, translation);
      checkCurrent();
      if (authorized['senderId'] != state.user?['id'] &&
          target != state.listeningLanguage) {
        throw _PlaybackCancelled();
      }
      if (automatic &&
          translation['needsDeviceTranslation'] == true &&
          AudioService.quantitiesChanged(
            authorized['sourceText'] ?? '',
            spokenText,
          )) {
        throw Exception(
          'The translated numbers changed. Open the message and check the translation before playing it.',
        );
      }
      if (!_foreground || _capturing || audio.recording || audio.dictating) {
        throw _PlaybackCancelled();
      }
      final deadline = automatic
          ? state.policy.nextBoundary(DateTime.now())?.millisecondsSinceEpoch
          : null;
      if (!kIsWeb && translation['audioUrl'] != null) {
        final base = Uri.parse(api.dio.options.baseUrl);
        final url = base.resolve(translation['audioUrl']);
        if (url.origin != base.origin) {
          throw Exception('Audio must come from your authorized server.');
        }
        await audio.playRemote(
          id,
          url.toString(),
          {'Authorization': 'Bearer ${api.token}'},
          headphonesOnly:
              state.receiveMode == 'headphones' || state.headphonesOnly,
          stopAtEpochMillis: deadline,
          playbackRequestId: request.id,
        );
      } else {
        await audio.speak(
          authorized['id'],
          spokenText,
          translation['language'],
          headphonesOnly:
              state.receiveMode == 'headphones' || state.headphonesOnly,
          stopAtEpochMillis: deadline,
          playbackRequestId: request.id,
        );
      }
    } catch (_) {
      if (identical(_playback, request)) {
        _playback = null;
        state = state.copy(clearSpeaker: true);
        _playNext();
      }
      rethrow;
    }
  }

  Future<void> setReceiving(bool active) async {
    if (active && kIsWeb) {
      throw Exception(
        'Automatic receiving requires the mobile app. Replay messages manually in this browser.',
      );
    }
    final generation = _sessionGeneration;
    final audioGeneration = ++_audioGeneration;
    if (!active) {
      state = state.copy(receiving: false);
      _playQueue.clear();
      _playback = null;
      state = state.copy(clearSpeaker: true);
    }
    await audio.receive(active);
    if (!_current(generation) || audioGeneration != _audioGeneration) return;
    state = state.copy(receiving: active);
    if (!active) {
      _playQueue.clear();
      _playback = null;
      state = state.copy(clearSpeaker: true);
      await audio.stopPlayback();
    }
  }

  Future<void> pauseForCapture() async {
    _capturing = true;
    ++_audioGeneration;
    _playback = null;
    await audio.stopPlayback();
  }

  void resumeAfterCapture() {
    _capturing = false;
    if (!_disposed) _playNext();
  }

  Future<void> settings({
    String? inputMode,
    String? receiveMode,
    String? uiLanguage,
    bool? headphonesOnly,
    ReceivingPolicy? policy,
  }) async {
    final generation = _sessionGeneration;
    if (policy != null) {
      state = state.copy(policy: policy);
      ++_audioGeneration;
      _playQueue.clear();
      if (_playback?.automatic == true) {
        _playback = null;
        state = state.copy(clearSpeaker: true);
        await audio.stopPlayback();
      }
      if (!_current(generation)) return;
      _scheduleQuietHours();
    }
    if ((receiveMode != null && receiveMode != state.receiveMode) ||
        (headphonesOnly != null && headphonesOnly != state.headphonesOnly)) {
      ++_audioGeneration;
      _playQueue.clear();
      _playback = null;
      state = state.copy(clearSpeaker: true);
      state = state.copy(receiveMode: receiveMode);
      await audio.stopPlayback();
      if (!_current(generation)) return;
      if (receiveMode != null &&
          ['silent', 'notification'].contains(receiveMode)) {
        await setReceiving(false);
        if (!_current(generation)) return;
      }
    }
    state = state.copy(
      inputMode: inputMode,
      receiveMode: receiveMode,
      uiLanguage: uiLanguage,
      headphonesOnly: headphonesOnly,
    );
    await _saveSettings();
  }

  Future<void> _saveSettings() => db.write('settings', {
    'baseUrl': api.dio.options.baseUrl,
    'receiveMode': state.receiveMode,
    'inputMode': state.inputMode,
    'headphonesOnly': state.headphonesOnly,
    'uiLanguage': state.uiLanguage,
    'receivingPolicy': state.policy.toJson(),
  });

  bool _allowsAutomatic(Json message) =>
      state.receiving &&
      ['automatic', 'headphones'].contains(state.receiveMode) &&
      state.policy.allowsGroup(
        message['groupId']?.toString() ?? '',
        DateTime.now(),
      );

  Future<void> muteGroup(String id, bool muted) =>
      settings(policy: state.policy.mute(id, muted));

  void _scheduleQuietHours() {
    _quietTimer?.cancel();
    if (_disposed || state.user == null) return;
    final now = DateTime.now();
    final next = state.policy.nextBoundary(now);
    if (next != null) {
      _quietTimer = Timer(next.difference(now), _checkQuietHours);
    }
  }

  void _checkQuietHours() {
    if (_disposed) return;
    if (state.policy.isQuiet(DateTime.now())) {
      _playQueue.clear();
      if (_playback?.automatic == true) {
        ++_audioGeneration;
        _playback = null;
        state = state.copy(clearSpeaker: true);
        audio.stopPlayback().catchError((Object _) {});
      }
    }
    state = state.copy();
    _scheduleQuietHours();
  }

  Future<Json> exportData() async =>
      Json.from(await api.get('/privacy/export'));
  Future<void> deleteAccount() async {
    await api.delete('/users/me', {'confirmation': 'DELETE'});
    await logout();
  }

  Future<void> logout() async {
    final generation = ++_sessionGeneration;
    ++_audioGeneration;
    ++_socketGeneration;
    final access = api.token, refresh = api.refreshToken;
    api.clearSession();
    state = AppState(
      loading: true,
      capabilities: state.capabilities,
      uiLanguage: state.uiLanguage,
    );
    final revocation = access == null
        ? Future.value()
        : api.dio
              .post(
                '/auth/logout',
                data: {'refreshToken': refresh},
                options: Options(headers: {'Authorization': 'Bearer $access'}),
              )
              .then((_) {})
              .catchError((_) {});
    _retry?.cancel();
    _queueTimer?.cancel();
    _quietTimer?.cancel();
    _syncTimer?.cancel();
    _messageFetches.clear();
    _profilePending = {};
    _profileBase = null;
    _profileFlush = null;
    _resyncRequested = false;
    _socket?.sink.close();
    try {
      await audio.cancel();
      await audio.receive(false);
      await audio.stopPlayback();
    } catch (_) {}
    _playQueue.clear();
    _playback = null;
    _capturing = false;
    await (_secureOperations = _secureOperations
        .catchError((_) {})
        .then((_) => secure.deleteAll()));
    await _profileCache.catchError((_) {});
    await db.clear();
    if (!_current(generation)) return;
    _played.clear();
    _receipts.clear();
    state = AppState(
      loading: false,
      capabilities: state.capabilities,
      uiLanguage: state.uiLanguage,
    );
    await _saveSettings();
    await revocation;
  }

  void clearError() {
    state = state.copy(clearError: true);
  }
}
