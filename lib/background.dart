import 'dart:io';

import 'package:flutter/services.dart';

/// Android kopma bildirimleri (MainActivity.kt'deki "tpcm/background" kanalı).
/// iOS bildirimleri henüz bağlanmadı.
class Background {
  static const _ch = MethodChannel('tpcm/background');

  static Future<void> notifyLost(String id, String name) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('notifyLost', {'id': id, 'name': name});
    } catch (_) {}
  }

  /// Sessiz dinleme: kayıtlı etiketlerin yayınını bağlanmadan dinle ve
  /// duyulduğunda son görülme zamanı/konumu kaydet (PassiveScan.kt).
  static Future<bool> setPassiveScan(bool enabled, List<String> ids) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>(
              'setPassiveScan', {'enabled': enabled, 'ids': ids}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Şu anki konumu bu cihazın son görülme kaydı olarak yaz (Sightings.kt).
  static Future<void> recordSighting(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('recordSighting', {'id': id});
    } catch (_) {}
  }

  /// Konumu telefonun harita/yol tarifi uygulamasında aç.
  static Future<bool> openMap(double lat, double lng, String label) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>(
              'openMap', {'lat': lat, 'lng': lng, 'label': label}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelLost(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelLost', {'id': id});
    } catch (_) {}
  }
}
