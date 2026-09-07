import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ORB 디스크립터 매칭을 여러 isolate에 나눠 돌려서 대규모 캐릭터 DB(2,319명) 스캔
/// 시간을 코어 수만큼 줄인다. 데스크톱 `DeckScreenshotRecognitionService`의
/// `Parallel.ForEach` 병렬화에 대응하는 부분([[kotodaman-mobile-flutter-port]] 3단계 참고).
///
/// `cv.Mat`은 네이티브 포인터를 감싸고 있어 isolate 경계를 못 건너므로, 디스크립터를
/// (rows, cols, bytes)로 풀어 보내고 각 isolate에서 `Mat.fromList`로 재구성한다.
/// 템플릿 디스크립터 자체를 만드는 비용(ORB.detectAndCompute)은 한 번만 하면 되므로
/// 여기서는 다루지 않고, 이미 만들어진 디스크립터로 하는 매칭만 병렬화한다.
///
/// 워커는 슬롯(호출)마다 새로 스폰하지 않고 세션 동안 재사용한다 — `Isolate.run`으로
/// 매번 새 isolate를 만들고 죽이면 OS 스레드/네이티브 힙 정리가 생성 속도를 못 따라가서
/// 몇 슬롯 뒤 네이티브 OOM(Scudo)으로 죽는 게 실기기에서 재현됐다(12슬롯 중 10번째
/// 근처, [[kotodaman-mobile-flutter-port]] 3단계 크래시 수정 절 참고 — Mat dispose를
/// 전부 챙긴 뒤에도 같은 지점에서 재현되어 isolate churn 자체가 원인으로 확정).
///
/// [queries]가 여러 개(슬롯 하나당 여러 ROI)면 템플릿마다 모든 쿼리와 매칭해 본 뒤
/// 가장 좋은 결과를 채택한다(데스크톱 `ScoreTemplate`의 "여러 ROI 중 최선" 방식과 동일) —
/// 인물 아트가 슬롯 안 어디에 있는지 프레이밍이 어긋나도 어느 한 ROI가 맞아떨어지면
/// 잡아낸다. 그만큼 매칭 연산량이 ROI 개수배로 늘어난다(정확도 우선, 사용자 확인 완료).

class TemplateDescriptor {
  final String id;
  final String name;
  final int rows;
  final int cols;
  final Uint8List bytes;

  const TemplateDescriptor({
    required this.id,
    required this.name,
    required this.rows,
    required this.cols,
    required this.bytes,
  });

  factory TemplateDescriptor.fromMat(String id, String name, cv.Mat descriptors) => TemplateDescriptor(
        id: id,
        name: name,
        rows: descriptors.rows,
        cols: descriptors.cols,
        bytes: Uint8List.fromList(descriptors.data),
      );
}

class MatchScore {
  final String id;
  final String name;
  final int matchCount;
  final double meanDistance;

  const MatchScore({required this.id, required this.name, required this.matchCount, required this.meanDistance});
}

const double _ratioTestThreshold = 0.75;

// ORB 디스크립터는 이진(비트) 값이라 거리 척도는 Hamming이 맞다 — 이전엔 BFMatcher가
// 기본값(NORM_L2, 유클리드 거리)으로 생성돼 바이트값 차이를 재고 있었다(데스크톱은
// 처음부터 NormTypes.Hamming을 명시). 시간 비용 없이 바로 매칭 정확도가 오르는 수정.
const int _kNormType = cv.NORM_HAMMING;

class _Worker {
  final SendPort sendPort;
  final Isolate isolate;
  _Worker(this.sendPort, this.isolate);
}

/// 세션 동안 재사용되는 고정 워커 풀 — 첫 호출에서 한 번만 스폰된다.
/// ponytail: 앱 프로세스가 살아있는 동안 유지되고 명시적으로 죽이지 않는다
/// (TemplateDescriptorCache와 동일한 전략 — 인식 화면을 다시 열어도 재스폰 없음).
class _WorkerPool {
  final List<_Worker> workers;
  _WorkerPool(this.workers);

  int get size => workers.length;

  static Future<_WorkerPool> spawn(int count) async {
    final workers = await Future.wait(List.generate(count, (_) => _spawnWorker()));
    return _WorkerPool(workers);
  }

