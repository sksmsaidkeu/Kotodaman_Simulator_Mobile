import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:word_search_engine/word_search_engine.dart';

import '../app_data.dart';
import '../character_avatar.dart';
import 'image_ops.dart';

/// PRD_Mobile.md §8 3단계 착수 전 성능 확인 스파이크 — 캐릭터 템플릿 N명으로 ORB 매칭
/// 실제 속도를 잰다(전체 2,319명 확장 전에 먼저 규모를 가늠). 0단계 `orb_spike_page.dart`와
/// 같은 패턴, 캐릭터 실제 이미지를 템플릿으로 쓴다는 점만 다르다.
/// 현재는 앱 내비게이션에 연결돼 있지 않다(측정 전용, `main.dart`에서 임시로 홈으로 교체해 사용).
class OrbMatchSpeedPage extends StatefulWidget {
  const OrbMatchSpeedPage({super.key});

  @override
  State<OrbMatchSpeedPage> createState() => _OrbMatchSpeedPageState();
}

const int _kTemplateCount = 50;
const int _kFullCharacterCount = 2319;

class _OrbMatchSpeedPageState extends State<OrbMatchSpeedPage> {
  bool _running = false;
  String _log = '대기 중 — 버튼을 눌러 측정을 시작하세요';

  Future<void> _run() async {
    setState(() {
      _running = true;
      _log = '캐릭터 데이터 로딩 중...';
    });

    final appData = await loadAppData();
    final templateCharacters = appData.characters.take(_kTemplateCount).toList();

    final orb = cv.ORB.create(nFeatures: 600);
    final matcher = cv.BFMatcher.create();

    setState(() => _log = '템플릿 ${templateCharacters.length}명 디스크립터 생성 중...');

    final templateDescriptors = <(CharacterEntry, cv.Mat)>[];
    final buildStopwatch = Stopwatch()..start();
    for (final c in templateCharacters) {
      final data = await rootBundle.load(characterImagePath(c.imageFileName));
      final mat = decodeUpscaledGray(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final (_, desc) = orb.detectAndCompute(mat, cv.Mat.empty());
      if (!desc.isEmpty) {
        templateDescriptors.add((c, desc));
      }
    }
    buildStopwatch.stop();

    setState(() => _log = '$_log\n템플릿 생성 완료: ${buildStopwatch.elapsedMilliseconds}ms '
        '(평균 ${(buildStopwatch.elapsedMilliseconds / templateCharacters.length).toStringAsFixed(1)}ms/명)');

    // 쿼리: 학습 샘플(실제 인게임 슬롯 크롭) 몇 장 — 0단계 스파이크 자산 재사용.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final queryPaths = manifest.listAssets().where((k) => k.startsWith('assets/orb_spike/refs/')).toList()
      ..sort();

    final buffer = StringBuffer(_log);
    int totalMatchMs = 0;
    int queryCount = 0;

    for (final path in queryPaths.take(5)) {
      final data = await rootBundle.load(path);
      final queryMat = decodeUpscaledGray(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final (_, queryDesc) = orb.detectAndCompute(queryMat, cv.Mat.empty());
      if (queryDesc.isEmpty) continue;

      final sw = Stopwatch()..start();
      String bestName = '(매칭 없음)';
      int bestGood = 0;
      for (final (character, templateDesc) in templateDescriptors) {
        final knn = matcher.knnMatch(templateDesc, queryDesc, 2);
        int good = 0;
        for (final pair in knn) {
          if (pair.length == 2 && pair[0].distance < 0.75 * pair[1].distance) good++;
        }
        if (good > bestGood) {
          bestGood = good;
          bestName = character.name;
        }
      }
      sw.stop();
      totalMatchMs += sw.elapsedMilliseconds;
      queryCount++;

      buffer.writeln();
      buffer.write('${path.split('/').last}: ${sw.elapsedMilliseconds}ms, 최고후보=$bestName ($bestGood matches)');
      setState(() => _log = buffer.toString());
    }

    if (queryCount > 0) {
      final avgPerQuery = totalMatchMs / queryCount;
      final avgPerTemplate = avgPerQuery / templateDescriptors.length;
      final estimateFull = (avgPerTemplate * _kFullCharacterCount).round();
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('쿼리 1장당 평균 매칭시간: ${avgPerQuery.toStringAsFixed(0)}ms '
          '(템플릿 ${templateDescriptors.length}명 기준)');
      buffer.write('2,319명 전체로 확장 시 추정: 쿼리 1장당 약 ${estimateFull}ms');
    }

    setState(() {
      _running = false;
      _log = buffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ORB 매칭 속도 측정 (캐릭터 템플릿)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? '측정 중...' : '측정 시작 (템플릿 $_kTemplateCount명)'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_log, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
