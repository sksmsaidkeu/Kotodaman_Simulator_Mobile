import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// 슬롯 안 캐릭터 원형 배지의 테두리 색으로 속성(火水木木光闇, 5종만)을 추정한다.
/// 데스크톱 `DeckScreenshotRecognitionService.DetectBasicAttributeFromBadge`를 그대로
/// 이식([[kotodaman-mobile-flutter-port]] 참고) — ORB만으로는 헷갈리는 후보를 속성색으로
/// 가볍게 보정하는 보조 신호. 모바일은 검수 축적 학습(PRD §7.1 제외)이 없어서 데스크톱의
/// "학습 프로필 코사인유사도" 경로는 포팅하지 않고, 학습 없이도 쓰는 기본 Hough-circle
/// 휴리스틱만 가져왔다.
///
/// 天/冥/虹은 기본 HSV 규칙으로는 火/水/木/光/闇 중 하나로 오판하기 쉬워 데스크톱도
/// 이 5종만 판정한다 — 나머지 속성 캐릭터는 그냥 판정 없음(evidence.none) 취급.
class AttributeColorEvidence {
  final String attribute; // '' means no evidence
  final double confidence;
  const AttributeColorEvidence(this.attribute, this.confidence);
  static const none = AttributeColorEvidence('', 0);
}

const List<String> _kBasicAttributes = ['火', '水', '木', '光', '闇'];
const double _kMinimumConfidence = 0.45; // GetAttributeRankingAdjustment 문턱값과 동일.

