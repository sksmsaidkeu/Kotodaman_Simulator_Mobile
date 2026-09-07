import 'models.dart';

/// 데스크톱 `Utilities/KanaUtility.SplitIntoCells`의 이식.
/// 결합 문자(NonSpacingMark) 병합 로직은 뺐다 — gaccag_words.json.gz는 전부
/// 이미 조합된(precomposed) 히라가나/가타카나 코드포인트라 결합 문자가 나오지 않는다.
/// ponytail: 필요해지면(예: 유저 단어에 결합 문자가 섞이면) 되살릴 것.
List<String> splitIntoCells(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  return trimmed.runes.map(String.fromCharCode).toList();
}

class _PreparedWord {
  final String text;
  final List<String> cells;
  _PreparedWord(this.text, this.cells);
}

class _RequiredSlot {
  final int boardIndex;
  final String letter;
  _RequiredSlot(this.boardIndex, this.letter);
}

class _CharacterLetterSet {
  final CharacterEntry character;
  final Set<String> letters;
  _CharacterLetterSet(this.character, this.letters);
}

/// 데스크톱 `Services/WordSearchService.cs`의 이식.
/// 1차 범위(PRD §4 D-6)는 미라클/그룹효과/문자상태/모드시프트가 없으므로
/// `TryAssignCharacters`의 "미라클/그룹 부여 문자보다 자체 문자 우선" 정렬과
/// `CharacterAssignment`의 폼/문자상태 필드는 이식하지 않았다 — 전부 항상
/// false/기본값이라 결과에 영향이 없다.
class WordSearchService {
  final Map<int, List<_PreparedWord>> _wordsByLength = {};
  final Map<int, Map<String, String>> _comboWordsByLength = {};

  WordSearchService(Iterable<String> words) {
    final seenKeysByLength = <int, Set<String>>{};

    for (final rawText in words) {
      final text = rawText.trim();
      if (text.isEmpty) continue;
      final cells = splitIntoCells(text);
      final length = cells.length;
      if (length < 2 || length > 7) continue;

      final cellKey = cells.join();
      final seen = seenKeysByLength.putIfAbsent(length, () => <String>{});
      if (!seen.add(cellKey)) continue;

      _comboWordsByLength.putIfAbsent(length, () => {})[cellKey] = text;

      if (length >= 4 && length <= 7) {
        _wordsByLength.putIfAbsent(length, () => []).add(_PreparedWord(text, cells));
      }
    }

    for (final list in _wordsByLength.values) {
      list.sort((a, b) => a.text.compareTo(b.text));
    }
  }

  SearchGroup findLongestWords(
    List<String?> board,
    List<CharacterEntry> availableCharacters, {
    int minimumLength = 4,
    int maximumLength = 7,
    int maximumPlacements = 4,
    int maximumResults = 30,
  }) {
    final groups = findWordsByLength(
      board,
      availableCharacters,
      minimumLength: minimumLength,
      maximumLength: maximumLength,
      maximumPlacements: maximumPlacements,
      maximumResultsPerLength: maximumResults,
    );

    final startLength = [maximumLength, board.length, 7].reduce((a, b) => a < b ? a : b);
    for (int length = startLength; length >= minimumLength; length--) {
      final group = groups[length];
      if (group != null && group.hasResults) return group;
    }
    return SearchGroup();
  }

  Map<int, SearchGroup> findWordsByLength(
    List<String?> board,
    List<CharacterEntry> availableCharacters, {
    int minimumLength = 4,
    int maximumLength = 7,
    int maximumPlacements = 4,
    int maximumResultsPerLength = 30,
  }) {
    final groups = <int, SearchGroup>{};
    if (board.isEmpty) return groups;

    final normalizedBoard = board
        .map((cell) => (cell == null || cell.trim().isEmpty) ? null : cell.trim())
        .toList();
    final characterLetters =
        availableCharacters.map((c) => _CharacterLetterSet(c, c.letters)).toList();

    final startLength = [maximumLength, board.length, 7].reduce((a, b) => a < b ? a : b);
    for (int length = startLength; length >= minimumLength; length--) {
      final results = _findWordsOfLength(
        normalizedBoard,
        characterLetters,
        length,
        maximumPlacements,
        maximumResultsPerLength,
      );
      groups[length] = SearchGroup(wordLength: length, results: results);
    }
    return groups;
  }

