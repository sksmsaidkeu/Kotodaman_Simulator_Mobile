import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:word_search_engine/word_search_engine.dart';

import '../character_avatar.dart';
import '../l10n/app_localizations.dart';
import 'attribute_color_detector.dart';
import 'image_ops.dart';
import 'letter_template_cache.dart';
import 'name_letter_detector.dart';
import 'parallel_orb_matcher.dart';
import 'template_descriptor_cache.dart';

/// 스크린샷 덱 인식(PRD_Mobile.md FR-4) — 갤러리에서 스크린샷 선택 → 그리드 형태(4×3/6×2)
/// 선택 후 12칸 영역 드래그 지정 → 슬롯별 ORB 인식(진행률 표시) → 슬롯별 상위 3후보
/// 검수(자동 확정 아님) → 확정 시 캐릭터 id 목록을 호출자에게 반환. 게임 UI가 업데이트로
/// 4열×3행에서 6열×2행으로 바뀐 적이 있어([[kotodaman-mobile-flutter-port]] 3단계 조사 절
/// 참고) 둘 다 지원한다 — 슬롯 개수(12)는 어느 쪽이든 같다.
class DeckRecognitionPage extends StatefulWidget {
  final List<CharacterEntry> characters;

  const DeckRecognitionPage({super.key, required this.characters});

  @override
  State<DeckRecognitionPage> createState() => _DeckRecognitionPageState();
}

enum _Step { pickImage, selectGrid, recognizing, review }

enum _GridShape {
  fourByThree(columns: 4, rows: 3, label: '4×3'),
  sixByTwo(columns: 6, rows: 2, label: '6×2');

  final int columns;
  final int rows;
  final String label;
  const _GridShape({required this.columns, required this.rows, required this.label});
}

const int _kSlotCount = 12;
const int _kTopCandidates = 3;
const double _kMinTouchTarget = 44;
const double _kMinBodyFont = 16;

// 슬롯 안에서 인물 아트가 실제로 어디 있는지는 프레임마다 조금씩 다를 수 있어, 서로 겹치는
// 3개의 상대 영역(왼쪽/위/오른쪽/아래 비율)에서 각각 특징점을 뽑아 그중 가장 잘 맞는 결과를
// 채택한다 — 데스크톱 `DeckScreenshotRecognitionService.SlotPortraitRegions`(6×2 그리드 기준
// 실측 비율)를 그대로 가져왔다.
// ponytail: 4×3 그리드는 슬롯 가로세로 비율이 달라 이 비율이 정확히 맞지는 않지만, 애초에
// "겹치는 여러 후보 영역 중 최선을 고른다"는 설계라 어느 정도 어긋나도 커버된다 — 실사용
// 테스트에서 4×3 인식률이 눈에 띄게 낮으면 4×3 전용 비율을 새로 재보정한다.
const List<List<double>> _kPortraitRegions = [
  [0.05, 0.02, 0.90, 0.55],
  [0.12, 0.05, 0.85, 0.52],
  [0.00, 0.00, 0.95, 0.58],
];

class _FittedImageRect {
  final Rect rect;
  final double scale; // 박스 픽셀 / 원본 이미지 픽셀
  const _FittedImageRect(this.rect, this.scale);
}

class _DeckRecognitionPageState extends State<DeckRecognitionPage> {
  _Step _step = _Step.pickImage;
  _GridShape _gridShape = _GridShape.fourByThree;
  Uint8List? _imageBytes;
  Size? _naturalSize;
  _FittedImageRect? _fitted;

  Offset? _dragStart;
  Offset? _dragCurrent;

