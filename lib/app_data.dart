import 'package:flutter/services.dart' show rootBundle;
import 'package:word_search_engine/word_search_engine.dart';

/// 캐릭터 전체 데이터(PRD FR-2) + 단어 탐색 엔진(FR-1, [[kotodaman-mobile-flutter-port]]
/// 1단계에서 검증됨)을 앱 시작 시 한 번 로드해 묶어 둔다.
class AppData {
  final List<CharacterEntry> characters;
  final WordSearchService wordSearchService;

  AppData({required this.characters, required this.wordSearchService});
}

Future<AppData> loadAppData() async {
  final charactersJson = await rootBundle.loadString('assets/characters/characters.json');
  final characters = decodeCharacters(charactersJson);

  final dictData = await rootBundle.load('assets/dictionary/gaccag_words.json.gz');
  final dictBytes = dictData.buffer.asUint8List(dictData.offsetInBytes, dictData.lengthInBytes);
  final words = decodeDictionaryWords(dictBytes);

  return AppData(
    characters: characters,
    wordSearchService: WordSearchService(words),
  );
}
