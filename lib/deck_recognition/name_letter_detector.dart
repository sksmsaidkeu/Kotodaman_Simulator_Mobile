import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// 슬롯 좌상단 원형 배지 위에 그려진 캐릭터 이름 첫 글자(히라가나/가타카나)를 인식해
/// ORB 매칭 후보를 좁히는 보조 신호([[kotodaman-mobile-flutter-port]] "이름 첫 글자 인식"
/// 절의 파이썬 사전검증을 그대로 이식). attribute_color_detector.dart가 찾는 것과 같은
/// 원(배지)인데 — 배지 내부 채움색이 속성색이고 그 위에 검은 글씨가 얹혀 있다.
///
/// 흐름: 배지 원 검출(Hough, 슬롯 좌상단 영역에 한정) → 반지름 0.72배 내부크롭(금색
/// 테두리 링 배제) → Otsu 이진화(소수 클래스=글자, 다수 클래스=배지 배경) → 최대 연결요소만
/// 채택(테두리 잔여물·노이즈 제거) → 48x48 정규화 → 실제 스크린샷 크롭 템플릿과 NCC 매칭.
class LetterMatch {
  final String letter;
  final double score; // NCC, -1..1
  const LetterMatch(this.letter, this.score);
}

const int kGlyphSize = 48;
const double _kInnerRadiusRatio = 0.72;

/// 템플릿 라이브러리가 아직 작고(9종, [[kotodaman-mobile-flutter-port]] 참고) 크로스-스크린샷
/// 매칭 노이즈가 있어 보수적으로 잡음 — 이 밑으로는 신뢰 못 할 추측이라 후보를 안 좁힌다.
const double kMinLetterConfidence = 0.6;

