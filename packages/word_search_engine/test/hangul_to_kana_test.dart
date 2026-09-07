import 'package:test/test.dart';
import 'package:word_search_engine/word_search_engine.dart';

void main() {
  test('기본 오십음도·탁음·반탁음·요음을 대응 가나로 바꾼다', () {
    expect(convertHangulToKana('아카사타나하마야라와'), 'あかさたなはまやらわ');
    expect(convertHangulToKana('가자다바파'), 'がざだばぱ');
    expect(convertHangulToKana('캬샤챠냐'), 'きゃしゃちゃにゃ');
  });

  test('받침 ㄴ/ㅅ은 뒤에 ん/っ을 붙인다', () {
    expect(convertHangulToKana('카렌'), 'かれん');
    expect(convertHangulToKana('아갓토'), 'あがっと');
  });

  test('가나·밑줄·공백처럼 매핑에 없는 문자는 그대로 둔다', () {
    expect(convertHangulToKana('あい_かん '), 'あい_かん ');
  });
}
