import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// 짧은 변이 180px 미만이면 업스케일(최대 2.4배) — 데스크톱 로직과 동일, ORB가 작은
/// 이미지에서 특징점을 충분히 못 뽑는 문제 대응. 캐릭터 템플릿·스크린샷 슬롯 크롭 양쪽에서 공용.
cv.Mat decodeUpscaledGray(Uint8List bytes) {
  return upscaleGrayIfSmall(cv.imdecode(bytes, cv.IMREAD_GRAYSCALE));
}

/// [mat]의 소유권을 넘겨받는다 — 업스케일이 필요하면 새 Mat을 만들고 원본은 여기서
/// 해제하며, 필요 없으면 원본을 그대로 돌려준다. 호출자는 반환값 하나만 관리하면 된다.
cv.Mat upscaleGrayIfSmall(cv.Mat mat) {
  if (mat.cols >= 180) return mat;
  final scale = (180 / mat.cols).clamp(1.0, 2.4);
  final resized = cv.resize(mat, (0, 0), fx: scale, fy: scale, interpolation: cv.INTER_CUBIC);
  mat.dispose();
  return resized;
}