/// [colorSlot]은 슬롯 크롭(BGR, 업스케일 전 원본 크기) — attribute_color_detector와 동일한
/// 입력을 재사용할 수 있게 시그니처를 맞췄다. 실패하면(원을 못 찾음/글자를 못 골라냄) null.
/// 반환된 Mat은 호출자가 dispose.
cv.Mat? extractLetterGlyph(cv.Mat colorSlot) {
  if (colorSlot.isEmpty || colorSlot.cols < 48 || colorSlot.rows < 48) return null;

  final cols = colorSlot.cols;
  final rows = colorSlot.rows;
  final gray = cv.cvtColor(colorSlot, cv.COLOR_BGR2GRAY);

  final roiWidth = (cols * 0.72).round().clamp(1, cols);
  final roiHeight = (rows * 0.48).round().clamp(1, rows);
  final roi = gray.region(cv.Rect(0, 0, roiWidth, roiHeight));
  final blurred = cv.gaussianBlur(roi, (5, 5), 1.2);
  roi.dispose();

  final minDimension = math.min(cols, rows);
  final minRadius = math.max(14, (minDimension * 0.085).round());
  final maxRadius = math.max(minRadius + 2, (minDimension * 0.23).round());

  cv.Mat circles;
  try {
    circles = cv.HoughCircles(
      blurred,
      cv.HOUGH_GRADIENT,
      1.0,
      math.max(18, minDimension * 0.09),
      param1: 80,
      param2: 18,
      minRadius: minRadius,
      maxRadius: maxRadius,
    );
  } catch (_) {
    blurred.dispose();
    gray.dispose();
    return null;
  }
  blurred.dispose();

  final circleCount = circles.total;
  if (circleCount == 0) {
    circles.dispose();
    gray.dispose();
    return null;
  }

  // attribute_color_detector.dart와 동일한 실측 비율(6x2 그리드 기준) — 같은 배지를
  // 찾는 것이므로 위치 기대값도 그대로 맞춘다.
  final expectedCenterX = cols * 0.163;
  final expectedCenterY = rows * 0.198;
  final allowedXDistance = cols * 0.16;
  final allowedYDistance = rows * 0.15;

  final circleRowMajor = circles.rows == 1;
  final circlesToCheck = math.min(circleCount, 14);
  var bestDistance = double.infinity;
  var bestX = 0.0, bestY = 0.0, bestRadius = 0.0;
  for (var i = 0; i < circlesToCheck; i++) {
    final pixel = circleRowMajor ? circles.atPixel(0, i) : circles.atPixel(i, 0);
    final centerX = pixel[0].toDouble();
    final centerY = pixel[1].toDouble();
    final radius = pixel[2].toDouble();
    final xDistance = (centerX - expectedCenterX).abs();
    final yDistance = (centerY - expectedCenterY).abs();
    if (xDistance > allowedXDistance || yDistance > allowedYDistance) continue;
    final distance = xDistance + yDistance;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestX = centerX;
      bestY = centerY;
      bestRadius = radius;
    }
  }
  circles.dispose();
  if (bestDistance == double.infinity) {
    gray.dispose();
    return null;
  }

  final innerRadius = bestRadius * _kInnerRadiusRatio;
  final x0 = math.max(0, (bestX - innerRadius).floor());
  final y0 = math.max(0, (bestY - innerRadius).floor());
  final x1 = math.min(cols, (bestX + innerRadius).ceil());
  final y1 = math.min(rows, (bestY + innerRadius).ceil());
  if (x1 - x0 < 8 || y1 - y0 < 8) {
    gray.dispose();
    return null;
  }

  final patch = gray.region(cv.Rect(x0, y0, x1 - x0, y1 - y0));
  gray.dispose();
  final (_, rawBinary) = cv.threshold(patch, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
  patch.dispose();

  // Otsu는 어느 클래스에 255를 줄지 모른다 — 항상 면적이 작은 쪽(글자 획)을 흰색으로 통일.
  final whiteCount = cv.countNonZero(rawBinary);
  final totalCount = rawBinary.rows * rawBinary.cols;
  cv.Mat binary;
  if (whiteCount * 2 > totalCount) {
    binary = cv.bitwiseNOT(rawBinary);
    rawBinary.dispose();
  } else {
    binary = rawBinary;
  }

  // 최대 연결요소만 골라내는 데 findContours(VecVecPoint)가 아니라
  // connectedComponentsWithStats(Mat 기반)를 쓴다 — dartcv4의 VecVecPoint.operator[]는
  // "참조라 dispose 불필요"라고 문서화돼 있지만 실제로는 부모 std::vector 내부 원소의
  // 주소를 그대로 감싸서 반환한다(`std_VecVecPoint_get_p` → `new VecPoint{&parent->at(i)}`).
  // 이 VecPoint를 dispose하면 `delete self->ptr`가 그 내부 주소에 그대로 걸려 네이티브
  // 힙이 깨진다(실기기에서 "invalid chunk state"/"misaligned pointer" 크래시로 확인됨) —
  // 반대로 안 지우면 작은 wrapper가 새어 몇 슬롯 만에 다른 크래시(Scudo 페이지 고갈)로
  // 이어진다(첫 구현에서 확인됨). 즉 이 타입은 인덱싱 자체를 피하는 게 유일하게 안전한
  // 길이라 Mat 픽셀 접근(atNum/set, 할당·해제 위험이 없는 단순 메모리 읽기/쓰기)만으로
  // 우회한다([[kotodaman-mobile-flutter-port]] 참고).
  final labels = cv.Mat.empty();
  final stats = cv.Mat.empty();
  final centroids = cv.Mat.empty();
  final numLabels = cv.connectedComponentsWithStats(
    binary,
    labels,
    stats,
    centroids,
    8,
    cv.MatType.CV_32S,
    cv.CCL_DEFAULT,
  );
  binary.dispose();
  centroids.dispose();

  if (numLabels < 2) {
    labels.dispose();
    stats.dispose();
    return null;
  }

  // 라벨 0은 배경 — stats 컬럼은 OpenCV CC_STAT_* 순서(LEFT/TOP/WIDTH/HEIGHT/AREA),
  // 이 패키지엔 이름 상수로 노출돼 있지 않아 인덱스를 그대로 쓴다.
  var bestLabel = -1;
  var bestArea = 0;
  for (var label = 1; label < numLabels; label++) {
    final area = stats.at<int>(label, 4);
    if (area > bestArea) {
      bestArea = area;
      bestLabel = label;
    }
  }
  if (bestLabel < 0 || bestArea < 4) {
    labels.dispose();
    stats.dispose();
    return null;
  }

  final left = stats.at<int>(bestLabel, 0);
  final top = stats.at<int>(bestLabel, 1);
  final width = stats.at<int>(bestLabel, 2);
  final height = stats.at<int>(bestLabel, 3);
  stats.dispose();

  // 최대 연결요소 라벨만 흰색으로 남기고 나머지(다른 잡음 성분)는 지운 마스크를
  // 바운딩박스 크기로 직접 그린다.
  final glyph = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (labels.at<int>(top + y, left + x) == bestLabel) {
        glyph.set<int>(y, x, 255);
      }
    }
  }
  labels.dispose();

  final resized = cv.resize(glyph, (kGlyphSize, kGlyphSize));
  glyph.dispose();
  return resized;
}

/// [glyph](48x48 이진 이미지, [extractLetterGlyph] 결과)를 [templates](글자→48x48 템플릿)와
/// NCC(TM_CCOEFF_NORMED)로 비교해 가장 잘 맞는 글자를 고른다. 템플릿이 비어 있으면 null.
LetterMatch? matchLetter(cv.Mat glyph, Map<String, cv.Mat> templates) {
  if (templates.isEmpty) return null;
  String? bestLetter;
  var bestScore = -2.0;
  for (final entry in templates.entries) {
    final result = cv.matchTemplate(glyph, entry.value, cv.TM_CCOEFF_NORMED);
    final score = result.at<double>(0, 0);
    result.dispose();
    if (score > bestScore) {
      bestScore = score;
      bestLetter = entry.key;
    }
  }
  return bestLetter == null ? null : LetterMatch(bestLetter, bestScore);
}
