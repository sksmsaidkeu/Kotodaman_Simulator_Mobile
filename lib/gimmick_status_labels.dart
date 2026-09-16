/// 기믹 대책/상태이상 내성 태그. GameWith 표에서 나오는 고정 어휘(데스크톱
/// `Services/CharacterNameLoc.cs`의 GimmickNames/StatusNames와 동일 목록)라
/// 캐릭터 데이터처럼 조회 파일을 두지 않고 여기 바로 적어둔다.
const Map<String, String> kGimmickNamesKo = {
  'シールド': '실드',
  'トゲ': '가시',
  'チェンジ': '체인지',
  '弱体': '약화',
  'ウォール': '벽',
  'ビリビリ': '감전',
  'ヒール': '힐',
  'コピー': '카피',
  'フリーズ': '빙결',
  '地雷': '지뢰',
  'スマッシュ': '스매시',
  'バルーン': '풍선',
  'レーザー': '레이저',
  'スーパーのみ': '슈퍼 전용',
};

const Map<String, String> kStatusNamesKo = {
  '毒': '독',
  '睡眠': '수면',
  '呪い': '저주',
  '混乱': '혼란',
  '汚染': '오염',
  '炎上': '화상',
  '改造': '개조',
  '衰弱': '쇠약',
  '変異': '변이',
  '消去': '소거',
};

List<String> get kGimmickOptions => kGimmickNamesKo.keys.toList();
List<String> get kStatusResistanceOptions => kStatusNamesKo.keys.toList();

/// ko 로케일에서만 한국어 표시명으로 바꾸고, ja/en은 원문(일본어) 그대로 둔다
/// (캐릭터/그룹 이름 한국어화와 같은 규칙, [[kotodaman-mobile-i18n]]).
String gimmickLabel(String raw, String languageCode) =>
    languageCode == 'ko' ? (kGimmickNamesKo[raw] ?? raw) : raw;

String statusResistanceLabel(String raw, String languageCode) =>
    languageCode == 'ko' ? (kStatusNamesKo[raw] ?? raw) : raw;
