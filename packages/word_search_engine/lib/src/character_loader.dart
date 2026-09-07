import 'dart:convert';

import 'models.dart';

/// `characters.json`(데스크톱 `Data/characters.json`과 동일 포맷, PascalCase 필드) 텍스트를
/// [CharacterEntry] 목록으로 변환한다. PRD §8 2단계 범위 필드만 읽는다 — 미라클/그룹효과·
/// 문자상태·모드시프트(2차 예정)는 읽지 않는다. Id/Name이 빈 캐릭터는 제외(데스크톱
/// `JsonDataLoader.LoadCharacters`와 동일한 최소 유효성 규칙).
List<CharacterEntry> decodeCharacters(String jsonText) {
  final list = json.decode(jsonText) as List<dynamic>;
  final result = <CharacterEntry>[];

  for (final raw in list) {
    final map = raw as Map<String, dynamic>;
    final id = (map['Id'] as String? ?? '').trim();
    final name = (map['Name'] as String? ?? '').trim();
    if (id.isEmpty || name.isEmpty) continue;

    result.add(CharacterEntry(
      id: id,
      name: name,
      letters: (map['Letters'] as List<dynamic>? ?? const []).cast<String>(),
      searchAliases: (map['SearchAliases'] as List<dynamic>? ?? const []).cast<String>(),
      attribute: map['Attribute'] as String? ?? '',
      species: map['Species'] as String? ?? '',
      groupName: map['GroupName'] as String? ?? '',
      category: map['Category'] as String? ?? '',
      imageFileName: map['ImageFileName'] as String? ?? '',
      deckRestrictionGroupId: map['DeckRestrictionGroupId'] as String? ?? '',
      gimmickCounters: (map['GimmickCounters'] as List<dynamic>? ?? const []).cast<String>(),
      statusResistances: (map['StatusResistances'] as List<dynamic>? ?? const []).cast<String>(),
    ));
  }

  return result;
}