  String _progressLabel = '';
  final List<List<MatchScore>> _slotCandidates = List.generate(_kSlotCount, (_) => []);
  final List<int?> _selected = List<int?>.filled(_kSlotCount, 0);

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _imageBytes = bytes;
      _naturalSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      _dragStart = null;
      _dragCurrent = null;
      _step = _Step.selectGrid;
    });
  }

  _FittedImageRect _computeFittedRect(Size box, Size natural) {
    final boxRatio = box.width / box.height;
    final imgRatio = natural.width / natural.height;
    double width, height;
    if (imgRatio > boxRatio) {
      width = box.width;
      height = width / imgRatio;
    } else {
      height = box.height;
      width = height * imgRatio;
    }
    final left = (box.width - width) / 2;
    final top = (box.height - height) / 2;
    return _FittedImageRect(Rect.fromLTWH(left, top, width, height), width / natural.width);
  }

  Offset _clampToFitted(Offset p) {
    final r = _fitted!.rect;
    return Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));
  }

  bool get _canConfirmGrid {
    if (_dragStart == null || _dragCurrent == null) return false;
    final r = Rect.fromPoints(_dragStart!, _dragCurrent!);
    return r.width > 20 && r.height > 20;
  }

  Future<void> _confirmGridAndRecognize() async {
    final fitted = _fitted!;
    final dragRect = Rect.fromPoints(_dragStart!, _dragCurrent!);
    final imgRect = Rect.fromLTWH(
      (dragRect.left - fitted.rect.left) / fitted.scale,
      (dragRect.top - fitted.rect.top) / fitted.scale,
      dragRect.width / fitted.scale,
      dragRect.height / fitted.scale,
    );
    setState(() => _step = _Step.recognizing);
    await _runRecognition(imgRect);
  }

  Future<void> _runRecognition(Rect gridRect) async {
    final loc = AppLocalizations.of(context)!;
    setState(() => _progressLabel = loc.templatePreparingMessage);
    final templates = await TemplateDescriptorCache.load(
      widget.characters,
      onProgress: (done, total) {
        if (done % 50 != 0 && done != total) return;
        setState(() => _progressLabel = loc.templateProgressMessage(done, total));
      },
    );

    final templatesById = {for (final t in templates) t.id: t};
    final attributeById = {for (final c in widget.characters) c.id: c.attribute};

    // 이름 첫 글자 인식(신뢰도 충분할 때만 ORB 후보를 그 글자로 시작하는 캐릭터로 좁힌다 —
    // 실패하거나 애매하면 전체 목록으로 안전하게 폴백, [[kotodaman-mobile-flutter-port]] 참고).
    // 배지 글자는 캐릭터 표시 이름의 첫 글자가 아니라 그 캐릭터가 보유한 문자부여용
    // `Letters`(1~6개) 중 첫 번째 글자다(사용자 정정, 2026-09-06) — `CharacterEntry.letters`는
    // `character_loader.dart`가 JSON `Letters` 배열 순서 그대로 읽어 LinkedHashSet으로 담으므로
    // `.first`가 그 첫 글자와 같다. 전체 2,327명 실측 결과 `Letters`가 빈 캐릭터는 없었지만
    // (45종의 가나로만 이루어짐, 이름의 한자/콜라보 여부와 무관) 방어적으로 빈 경우만
    // 미분류로 남겨 항상 후보에 포함시킨다.
    final letterTemplates = await LetterTemplateCache.load();
    final firstLetterByCharacterId = {
      for (final c in widget.characters)
        if (c.letters.isNotEmpty) c.id: c.letters.first,
    };
    final templatesByFirstLetter = <String, List<TemplateDescriptor>>{};
    final templatesWithUnknownFirstLetter = <TemplateDescriptor>[];
    for (final t in templates) {
      final firstLetter = firstLetterByCharacterId[t.id];
      if (firstLetter == null) {
        templatesWithUnknownFirstLetter.add(t);
      } else {
        templatesByFirstLetter.putIfAbsent(firstLetter, () => []).add(t);
      }
    }

    final fullMat = cv.imdecode(_imageBytes!, cv.IMREAD_GRAYSCALE);
    // 속성색 보조판정(Hough-circle)은 색 정보가 필요해서 컬러로도 한 번 더 디코드한다.
    final fullColorMat = cv.imdecode(_imageBytes!, cv.IMREAD_COLOR);
    final gridLeft = gridRect.left.round().clamp(0, fullMat.cols - 1);
    final gridTop = gridRect.top.round().clamp(0, fullMat.rows - 1);
    final gridWidth = gridRect.width.round().clamp(1, fullMat.cols - gridLeft);
    final gridHeight = gridRect.height.round().clamp(1, fullMat.rows - gridTop);
    final slots = computeSlotRects(
      gridLeft: gridLeft,
      gridTop: gridTop,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      columns: _gridShape.columns,
      rows: _gridShape.rows,
    );

    final orb = cv.ORB.create(nFeatures: 600);
    for (var i = 0; i < slots.length; i++) {
      setState(() => _progressLabel = loc.slotProgressMessage(i + 1, slots.length));
      final s = slots[i];
      final slotRect = cv.Rect(s.left, s.top, s.width, s.height);
      final region = fullMat.region(slotRect);
      final slotMat = upscaleGrayIfSmall(region.clone());
      region.dispose();

      final colorRegion = fullColorMat.region(slotRect);
      final attributeEvidence = detectBasicAttributeFromBadge(colorRegion);
      final letterGlyph = extractLetterGlyph(colorRegion);
      colorRegion.dispose();
      final letterMatch = letterGlyph == null ? null : matchLetter(letterGlyph, letterTemplates);
      letterGlyph?.dispose();

      var templatesForSlot = templates;
      if (letterMatch != null && letterMatch.score >= kMinLetterConfidence) {
        final narrowed = templatesByFirstLetter[letterMatch.letter];
        if (narrowed != null && narrowed.isNotEmpty) {
          templatesForSlot = [...narrowed, ...templatesWithUnknownFirstLetter];
        }
      }

      final queries = _buildPortraitRegionDescriptors(slotMat, orb);
      slotMat.dispose();

      var matches = queries.isEmpty
          ? <MatchScore>[]
          : await matchTemplatesParallel(queries, templatesForSlot, keepPerChunk: _kTopCandidates);
      if (matches.isNotEmpty) {
        final externalBoost = <String, double>{
          for (final m in matches) m.id: attributeRankingAdjustment(attributeById[m.id] ?? '', attributeEvidence),
        }..removeWhere((_, boost) => boost <= 0);
        matches = refineWithReciprocalCrossCheck(
          queries: queries,
          rankedCandidates: matches,
          templatesById: templatesById,
          candidateCount: _kTopCandidates,
          externalBoost: externalBoost,
        );
      }
      for (final q in queries) {
        q.dispose();
      }
      setState(() => _slotCandidates[i] = matches);
    }
    fullMat.dispose();
    fullColorMat.dispose();
    orb.dispose();

    setState(() => _step = _Step.review);
  }

  // 슬롯 크롭 하나에서 겹치는 여러 상대 영역(_kPortraitRegions)마다 ORB 디스크립터를
  // 뽑는다 — 너무 작은 영역(가로/세로 24px 미만, 업스케일 전이면 잘려서 특징점이 거의
  // 안 나오는 경우)이나 특징점을 못 찾은 영역은 건너뛴다. 반환된 Mat들은 호출자가 dispose.
  List<cv.Mat> _buildPortraitRegionDescriptors(cv.Mat slotMat, cv.ORB orb) {
    final result = <cv.Mat>[];
    for (final r in _kPortraitRegions) {
      final left = (r[0] * slotMat.cols).round().clamp(0, slotMat.cols - 1);
      final top = (r[1] * slotMat.rows).round().clamp(0, slotMat.rows - 1);
      final width = ((r[2] - r[0]) * slotMat.cols).round().clamp(1, slotMat.cols - left);
      final height = ((r[3] - r[1]) * slotMat.rows).round().clamp(1, slotMat.rows - top);
      if (width < 24 || height < 24) continue;

      final roi = slotMat.region(cv.Rect(left, top, width, height));
      final mask = cv.Mat.empty();
      final (keypoints, desc) = orb.detectAndCompute(roi, mask);
      roi.dispose();
      mask.dispose();
      keypoints.dispose();
      if (desc.isEmpty || desc.rows < 2) {
        desc.dispose();
        continue;
      }
      result.add(desc);
    }
    return result;
  }

  void _confirmReview() {
    final ids = <String>[];
    for (var i = 0; i < _kSlotCount; i++) {
      final idx = _selected[i];
      final candidates = _slotCandidates[i];
      if (idx == null || idx >= candidates.length) continue;
      ids.add(candidates[idx].id);
    }
    Navigator.of(context).pop(ids);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.screenshotRecognitionTitle)),
      body: switch (_step) {
        _Step.pickImage => _buildPickImage(),
        _Step.selectGrid => _buildSelectGrid(),
        _Step.recognizing => _buildRecognizing(),
        _Step.review => _buildReview(),
      },
    );
  }

  Widget _buildPickImage() {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _kMinTouchTarget + 8,
            child: ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Symbols.photo_library_rounded, fill: 1),
              label: Text(loc.pickScreenshotButton, style: const TextStyle(fontSize: _kMinBodyFont)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              loc.recognitionAccuracyWarning,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectGrid() {
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Text(loc.gridShapeLabel, style: const TextStyle(fontSize: _kMinBodyFont)),
              const SizedBox(width: 12),
              SegmentedButton<_GridShape>(
                segments: _GridShape.values
                    .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                    .toList(),
                selected: {_gridShape},
                onSelectionChanged: (s) => setState(() => _gridShape = s.first),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            loc.selectGridAreaHint,
            style: const TextStyle(fontSize: _kMinBodyFont),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final box = Size(constraints.maxWidth, constraints.maxHeight);
              _fitted = _computeFittedRect(box, _naturalSize!);
              return GestureDetector(
                onPanStart: (d) => setState(() {
                  _dragStart = _clampToFitted(d.localPosition);
                  _dragCurrent = _dragStart;
                }),
                onPanUpdate: (d) => setState(() {
                  _dragCurrent = _clampToFitted(d.localPosition);
                }),
                child: Stack(
                  children: [
                    Positioned.fill(child: Image.memory(_imageBytes!, fit: BoxFit.contain)),
                    if (_dragStart != null && _dragCurrent != null)
                      Positioned.fromRect(
                        rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.orangeAccent, width: 2),
                            color: Colors.orangeAccent.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: _kMinTouchTarget + 8,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canConfirmGrid ? _confirmGridAndRecognize : null,
                child: Text(loc.startRecognitionButton, style: const TextStyle(fontSize: _kMinBodyFont)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_progressLabel, style: const TextStyle(fontSize: _kMinBodyFont), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text(
            loc.recognitionAccuracyWarning,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _kSlotCount,
            separatorBuilder: (context, index) => const Divider(height: 20),
            itemBuilder: (context, i) => _buildSlotReviewRow(i),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: _kMinTouchTarget + 8,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmReview,
                child: Text(loc.confirmApplyButton, style: const TextStyle(fontSize: _kMinBodyFont)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlotReviewRow(int i) {
    final loc = AppLocalizations.of(context)!;
    final candidates = _slotCandidates[i];
    final byId = {for (final c in widget.characters) c.id: c};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.slotLabel(i + 1), style: const TextStyle(fontSize: _kMinBodyFont, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (var c = 0; c < candidates.length; c++) _candidateChip(i, c, byId[candidates[c].id]),
            _skipChip(i),
          ],
        ),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(loc.noCandidatesMessage, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _candidateChip(int slotIndex, int candidateIndex, CharacterEntry? c) {
    if (c == null) return const SizedBox.shrink();
    final selected = _selected[slotIndex] == candidateIndex;
    return GestureDetector(
      onTap: () => setState(() => _selected[slotIndex] = candidateIndex),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: Theme.of(context).colorScheme.secondary, width: 3) : null,
              ),
              child: attributeAvatar(c, radius: 24),
            ),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skipChip(int slotIndex) {
    final selected = _selected[slotIndex] == null;
    final accent = Theme.of(context).colorScheme.secondary;
    return GestureDetector(
      onTap: () => setState(() => _selected[slotIndex] = null),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: selected ? accent : Colors.grey.shade300,
              child: const Icon(Symbols.block_rounded, fill: 1, color: Colors.white),
            ),
            Text(AppLocalizations.of(context)!.skipLabel,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