/// [colorSlot]은 슬롯을 크롭한 BGR(3채널) Mat — 업스케일 전 원본 크기 그대로 넣는다
/// (데스크톱도 인식용으로 확대한 그레이스케일이 아니라 원본 슬롯 크롭을 그대로 씀).
AttributeColorEvidence detectBasicAttributeFromBadge(cv.Mat colorSlot) {
  if (colorSlot.isEmpty || colorSlot.cols < 48 || colorSlot.rows < 48) return AttributeColorEvidence.none;

  final cols = colorSlot.cols;
  final rows = colorSlot.rows;

  final gray = cv.cvtColor(colorSlot, cv.COLOR_BGR2GRAY);
  final roiWidth = (cols * 0.72).round().clamp(1, cols);
  final roiHeight = (rows * 0.48).round().clamp(1, rows);
  final roi = gray.region(cv.Rect(0, 0, roiWidth, roiHeight));
  final blurred = cv.gaussianBlur(roi, (5, 5), 1.2);
  roi.dispose();
  gray.dispose();

  final minDimension = math.min(cols, rows);
  final minRadius = math.max(14, (minDimension * 0.085).round());
  // 6열x2행 슬롯은 폭이 좁아 문자 원 반지름이 폭 대비 더 크게 잡힌다(약 0.20~0.21).
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
    return AttributeColorEvidence.none;
  }
  blurred.dispose();

  final circleCount = circles.total;
  if (circleCount == 0) {
    circles.dispose();
    return AttributeColorEvidence.none;
  }

  final hsv = cv.cvtColor(colorSlot, cv.COLOR_BGR2HSV);

  // v1.25.2의 6열x2행 그리드 보정값 — 12칸 모두 문자 원이 슬롯 왼쪽 약 16%, 위쪽 약 20%
  // 지점에 온다(슬롯이 세로로 길어져 비율이 이동). ponytail: 4×3 그리드는 이 비율이 정확히
  // 안 맞을 수 있음 — 그래도 안전한 실패(그냥 evidence.none)라 4×3에서 손해는 없다.
  final expectedCenterX = cols * 0.163;
  final expectedCenterY = rows * 0.198;
  final allowedXDistance = cols * 0.16;
  final allowedYDistance = rows * 0.15;

  var bestAttribute = '';
  var bestEvidenceScore = 0.0;
  var bestConfidence = 0.0;

  final circleRowMajor = circles.rows == 1;
  final circlesToCheck = math.min(circleCount, 14);
  for (var i = 0; i < circlesToCheck; i++) {
    final pixel = circleRowMajor ? circles.atPixel(0, i) : circles.atPixel(i, 0);
    final centerX = pixel[0].toDouble();
    final centerY = pixel[1].toDouble();
    final radius = pixel[2].toDouble();
    final xDistance = (centerX - expectedCenterX).abs();
    final yDistance = (centerY - expectedCenterY).abs();
    if (centerX < 0 ||
        centerY < 0 ||
        centerX > cols * 0.72 ||
        centerY > rows * 0.48 ||
        xDistance > allowedXDistance ||
        yDistance > allowedYDistance) {
      continue;
    }

    final votes = {for (final a in _kBasicAttributes) a: 0};

    final x0 = math.max(0, (centerX - radius * 0.82).floor());
    final x1 = math.min(cols - 1, (centerX + radius * 0.82).ceil());
    final y0 = math.max(0, (centerY - radius * 0.82).floor());
    final y1 = math.min(rows - 1, (centerY + radius * 0.82).ceil());
    final innerRadiusSquared = radius * radius * 0.82 * 0.82;
    var coloredPixelCount = 0;

    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - centerX;
        final dy = y - centerY;
        if (dx * dx + dy * dy > innerRadiusSquared) continue;

        final p = hsv.atPixel(y, x);
        final hue = p[0].toInt();
        final saturation = p[1].toInt();
        final value = p[2].toInt();
        if (saturation < 78 || value < 60) continue;

        coloredPixelCount++;
        if (hue <= 8 || hue >= 174) {
          votes['火'] = votes['火']! + 1;
        } else if (hue >= 98 && hue <= 119) {
          votes['水'] = votes['水']! + 1;
        } else if (hue >= 40 && hue <= 84) {
          votes['木'] = votes['木']! + 1;
        } else if (hue >= 20 && hue <= 38 && value >= 135) {
          votes['光'] = votes['光']! + 1;
        } else if (hue >= 123 && hue <= 160) {
          votes['闇'] = votes['闇']! + 1;
        }
      }
    }

    if (coloredPixelCount < 80) continue;

    final rankedVotes = votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final attribute = rankedVotes[0].key;
    final topVotes = rankedVotes[0].value;
    final secondVotes = rankedVotes.length > 1 ? rankedVotes[1].value : 0;
    if (topVotes < 36) continue;

    final purity = topVotes / math.max(1, topVotes + secondVotes);
    final coverage = topVotes / math.max(1, coloredPixelCount);
    final minimumPurity = attribute == '光' ? 0.72 : 0.58;
    if (purity < minimumPurity || coverage < 0.08) continue;

    final voteStrength = (topVotes / 240.0).clamp(0.0, 1.0);
    final confidence = (((purity - minimumPurity) / math.max(0.01, 1.0 - minimumPurity)) * 0.55 + voteStrength * 0.45)
        .clamp(0.0, 1.0);
    final positionDistance =
        xDistance / math.max(1.0, allowedXDistance) + yDistance / math.max(1.0, allowedYDistance);
    final positionWeight = (1.15 - positionDistance * 0.42).clamp(0.45, 1.15);
    final evidenceScore = topVotes * (0.5 + purity * 0.5) * positionWeight;

    if (confidence >= 0.42 && evidenceScore > bestEvidenceScore) {
      bestEvidenceScore = evidenceScore;
      bestAttribute = attribute;
      // 기본 HSV 규칙은 天/冥/虹을 光 등으로 오판할 여지가 있어 강한 자동확정 기준(72%)까지는
      // 안 올라가게 상한을 둔다.
      bestConfidence = math.min(confidence, 0.68);
    }
  }

  hsv.dispose();
  circles.dispose();

  return bestAttribute.isEmpty || bestConfidence < 0.55
      ? AttributeColorEvidence.none
      : AttributeColorEvidence(bestAttribute, bestConfidence);
}

/// 후보 캐릭터의 속성이 감지된 배지 색과 일치하면 순위 점수에 소폭 가산한다(데스크톱
/// `GetAttributeRankingAdjustment`의 기본-휴리스틱 분기와 동일 — 학습 색상 경로는 모바일에
/// 없어서 뺐다). 불일치해도 감점하지 않는다 — 기본 HSV가 천/명/홍 속성을 잘못 볼 수 있어서,
/// 틀렸다고 후보를 깎으면 오히려 정답을 밀어낼 수 있기 때문(데스크톱 주석 그대로 계승).
double attributeRankingAdjustment(String characterAttribute, AttributeColorEvidence evidence) {
  if (evidence.confidence < _kMinimumConfidence || evidence.attribute.isEmpty) return 0;
  return characterAttribute == evidence.attribute ? 0.8 * evidence.confidence : 0;
}
