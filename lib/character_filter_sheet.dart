import 'package:flutter/material.dart';
import 'package:word_search_engine/word_search_engine.dart';

import 'app_theme.dart';
import 'l10n/app_localizations.dart';

/// 데스크톱 `Models/CharacterCategories.All`과 같은 순서(등급) 그대로.
const List<String> kGradeOptions = [
  '스페셜',
  '레전드',
  '그랜드',
  '드림',
  '미라클',
  '오리지널',
  '콜라보',
  '기타',
];

/// 덱 편성 화면의 캐릭터 그리드 필터. 각 카테고리 안에서는 OR(하나라도 맞으면 통과),
/// 카테고리 사이에는 AND. 카테고리가 비어 있으면(선택 없음) 그 기준은 걸지 않는다.
class CharacterFilter {
  final Set<String> grades = {};
  final Set<String> species = {};
  final Set<String> groups = {};
  final Set<String> attributes = {};

  bool get isEmpty => grades.isEmpty && species.isEmpty && groups.isEmpty && attributes.isEmpty;

  int get activeCount =>
      (grades.isNotEmpty ? 1 : 0) +
      (species.isNotEmpty ? 1 : 0) +
      (groups.isNotEmpty ? 1 : 0) +
      (attributes.isNotEmpty ? 1 : 0);

  void clear() {
    grades.clear();
    species.clear();
    groups.clear();
    attributes.clear();
  }

  bool matches(CharacterEntry c) {
    if (grades.isNotEmpty && !grades.contains(c.category)) return false;
    if (species.isNotEmpty && !species.contains(c.species)) return false;
    if (groups.isNotEmpty && !groups.contains(c.groupName)) return false;
    if (attributes.isNotEmpty && !attributes.contains(c.attribute)) return false;
    return true;
  }
}

Future<void> showCharacterFilterSheet(
  BuildContext context, {
  required CharacterFilter filter,
  required List<String> allSpecies,
  required List<String> allGroups,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _FilterSheet(
      filter: filter,
      allSpecies: allSpecies,
      allGroups: allGroups,
      onChanged: onChanged,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  final CharacterFilter filter;
  final List<String> allSpecies;
  final List<String> allGroups;
  final VoidCallback onChanged;

  const _FilterSheet({
    required this.filter,
    required this.allSpecies,
    required this.allGroups,
    required this.onChanged,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  void _toggle(Set<String> set, String value) {
    setState(() {
      if (!set.add(value)) set.remove(value);
    });
    widget.onChanged();
  }

  Future<void> _openGroupPage() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GroupFilterPage(
        allGroups: widget.allGroups,
        selected: widget.filter.groups,
        onChanged: widget.onChanged,
      ),
    ));
    setState(() {}); // 그룹 페이지에서 고른 개수를 배지에 반영
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(loc.filterSheetTitle, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
              TextButton(
                onPressed: () {
                  setState(widget.filter.clear);
                  widget.onChanged();
                },
                child: Text(loc.resetButton, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          _buildSection(loc.gradeLabel, kGradeOptions, widget.filter.grades),
          _buildSection(loc.attributeLabel, AppColors.attribute.keys.toList(), widget.filter.attributes),
          _buildSection(loc.speciesLabel, widget.allSpecies, widget.filter.species),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.groupLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _openGroupPage,
                  child: Text(
                    widget.filter.groups.isEmpty
                        ? loc.selectGroupButton
                        : loc.selectGroupButtonWithCount(widget.filter.groups.length),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<String> options, Set<String> selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map((o) => FilterChip(
                      label: Text(o, style: const TextStyle(fontSize: 14)),
                      selected: selected.contains(o),
                      onSelected: (_) => _toggle(selected, o),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// 그룹은 90종류라 필터 시트 안에 다 펼치면 과밀해져서(FR-5) 별도 페이지로 뺐다 —
/// 게임 내 "표시 조건 설정"의 그룹 버튼과 같은 패턴.
class _GroupFilterPage extends StatefulWidget {
  final List<String> allGroups;
  final Set<String> selected;
  final VoidCallback onChanged;

  const _GroupFilterPage({required this.allGroups, required this.selected, required this.onChanged});

  @override
  State<_GroupFilterPage> createState() => _GroupFilterPageState();
}

class _GroupFilterPageState extends State<_GroupFilterPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final filtered = widget.allGroups
        .where((g) => _query.trim().isEmpty || g.contains(_query.trim()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.groupFilterPageTitle(widget.selected.length)),
        actions: [
          TextButton(
            onPressed: () {
              setState(widget.selected.clear);
              widget.onChanged();
            },
            child: Text(loc.resetButton, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: loc.groupSearchHint,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final g = filtered[i];
                return CheckboxListTile(
                  title: Text(g, style: const TextStyle(fontSize: 16)),
                  value: widget.selected.contains(g),
                  onChanged: (_) {
                    setState(() {
                      if (!widget.selected.add(g)) widget.selected.remove(g);
                    });
                    widget.onChanged();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
