/// 한글 자모(오십음도 표기 관용)를 대응하는 히라가나로 바꾼다. 데스크톱
/// `KotodamanWordFinder_v1.25.1/Utilities/KanaUtility.cs`의 `ConvertHangulToKana`를
/// 그대로 이식([[kotodaman-mobile-flutter-port]] 참고) — 판 입력 시 한글 IME로 타이핑해도
/// 히라가나로 자동 변환되게 하는 데 쓴다.
///
/// つ는 흔히 쓰는 '츠' 표기를 기준으로 삼았다('쓰'가 필요하면 이 표를 바꾸면 된다).
/// ん은 '응'으로, 요음(캬/쵸 등)은 두 글자 가나(きゃ/ちょ 등)로 대응한다.
/// 받침 ㄴ은 뒤에 ん을, 받침 ㅅ은 뒤에 っ을 붙인다(예: 카렌→かれん, 아갓토→あがっと).
/// っ(촉음)·장음 표기(ー)·겹받침은 대상이 아니다.
library;

const Map<String, String> _hangulToKanaMap = {
  // あ행
  '아': 'あ', '이': 'い', '우': 'う', '에': 'え', '오': 'お',
  // か행
  '카': 'か', '키': 'き', '쿠': 'く', '케': 'け', '코': 'こ',
  // さ행
  '사': 'さ', '시': 'し', '스': 'す', '세': 'せ', '소': 'そ',
  // た행
  '타': 'た', '치': 'ち', '츠': 'つ', '테': 'て', '토': 'と',
  // な행
  '나': 'な', '니': 'に', '누': 'ぬ', '네': 'ね', '노': 'の',
  // は행
  '하': 'は', '히': 'ひ', '후': 'ふ', '헤': 'へ', '호': 'ほ',
  // ま행
  '마': 'ま', '미': 'み', '무': 'む', '메': 'め', '모': 'も',
  // や행
  '야': 'や', '유': 'ゆ', '요': 'よ',
  // ら행
  '라': 'ら', '리': 'り', '루': 'る', '레': 'れ', '로': 'ろ',
  // わ행 · ん
  '와': 'わ', '응': 'ん',
  // が행
  '가': 'が', '기': 'ぎ', '구': 'ぐ', '게': 'げ', '고': 'ご',
  // ざ행
  '자': 'ざ', '지': 'じ', '즈': 'ず', '제': 'ぜ', '조': 'ぞ',
  // だ행(ぢ/づ는 じ/ず와 겹쳐 생략)
  '다': 'だ', '데': 'で', '도': 'ど',
  // ば행
  '바': 'ば', '비': 'び', '부': 'ぶ', '베': 'べ', '보': 'ぼ',
  // ぱ행
  '파': 'ぱ', '피': 'ぴ', '푸': 'ぷ', '페': 'ぺ', '포': 'ぽ',
  // 요음
  '캬': 'きゃ', '큐': 'きゅ', '쿄': 'きょ',
  '샤': 'しゃ', '슈': 'しゅ', '쇼': 'しょ',
  '챠': 'ちゃ', '츄': 'ちゅ', '쵸': 'ちょ',
  '냐': 'にゃ', '뉴': 'にゅ', '뇨': 'にょ',
  '햐': 'ひゃ', '휴': 'ひゅ', '효': 'ひょ',
  '먀': 'みゃ', '뮤': 'みゅ', '묘': 'みょ',
  '랴': 'りゃ', '류': 'りゅ', '료': 'りょ',
  '갸': 'ぎゃ', '규': 'ぎゅ', '교': 'ぎょ',
  '쟈': 'じゃ', '쥬': 'じゅ', '죠': 'じょ',
  '뱌': 'びゃ', '뷰': 'びゅ', '뵤': 'びょ',
  '퍄': 'ぴゃ', '퓨': 'ぴゅ', '표': 'ぴょ',
};

const int _hangulSyllableBase = 0xAC00;
const int _hangulSyllableLast = 0xD7A3;
const int _hangulFinalCount = 28;
const int _hangulFinalNieun = 4; // 받침 ㄴ
const int _hangulFinalSiot = 19; // 받침 ㅅ

String _convertHangulCharacter(String character) {
  final exact = _hangulToKanaMap[character];
  if (exact != null) return exact;

  final code = character.runes.single;
  if (code < _hangulSyllableBase || code > _hangulSyllableLast) return character;

  final finalIndex = (code - _hangulSyllableBase) % _hangulFinalCount;
  final String? suffix = switch (finalIndex) {
    _hangulFinalNieun => 'ん',
    _hangulFinalSiot => 'っ',
    _ => null,
  };
  if (suffix == null) return character;

  final baseCharacter = String.fromCharCode(code - finalIndex);
  final baseKana = _hangulToKanaMap[baseCharacter];
  return baseKana == null ? character : baseKana + suffix;
}

String convertHangulToKana(String text) {
  if (text.isEmpty) return text;
  return text.runes.map((r) => _convertHangulCharacter(String.fromCharCode(r))).join();
}
