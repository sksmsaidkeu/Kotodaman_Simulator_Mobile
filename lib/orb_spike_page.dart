import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// 0단계 실현가능성 스파이크(PRD_Mobile.md §8 0단계) — ORB 매칭 속도 검증용.
/// 3단계(스크린샷 덱 인식, FR-4)에서 다시 참고/확장할 코드라 남겨둔다.
/// 현재는 앱 내비게이션에 연결돼 있지 않다.
class OrbSpikePage extends StatefulWidget {
  const OrbSpikePage({super.key});

  @override
  State<OrbSpikePage> createState() => _OrbSpikePageState();
}

class _MatchResult {
  final String refName;
  final int goodMatches;
  final int elapsedMs;
  _MatchResult(this.refName, this.goodMatches, this.elapsedMs);
}

class _OrbSpikePageState extends State<OrbSpikePage> {
  bool _running = false;
  String _status = '대기 중 — 아래 버튼을 눌러 ORB 매칭 스파이크를 시작하세요';
  List<_MatchResult> _results = [];

  Future<List<String>> _listRefAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().where((k) => k.startsWith('assets/orb_spike/refs/')).toList()..sort();
  }

  Future<void> _runSpike() async {
    setState(() {
      _running = true;
      _status = '씬 이미지 로딩 중...';
      _results = [];
    });

    final sceneBytes = await rootBundle.load('assets/orb_spike/scene.jpg');
    final sceneMat = cv.imdecode(
      sceneBytes.buffer.asUint8List(),
      cv.IMREAD_GRAYSCALE,
    );

    final orb = cv.ORB.create();
    final swScene = Stopwatch()..start();
    final (sceneKp, sceneDesc) = orb.detectAndCompute(sceneMat, cv.Mat.empty());
    swScene.stop();

    setState(() {
      _status =
          '씬 특징점 ${sceneKp.length}개 추출: ${swScene.elapsedMilliseconds}ms\n레퍼런스 매칭 중...';
    });

    final refPaths = await _listRefAssets();
    final matcher = cv.BFMatcher.create();
    final results = <_MatchResult>[];
    int totalMs = swScene.elapsedMilliseconds;

    for (final path in refPaths) {
      final data = await rootBundle.load(path);
      final sw = Stopwatch()..start();

      final refMat = cv.imdecode(data.buffer.asUint8List(), cv.IMREAD_GRAYSCALE);
      final (_, refDesc) = orb.detectAndCompute(refMat, cv.Mat.empty());

      int good = 0;
      if (!refDesc.isEmpty && !sceneDesc.isEmpty) {
        final knn = matcher.knnMatch(refDesc, sceneDesc, 2);
        for (final pair in knn) {
          if (pair.length == 2 && pair[0].distance < 0.75 * pair[1].distance) {
            good++;
          }
        }
      }
      sw.stop();
      totalMs += sw.elapsedMilliseconds;

      results.add(_MatchResult(path.split('/').last, good, sw.elapsedMilliseconds));

      setState(() {
        _results = List.of(results);
        _status = '${results.length}/${refPaths.length} 처리 중... (누적 ${totalMs}ms)';
      });
    }

    setState(() {
      _running = false;
      _status = '완료 — 레퍼런스 ${refPaths.length}장, 총 ${totalMs}ms '
          '(레퍼런스 1장당 평균 ${(totalMs / refPaths.length).toStringAsFixed(0)}ms)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('코토다망 ORB 매칭 속도 스파이크')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _running ? null : _runSpike,
              child: Text(_running ? '실행 중...' : 'ORB 매칭 스파이크 실행'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(r.refName),
                    trailing: Text('${r.goodMatches} matches / ${r.elapsedMs}ms'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
