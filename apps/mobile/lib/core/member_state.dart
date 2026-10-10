typedef MemberJson = Map<String, dynamic>;

String memberDisplayName(dynamic value, {String fallback = 'Team Member'}) {
  if (value is! String) return fallback;
  final name = value.trim();
  return name.isEmpty || ['null', 'undefined'].contains(name.toLowerCase())
      ? fallback
      : name;
}

String preferenceLanguage(dynamic value, {String fallback = 'en'}) {
  if (value is! String ||
      value.trim().isEmpty ||
      ['null', 'undefined'].contains(value.trim().toLowerCase())) {
    return fallback;
  }
  return value.trim().toLowerCase().replaceAll('_', '-').split('-').first;
}

MemberJson normalizeMember(MemberJson value) => {
  ...value,
  'displayName': memberDisplayName(value['displayName']),
  'spokenLanguage': preferenceLanguage(
    value['spokenLanguage'],
    fallback: preferenceLanguage(value['listeningLanguage']),
  ),
  'listeningLanguage': preferenceLanguage(
    value['listeningLanguage'],
    fallback: preferenceLanguage(value['spokenLanguage']),
  ),
  'version': value['version'] is int ? value['version'] : 0,
};
int memberVersion(MemberJson value) =>
    value['version'] is int ? value['version'] : 0;

/// Stable userId, never list position/name. Same/older events are idempotent.
MemberJson mergeMember(MemberJson current, MemberJson incoming) =>
    memberVersion(incoming) > memberVersion(current)
    ? normalizeMember({...current, ...incoming})
    : normalizeMember(current);
List<MemberJson> mergeTeamSnapshot(
  List<MemberJson> incoming,
  List<MemberJson> current,
) => incoming.map((group) {
  final old = current.where((g) => g['id'] == group['id']).firstOrNull;
  final previous = (old?['members'] as List? ?? []).cast<Map>();
  return {
    ...group,
    'members': (group['members'] as List? ?? []).cast<Map>().map((raw) {
      final member = MemberJson.from(raw);
      final prior = previous
          .where((m) => m['userId'] == member['userId'])
          .firstOrNull;
      return prior == null
          ? normalizeMember(member)
          : mergeMember(member, MemberJson.from(prior));
    }).toList(),
  };
}).toList();
List<MemberJson> patchMember(
  List<MemberJson> groups,
  String groupId,
  MemberJson incoming,
) => groups.map((group) {
  if (group['id'] != groupId) return group;
  return {
    ...group,
    'members': (group['members'] as List? ?? []).cast<Map>().map((raw) {
      final member = MemberJson.from(raw);
      return member['userId'] == incoming['userId']
          ? mergeMember(member, incoming)
          : member;
    }).toList(),
  };
}).toList();
