import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Drift SQL store without generated models. Content is local to this device;
/// every account switch purges it. OS disk protection applies; not E2EE.
class LocalStore extends GeneratedDatabase {
  LocalStore([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'mine2yourlingo',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.dart.js'),
              ),
            ),
      );
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, retry_at INTEGER NOT NULL DEFAULT 0, error TEXT)',
      );
    },
  );
  Future<dynamic> read(String key) async {
    final rows = await customSelect(
      'SELECT value FROM cache WHERE key = ?',
      variables: [Variable(key)],
    ).get();
    return rows.isEmpty ? null : jsonDecode(rows.first.read<String>('value'));
  }

  Future<void> write(String key, dynamic value) => customStatement(
    'INSERT OR REPLACE INTO cache (key,value) VALUES (?,?)',
    [key, jsonEncode(value)],
  );
  Future<void> enqueue(Map<String, dynamic> payload) => customStatement(
    'INSERT OR IGNORE INTO outbox (id,payload) VALUES (?,?)',
    [payload['idempotencyKey'], jsonEncode(payload)],
  );
  Future<List<Map<String, dynamic>>> pending() async =>
      (await customSelect('SELECT * FROM outbox ORDER BY rowid').get())
          .map(
            (r) => {
              ...r.data,
              'payload': jsonDecode(r.read<String>('payload')),
            },
          )
          .toList();
  Future<void> remove(String id) =>
      customStatement('DELETE FROM outbox WHERE id = ?', [id]);
  Future<void> retryLater(String id, int attempts, int retryAt, String error) =>
      customStatement(
        'UPDATE outbox SET attempts = ?, retry_at = ?, error = ? WHERE id = ?',
        [attempts, retryAt, error, id],
      );
  Future<void> clear() async {
    await customStatement('DELETE FROM cache');
    await customStatement('DELETE FROM outbox');
  }
}
