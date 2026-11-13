import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Tek izin grubu: 'bluetooth' (tarama + bağlantı).
///
/// Android'de MainActivity.kt içindeki "tpcm/permissions" kanalını kullanır.
/// iOS'ta Bluetooth izni sistem tarafından ilk kullanımda sorulur.
class Perms {
  static const _ch = MethodChannel('tpcm/permissions');

  static bool get supported => Platform.isAndroid;

  static Future<Map<String, bool>> status() async {
    if (!Platform.isAndroid) return {'bluetooth': true};
    try {
      return await _ch.invokeMapMethod<String, bool>('status') ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<bool> request(String group) async {
    if (!Platform.isAndroid) {
      // iOS: CoreBluetooth'a ilk erişim izin penceresini açar.
      try {
        await FlutterBluePlus.adapterState.first;
      } catch (_) {}
      return true;
    }
    try {
      return await _ch.invokeMethod<bool>('request', {'group': group}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }
}
