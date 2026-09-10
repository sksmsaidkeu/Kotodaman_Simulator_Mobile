import 'dart:convert';

import 'models.dart';

/// `characters.json`(데스크톱 `Data/characters.json`과 동일 포맷, PascalCase 필드) 텍스트를
/// [CharacterEntry] 목록으로 변환한다. PRD §8 2단계 범위 필드만 읽는다 — 미라클/그룹효과·
/// 문자상태·모드시프트(2차 예정)는 읽지 않는다. Id/Name이 빈 캐릭터는 제외(데스크톱
/// `JsonDataLoader.LoadCharacters`와 동일한 최소 유효성 규칙).
///
/// [koNames](Id → 한국어 이름, `character_names.ko.json`)와 [koGroupNames](일본어
/// GroupName → 한국어 그룹명, `group_names.ko.json`)가 주어지면 이름/그룹명을 그 자리에서
/// 한국어로 덮어쓴다 — 데스크톱 캐릭터 이름 한국어화([[kotodaman-character-name-ko]])와
/// 같은 조회 파일을 그대로 재사용. 매칭 안 되는 항목은 원문(일본어) 그대로 둔다.
List<CharacterEntry> decodeCharacters(
  String jsonText, {
  Map<String, String> koNames = const {},
  Map<String, String> koGroupNames = const {},
}) {
  final list = json.decode(jsonText) as List<dynamic>;
  final result = <CharacterEntry>[];

  for (final raw in list) {
    final map = raw as Map<String, dynamic>;
    final id = (map['Id'] as String? ?? '').trim();
    final name = (map['Name'] as String? ?? '').trim();
    if (id.isEmpty || name.isEmpty) continue;
    final groupName = map['GroupName'] as String? ?? '';

    result.add(CharacterEntry(
      id: id,
      name: koNames[id] ?? name,
      letters: (map['Letters'] as List<dynamic>? ?? const []).cast<String>(),
      searchAliases: (map['SearchAliases'] as List<dynamic>? ?? const []).cast<String>(),
      attribute: map['Attribute'] as String? ?? '',
      species: map['Species'] as String? ?? '',
      groupName: koGroupNames[groupName] ?? groupName,
      category: map['Category'] as String? ?? '',
      imageFileName: map['ImageFileName'] as String? ?? '',
      deckRestrictionGroupId: map['DeckRestrictionGroupId'] as String? ?? '',
      gimmickCounters: (map['GimmickCounters'] as List<dynamic>? ?? const []).cast<String>(),
      statusResistances: (map['StatusResistances'] as List<dynamic>? ?? const []).cast<String>(),
    ));
  }

  return result;
}

/// `character_names.ko.json`/`group_names.ko.json` 둘 다 `{키: 한국어값}` 단순 맵 포맷이라
/// 공용으로 쓴다.
Map<String, String> decodeKoNameMap(String jsonText) =>
    (json.decode(jsonText) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
