// Real local HTTP checks through the production mobile Dio client.
// Uses isolated English identities: no cloud translation/provider fixture.
import 'dart:async';
import 'dart:io';

import 'package:mine2yourlingo/core/api.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  final base = Platform.environment['API_URL'] ?? 'http://127.0.0.1:3100/v1';
  final uri = Uri.parse(base);
  if (!['127.0.0.1', 'localhost', '::1'].contains(uri.host)) {
    throw StateError(
      'This destructive fixture test only permits loopback APIs.',
    );
  }
  final sender = ApiClient(baseUrl: base), receiver = ApiClient(baseUrl: base);
  var checks = 0;
  void check(bool value, String description) {
    if (!value) throw StateError(description);
    checks++;
  }

  try {
    final capabilities = await sender.get('/capabilities');
    check(capabilities['developmentAuth'] == true, 'Isolated auth is required');
    for (final entry in [
      (sender, 'Contract sender'),
      (receiver, 'Contract receiver'),
    ]) {
      final session = await entry.$1.post('/auth/dev', {
        'displayName': entry.$2,
        'language': 'en',
      });
      entry.$1.acceptSession(session['accessToken'], session['refreshToken']);
      check(
        session['mode'] == 'development-simulator',
        'Simulator is labelled',
      );
    }
    final group = await sender.post('/groups', {
      'name': 'Ephemeral mobile contract check',
      'description': 'Automatically removed after verification',
    });
    final id = group['id'];
    final invitation = await sender.post('/groups/$id/invitations', {
      'expiresInHours': 1,
    });
    check(invitation['token'] is String, 'Invitation contains a real token');
    await receiver.post('/groups/join', {'token': invitation['token']});
    final joined = await receiver.get('/groups/$id');
    check(joined['members'].length == 2, 'Authorized private membership');
    final key = const Uuid().v4();
    final payload = {
      'groupId': id,
      'sourceLanguage': 'en',
      'text': 'Hello team',
      'mode': 'group',
      'idempotencyKey': key,
    };
    final created = await sender.post('/messages', payload);
    final duplicate = await sender.post('/messages', payload);
    check(created['id'] == duplicate['id'], 'Idempotency creates one message');
    dynamic message;
    for (var attempt = 0; attempt < 40; attempt++) {
      message = await receiver.get('/messages/${created['id']}');
      if (message['state'] != 'PROCESSING') break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(message['state'] == 'READY', 'Same-language message is ready');
    check(
      message['translations'].single['text'] == 'Hello team',
      'Same-language text preserved',
    );
    check(
      message['translations'].single['provider'] ==
          'source-language-passthrough',
      'No AI translation claim',
    );
    for (final state in [
      'DELIVERED',
      'PLAYBACK_STARTED',
      'PLAYBACK_COMPLETED',
    ]) {
      final receipt = await receiver.post('/messages/${created['id']}/ack', {
        'state': state,
      });
      check(receipt['state'] == state, 'Ordered receipt accepted: $state');
    }
    final finalMessage = await sender.get('/messages/${created['id']}');
    check(
      finalMessage['recipients'].single['state'] == 'PLAYBACK_COMPLETED',
      'Sender sees final receipt',
    );
    final usage = await sender.get('/usage');
    check(usage['messages'] == 1, 'Idempotency metered once');
    stdout.writeln('$checks live mobile-client HTTP contract checks passed.');
    stdout.writeln(
      'Receipt transitions were submitted by this test; no audio playback or cross-language quality was tested.',
    );
  } finally {
    for (final client in [receiver, sender]) {
      if (client.token != null) {
        await client.delete('/users/me', {'confirmation': 'DELETE'});
      }
      client.dio.close(force: true);
    }
  }
}
