import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/api.dart';

class RealHttp extends HttpOverrides {}

void main() {
  test('expired concurrent requests rotate once and native audio gets the refreshed token', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var rotations = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/refresh') {
          rotations++;
          await request.drain<void>();
          await Future<void>.delayed(const Duration(milliseconds: 40));
          request.response.write(jsonEncode({'accessToken': 'fresh-access', 'refreshToken': 'fresh-refresh'}));
        } else if (request.headers.value('Authorization') != 'Bearer fresh-access') {
          request.response.statusCode = 401;
          request.response.write(jsonEncode({'message': 'Unauthorized'}));
        } else {
          request.response.write(jsonEncode({'id': 'same-device-user'}));
        }
        await request.response.close();
      });
      final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      api.acceptSession('expired-access', 'valid-refresh');
      var persisted = 0;
      api.onTokens = (_, _) async { persisted++; };
      try {
        final results = await Future.wait([api.get('/users/me'), api.get('/messages')]);
        expect(results.every((r) => r['id'] == 'same-device-user'), true);
        expect(rotations, 1);
        expect(persisted, 1);
        await api.ensureSession();
        expect(api.token, 'fresh-access');
      } finally { api.dio.close(force: true); await server.close(force: true); }
    }, RealHttp());
  });

  test('invalid refresh transparently recovers the bound device without a login prompt', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/refresh' || request.headers.value('Authorization') != 'Bearer recovered-access') {
          request.response.statusCode = 401;
          request.response.write(jsonEncode({'message': 'Unauthorized'}));
        } else { request.response.write(jsonEncode({'id': 'same-device-user'})); }
        await request.response.close();
      });
      final api = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
      api.acceptSession('expired-access', 'expired-refresh');
      var recovered = 0;
      api.recoverSession = () async { recovered++; return {'accessToken': 'recovered-access', 'refreshToken': 'recovered-refresh'}; };
      try { await api.ensureSession(); expect(recovered, 1); expect(api.token, 'recovered-access'); }
      finally { api.dio.close(force: true); await server.close(force: true); }
    }, RealHttp());
  });
}
