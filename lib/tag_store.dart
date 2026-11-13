import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bu telefonda en az bir kez bağlanılmış (kayıtlı) bir Bluetooth cihazı.
///
/// [id]: Android'de cihazın MAC adresi, iOS'ta iPhone'un bu cihaza verdiği
/// UUID. iOS MAC adresini göstermediği için bu kimlik telefona özeldir;
/// her telefon cihazı kendisi bulup kaydetmelidir.
class SavedTag {
  SavedTag({
    required this.id,
    required this.name,
    this.isItag = true,
    this.autoConnect = true,
  });

  final String id;
  final String name;

  /// İlk bağlantıda iTag parmak izine uydu mu? Uyduysa sonraki
  /// bağlantılarda da uymak zorunda (taklit kontrolü).
  final bool isItag;

  /// Uygulama bu cihazı görünce kendiliğinden bağlansın mı?
  final bool autoConnect;

  SavedTag copyWith({String? name, bool? autoConnect}) => SavedTag(
        id: id,
        name: name ?? this.name,
        isItag: isItag,
        autoConnect: autoConnect ?? this.autoConnect,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'isItag': isItag, 'autoConnect': autoConnect};

  factory SavedTag.fromJson(Map<String, dynamic> j) => SavedTag(
        id: j['id'] as String,
        name: j['name'] as String,
        isItag: j['isItag'] as bool? ?? true,
        autoConnect: j['autoConnect'] as bool? ?? true,
      );
}

/// Kayıtlı cihazları telefonun yerel deposunda (SharedPreferences) tutar.
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
