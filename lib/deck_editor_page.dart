import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:word_search_engine/word_search_engine.dart';

import 'app_data.dart';
import 'character_avatar.dart';
import 'character_filter_sheet.dart';
import 'deck_preset_store.dart';
import 'deck_recognition/deck_recognition_page.dart';
import 'l10n/app_localizations.dart';
import 'language_toggle_button.dart';
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

  String? _loadedLocaleCode;

  @override
  void initState() {
    super.initState();
    _presetStore.loadAll().then((presets) => setState(() => _presets = presets));
    checkForUpdate().then((update) {
      if (update != null && mounted) _showUpdateBanner(update);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 언어가 ko↔ja/en으로 바뀌면 캐릭터 이름 표시(한국어 오버레이 vs 원문)가 달라지므로 다시 로드한다.
    final localeCode = Localizations.localeOf(context).languageCode;
    if (localeCode == _loadedLocaleCode) return;
    _loadedLocaleCode = localeCode;
    _dataFuture = loadAppData(useKoreanNames: localeCode == 'ko');
    _dataFuture.then((data) {
      if (!mounted) return;
      setState(() {
        _allCharacters = data.characters;
        _byId = {for (final c in data.characters) c.id: c};
        _searchService = data.wordSearchService;
        _allSpecies = data.characters.map((c) => c.species).where((s) => s.isNotEmpty).toSet().toList()..sort();
        _allGroups = data.characters.map((c) => c.groupName).where((g) => g.isNotEmpty).toSet().toList()..sort();
      });
    });
  }

  void _showUpdateBanner(MobileUpdateInfo update) {
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(loc.updateAvailableBanner(update.version)),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _startUpdate(update);
            },
            child: Text(loc.updateActionNow),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: Text(loc.updateActionLater),
          ),
        ],
      ),
    );
  }

  Future<void> _startUpdate(MobileUpdateInfo update) async {
    final loc = AppLocalizations.of(context)!;
    final progress = ValueNotifier<double?>(null);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(loc.updateDownloadingTitle),
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
      if (mounted) _showMessage(loc.updateFailedMessage('$e'));
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
    final loc = AppLocalizations.of(context)!;
    if (_deckOrder.contains(character.id)) {
      _showMessage(loc.alreadyInDeckMessage);
      return;
    }
    if (_deckOrder.length >= _kMaxDeckSize) {
      _showMessage(loc.deckFullMessage(_kMaxDeckSize));
      return;
    }
    if (character.deckRestrictionGroupId.isNotEmpty) {
      final conflict = _deckCharacters.any(
        (c) => c.deckRestrictionGroupId == character.deckRestrictionGroupId,
      );
      if (conflict) {
        _showMessage(loc.deckRestrictionConflictMessage);
        return;
      }
    }
    setState(() => _deckOrder.add(character.id));
  }

  void _removeFromDeck(String characterId) {
    setState(() => _deckOrder.remove(characterId));
  }

  Future<void> _savePreset() async {
    final loc = AppLocalizations.of(context)!;
    if (_deckOrder.isEmpty) {
      _showMessage(loc.emptyDeckMessage);
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
    _showMessage(loc.presetSavedMessage(name));
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
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.deckNameDialogTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.cancelButton)),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(loc.saveButton),
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
    if (result == null || !mounted) return;
    setState(() {
      _deckOrder
        ..clear()
        ..addAll(result.where(_byId.containsKey).toSet());
    });
    _showMessage(AppLocalizations.of(context)!.screenshotDeckReplacedMessage(_deckOrder.length));
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
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.deckEditorTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: OutlinedButton(
              onPressed: _openScreenshotRecognition,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: Text(
                loc.screenshotImportButton,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.2),
              ),
            ),
          ),
          const LanguageToggleButton(),
        ],
      ),
      body: FutureBuilder<AppData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(loc.dataLoadError('${snapshot.error}')));
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
                    _filter.isEmpty
                        ? loc.filterButton
                        : loc.filterButtonWithCount(_filter.activeCount),
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
                    label: Text(loc.searchWithDeckButton, style: const TextStyle(fontSize: _kMinBodyFont)),
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
    final loc = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            style: const TextStyle(fontSize: _kMinBodyFont),
            decoration: InputDecoration(
              labelText: loc.characterSearchLabel,
              isDense: false,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        _buildSectionHeader(loc.deckSectionHeader(_deckOrder.length, _kMaxDeckSize)),
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          AppLocalizations.of(context)!.addCharacterHint,
          style: const TextStyle(fontSize: _kMinBodyFont),
        ),
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
            child: ElevatedButton(
              onPressed: _savePreset,
              child: Text(AppLocalizations.of(context)!.savePresetButton),
            ),
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
          onTap: () => inDeck
              ? _showMessage(AppLocalizations.of(context)!.alreadyInDeckMessage)
              : _addToDeck(c),
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
