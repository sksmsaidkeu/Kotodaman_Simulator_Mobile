import 'package:test/test.dart';
import 'package:word_search_engine/word_search_engine.dart';

void main() {
  test('4열×3행으로 12칸을 만들고 전체 영역을 정확히 채운다', () {
    final rects = computeSlotRects(
      gridLeft: 0,
      gridTop: 0,
      gridWidth: 400,
      gridHeight: 300,
      columns: 4,
      rows: 3,
    );

    expect(rects.length, 12);
    expect(rects.first, const SlotRect(0, 0, 100, 100));
    expect(rects.last, const SlotRect(300, 200, 100, 100));

    for (int row = 0; row < 3; row++) {
      final lastInRow = rects[row * 4 + 3];
      expect(lastInRow.left + lastInRow.width, 400);
    }
    for (final r in rects.sublist(8, 12)) {
      expect(r.top + r.height, 300);
    }
  });

  test('나누어떨어지지 않는 크기도 반올림 갭/겹침 없이 이웃 칸과 이어진다', () {
    final rects = computeSlotRects(
      gridLeft: 10,
      gridTop: 5,
      gridWidth: 401,
      gridHeight: 299,
      columns: 4,
      rows: 3,
    );

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final a = rects[row * 4 + col];
        final b = rects[row * 4 + col + 1];
        expect(a.left + a.width, b.left);
      }
    }
    for (int col = 0; col < 4; col++) {
      for (int row = 0; row < 2; row++) {
        final a = rects[row * 4 + col];
        final b = rects[(row + 1) * 4 + col];
        expect(a.top + a.height, b.top);
      }
    }
  });
}
