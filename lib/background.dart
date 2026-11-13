import 'dart:io';

import 'package:flutter/services.dart';

/// Android arka plan servisi ve kopma bildirimleri (App.kt'deki
/// "tpcm/background" kanalı).
///
/// iOS: Info.plist'teki bluetooth-central arka plan modu sayesinde sistem
/// bağlantıyı uygulama arka plandayken tutar; ayrı servis gerekmez.
/// (iOS bildirimleri henüz bağlanmadı.)
class Background {
  static const _ch = MethodChannel('tpcm/background');

  static Future<void> setKeepAlive(bool enabled, int count) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setKeepAlive', {'enabled': enabled, 'count': count});
    } catch (_) {}
  }

  static Future<void> notifyLost(String id, String name) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('notifyLost', {'id': id, 'name': name});
    } catch (_) {}
  }

  static Future<void> cancelLost(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelLost', {'id': id});
    } catch (_) {}
  }
}