  static Future<_Worker> _spawnWorker() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, ready.sendPort);
    final workerSendPort = await ready.first as SendPort;
    ready.close();
    return _Worker(workerSendPort, isolate);
  }

  Future<List<Map<String, Object>>> dispatch(int index, Map<String, dynamic> job) async {
    final reply = ReceivePort();
    workers[index].sendPort.send({...job, 'replyPort': reply.sendPort});
    final result = await reply.first;
    reply.close();
    return (result as List).cast<Map<String, Object>>();
  }
}

Future<_WorkerPool>? _poolFuture;

Future<_WorkerPool> _ensurePool(int size) => _poolFuture ??= _WorkerPool.spawn(size);

/// [templates]를 워커 풀 크기만큼 나눠 병렬로 [queries](슬롯 하나당 여러 ROI 디스크립터)와
/// 매칭하고, 매칭수 내림차순으로 정렬된 결과를 합쳐 반환한다. 청크마다 상위 [keepPerChunk]개만
/// 유지 후 병합한다(전체 결과를 다 들고 있을 필요 없이 최종 상위 N개만 있으면 되므로).
Future<List<MatchScore>> matchTemplatesParallel(
  List<cv.Mat> queries,
  List<TemplateDescriptor> templates, {
  int keepPerChunk = 260,
}) async {
  final usableQueries = queries.where((q) => q.rows >= 2).toList();
  if (templates.isEmpty || usableQueries.isEmpty) return [];

  // 코어 개수만큼만 나누면 big.LITTLE(성능 코어/효율 코어 혼합) 모바일 SoC에서
  // 가장 느린 코어가 맡은 청크가 전체 완료 시간을 좌우한다(실측: 8청크=2.1배 가속에 그침).
  // 코어 수보다 훨씬 잘게 나누면 OS 스케줄러가 빠른 코어에 청크를 더 몰아줘서
  // 자연스럽게 부하가 분산된다 — 청크당 템플릿 ~100개를 목표로 개수를 정한다.
  final poolSize = (templates.length / 100).ceil().clamp(Platform.numberOfProcessors, 32);
  final pool = await _ensurePool(poolSize);
  final chunkCount = pool.size;
  final queryData = usableQueries
      .map((q) => {'rows': q.rows, 'cols': q.cols, 'bytes': Uint8List.fromList(q.data)})
      .toList();

  final chunkSize = (templates.length / chunkCount).ceil();
  final futures = <Future<List<Map<String, Object>>>>[];
  var workerIndex = 0;
  for (var start = 0; start < templates.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, templates.length).toInt();
    final chunk = templates.sublist(start, end);
    final job = {
      'queries': queryData,
      'templates': chunk
          .map((t) => {'id': t.id, 'name': t.name, 'rows': t.rows, 'cols': t.cols, 'bytes': t.bytes})
          .toList(),
      'keep': keepPerChunk,
    };
    futures.add(pool.dispatch(workerIndex % pool.size, job));
    workerIndex++;
  }

  final chunkResults = await Future.wait(futures);
  final merged = <MatchScore>[];
  for (final chunkResult in chunkResults) {
    for (final m in chunkResult) {
      merged.add(MatchScore(
        id: m['id'] as String,
        name: m['name'] as String,
        matchCount: m['matchCount'] as int,
        meanDistance: m['meanDistance'] as double,
      ));
    }
  }
  merged.sort((a, b) {
    final byCount = b.matchCount.compareTo(a.matchCount);
    if (byCount != 0) return byCount;
    return a.meanDistance.compareTo(b.meanDistance);
  });
  return merged;
}

// 상위 후보만 상호검증(reciprocal cross-check)으로 재채점한다 — 데스크톱
// `ScoreTemplateReciprocal`과 동일한 방식: ratio test 없이 "서로가 서로의 최선의 짝"인
// 매칭만 세고, 그 개수가 많을수록(최대 20개까지 가산) 원래 점수에 보너스를 얹어 재정렬한다.
// 후보 12개 안팎만 다시 보는 거라 워커 풀 없이 메인 isolate에서 그냥 돌려도 충분히 빠르다.
const double _kReciprocalDistanceThreshold = 64;
const int _kReciprocalRefineCount = 12;

