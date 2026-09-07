import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../app_data.dart';
import '../character_avatar.dart';
import 'parallel_orb_matcher.dart';

/// PRD_Mobile.md §8 3단계 — isolate 병렬화만으로는 가속비가 ~2.5배에 막힌다는 걸
/// 확인([[kotodaman-mobile-flutter-port]] ORB 매칭 속도 스파이크 결과, 이 폰은
/// 이 연산에 쓸만한 "빠른 코어"가 사실상 2개뿐인 것으로 추정)했으므로, 이번엔
/// 1차 스캔(전체 2,319명)의 ORB 특징점 수 자체를 줄여서(600→150) 연산량을 줄이는
/// 실험. 특징점은 반응 강도순으로 담기므로 이미 뽑은 600개 중 앞 150개만 잘라
/// 쓰면(재검출 없이) 600개 결과를 "정답"으로 삼아 150개 결과의 정확도를 검증할 수 있다.
class ParallelMatchSpeedPage extends StatefulWidget {
  const ParallelMatchSpeedPage({super.key});

  @override
  State<ParallelMatchSpeedPage> createState() => _ParallelMatchSpeedPageState();
}

const int _kBroadFeatureCap = 150;
const int _kCutCandidateCount = 300; // 데스크톱 FullRefineCandidateCount(220)+속성구제(80) 근사치

class _ParallelMatchSpeedPageState extends State<ParallelMatchSpeedPage> {
  bool _running = false;
  String _log = '대기 중 — 버튼을 눌러 측정을 시작하세요 (2,319명 전체, 시간이 좀 걸립니다)';

  cv.Mat _decodeUpscaled(Uint8List bytes) {
    var mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    if (mat.cols < 180) {
      final scale = (180 / mat.cols).clamp(1.0, 2.4);
      mat = cv.resize(mat, (0, 0), fx: scale, fy: scale, interpolation: cv.INTER_CUBIC);
    }
    return mat;
  }

  /// ORB는 특징점을 반응 강도 내림차순으로 담으므로, 앞 [maxRows]개만 잘라내면
  /// "처음부터 nFeatures를 작게 잡고 재검출한 것"과 사실상 동등한 결과가 된다.
  cv.Mat _capRows(cv.Mat mat, int maxRows) {
    if (mat.rows <= maxRows) return mat;
    return cv.Mat.fromRange(mat, 0, maxRows);
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _log = '캐릭터 데이터 로딩 중...';
    });

    final appData = await loadAppData();
    final characters = appData.characters;
    final orb = cv.ORB.create(nFeatures: 600);

    setState(() => _log = '템플릿 ${characters.length}명 디스크립터 생성 중... (한 번만 하면 되는 비용)');

    final templatesFull = <TemplateDescriptor>[];
    final templatesBroad = <TemplateDescriptor>[];
    final buildStopwatch = Stopwatch()..start();
    for (var i = 0; i < characters.length; i++) {
      final c = characters[i];
      final data = await rootBundle.load(characterImagePath(c.imageFileName));
      final mat = _decodeUpscaled(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final (_, desc) = orb.detectAndCompute(mat, cv.Mat.empty());
      if (!desc.isEmpty) {
        templatesFull.add(TemplateDescriptor.fromMat(c.id, c.name, desc));
        templatesBroad.add(TemplateDescriptor.fromMat(c.id, c.name, _capRows(desc, _kBroadFeatureCap)));
      }
      if (i % 300 == 0) {
        setState(() => _log = '템플릿 디스크립터 생성 중... $i/${characters.length}');
      }
    }
    buildStopwatch.stop();

    final buffer = StringBuffer(_log);
    buffer.writeln();
    buffer.writeln('템플릿 생성 완료: ${buildStopwatch.elapsedMilliseconds}ms '
        '(템플릿 ${templatesFull.length}개, 이건 앱 실행 중 한 번만 드는 비용)');
    setState(() => _log = buffer.toString());

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final queryPaths = manifest.listAssets().where((k) => k.startsWith('assets/orb_spike/refs/')).toList()
      ..sort();

    int totalTruthMs = 0;
    int totalBroadMs = 0;
    int queryCount = 0;
    int top1Matches = 0;
    int within300 = 0;

    for (final path in queryPaths.take(3)) {
      final data = await rootBundle.load(path);
      final queryMat = _decodeUpscaled(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final (_, queryDescFull) = orb.detectAndCompute(queryMat, cv.Mat.empty());
      if (queryDescFull.isEmpty) continue;
      final queryDescBroad = _capRows(queryDescFull, _kBroadFeatureCap);

      // 정답 기준선: 특징점 600개 전체로 한 병렬 매칭(isolate 병렬화만 적용한 이전 실험과 동일 조건).
      final truthSw = Stopwatch()..start();
      final truthResults = await matchTemplatesParallel([queryDescFull], templatesFull);
      truthSw.stop();
      final truth = truthResults.isNotEmpty ? truthResults.first : null;

      // 실험 대상: 특징점 150개로 잘라서 한 병렬 매칭.
      final broadSw = Stopwatch()..start();
      final broadResults = await matchTemplatesParallel([queryDescBroad], templatesBroad);
      broadSw.stop();
      final broadBest = broadResults.isNotEmpty ? broadResults.first : null;

      totalTruthMs += truthSw.elapsedMilliseconds;
      totalBroadMs += broadSw.elapsedMilliseconds;
      queryCount++;

      final isTop1Match = truth != null && broadBest != null && broadBest.id == truth.id;
      final truthRank = truth == null ? -1 : broadResults.indexWhere((m) => m.id == truth.id);
      final isWithinCut = truthRank >= 0 && truthRank < _kCutCandidateCount;
      if (isTop1Match) top1Matches++;
      if (isWithinCut) within300++;

      buffer.writeln();
      buffer.writeln('${path.split('/').last}:');
      buffer.writeln('  정답(특징점600): ${truthSw.elapsedMilliseconds}ms, 1위=${truth?.name} (${truth?.matchCount} matches)');
      buffer.writeln('  실험(특징점150): ${broadSw.elapsedMilliseconds}ms, 1위=${broadBest?.name} '
          '(${broadBest?.matchCount} matches) ${isTop1Match ? "✓1위일치" : "1위다름"}, '
          '정답 순위=${truthRank < 0 ? "밖" : "$truthRank위"} ${isWithinCut ? "✓상위$_kCutCandidateCount 안" : "✗컷 밖!"}');
      setState(() => _log = buffer.toString());
    }

    if (queryCount > 0) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('정답(특징점600) 평균: ${(totalTruthMs / queryCount).toStringAsFixed(0)}ms/쿼리');
      buffer.writeln('실험(특징점150) 평균: ${(totalBroadMs / queryCount).toStringAsFixed(0)}ms/쿼리');
      buffer.writeln('배속: ${(totalTruthMs / totalBroadMs).toStringAsFixed(1)}x');
      buffer.writeln('1위 일치: $top1Matches/$queryCount, 상위 $_kCutCandidateCount 안에 정답 포함: $within300/$queryCount');
      buffer.writeln('12슬롯 예상(특징점150, 1차 스캔만): ${((totalBroadMs / queryCount) * 12 / 1000).toStringAsFixed(1)}초');
    }

    setState(() {
      _running = false;
      _log = buffer.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('1차 스캔 특징점 축소 실험 (600→150)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? '측정 중... (수십 초 소요)' : '측정 시작 (전체 2,319명)'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_log, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
