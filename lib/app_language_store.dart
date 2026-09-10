import 'package:shared_preferences/shared_preferences.dart';

/// UI 언어(한/일/영, PRD_Mobile_i18n.md FR-3) 로컬 저장. [DeckPresetStore]와 동일한
/// `shared_preferences` 단일 키 패턴.
class AppLanguageStore {
  static const _prefsKey = 'app_language';

  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  Future<void> save(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, languageCode);
  }
}
