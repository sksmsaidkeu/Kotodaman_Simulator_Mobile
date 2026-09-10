import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:word_search_engine/word_search_engine.dart';

void main() {
  test('PascalCase 필드를 CharacterEntry로 매핑한다', () {
    final jsonText = jsonEncode([
      {
        'Id': 'character-1',
        'Name': 'テスト',
        'SearchAliases': ['테스트'],
        'Attribute': '火',
        'Species': '神',
        'GroupName': '그룹',
        'ImageFileName': 'character-1.png',
        'Letters': ['て', 'す', 'と'],
        'DeckRestrictionGroupId': 'group-a',
        'GimmickCounters': ['フリーズ'],
        'StatusResistances': ['毒'],
      },
      {'Id': '', 'Name': '이름만 있고 Id 없음', 'Letters': []},
      {'Id': 'character-2', 'Name': '', 'Letters': []},
    ]);

    final characters = decodeCharacters(jsonText);

    expect(characters, hasLength(1));
    final c = characters.single;
    expect(c.id, 'character-1');
    expect(c.name, 'テスト');
    expect(c.searchAliases, ['테스트']);
    expect(c.attribute, '火');
    expect(c.species, '神');
    expect(c.groupName, '그룹');
    expect(c.imageFileName, 'character-1.png');
    expect(c.letters, {'て', 'す', 'と'});
    expect(c.deckRestrictionGroupId, 'group-a');
    expect(c.gimmickCounters, ['フリーズ']);
    expect(c.statusResistances, ['毒']);
  });

  test('실제 characters.json 전체를 읽는다(빈 Id/Name 제외 개수와 일치)', () {
    final path = '../../assets/characters/characters.json';
    if (!File(path).existsSync()) {
      // 앱 asset이 아직 없는 다른 실행 환경(CI 등)에서는 건너뛴다.
      return;
    }
    final jsonText = File(path).readAsStringSync();

    // 게임 데이터가 갱신되면 인원 수가 계속 늘어난다 — 하드코딩된 숫자는 매번 갱신을
    // 잊어서 깨진다(실제로 2,327로 박아뒀다가 2,333으로 늘어난 뒤 방치돼 있었음).
    // 원본 JSON에서 같은 유효성 규칙(Id/Name 비어있지 않음)으로 직접 센 값과 비교해서
    // "파싱 로직이 실제 데이터를 다 읽는지"만 검증하고, 인원 수 자체는 고정하지 않는다.
    final raw = jsonDecode(jsonText) as List<dynamic>;
    final expectedCount = raw.where((e) {
      final map = e as Map<String, dynamic>;
      final id = (map['Id'] as String? ?? '').trim();
      final name = (map['Name'] as String? ?? '').trim();
      return id.isNotEmpty && name.isNotEmpty;
    }).length;

    final characters = decodeCharacters(jsonText);
    expect(characters, hasLength(expectedCount));
  });
}
