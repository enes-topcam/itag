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

  static Future<void> cancelLost(String id) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelLost', {'id': id});
    } catch (_) {}
  }
}
