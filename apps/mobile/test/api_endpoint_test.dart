import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/api.dart';

void main() {
  test('fresh install uses the build endpoint', () {
    expect(ApiClient.restoreBase(null), ApiClient.defaultBase);
  });
  test('USB review migration needs an explicit build opt-in', () {
    const old = 'http://127.0.0.1:3100/v1';
    expect(
      ApiClient.restoreBase(old),
      ApiClient.migrateUsbReview ? ApiClient.defaultBase : old,
    );
    const localhost = 'http://localhost:3100/v1';
    expect(
      ApiClient.restoreBase(localhost),
      ApiClient.migrateUsbReview ? ApiClient.defaultBase : localhost,
    );
  });
  test(
    'custom servers are preserved instead of moving session credentials',
    () {
      for (final custom in [
        'https://other.example/v1',
        'http://192.168.2.10:3100/v1',
        'http://127.0.0.1:3200/v1',
        'http://localhost:3100/other',
      ]) {
        expect(ApiClient.restoreBase(custom), custom);
      }
    },
  );
  test('only the explicitly named previous review endpoint can move', () {
    if (ApiClient.reviewPreviousBase.isNotEmpty) {
      expect(
        ApiClient.restoreBase(ApiClient.reviewPreviousBase),
        ApiClient.migrateUsbReview
            ? ApiClient.defaultBase
            : ApiClient.reviewPreviousBase,
      );
    }
    expect(
      ApiClient.restoreBase('http://192.168.0.199:3100/v1'),
      'http://192.168.0.199:3100/v1',
    );
  });
}
