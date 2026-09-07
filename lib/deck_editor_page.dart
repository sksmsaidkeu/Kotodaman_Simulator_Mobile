import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:word_search_engine/word_search_engine.dart';

import 'app_data.dart';
import 'character_avatar.dart';
import 'character_filter_sheet.dart';
import 'deck_preset_store.dart';
import 'deck_recognition/deck_recognition_page.dart';
import 'update_checker.dart';
import 'word_search_page.dart';

/// 화면 가시성 기준(PRD FR-5) — 세로모드 폰(폭 360~430dp) 기준.
const double _kMinTouchTarget = 44;
const double _kMinBodyFont = 16;

const int _kMaxDeckSize = 12;

// 덱이 늘어나도 아래 캐릭터 선택 그리드가 항상 보이도록 고정 높이 + 가로 스크롤로 감싼다
// (PRD FR-5: "한 화면에 과밀 배치하지 않는다 — 스크롤 또는 섹션으로 분리").
const double _kChipRowHeight = 56;

class DeckEditorPage extends StatefulWidget {
  const DeckEditorPage({super.key});

  @override
  State<DeckEditorPage> createState() => _DeckEditorPageState();
}

class _DeckEditorPageState extends State<DeckEditorPage> {
  final _presetStore = DeckPresetStore();
  late Future<AppData> _dataFuture;

  List<CharacterEntry> _allCharacters = [];
  Map<String, CharacterEntry> _byId = {};
  WordSearchService? _searchService;
  List<String> _allSpecies = [];
  List<String> _allGroups = [];

