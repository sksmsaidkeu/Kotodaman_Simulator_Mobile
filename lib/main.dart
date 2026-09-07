import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'deck_editor_page.dart';

void main() {
  runApp(const KotodamanApp());
}

class KotodamanApp extends StatelessWidget {
  const KotodamanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '코토다망 최장 단어 탐색기',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const DeckEditorPage(),
    );
  }
}
