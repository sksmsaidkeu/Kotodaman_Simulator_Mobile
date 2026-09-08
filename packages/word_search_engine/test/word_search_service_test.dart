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

  test('타이핑한 길이 그대로의 판(패딩 없음)은 위치가 고정된 패턴으로만 매칭한다', () {
    // 모바일 word_search_page의 board 입력은 타이핑한 길이만큼만 배열을 만든다
    // (7칸으로 뒤를 null 패딩하지 않는다) — 그래야 sliding window가 타이핑하지
    // 않은 자리까지 "빈 슬롯"으로 오인해 엉뚱한 위치에서 매칭하는 걸 막는다.
    // "い＿＿た"(4글자)로 찾으면 いいかた(0번=い, 3번=た)는 나오지만, 3번째
    // 글자만 た인 けいたい는 나오면 안 된다.
    final service = WordSearchService(['いいかた', 'けいたい']);
    final hand = [
      // 빈칸 2개(1번=い, 2번=か)를 채우려면 캐릭터가 2명 필요하다 — 캐릭터
      // 한 명은 슬롯 하나에만 글자를 공급한다.
      CharacterEntry(id: 'c1', name: 'X', letters: ['い']),
      CharacterEntry(id: 'c2', name: 'Y', letters: ['か']),
    ];

    final board = ['い', null, null, 'た']; // 패딩 없이 타이핑한 4칸 그대로
    final groups = service.findWordsByLength(
      board,
      hand,
      minimumLength: 4,
      maximumLength: 4,
    );

    final words = groups[4]!.results.map((r) => r.word).toList();
    expect(words, contains('いいかた'));
    expect(words, isNot(contains('けいたい')));
  });
}
