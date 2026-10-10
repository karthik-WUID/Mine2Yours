/// Device-local controls for automatic speech. Explicit user replay is separate.
class ReceivingPolicy {
  final bool quietHours;
  final int quietStart, quietEnd;
  final List<String> mutedGroups;
  const ReceivingPolicy({
    this.quietHours = false,
    this.quietStart = 22 * 60,
    this.quietEnd = 7 * 60,
    this.mutedGroups = const [],
  });

  factory ReceivingPolicy.fromJson(Map? json) {
    final groups = json?['mutedGroups'];
    int minute(String key, int fallback) {
      final value = json?[key];
      return value is int && value >= 0 && value < 1440 ? value : fallback;
    }

    return ReceivingPolicy(
      quietHours: json?['quietHours'] == true,
      quietStart: minute('quietStart', 22 * 60),
      quietEnd: minute('quietEnd', 7 * 60),
      mutedGroups: List.unmodifiable(
        (groups is List ? groups : []).whereType<String>().toSet(),
      ),
    );
  }

  bool isQuiet(DateTime localTime) {
    if (!quietHours) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    if (quietStart == quietEnd) return true;
    if (quietStart < quietEnd) {
      return minute >= quietStart && minute < quietEnd;
    }
    return minute >= quietStart || minute < quietEnd;
  }

  bool allowsGroup(String groupId, DateTime localTime) =>
      !mutedGroups.contains(groupId) && !isQuiet(localTime);

  ReceivingPolicy copy({bool? quietHours, int? quietStart, int? quietEnd}) =>
      ReceivingPolicy(
        quietHours: quietHours ?? this.quietHours,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        mutedGroups: mutedGroups,
      );

  ReceivingPolicy mute(String groupId, bool active) {
    final groups = mutedGroups.toSet();
    if (active) {
      groups.add(groupId);
    } else {
      groups.remove(groupId);
    }
    return ReceivingPolicy(
      quietHours: quietHours,
      quietStart: quietStart,
      quietEnd: quietEnd,
      mutedGroups: List.unmodifiable(groups),
    );
  }

  DateTime? nextBoundary(DateTime localTime) {
    if (!quietHours || quietStart == quietEnd) return null;
    final candidates = <DateTime>[];
    for (final minute in [quietStart, quietEnd]) {
      var next = DateTime(
        localTime.year,
        localTime.month,
        localTime.day,
        minute ~/ 60,
        minute % 60,
      );
      if (!next.isAfter(localTime)) {
        next = DateTime(
          localTime.year,
          localTime.month,
          localTime.day + 1,
          minute ~/ 60,
          minute % 60,
        );
      }
      candidates.add(next);
    }
    candidates.sort();
    return candidates.first;
  }

  Map<String, dynamic> toJson() => {
    'quietHours': quietHours,
    'quietStart': quietStart,
    'quietEnd': quietEnd,
    'mutedGroups': mutedGroups,
  };
}
