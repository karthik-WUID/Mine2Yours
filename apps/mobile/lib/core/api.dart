import 'package:dio/dio.dart';

class ApiClient {
  static const defaultBase = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3100/v1',
  );
  static const migrateUsbReview = bool.fromEnvironment('MIGRATE_USB_REVIEW');
  static const reviewPreviousBase = String.fromEnvironment(
    'REVIEW_PREVIOUS_API_URL',
  );
  static const _debugBuild =
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.vm.profile');

  /// Explicit debug-only move of this review's existing backend to the internet review endpoint.
  /// Custom server settings and release builds retain their saved endpoint.
  static String restoreBase(String? saved) {
    if (saved == null) return defaultBase;
    if (_debugBuild &&
        migrateUsbReview &&
        (const {
              'http://127.0.0.1:3100/v1',
              'http://localhost:3100/v1',
            }.contains(saved) ||
            (reviewPreviousBase.isNotEmpty && saved == reviewPreviousBase))) {
      return defaultBase;
    }
    return saved;
  }

  final Dio dio;
  String? token;
  String? refreshToken;
  int sessionGeneration = 0;
  Future<void> Function(String, String)? onTokens;
  Future<Map<String, dynamic>>? _refreshing;
  final _cooldowns = <String, DateTime>{};
  static String _bucket(String path, String method) => path.contains('/auth/')
      ? 'auth'
      : path.contains('/messages') && method == 'POST' && !path.endsWith('/ack')
      ? 'message'
      : 'api';
  Future<Map<String, dynamic>> Function()? recoverSession;
  ApiClient({String baseUrl = defaultBase})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          final until = _cooldowns[_bucket(o.path, o.method)];
          if (until != null && until.isAfter(DateTime.now())) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: o,
                  statusCode: 429,
                  headers: Headers.fromMap({
                    'retry-after': [
                      '${until.difference(DateTime.now()).inSeconds + 1}',
                    ],
                  }),
                  data: {
                    'code': 'RATE_LIMITED',
                    'localCooldown': true,
                    'message': 'Please wait a moment. Your message will send automatically.',
                  },
                ),
              ),
            );
            return;
          }
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
          h.next(o);
        },
        onError: (e, h) async {
          if (isRateLimited(e) &&
              !(e.response?.data is Map &&
                  e.response?.data['localCooldown'] == true)) {
            _cooldowns[_bucket(
              e.requestOptions.path,
              e.requestOptions.method,
            )] = DateTime.now().add(
              retryAfter(e),
            );
          }
          if (e.response?.statusCode == 401 &&
              refreshToken != null &&
              e.requestOptions.extra['retried'] != true &&
              !e.requestOptions.path.contains('/auth/')) {
            final generation = sessionGeneration;
            // A delayed 401 may belong to the token another request already replaced.
            if (token != null &&
                e.requestOptions.headers['Authorization'] != 'Bearer $token') {
              e.requestOptions.extra['retried'] = true;
              e.requestOptions.headers['Authorization'] = 'Bearer $token';
              try {
                return h.resolve(await dio.fetch(e.requestOptions));
              } catch (_) {
                h.next(e);
                return;
              }
            }
            final pending = _refreshing ??= _refreshSession(generation);
            try {
              await pending;
              if (generation != sessionGeneration) {
                h.next(e);
                return;
              }
              e.requestOptions.extra['retried'] = true;
              e.requestOptions.headers['Authorization'] = 'Bearer $token';
              return h.resolve(await dio.fetch(e.requestOptions));
            } catch (_) {
              h.next(e);
            } finally {
              if (identical(pending, _refreshing)) _refreshing = null;
            }
          } else {
            h.next(e);
          }
        },
      ),
    );
  }
  void clearSession() {
    ++sessionGeneration;
    token = null;
    refreshToken = null;
    _refreshing = null;
  }

  void acceptSession(String access, String refresh) {
    ++sessionGeneration;
    token = access;
    refreshToken = refresh;
    _refreshing = null;
  }

  Future<Map<String, dynamic>> _refreshSession(int generation) async {
    final result = await _rotate();
    if (generation != sessionGeneration) {
      throw Exception('The session changed.');
    }
    token = result['accessToken'];
    refreshToken = result['refreshToken'];
    await onTokens?.call(token!, refreshToken!);
    if (generation != sessionGeneration) {
      throw Exception('The session changed.');
    }
    return result;
  }

  Future<Map<String, dynamic>> _rotate() async {
    try {
      return Map<String, dynamic>.from(
        (await Dio(
          BaseOptions(
            baseUrl: dio.options.baseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
        ).post('/auth/refresh', data: {'refreshToken': refreshToken})).data,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 && recoverSession != null) {
        return await recoverSession!();
      }
      rethrow;
    }
  }

  Future<void> ensureSession() async {
    await get('/users/me');
  }

  Future<dynamic> get(String path) async => (await dio.get(path)).data;
  Future<dynamic> post(String path, [dynamic data]) async =>
      (await dio.post(path, data: data)).data;
  Future<dynamic> patch(String path, dynamic data) async =>
      (await dio.patch(path, data: data)).data;
  Future<dynamic> delete(String path, [dynamic data]) async =>
      (await dio.delete(path, data: data)).data;
  static bool isRateLimited(Object error) =>
      error is DioException && error.response?.statusCode == 429;
  static bool isRetryable(Object error) =>
      isConnectionError(error) || isRateLimited(error);
  static Duration retryAfter(Object error) {
    if (error is DioException) {
      final header = error.response?.headers.value('retry-after');
      final seconds = int.tryParse(header ?? '');
      if (seconds != null) return Duration(seconds: seconds.clamp(1, 300));
      final date = DateTime.tryParse(header ?? '');
      if (date != null) {
        return Duration(
          milliseconds: date
              .difference(DateTime.now())
              .inMilliseconds
              .clamp(1000, 300000),
        );
      }
    }
    return const Duration(seconds: 60);
  }

  static bool isConnectionError(Object error) =>
      error is DioException &&
      [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ].contains(error.type);
  static String describe(Object error) {
    if (error is DioException) {
      if (isRateLimited(error)) return 'Server is busy. Please wait a moment.';
      final data = error.response?.data;
      if (data is Map) {
        final message = data['message'] ?? data['error'];
        if (message is List) return message.join('. ');
        if (message != null) return message.toString();
      }
      if (isConnectionError(error)) {
        return 'Cannot connect right now. Check your internet connection and try again.';
      }
      return 'Request failed (${error.response?.statusCode ?? 'network error'}). Please try again.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
