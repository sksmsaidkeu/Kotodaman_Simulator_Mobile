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

  test('실제 characters.json 2,327명을 전부 읽는다', () {
    final path = '../../assets/characters/characters.json';
    if (!File(path).existsSync()) {
      // 앱 asset이 아직 없는 다른 실행 환경(CI 등)에서는 건너뛴다.
      return;
    }
    final characters = decodeCharacters(File(path).readAsStringSync());
    expect(characters, hasLength(2327));
  });
}
