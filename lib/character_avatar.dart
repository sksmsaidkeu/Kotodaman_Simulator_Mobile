import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:word_search_engine/word_search_engine.dart';

import 'app_theme.dart';

String characterImagePath(String imageFileName) =>
    'assets/characters/CharacterImages/$imageFileName';

/// 데스크톱 `DataPalette.AttributeColor`와 같은 규칙 — 속성색 테두리로 감싼 아바타.
Widget attributeAvatar(CharacterEntry c, {double radius = 20}) {
  return CircleAvatar(
    radius: radius + 2,
    backgroundColor: AppColors.attributeColor(c.attribute),
    child: CircleAvatar(radius: radius, backgroundImage: AssetImage(characterImagePath(c.imageFileName))),
  );
}

/// 탭하면 제거되는 아이콘 전용 아바타(덱 목록 등). 이름을 같이 보여주면 12명이 찼을 때
/// 화면 밖으로 넘치므로 아이콘 + X 배지만 쓰고, 이름은 툴팁으로 확인한다.
class RemovableCharacterAvatar extends StatelessWidget {
  final CharacterEntry character;
  final VoidCallback onTap;

  const RemovableCharacterAvatar({super.key, required this.character, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '${character.name} (탭해서 제외)',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            attributeAvatar(character, radius: 20),
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
                child: const Icon(Symbols.close_rounded, fill: 1, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 탭하면 선택 토글되는 아이콘 전용 아바타(손패 선택 등). 선택 여부는 테두리 링 + 체크
/// 배지로 표시한다.
class SelectableCharacterAvatar extends StatelessWidget {
  final CharacterEntry character;
  final bool selected;
  final VoidCallback onTap;

  const SelectableCharacterAvatar({
    super.key,
    required this.character,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: character.name,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected ? Border.all(color: accent, width: 3) : null,
              ),
              child: attributeAvatar(character, radius: 20),
            ),
            if (selected)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(Symbols.check_rounded, fill: 1, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
