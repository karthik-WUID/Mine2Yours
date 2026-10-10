import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/local_store.dart';

void main() {
  late LocalStore db;
  setUp(() => db = LocalStore(NativeDatabase.memory()));
  tearDown(() => db.close());
  test(
    'repeated outbox enqueue preserves the first idempotent submission',
    () async {
      await db.enqueue({'idempotencyKey': 'key', 'text': 'first'});
      await db.enqueue({'idempotencyKey': 'key', 'text': 'second'});
      final pending = await db.pending();
      expect(pending.length, 1);
      expect(pending.single['payload']['text'], 'first');
      await db.retryLater('key', 2, 9000, 'Connection unavailable');
      expect((await db.pending()).single['retry_at'], 9000);
      await db.remove('key');
      expect(await db.pending(), isEmpty);
    },
  );
  test('account switch clears transcripts and pending content', () async {
    await db.write('messages', [
      {'sourceText': 'private content'},
    ]);
    await db.enqueue({'idempotencyKey': 'key', 'text': 'private content'});
    await db.clear();
    expect(await db.read('messages'), isNull);
    expect(await db.pending(), isEmpty);
  });
}
