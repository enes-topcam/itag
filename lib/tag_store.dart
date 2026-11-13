import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bu telefona kaydedilmiş bir iTag.
///
/// [id]: Android'de cihazın MAC adresi, iOS'ta iPhone'un bu cihaza verdiği
/// UUID. iOS MAC adresini göstermediği için bu kimlik telefona özeldir;
/// her telefon etiketi kendisi taramalı ve kaydetmelidir.
class SavedTag {
  SavedTag({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory SavedTag.fromJson(Map<String, dynamic> j) =>
      SavedTag(id: j['id'] as String, name: j['name'] as String);
}

/// Kayıtlı etiketleri telefonun yerel deposunda (SharedPreferences) tutar.
class TagStore {
  static const _key = 'saved_tags_v1';

  static Future<List<SavedTag>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final tags = <SavedTag>[];
    for (final s in raw) {
      try {
        tags.add(SavedTag.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // Bozuk kayıt: yok say
      }
    }
    return tags;
  }

  static Future<void> save(List<SavedTag> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, tags.map((t) => jsonEncode(t.toJson())).toList());
  }
}
