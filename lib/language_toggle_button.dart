import 'package:flutter/material.dart';

import 'main.dart';

const Map<String, String> _kLanguageAbbreviations = {'ko': 'KOR', 'ja': 'JPN', 'en': 'ENG'};

/// 한/일/영 순환 토글(PRD_Mobile_i18n.md FR-1) — 데스크톱과 동일하게 약어(KOR/JPN/ENG,
/// 번역하지 않는 코드 리터럴) 표기 버튼 하나로 다음 언어로 순환한다. AppBar `actions`의
/// 맨 끝(화면 우측 상단)에 배치해서 쓴다.
class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = Localizations.localeOf(context);
    final currentIndex = kSupportedLocales.indexWhere((l) => l.languageCode == current.languageCode);
    final next = kSupportedLocales[(currentIndex + 1) % kSupportedLocales.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: OutlinedButton(
        onPressed: () => KotodamanApp.setLocale(context, next),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
        child: Text(
          _kLanguageAbbreviations[current.languageCode] ?? current.languageCode.toUpperCase(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
