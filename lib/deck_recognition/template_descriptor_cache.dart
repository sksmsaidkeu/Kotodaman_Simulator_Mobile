import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:word_search_engine/word_search_engine.dart';

import '../character_avatar.dart';
import 'image_ops.dart';
import 'parallel_orb_matcher.dart';

/// 캐릭터 2,319명 전체 ORB 템플릿 디스크립터 — 빌드 비용이 커서 앱 프로세스가 살아있는
/// 동안 한 번만 만들어 재사용한다(인식 화면을 다시 열어도 재빌드하지 않음).
/// ponytail: 프로세스를 재시작하면 다시 빌드됨(디스크 캐시 없음) — 실사용해보고 빌드
/// 시간이 문제가 되면 그때 파일로 직렬화하는 디스크 캐시를 추가한다.
class TemplateDescriptorCache {
  static Future<List<TemplateDescriptor>>? _future;

  static Future<List<TemplateDescriptor>> load(
    List<CharacterEntry> characters, {
    void Function(int done, int total)? onProgress,
  }) {
    return _future ??= _build(characters, onProgress);
  }

  static Future<List<TemplateDescriptor>> _build(
    List<CharacterEntry> characters,
    void Function(int done, int total)? onProgress,
  ) async {
    final orb = cv.ORB.create(nFeatures: 600);
    final result = <TemplateDescriptor>[];
    var done = 0;
    for (final c in characters) {
      if (c.imageFileName.isNotEmpty) {
        final data = await rootBundle.load(characterImagePath(c.imageFileName));
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final mat = decodeUpscaledGray(bytes);
        final mask = cv.Mat.empty();
        final (keypoints, desc) = orb.detectAndCompute(mat, mask);
        if (!desc.isEmpty) {
          // TemplateDescriptor.fromMat이 .data를 Uint8List로 복사해가므로, 원본 네이티브
          // Mat은 여기서 바로 해제한다(안 그러면 2,319명분 Mat이 전부 native 메모리에 남는다).
          result.add(TemplateDescriptor.fromMat(c.id, c.name, desc));
        }
        mat.dispose();
        mask.dispose();
        keypoints.dispose();
        desc.dispose();
      }
      done++;
      onProgress?.call(done, characters.length);
    }
    return result;
  }
}