  List<SearchResult> _findWordsOfLength(
    List<String?> normalizedBoard,
    List<_CharacterLetterSet> characterLetters,
    int wordLength,
    int maximumPlacements,
    int maximumResults,
  ) {
    final words = _wordsByLength[wordLength];
    if (words == null) return const [];

    final found = <SearchResult>[];
    final seenWords = <String>{};

    for (final word in words) {
      for (int start = 0; start <= normalizedBoard.length - wordLength; start++) {
        final requiredSlots = <_RequiredSlot>[];
        if (!_tryMatchBoard(word, normalizedBoard, start, maximumPlacements, requiredSlots)) {
          continue;
        }
        if (requiredSlots.isEmpty) continue;

        final assignments = _tryAssignCharacters(requiredSlots, characterLetters);
        if (assignments == null) continue;

        if (seenWords.add(word.text)) {
          final completedBoard = List<String?>.from(normalizedBoard);
          for (int offset = 0; offset < word.cells.length; offset++) {
            completedBoard[start + offset] = word.cells[offset];
          }
          final placedIndexes = assignments.map((a) => a.boardIndex).toSet();

          found.add(SearchResult(
            word: word.text,
            cells: word.cells,
            startIndex: start,
            endIndex: start + wordLength - 1,
            assignments: assignments,
            completedBoard: completedBoard,
            comboMatches: _findComboMatches(completedBoard, placedIndexes),
          ));
        }

        break;
      }
    }

    found.sort((a, b) {
      int cmp = b.comboCount.compareTo(a.comboCount);
      if (cmp != 0) return cmp;
      cmp = a.assignments.length.compareTo(b.assignments.length);
      if (cmp != 0) return cmp;
      cmp = a.startIndex.compareTo(b.startIndex);
      if (cmp != 0) return cmp;
      return a.word.compareTo(b.word);
    });

    return found.take(maximumResults).toList();
  }

  List<ComboMatch> _findComboMatches(List<String?> board, Set<int> placedBoardIndexes) {
    final matches = <ComboMatch>[];

    for (int start = 0; start < board.length; start++) {
      if (board[start] == null) continue;

      final cells = <String>[];
      bool containsPlacedCharacter = false;

      for (int end = start; end < board.length && end - start < 7; end++) {
        final cell = board[end];
        if (cell == null) break;

        cells.add(cell);
        if (placedBoardIndexes.contains(end)) containsPlacedCharacter = true;

        final length = cells.length;
        if (length < 2 || !containsPlacedCharacter) continue;

        final words = _comboWordsByLength[length];
        if (words == null) continue;

        final key = cells.join();
        final displayWord = words[key];
        if (displayWord == null) continue;

        matches.add(ComboMatch(word: displayWord, startIndex: start, endIndex: end, wordLength: length));
      }
    }

    matches.sort((a, b) {
      final cmp = a.startIndex.compareTo(b.startIndex);
      if (cmp != 0) return cmp;
      return a.endIndex.compareTo(b.endIndex);
    });
    return matches;
  }

  static bool _tryMatchBoard(
    _PreparedWord word,
    List<String?> board,
    int startIndex,
    int maximumPlacements,
    List<_RequiredSlot> requiredSlots,
  ) {
    for (int offset = 0; offset < word.cells.length; offset++) {
      final boardIndex = startIndex + offset;
      final targetLetter = word.cells[offset];
      final boardLetter = board[boardIndex];

      if (boardLetter == null) {
        requiredSlots.add(_RequiredSlot(boardIndex, targetLetter));
        if (requiredSlots.length > maximumPlacements) return false;
        continue;
      }

      if (boardLetter != targetLetter) return false;
    }
    return true;
  }

  static List<CharacterAssignment>? _tryAssignCharacters(
    List<_RequiredSlot> requiredSlots,
    List<_CharacterLetterSet> characters,
  ) {
    if (requiredSlots.length > characters.length) return null;

    final candidateCharacterIndexes = <List<int>>[];
    for (final slot in requiredSlots) {
      final candidates = <int>[];
      for (int i = 0; i < characters.length; i++) {
        if (characters[i].letters.contains(slot.letter)) candidates.add(i);
      }
      if (candidates.isEmpty) return null;
      candidateCharacterIndexes.add(candidates);
    }

    // 후보 수가 적은 칸부터 배정 — 동률이면 원래 칸 순서 유지(안정 정렬과 동일 효과).
    final slotOrder = List<int>.generate(requiredSlots.length, (i) => i)
      ..sort((a, b) {
        final cmp = candidateCharacterIndexes[a].length.compareTo(candidateCharacterIndexes[b].length);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    final usedCharacters = List<bool>.filled(characters.length, false);
    final selectedCharacterBySlot = List<int>.filled(requiredSlots.length, -1);

    bool search(int orderIndex) {
      if (orderIndex >= slotOrder.length) return true;
      final slotIndex = slotOrder[orderIndex];

      for (final characterIndex in candidateCharacterIndexes[slotIndex]) {
        if (usedCharacters[characterIndex]) continue;
        usedCharacters[characterIndex] = true;
        selectedCharacterBySlot[slotIndex] = characterIndex;

        if (search(orderIndex + 1)) return true;

        selectedCharacterBySlot[slotIndex] = -1;
        usedCharacters[characterIndex] = false;
      }
      return false;
    }

    if (!search(0)) return null;

    final assignments = <CharacterAssignment>[];
    for (int slotIndex = 0; slotIndex < requiredSlots.length; slotIndex++) {
      final character = characters[selectedCharacterBySlot[slotIndex]].character;
      assignments.add(CharacterAssignment(
        boardIndex: requiredSlots[slotIndex].boardIndex,
        letter: requiredSlots[slotIndex].letter,
        characterId: character.id,
        characterName: character.name,
      ));
    }
    assignments.sort((a, b) => a.boardIndex.compareTo(b.boardIndex));
    return assignments;
  }
}
