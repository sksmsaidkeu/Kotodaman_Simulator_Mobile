import 'dart:io';

import 'package:test/test.dart';
import 'package:word_search_engine/word_search_engine.dart';

// 골든 값은 데스크톱 원본 `WordSearchService.cs`를 그대로(로직 무수정) 실행해서 뽑았다
// (같은 캐릭터 4명 + gaccag_words.json.gz만, 빈 판 7칸) — PRD_Mobile.md §8 1단계 완료 기준.
void main() {
  test('빈 판 + 손패 4명 → 데스크톱과 동일한 최장 단어(4글자, "あいかん")를 찾는다', () {
    final bytes = File('assets/gaccag_words.json.gz').readAsBytesSync();
    final words = decodeDictionaryWords(bytes);
    expect(words.length, greaterThan(200000));

    final service = WordSearchService(words);

    final hand = [
      CharacterEntry(id: 'c1', name: 'サイタマ', letters: ['さ', 'い', 'た', 'ま', 'ん', 'と']),
      CharacterEntry(id: 'c2', name: 'カズマパーティ', letters: ['か', 'あ', 'め', 'た', 'だ', 'こ']),
      CharacterEntry(id: 'c3', name: 'ホウ煖', letters: ['ほ', 'う', 'け', 'ん', 'ち', 'さ']),
      CharacterEntry(id: 'c4', name: 'モモ&変身・オカルン', letters: ['お', 'か', 'る', 'ん', 'も', 'あ']),
    ];

    final emptyBoard = List<String?>.filled(7, null);
    final result = service.findLongestWords(emptyBoard, hand);

    expect(result.wordLength, 4);
    expect(result.results.length, 30);
    expect(result.results.first.word, 'あいかん');
    expect(result.results.first.comboCount, 6);
  });

  test('4명 중 아무도 없는 문자로는 단어를 찾지 못한다', () {
    final service = WordSearchService(['あいうえ', 'かきくけ']);
    final hand = [
      CharacterEntry(id: 'c1', name: 'X', letters: ['さ', 'し', 'す', 'せ']),
    ];
    final result = service.findLongestWords(List<String?>.filled(7, null), hand);
    expect(result.results, isEmpty);
  });
}