/// [rankedCandidates](matchTemplatesParallel 결과, 매칭수 내림차순 정렬돼 있어야 함) 중
/// 상위 [_kReciprocalRefineCount]개(또는 [candidateCount] 중 큰 쪽)를 상호검증으로 재채점해
/// 상위 [candidateCount]개를 반환한다. [templatesById]는 후보 id로 디스크립터를 다시 찾기
/// 위한 맵. [externalBoost]는 캐릭터 id별 추가 가산점(예: 속성색 보조판정) — ORB 매칭수와
/// 같은 단위로 더해진다. 순서 선정과 최종 재정렬 양쪽에 반영한다(데스크톱도 두 단계 다
/// `MatchCount + GetAttributeRankingAdjustment`로 계산).
List<MatchScore> refineWithReciprocalCrossCheck({
  required List<cv.Mat> queries,
  required List<MatchScore> rankedCandidates,
  required Map<String, TemplateDescriptor> templatesById,
  int candidateCount = 3,
  Map<String, double> externalBoost = const {},
}) {
  final usableQueries = queries.where((q) => q.rows >= 2).toList();
  if (rankedCandidates.isEmpty) return [];

  final boosted = [...rankedCandidates]
    ..sort((a, b) {
      final boostedA = a.matchCount + (externalBoost[a.id] ?? 0);
      final boostedB = b.matchCount + (externalBoost[b.id] ?? 0);
      final byBoosted = boostedB.compareTo(boostedA);
      if (byBoosted != 0) return byBoosted;
      return a.meanDistance.compareTo(b.meanDistance);
    });

  if (usableQueries.isEmpty) {
    return boosted.take(candidateCount).toList();
  }

  // Iterable.take은 요청 개수가 실제 길이보다 많아도 있는 만큼만 반환하므로 안전하다
  // (rankedCandidates.length < _kReciprocalRefineCount인 경우도 그대로 처리됨).
  final refineTargets = boosted.take(_kReciprocalRefineCount).toList();
  final matcher = cv.BFMatcher.create(type: _kNormType, crossCheck: true);

  final scored = <(MatchScore candidate, int reciprocalCount)>[];
  for (final candidate in refineTargets) {
    final template = templatesById[candidate.id];
    if (template == null || template.rows < 2) {
      scored.add((candidate, 0));
      continue;
    }
    final trainMat = cv.Mat.fromList(template.rows, template.cols, cv.MatType.CV_8UC1, template.bytes);
    var bestCount = 0;
    for (final queryMat in usableQueries) {
      final matches = matcher.match(queryMat, trainMat);
      var count = 0;
      for (var i = 0; i < matches.length; i++) {
        final m = matches[i];
        if (m.distance <= _kReciprocalDistanceThreshold) count++;
        m.dispose(); // knnMatch의 pair와 동일한 이유(VecDMatch_get_p가 매번 새로 할당)로 필요.
      }
      matches.dispose();
      if (count > bestCount) bestCount = count;
    }
    trainMat.dispose();
    scored.add((candidate, bestCount));
  }
  matcher.dispose();

  scored.sort((a, b) {
    double combined((MatchScore, int) s) =>
        s.$1.matchCount + s.$2.clamp(0, 20) * 0.075 + (externalBoost[s.$1.id] ?? 0);
    final byCombined = combined(b).compareTo(combined(a));
    if (byCombined != 0) return byCombined;
    final byCount = b.$1.matchCount.compareTo(a.$1.matchCount);
    if (byCount != 0) return byCount;
    final byReciprocal = b.$2.compareTo(a.$2);
    if (byReciprocal != 0) return byReciprocal;
    return a.$1.meanDistance.compareTo(b.$1.meanDistance);
  });

  return scored.take(candidateCount).map((s) => s.$1).toList();
}

