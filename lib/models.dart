import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kayıtlı cihaz (tasarım dokümanı §18'deki SavedDevice'ın Flutter karşılığı).
///
/// Doküman Room önerir; birkaç cihazlık küçük veri için SharedPreferences
/// içinde JSON saklıyoruz. Veri büyürse (ör. konum geçmişi) sqflite/drift'e
/// geçilebilir.
class SavedDevice {
  SavedDevice({
    required this.id,
    required this.displayName,
    this.advertisedName,
    this.iconKey = 'key',
    this.isItag = true,
    required this.firstConnectedAt,
    this.lastConnectedAt,
    this.lastSeenAt,
    this.lastLatitude,
    this.lastLongitude,
    this.alertOnDisconnect = true,
    this.autoConnect = true,
    this.lastAlertAt,
  });

  /// Platform tanımlayıcısı: Android'de MAC adresi, iOS'ta iPhone'un bu
  /// cihaza verdiği UUID (iOS MAC göstermez; her telefon kendisi kaydeder).
  final String id;
  final String displayName;
  final String? advertisedName;
  final String iconKey;

  /// İlk bağlantıda iTag parmak izine (1802/2A06 + FFE0/FFE1) uydu mu?
  /// Uyduysa ses/düğme özellikleri açılır ve sonraki bağlantılarda da uymak
  /// zorundadır (taklit kontrolü).
  final bool isItag;
  final DateTime firstConnectedAt;
  final DateTime? lastConnectedAt;
  final DateTime? lastSeenAt;
  final double? lastLatitude;
  final double? lastLongitude;

  /// Kayıp modu: bağlantı beklenmedik şekilde koparsa uyar.
  final bool alertOnDisconnect;

  /// Uygulama cihazı görünce kendiliğinden bağlansın mı?
  final bool autoConnect;
  final DateTime? lastAlertAt;

  SavedDevice copyWith({
    String? displayName,
    String? iconKey,
    DateTime? lastConnectedAt,
    DateTime? lastSeenAt,
    bool? alertOnDisconnect,
    bool? autoConnect,
    DateTime? lastAlertAt,
  }) =>
      SavedDevice(
        id: id,
        displayName: displayName ?? this.displayName,
        advertisedName: advertisedName,
        iconKey: iconKey ?? this.iconKey,
        isItag: isItag,
        firstConnectedAt: firstConnectedAt,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        lastLatitude: lastLatitude,
        lastLongitude: lastLongitude,
        alertOnDisconnect: alertOnDisconnect ?? this.alertOnDisconnect,
        autoConnect: autoConnect ?? this.autoConnect,
        lastAlertAt: lastAlertAt ?? this.lastAlertAt,
      );

  static DateTime? _date(dynamic v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'advertisedName': advertisedName,
        'iconKey': iconKey,
        'isItag': isItag,
        'firstConnectedAt': firstConnectedAt.millisecondsSinceEpoch,
        'lastConnectedAt': lastConnectedAt?.millisecondsSinceEpoch,
        'lastSeenAt': lastSeenAt?.millisecondsSinceEpoch,
        'lastLatitude': lastLatitude,
        'lastLongitude': lastLongitude,
        'alertOnDisconnect': alertOnDisconnect,
        'autoConnect': autoConnect,
        'lastAlertAt': lastAlertAt?.millisecondsSinceEpoch,
      };

  /// Eski sürümün kaydı ({id, name, isItag, autoConnect}) da okunur.
  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        displayName: (j['displayName'] ?? j['name'] ?? 'Cihaz') as String,
        advertisedName: j['advertisedName'] as String?,
        iconKey: j['iconKey'] as String? ?? 'key',
        isItag: j['isItag'] as bool? ?? true,
        firstConnectedAt: _date(j['firstConnectedAt']) ?? DateTime.now(),
        lastConnectedAt: _date(j['lastConnectedAt']),
        lastSeenAt: _date(j['lastSeenAt']),
        lastLatitude: (j['lastLatitude'] as num?)?.toDouble(),
        lastLongitude: (j['lastLongitude'] as num?)?.toDouble(),
        alertOnDisconnect: j['alertOnDisconnect'] as bool? ?? true,
        autoConnect: j['autoConnect'] as bool? ?? true,
        lastAlertAt: _date(j['lastAlertAt']),
      );
}

class DeviceStore {
  static const _key = 'saved_tags_v1';

  static Future<List<SavedDevice>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <SavedDevice>[];
    for (final s in prefs.getStringList(_key) ?? const <String>[]) {
      try {
        out.add(SavedDevice.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // bozuk kayıt: yok say
      }
    }
    return out;
  }

  static Future<void> save(List<SavedDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, devices.map((d) => jsonEncode(d.toJson())).toList());
  }
}

/// Uygulama geneli tercihler (doküman DataStore önerir; SharedPreferences).
class AppSettings extends ChangeNotifier {
  bool onboarded = false;
  bool alertsEnabled = true; // global kopma uyarısı
  bool alertSound = true;
  bool alertVibrate = true;
  bool alertNotify = true; // sistem bildirimi (uygulama kapalıyken de)
  bool keepAlive = true; // uygulama kapatılınca da bağlı kal

  late SharedPreferences _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    onboarded = _p.getBool('onboarded') ?? false;
    alertsEnabled = _p.getBool('alertsEnabled') ?? true;
    alertSound = _p.getBool('alertSound') ?? true;
    alertVibrate = _p.getBool('alertVibrate') ?? true;
    alertNotify = _p.getBool('alertNotify') ?? true;
    keepAlive = _p.getBool('keepAlive') ?? true;
  }

  Future<void> set({
    bool? onboarded,
    bool? alertsEnabled,
    bool? alertSound,
    bool? alertVibrate,
    bool? alertNotify,
    bool? keepAlive,
  }) async {
    if (alertNotify != null) {
      this.alertNotify = alertNotify;
      await _p.setBool('alertNotify', alertNotify);
    }
    if (keepAlive != null) {
      this.keepAlive = keepAlive;
      await _p.setBool('keepAlive', keepAlive);
    }
    if (onboarded != null) {
      this.onboarded = onboarded;
      await _p.setBool('onboarded', onboarded);
    }
    if (alertsEnabled != null) {
      this.alertsEnabled = alertsEnabled;
      await _p.setBool('alertsEnabled', alertsEnabled);
    }
    if (alertSound != null) {
      this.alertSound = alertSound;
      await _p.setBool('alertSound', alertSound);
    }
    if (alertVibrate != null) {
      this.alertVibrate = alertVibrate;
      await _p.setBool('alertVibrate', alertVibrate);
    }
    notifyListeners();
  }
}

final appSettings = AppSettings();
