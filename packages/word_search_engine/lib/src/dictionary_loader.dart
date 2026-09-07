import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// gzip 압축된 사전(`gaccag_words.json.gz`, `[{"Text": "...", ...}, ...]`) 바이트를
/// 풀어 단어 텍스트 목록으로 만든다. 모바일은 이 사전 하나만 번들하므로(PRD §3 FR-1)
/// 데스크톱 `JsonDataLoader.LoadWords`의 BuiltIn/User 병합·소스 우선순위는 이식하지
/// 않았다. Flutter 앱에서는 `rootBundle.load()`로 받은 바이트를 그대로 넘기면 되고,
/// 이 패키지 자체는 dart:io만 쓰므로 Flutter 의존이 없다.
List<String> decodeDictionaryWords(Uint8List gzipBytes) {
  final decompressed = GZipCodec().decode(gzipBytes);
  final list = json.decode(utf8.decode(decompressed)) as List<dynamic>;
  return list
      .map((entry) => (entry as Map<String, dynamic>)['Text'] as String?)
      .whereType<String>()
      .where((text) => text.trim().isNotEmpty)
      .toList();
}