/// 워커 isolate의 진입점 — 살아있는 동안 [commandPort]로 들어오는 job을 계속 처리한다
/// (예전처럼 job 하나 처리하고 isolate째 종료하지 않음).
void _workerMain(SendPort mainSendPort) {
  // OpenCV 내부 스레딩이 켜져 있으면 각 워커의 knnMatch 호출이 자체적으로 여러 코어를
  // 또 쓰려 들어서 isolate 단위 병렬화와 코어를 경합한다 — 꺼서 isolate 병렬화에만 맡긴다.
  cv.setNumThreads(1);
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);
  commandPort.listen((message) {
    final job = message as Map<String, dynamic>;
    final replyPort = job['replyPort'] as SendPort;
    replyPort.send(_matchChunk(job));
  });
}

/// 워커 안에서 실행됨 — 인자·반환값 전부 String/int/double/Uint8List/List/Map(sendable
/// 타입)만 사용한다.
List<Map<String, Object>> _matchChunk(Map<String, dynamic> job) {
  final queryData = job['queries'] as List;
  final queryMats = queryData
      .map((q) => cv.Mat.fromList(
            (q as Map)['rows'] as int,
            q['cols'] as int,
            cv.MatType.CV_8UC1,
            q['bytes'] as Uint8List,
          ))
      .toList();
  final matcher = cv.BFMatcher.create(type: _kNormType);
  final templates = job['templates'] as List;
  final keep = job['keep'] as int;

  final results = <Map<String, Object>>[];
  for (final t in templates) {
    final rows = t['rows'] as int;
    final cols = t['cols'] as int;
    if (rows < 2) continue;
    final trainMat = cv.Mat.fromList(rows, cols, cv.MatType.CV_8UC1, t['bytes'] as Uint8List);

    // 슬롯 하나당 여러 ROI 쿼리 중 이 템플릿과 가장 잘 맞는 결과를 채택한다
    // (데스크톱 `ScoreTemplate`과 동일 — 인물 아트 위치가 어느 ROI와 맞아떨어지는지 미리
    // 알 수 없으므로 전부 시도해 최선을 고른다).
    var bestGood = 0;
    var bestMeanDist = 999.0;
    for (final queryMat in queryMats) {
      final knn = matcher.knnMatch(queryMat, trainMat, 2);
      var good = 0;
      var sumDist = 0.0;
      for (final pair in knn) {
        // knn(VecVecDMatch)을 순회할 때 얻는 pair(VecDMatch)는 dartcv4 문서상
        // "참조라 dispose 불필요"라고 되어 있지만, 실제 네이티브 구현
        // (stdvec.cpp: std_VecVecDMatch_get_p)은 호출마다 `new std::vector<cv::DMatch>`+
        // `new VecDMatch`로 진짜 새 힙 할당을 한다 — 문서와 구현이 다른 라이브러리 버그.
        // pair[0]/pair[1] 인덱싱도 마찬가지로 매번 `new DMatch`를 새로 만든다
        // (std_VecDMatch_get_p). 셋 다 안 지우면 슬롯당(키포인트 수 × 템플릿 2,319명)
        // 만큼 쌓여 isolate 구조와 무관하게 몇 슬롯 만에 네이티브 OOM으로 죽는다.
        if (pair.length != 2) {
          pair.dispose();
          continue;
        }
        final best = pair[0];
        final second = pair[1];
        if (best.distance < _ratioTestThreshold * second.distance) {
          good++;
          sumDist += best.distance;
        }
        best.dispose();
        second.dispose();
        pair.dispose();
      }
      knn.dispose();
      final meanDist = good > 0 ? sumDist / good : 999.0;
      if (good > bestGood || (good == bestGood && meanDist < bestMeanDist)) {
        bestGood = good;
        bestMeanDist = meanDist;
      }
    }

    results.add({
      'id': t['id'] as String,
      'name': t['name'] as String,
      'matchCount': bestGood,
      'meanDistance': bestMeanDist,
    });
    // 워커가 계속 살아있으므로(더 이상 job마다 isolate가 죽지 않음) 다음 job을 위해
    // job 하나 안에서 만든 Mat은 여기서 바로 해제해야 한다 — 안 그러면 이 워커가
    // 살아있는 동안 계속 쌓인다.
    trainMat.dispose();
  }
  for (final q in queryMats) {
    q.dispose();
  }
  matcher.dispose();

  results.sort((a, b) => (b['matchCount'] as int).compareTo(a['matchCount'] as int));
  return results.take(keep).toList();
}
