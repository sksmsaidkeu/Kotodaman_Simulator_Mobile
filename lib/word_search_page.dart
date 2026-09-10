import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:word_search_engine/word_search_engine.dart';

import 'character_avatar.dart';
import 'l10n/app_localizations.dart';

const double _kMinBodyFont = 16;
const double _kLetterSlotFont = 20;
const int _kMaxHandSize = 4;

/// PRD_Mobile.md FR-1 — 덱 편집 페이지에서 넘어온 덱(최대 12명)을 대상으로, 판 상태를
/// 입력해 두 종류의 결과를 나눠 보여준다: 손패(최대 4명, 5~7글자)와 덱 전체(4~7글자,
/// "이 덱으로 무엇까지 만들 수 있는지" 미리보기 — 실제 한 턴에 쓸 수 있는 문자는 손패
/// 기준이지만, 덱 전체 기준은 덱빌딩 참고용).
class WordSearchPage extends StatefulWidget {
  final List<CharacterEntry> deck;
  final WordSearchService service;

  const WordSearchPage({super.key, required this.deck, required this.service});

  @override
  State<WordSearchPage> createState() => _WordSearchPageState();
}

class _WordSearchPageState extends State<WordSearchPage> {
  final _boardController = TextEditingController();
  final Set<String> _handIds = {};
  Map<int, SearchGroup>? _handGroups;
  Map<int, SearchGroup>? _deckGroups;

  @override
  void initState() {
    super.initState();
    _boardController.addListener(_convertBoardInputToKana);
  }

  // 한글 IME로 타이핑해도 히라가나로 바로 보이도록 자동 변환한다. 조합 중인 음절은
  // 건드리지 않는다(composing 도중 텍스트를 바꾸면 IME 입력이 깨진다) — 한 음절이
  // 완성돼 composing이 비워질 때만 변환한다.
  void _convertBoardInputToKana() {
    final value = _boardController.value;
    if (value.composing.isValid) return;
    final converted = convertHangulToKana(value.text);
    if (converted == value.text) return;
    _boardController.value = value.copyWith(
      text: converted,
      selection: TextSelection.collapsed(offset: converted.length),
      composing: TextRange.empty,
    );
  }

  List<CharacterEntry> get _hand =>
      widget.deck.where((c) => _handIds.contains(c.id)).toList();

  // 데스크톱 `_boardCells`(MainWindow.xaml.cs)와 같은 개념 — 이미 놓인 글자.
  // '_'나 공백은 빈칸으로 취급한다. 입력한 길이만큼만 배열을 만든다(7칸으로 뒤를
  // null 패딩하면, 검색 엔진이 그 패딩까지 "빈 슬롯"으로 보고 실제로 안 친 자리에서도
  // 창을 밀어 매칭해 버려 — 예: "い　　た"(4글자)를 쳤는데 위치가 안 맞는 「けいたい」
  // 같은 단어까지 걸리는 오탐이 생겼다).
  List<String?> _parseBoard(String text) {
    final runes = text.runes.take(7).toList();
    return runes
        .map((r) => String.fromCharCode(r))
        .map((cell) => (cell == '_' || cell.trim().isEmpty) ? null : cell)
        .toList();
  }

  void _toggleHand(String characterId) {
    setState(() {
      if (_handIds.contains(characterId)) {
        _handIds.remove(characterId);
        return;
      }
      if (_handIds.length >= _kMaxHandSize) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.handFullMessage)));
        return;
      }
      _handIds.add(characterId);
    });
  }

  void _runSearch() {
    final board = _parseBoard(_boardController.text);
    setState(() {
      // 손패: 최대 4명, 5글자부터(엔진 기본 maximumPlacements=4).
      _handGroups = widget.service.findWordsByLength(
        board,
        _hand,
        minimumLength: 5,
      );
      // 덱 전체: 최대 12명이라 판이 비어 있어도 더 긴 단어를 채울 여지가 있다 — 4글자부터,
      // 배치 상한도 7로 올려 "이 덱으로 뭘 만들 수 있는지" 전체를 본다.
      _deckGroups = widget.service.findWordsByLength(
        board,
        widget.deck,
        maximumPlacements: 7,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.wordSearchTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(loc.boardInputLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: _kMinBodyFont)),
          const SizedBox(height: 4),
          TextField(
            controller: _boardController,
            style: const TextStyle(fontSize: _kLetterSlotFont),
            decoration: InputDecoration(
              hintText: loc.boardInputHint,
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(loc.handSelectionLabel(_handIds.length, _kMaxHandSize, widget.deck.length),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: _kMinBodyFont)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            children: widget.deck
                .map((c) => Center(
                      child: SelectableCharacterAvatar(
                        character: c,
                        selected: _handIds.contains(c.id),
                        onTap: () => _toggleHand(c.id),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _runSearch,
              icon: const Icon(Symbols.search_rounded, fill: 1),
              label: Text(loc.searchButton, style: const TextStyle(fontSize: _kMinBodyFont)),
            ),
          ),
          const SizedBox(height: 16),
          if (_handGroups != null)
            ..._buildResultSections(loc.handResultsTitle(_hand.length), _handGroups!),
          if (_deckGroups != null)
            ..._buildResultSections(loc.deckResultsTitle(widget.deck.length), _deckGroups!),
        ],
      ),
    );
  }

  List<Widget> _buildResultSections(String title, Map<int, SearchGroup> groups) {
    final lengths = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _kLetterSlotFont)),
      ),
      for (final length in lengths) _buildLengthTile(length, groups[length]!),
    ];
  }

  Widget _buildLengthTile(int length, SearchGroup group) {
    final loc = AppLocalizations.of(context)!;
    return Card(
      child: ExpansionTile(
        title: Text(loc.lengthTileTitle(length, group.results.length),
            style: const TextStyle(fontSize: _kMinBodyFont)),
        children: group.results.isEmpty
            ? [Padding(padding: const EdgeInsets.all(12), child: Text(loc.noResultsMessage))]
            : group.results
                .map((r) => ListTile(
                      dense: true,
                      title: Text(r.word, style: const TextStyle(fontSize: _kLetterSlotFont)),
                      trailing: Text(loc.comboCountLabel(r.comboCount)),
                    ))
                .toList(),
      ),
    );
  }

  @override
  void dispose() {
    _boardController.removeListener(_convertBoardInputToKana);
    _boardController.dispose();
    super.dispose();
  }
}
