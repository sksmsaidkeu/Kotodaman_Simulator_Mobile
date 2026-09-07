/// 데스크톱 `Models/CharacterEntry.cs` 필드 중 PRD 2단계(§8, FR-2/FR-3)까지 필요한
/// 것만 이식. 미라클/그룹효과·문자상태·모드시프트(§4 D-6, 2차 예정)는 여기 없다.
class CharacterEntry {
  final String id;
  final String name;
  final Set<String> letters;
  final List<String> searchAliases;
  final String attribute;
  final String species;
  final String groupName;
  final String category;
  final String imageFileName;
  final String deckRestrictionGroupId;
  final List<String> gimmickCounters;
  final List<String> statusResistances;

  CharacterEntry({
    required this.id,
    required this.name,
    required List<String> letters,
    this.searchAliases = const [],
    this.attribute = '',
    this.species = '',
    this.groupName = '',
    this.category = '',
    this.imageFileName = '',
    this.deckRestrictionGroupId = '',
    this.gimmickCounters = const [],
    this.statusResistances = const [],
  }) : letters = letters.toSet();
}

class CharacterAssignment {
  final int boardIndex;
  final String letter;
  final String characterId;
  final String characterName;

  CharacterAssignment({
    required this.boardIndex,
    required this.letter,
    required this.characterId,
    required this.characterName,
  });
}

class ComboMatch {
  final String word;
  final int startIndex;
  final int endIndex;
  final int wordLength;

  ComboMatch({
    required this.word,
    required this.startIndex,
    required this.endIndex,
    required this.wordLength,
  });
}

class SearchResult {
  final String word;
  final List<String> cells;
  final int startIndex;
  final int endIndex;
  final List<CharacterAssignment> assignments;
  final List<String?> completedBoard;
  final List<ComboMatch> comboMatches;

  int get comboCount => comboMatches.length;

  SearchResult({
    required this.word,
    required this.cells,
    required this.startIndex,
    required this.endIndex,
    required this.assignments,
    required this.completedBoard,
    required this.comboMatches,
  });
}

class SearchGroup {
  final int wordLength;
  final List<SearchResult> results;

  bool get hasResults => results.isNotEmpty;

  SearchGroup({this.wordLength = 0, this.results = const []});
}
