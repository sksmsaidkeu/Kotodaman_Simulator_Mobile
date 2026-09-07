import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 덱 프리셋(PRD FR-3) 로컬 저장. 개수가 적어(사용자 몇~수십 개) 별도 DB 없이
/// `shared_preferences` 하나의 키에 JSON으로 통째로 저장하면 충분하다(PRD §8 2단계).
class DeckPreset {
  final String name;
  final List<String> characterIds;

  DeckPreset({required this.name, required this.characterIds});

  Map<String, dynamic> toJson() => {'name': name, 'characterIds': characterIds};

  factory DeckPreset.fromJson(Map<String, dynamic> json) => DeckPreset(
        name: json['name'] as String,
        characterIds: (json['characterIds'] as List<dynamic>).cast<String>(),
      );
}

class DeckPresetStore {
  static const _prefsKey = 'deck_presets_v1';

  Future<List<DeckPreset>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list.map((e) => DeckPreset.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAll(List<DeckPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(presets.map((p) => p.toJson()).toList()));
  }
}
