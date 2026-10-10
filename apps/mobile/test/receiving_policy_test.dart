import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/receiving_policy.dart';

void main() {
  DateTime time(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 9, hour, minute);
  test('daytime quiet interval includes start and excludes end', () {
    const policy = ReceivingPolicy(
      quietHours: true,
      quietStart: 9 * 60,
      quietEnd: 17 * 60,
    );
    expect(policy.isQuiet(time(8, 59)), false);
    expect(policy.isQuiet(time(9)), true);
    expect(policy.isQuiet(time(16, 59)), true);
    expect(policy.isQuiet(time(17)), false);
  });
  test(
    'overnight quiet interval crosses midnight and schedules the next boundary',
    () {
      const policy = ReceivingPolicy(quietHours: true);
      expect(policy.isQuiet(time(21, 59)), false);
      expect(policy.isQuiet(time(22)), true);
      expect(policy.isQuiet(time(0)), true);
      expect(policy.isQuiet(time(6, 59)), true);
      expect(policy.isQuiet(time(7)), false);
      expect(policy.nextBoundary(time(23)), DateTime(2026, 10, 10, 7));
      expect(policy.nextBoundary(time(7)), time(22));
    },
  );
  test('disabled quiet hours still honor group mute and preserve independent groups', () {
    final policy = const ReceivingPolicy().mute('private', true);
    expect(policy.allowsGroup('private', time(23)), false);
    expect(policy.allowsGroup('other', time(23)), true);
    expect(
      policy.mute('private', false).allowsGroup('private', time(23)),
      true,
    );
    expect(policy.nextBoundary(time(23)), isNull);
  });
  test('equal quiet times mean all day with no repeated boundary timer', () {
    const policy = ReceivingPolicy(
      quietHours: true,
      quietStart: 0,
      quietEnd: 0,
    );
    expect(policy.isQuiet(time(0)), true);
    expect(policy.isQuiet(time(23, 59)), true);
    expect(policy.nextBoundary(time(12)), isNull);
  });
  test('stored settings validate minutes and snapshot muted groups', () {
    final groups = ['a', 'a', 42];
    final policy = ReceivingPolicy.fromJson({
      'quietHours': true,
      'quietStart': -1,
      'quietEnd': 9999,
      'mutedGroups': groups,
    });
    groups.add('b');
    expect(policy.quietStart, 22 * 60);
    expect(policy.quietEnd, 7 * 60);
    expect(policy.mutedGroups, ['a']);
    expect(() => policy.mutedGroups.add('b'), throwsUnsupportedError);
    expect(ReceivingPolicy.fromJson(policy.toJson()).toJson(), policy.toJson());
  });
}
