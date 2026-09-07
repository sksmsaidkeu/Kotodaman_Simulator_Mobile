import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// `assets/letter_templates/*.png`(파일명은 로마자, 예 `ka.png`=か)를 한 번만 읽어
/// 글자→48x48 그레이스케일 Mat 맵으로 캐싱한다 — TemplateDescriptorCache와 동일한 전략
/// (프로세스가 살아있는 동안 재사용, 재시작하면 다시 로드).
class LetterTemplateCache {
  static Future<Map<String, cv.Mat>>? _future;

  static Future<Map<String, cv.Mat>> load() => _future ??= _build();

  static Future<Map<String, cv.Mat>> _build() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets().where((k) => k.startsWith('assets/letter_templates/')).toList();
    final result = <String, cv.Mat>{};
    for (final key in keys) {
      final romaji = key.split('/').last.replaceAll('.png', '');
      final letter = _kRomajiToKana[romaji];
      if (letter == null) continue;
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      result[letter] = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    }
    return result;
  }
}

// 파일 시스템에 안전한 로마자 파일명 <-> 실제 글자 매핑. 템플릿을 늘릴 때는 이 맵에도
// 항목을 추가해야 한다([[kotodaman-mobile-flutter-port]] 다음 세션 절 참고 — 지금은
// 실제 스크린샷 1장에서 뽑은 9종뿐).
const Map<String, String> _kRomajiToKana = {
  'a': 'あ',
  'u': 'う',
  'ka': 'か',
  'ko': 'こ',
  'tsu': 'つ',
  'ma': 'ま',
  'mu': 'む',
  'yo': 'よ',
  'n': 'ん',
};
