import 'package:flutter/services.dart' show rootBundle;
import 'package:word_search_engine/word_search_engine.dart';

/// 캐릭터 전체 데이터(PRD FR-2) + 단어 탐색 엔진(FR-1, [[kotodaman-mobile-flutter-port]]
/// 1단계에서 검증됨)을 앱 시작 시 한 번 로드해 묶어 둔다.
class AppData {
  final List<CharacterEntry> characters;
  final WordSearchService wordSearchService;

  AppData({required this.characters, required this.wordSearchService});
}

/// [useKoreanNames]가 false면 한국어 이름 오버레이를 건너뛰고 characters.json 원문(일본어)을
/// 그대로 쓴다 — 일본어/영어 언어 모드용([[kotodaman-mobile-i18n]] 참고, 영어 번역 데이터는 없음).
Future<AppData> loadAppData({bool useKoreanNames = true}) async {
  final charactersJson = await rootBundle.loadString('assets/characters/characters.json');
  final koNames = useKoreanNames
      ? decodeKoNameMap(await rootBundle.loadString('assets/characters/character_names.ko.json'))
      : const <String, String>{};
  final koGroupNames = useKoreanNames
      ? decodeKoNameMap(await rootBundle.loadString('assets/characters/group_names.ko.json'))
      : const <String, String>{};
  final characters = decodeCharacters(charactersJson, koNames: koNames, koGroupNames: koGroupNames);

  final dictData = await rootBundle.load('assets/dictionary/gaccag_words.json.gz');
  final dictBytes = dictData.buffer.asUint8List(dictData.offsetInBytes, dictData.lengthInBytes);
  final words = decodeDictionaryWords(dictBytes);

  return AppData(
    characters: characters,
    wordSearchService: WordSearchService(words),
  );
}
