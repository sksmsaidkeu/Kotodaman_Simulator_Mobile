/// 스크린샷 덱 인식(PRD_Mobile.md FR-4)에서 쓰는 슬롯 그리드 분할 — 이 함수 자체는
/// 단어탐색과 무관하지만, 이 머신엔 메인 앱(`opencv_dart` 의존)의 네이티브 빌드가
/// 막혀 있어(Windows용 C++ 컴파일러 없음) 거기 두면 `dart test`가 아예 안 돈다.
/// 순수 산술이라 여기(Flutter 비의존 순수 Dart 패키지)에 둬서 테스트 가능하게 유지한다.
class SlotRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const SlotRect(this.left, this.top, this.width, this.height);

  @override
  String toString() => 'SlotRect($left,$top,$width,$height)';

  @override
  bool operator ==(Object other) =>
      other is SlotRect &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// 데스크톱 `DeckScreenshotRecognitionService.GetSlotRect`와 같은 비율 분할 — 픽셀좌표를
/// 고정하지 않고 (gridLeft,gridTop,gridWidth,gridHeight) 영역을 `columns`×`rows`로 나눈다.
/// 매 칸의 경계를 누적 비율(`gridWidth * col / columns`)로 계산해 반올림 오차가 쌓여도
/// 이웃 칸과 갭/겹침이 생기지 않는다. 인덱스는 행 우선(왼쪽→오른쪽, 위→아래) 순서.
List<SlotRect> computeSlotRects({
  required int gridLeft,
  required int gridTop,
  required int gridWidth,
  required int gridHeight,
  required int columns,
  required int rows,
}) {
  final rects = <SlotRect>[];
  for (int row = 0; row < rows; row++) {
    final top = gridTop + (gridHeight * row / rows).round();
    final bottom = gridTop + (gridHeight * (row + 1) / rows).round();
    for (int col = 0; col < columns; col++) {
      final left = gridLeft + (gridWidth * col / columns).round();
      final right = gridLeft + (gridWidth * (col + 1) / columns).round();
      rects.add(SlotRect(left, top, right - left, bottom - top));
    }
  }
  return rects;
}
