import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/api.dart';

class LimitedAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    calls++;
    return ResponseBody.fromString(
      '{"code":"RATE_LIMITED"}',
      429,
      headers: {
        'content-type': ['application/json'],
        'retry-after': ['30'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'server cooldown blocks repeated network calls without retrying writes',
    () async {
      final api = ApiClient();
      final adapter = LimitedAdapter();
      api.dio.httpClientAdapter = adapter;
      for (var i = 0; i < 10; i++) {
        await expectLater(
          api.post('/messages', {'text': 'Test'}),
          throwsA(isA<DioException>()),
        );
      }
      expect(adapter.calls, 1);
      // Receipts and reads have an independent budget from sending.
      await expectLater(api.get('/messages'), throwsA(isA<DioException>()));
      expect(adapter.calls, 2);
      api.dio.close(force: true);
    },
  );
  test('429 is retryable, unlike authorization failures', () {
    final options = RequestOptions(path: '/messages');
    final limited = DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: 429,
        headers: Headers.fromMap({
          'retry-after': ['42'],
        }),
      ),
    );
    expect(ApiClient.isRetryable(limited), true);
    expect(ApiClient.retryAfter(limited), const Duration(seconds: 42));
    final denied = DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 403),
    );
    expect(ApiClient.isRetryable(denied), false);
  });
}
