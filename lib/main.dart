import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_language_store.dart';
import 'app_theme.dart';
import 'deck_editor_page.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const KotodamanApp());
}

/// 지원 언어 3개(PRD_Mobile_i18n.md FR-1) — KOR→JPN→ENG 순환 고정 순서.
const List<Locale> kSupportedLocales = [Locale('ko'), Locale('ja'), Locale('en')];

class KotodamanApp extends StatefulWidget {
  const KotodamanApp({super.key});

  /// 어디서든(예: 언어 토글 버튼) 앱 전체 언어를 바꾼다 — 재시작 불필요, 즉시 반영.
  static void setLocale(BuildContext context, Locale locale) {
    context.findAncestorStateOfType<_KotodamanAppState>()?._setLocale(locale);
  }

  @override
  State<KotodamanApp> createState() => _KotodamanAppState();
}

class _KotodamanAppState extends State<KotodamanApp> {
  Locale _locale = const Locale('ko');
  final _languageStore = AppLanguageStore();

  @override
  void initState() {
    super.initState();
    _languageStore.load().then((code) {
      if (code == null || !mounted) return;
      final match = kSupportedLocales.where((l) => l.languageCode == code);
      if (match.isNotEmpty) setState(() => _locale = match.first);
    });
  }

  void _setLocale(Locale locale) {
    setState(() => _locale = locale);
    _languageStore.save(locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      locale: _locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const DeckEditorPage(),
    );
  }
}