  final List<String> _deckOrder = [];
  final _filter = CharacterFilter();
  String _searchQuery = '';
  List<DeckPreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _dataFuture = loadAppData();
    _dataFuture.then((data) {
      setState(() {
        _allCharacters = data.characters;
        _byId = {for (final c in data.characters) c.id: c};
        _searchService = data.wordSearchService;
        _allSpecies = data.characters.map((c) => c.species).where((s) => s.isNotEmpty).toSet().toList()..sort();
        _allGroups = data.characters.map((c) => c.groupName).where((g) => g.isNotEmpty).toSet().toList()..sort();
      });
    });
    _presetStore.loadAll().then((presets) => setState(() => _presets = presets));
    checkForUpdate().then((update) {
      if (update != null && mounted) _showUpdateBanner(update);
    });
  }

  void _showUpdateBanner(MobileUpdateInfo update) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text('새 버전 ${update.version}이 있습니다.'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _startUpdate(update);
            },
            child: const Text('업데이트'),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('나중에'),
          ),
        ],
      ),
    );
  }

  Future<void> _startUpdate(MobileUpdateInfo update) async {
    final progress = ValueNotifier<double?>(null);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('업데이트 다운로드 중'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => LinearProgressIndicator(value: value),
        ),
      ),
    );
    try {
      await downloadAndInstallUpdate(
        update,
        onProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );
    } catch (e) {
      if (mounted) _showMessage('업데이트 실패: $e');
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  List<CharacterEntry> get _deckCharacters =>
      _deckOrder.map((id) => _byId[id]).whereType<CharacterEntry>().toList();

  List<CharacterEntry> get _filteredCharacters {
    var list = _allCharacters;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim();
      list = list.where((c) => c.name.contains(q) || c.searchAliases.any((a) => a.contains(q))).toList();
    }
    if (!_filter.isEmpty) {
      list = list.where(_filter.matches).toList();
    }
    return list;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addToDeck(CharacterEntry character) {
    if (_deckOrder.contains(character.id)) {
      _showMessage('이미 덱에 있는 캐릭터입니다.');
      return;
    }
    if (_deckOrder.length >= _kMaxDeckSize) {
      _showMessage('덱은 최대 $_kMaxDeckSize명까지 편성할 수 있습니다.');
      return;
    }
    if (character.deckRestrictionGroupId.isNotEmpty) {
      final conflict = _deckCharacters.any(
        (c) => c.deckRestrictionGroupId == character.deckRestrictionGroupId,
      );
      if (conflict) {
        _showMessage('같은 그룹의 캐릭터는 동시에 편성할 수 없습니다.');
        return;
      }
    }
    setState(() => _deckOrder.add(character.id));
  }

  void _removeFromDeck(String characterId) {
    setState(() => _deckOrder.remove(characterId));
  }

  Future<void> _savePreset() async {
    if (_deckOrder.isEmpty) {
      _showMessage('저장할 덱이 비어 있습니다.');
      return;
    }
    final name = await _promptForName();
    if (name == null || name.trim().isEmpty) return;

    setState(() {
      _presets = [
        ..._presets.where((p) => p.name != name),
        DeckPreset(name: name, characterIds: List.of(_deckOrder)),
      ];
    });
    await _presetStore.saveAll(_presets);
    _showMessage('"$name" 저장했습니다.');
  }

  void _loadPreset(DeckPreset preset) {
    setState(() {
      _deckOrder
        ..clear()
        ..addAll(preset.characterIds.where(_byId.containsKey));
    });
  }

  Future<void> _deletePreset(DeckPreset preset) async {
    setState(() => _presets = _presets.where((p) => p.name != preset.name).toList());
    await _presetStore.saveAll(_presets);
  }

  Future<String?> _promptForName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('덱 이름'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _goToWordSearch() {
    final service = _searchService;
    if (service == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WordSearchPage(deck: _deckCharacters, service: service),
    ));
  }

  Future<void> _openScreenshotRecognition() async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => DeckRecognitionPage(characters: _allCharacters)),
    );
    if (result == null) return;
    setState(() {
      _deckOrder
        ..clear()
        ..addAll(result.where(_byId.containsKey).toSet());
    });
    _showMessage('스크린샷 인식 결과로 덱을 교체했습니다 (${_deckOrder.length}명).');
  }

  void _openFilterSheet() {
    showCharacterFilterSheet(
      context,
      filter: _filter,
      allSpecies: _allSpecies,
      allGroups: _allGroups,
      onChanged: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('코토다망 덱 편성'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: OutlinedButton(
              onPressed: _openScreenshotRecognition,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text(
                '스크린샷으로\n불러오기',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.2),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<AppData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('데이터 로딩 실패: ${snapshot.error}'));
          }
          return _buildBody(context);
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                height: _kMinTouchTarget + 8,
                child: OutlinedButton.icon(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Symbols.filter_alt_rounded, fill: 1),
                  label: Text(
                    _filter.isEmpty ? '필터' : '필터(${_filter.activeCount})',
                    style: const TextStyle(fontSize: _kMinBodyFont),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: _kMinTouchTarget + 8,
                  child: ElevatedButton.icon(
                    onPressed: _deckOrder.isEmpty || _searchService == null ? null : _goToWordSearch,
                    icon: const Icon(Symbols.search_rounded, fill: 1),
                    label: const Text('이 덱으로 검색하기', style: TextStyle(fontSize: _kMinBodyFont)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            style: const TextStyle(fontSize: _kMinBodyFont),
            decoration: const InputDecoration(
              labelText: '캐릭터 검색 (이름 · 별칭)',
              isDense: false,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        _buildSectionHeader('덱 (${_deckOrder.length}/$_kMaxDeckSize)'),
        _buildDeckChips(),
        _buildPresetRow(),
        const Divider(height: 1),
        Expanded(child: _buildCharacterGrid()),
      ],
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: _kMinBodyFont),
        ),
      );

  Widget _buildDeckChips() {
    if (_deckOrder.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('아래 목록에서 캐릭터를 탭해 덱에 추가하세요.', style: TextStyle(fontSize: _kMinBodyFont)),
      );
    }
    // 12자리를 한 줄로 가로 스크롤하면 뒷부분이 안 보여서 2행×6열로 고정 배치한다
    // (덱 최대 인원이 정확히 12명이라 스크롤 없이 항상 다 보인다).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
        children: _deckCharacters
            .map((c) => RemovableCharacterAvatar(character: c, onTap: () => _removeFromDeck(c.id)))
            .toList(),
      ),
    );
  }

  Widget _buildPresetRow() {
    return SizedBox(
      height: _kChipRowHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          SizedBox(
            height: _kMinTouchTarget,
            child: ElevatedButton(onPressed: _savePreset, child: const Text('덱 저장')),
          ),
          for (final preset in _presets)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InputChip(
                label: Text(preset.name, style: const TextStyle(fontSize: _kMinBodyFont)),
                onPressed: () => _loadPreset(preset),
                onDeleted: () => _deletePreset(preset),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCharacterGrid() {
    final list = _filteredCharacters;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 96,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final c = list[index];
        final inDeck = _deckOrder.contains(c.id);
        return InkWell(
          onTap: () => inDeck ? _showMessage('이미 덱에 있는 캐릭터입니다.') : _addToDeck(c),
          child: Opacity(
            opacity: inDeck ? 0.4 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                attributeAvatar(c, radius: 26),
                const SizedBox(height: 4),
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
