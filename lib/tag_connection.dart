import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'tag_store.dart';

/// iTag tipi ucuz BLE etiketlerin GATT UUID'leri.
class ItagUuids {
  // Immediate Alert: etiketi öttürmek için (0x00 sus, 0x01 hafif, 0x02 yüksek)
  static final immediateAlertService = Guid('1802');
  static final alertLevel = Guid('2A06');
  // Etiket üzerindeki düğme bildirimi (üreticiye özel)
  static final buttonService = Guid('FFE0');
  static final buttonChar = Guid('FFE1');
  // Pil
  static final batteryService = Guid('180F');
  static final batteryLevel = Guid('2A19');
}

/// Bağlanılan cihazın gerçekten bir iTag gibi görünüp görünmediğini kontrol
/// eder ("parmak izi"). Beklenen servis + karakteristikler yoksa ona
/// güvenmeyiz. Not: Bu, taklidi zorlaştırır ama tamamen engellemez.
class ItagFingerprint {
  ItagFingerprint(List<BluetoothService> services) {
    for (final s in services) {
      for (final c in s.characteristics) {
        if (s.uuid == ItagUuids.immediateAlertService &&
            c.uuid == ItagUuids.alertLevel) {
          alertChar = c;
        }
        if (s.uuid == ItagUuids.buttonService &&
            c.uuid == ItagUuids.buttonChar) {
          buttonChar = c;
        }
        if (s.uuid == ItagUuids.batteryService &&
            c.uuid == ItagUuids.batteryLevel) {
          batteryChar = c;
        }
      }
    }
  }

  BluetoothCharacteristic? alertChar;
  BluetoothCharacteristic? buttonChar;
  BluetoothCharacteristic? batteryChar;

  bool get looksLikeItag => alertChar != null && buttonChar != null;
}

/// Kayıtlı tek bir etiketle olan kalıcı bağlantıyı yönetir.
///
/// - autoConnect ile bağlanır: bağlantı koparsa işletim sistemi cihazı
///   tekrar gördüğünde kendiliğinden yeniden bağlanır.
/// - Biz bağlıyken etiket reklam yayınını keser; başkası bağlanamaz.
/// - Beklenmedik kopmada telefonda alarm başlatır.
class TagConnection extends ChangeNotifier {
  TagConnection(this.tag) : device = BluetoothDevice.fromId(tag.id);

  final SavedTag tag;
  final BluetoothDevice device;

  BluetoothConnectionState state = BluetoothConnectionState.disconnected;
  int? rssi;
  int? battery;
  int buttonPresses = 0;
  bool ringing = false;
  bool trusted = false; // parmak izi kontrolünden geçti mi
  bool lostAlarm = false; // bağlantı beklenmedik şekilde koptu
  final List<String> log = [];

  BluetoothCharacteristic? _alertChar;
  StreamSubscription? _connSub;
  StreamSubscription? _buttonSub;
  Timer? _rssiTimer;
  Timer? _alarmTimer;
  bool _stopping = false;
  bool _wasConnected = false;
  final List<DateTime> _recentPresses = [];

  bool get isConnected => state == BluetoothConnectionState.connected;
  bool get canRing => isConnected && trusted && _alertChar != null;

  void _log(String m) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    log.insert(0, '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $m');
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }

  Future<void> start() async {
    _stopping = false;
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onState);
    _log('Bağlantı bekleniyor (otomatik)...');
    try {
      // mtu:null zorunlu: autoConnect ile MTU isteği uyumsuz.
      await device.connect(
        license: License.nonprofit,
        autoConnect: true,
        mtu: null,
      );
    } catch (e) {
      _log('Bağlantı isteği hatası: $e');
    }
  }

  Future<void> stop() async {
    _stopping = true;
    _stopAlarm();
    _rssiTimer?.cancel();
    _buttonSub?.cancel();
    _connSub?.cancel();
    try {
      await device.disconnect(); // autoConnect'i de kapatır
    } catch (_) {}
  }

  Future<void> _onState(BluetoothConnectionState s) async {
    state = s;
    notifyListeners();
    if (s == BluetoothConnectionState.connected) {
      _wasConnected = true;
      _log('Bağlandı');
      if (lostAlarm) {
        lostAlarm = false;
        _stopAlarm();
        _log('Etiket geri geldi, alarm durdu');
      }
      await _setup();
    } else if (s == BluetoothConnectionState.disconnected) {
      _rssiTimer?.cancel();
      _buttonSub?.cancel();
      _alertChar = null;
      trusted = false;
      ringing = false;
      rssi = null;
      if (_wasConnected && !_stopping) {
        _log('BAĞLANTI KOPTU! Etiket uzakta olabilir.');
        lostAlarm = true;
        _startAlarm();
      }
      notifyListeners();
    }
  }

  Future<void> _setup() async {
    try {
      final fp = ItagFingerprint(await device.discoverServices());
      if (!fp.looksLikeItag) {
        // Kaydettiğimiz kimlikle bağlanan cihaz beklenen servislere sahip
        // değil: taklit olabilir. Hiçbir komut göndermeden ayrıl.
        _log('UYARI: Cihaz iTag parmak izine uymuyor, bağlantı kesildi');
        _stopping = true;
        await device.disconnect();
        return;
      }
      trusted = true;
      _alertChar = fp.alertChar;

      final b = fp.batteryChar;
      if (b != null) {
        try {
          final v = await b.read();
          // Pil 0-100 aralığında olmalı; dışındaysa güvenme.
          if (v.length == 1 && v.first <= 100) battery = v.first;
        } catch (_) {}
      }

      await fp.buttonChar!.setNotifyValue(true);
      _buttonSub?.cancel();
      _buttonSub = fp.buttonChar!.onValueReceived.listen(_onButton);

      _rssiTimer?.cancel();
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          rssi = await device.readRssi();
          notifyListeners();
        } catch (_) {}
      });
      _log('Hazır (iTag doğrulandı)');
    } catch (e) {
      _log('Kurulum hatası: $e');
    }
  }

  void _onButton(List<int> value) {
    // 1) Doğrulama: iTag düğmesi her zaman tek byte 0x01 gönderir.
    if (value.length != 1 || value.first != 0x01) {
      _log('Beklenmeyen veri yok sayıldı: $value');
      return;
    }
    // 2) Hız sınırı: 2 saniyede 5'ten fazla bildirim normal değil.
    final now = DateTime.now();
    _recentPresses
        .removeWhere((t) => now.difference(t) > const Duration(seconds: 2));
    _recentPresses.add(now);
    if (_recentPresses.length > 5) {
      _log('Çok hızlı bildirim, yok sayıldı');
      return;
    }

    buttonPresses++;
    _log('Düğmeye basıldı');
    // Şimdilik titreşim + sistem sesi. Gerçek alarm sesi sonraki adımda.
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> setTagAlert(bool on) async {
    final c = _alertChar;
    if (c == null || !trusted) return;
    try {
      await c.write([on ? 0x02 : 0x00],
          withoutResponse: c.properties.writeWithoutResponse);
      ringing = on;
      _log(on ? 'Etiket öttürülüyor' : 'Etiket susturuldu');
    } catch (e) {
      _log('Yazma hatası: $e');
    }
  }

  // Telefon tarafı kayıp alarmı (şimdilik titreşim + sistem sesi döngüsü).
  void _startAlarm() {
    _alarmTimer?.cancel();
    var count = 0;
    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      if (++count >= 30) t.cancel(); // en fazla 30 sn
    });
  }

  void _stopAlarm() {
    _alarmTimer?.cancel();
    _alarmTimer = null;
  }

  void dismissAlarm() {
    _stopAlarm();
    lostAlarm = false;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

/// Uygulama genelinde tüm kayıtlı etiketlerin bağlantılarını tutar.
class TagManager extends ChangeNotifier {
  final Map<String, TagConnection> _conns = {};
  List<SavedTag> _tags = [];
  bool loaded = false;

  List<TagConnection> get connections =>
      _tags.map((t) => _conns[t.id]!).toList();

  bool isSaved(String id) => _conns.containsKey(id);

  Future<void> init() async {
    _tags = await TagStore.load();
    for (final t in _tags) {
      final c = TagConnection(t);
      c.addListener(notifyListeners);
      _conns[t.id] = c;
      c.start();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> add(SavedTag tag) async {
    if (isSaved(tag.id)) return;
    _tags = [..._tags, tag];
    await TagStore.save(_tags);
    final c = TagConnection(tag);
    c.addListener(notifyListeners);
    _conns[tag.id] = c;
    c.start();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final c = _conns.remove(id);
    _tags = _tags.where((t) => t.id != id).toList();
    await TagStore.save(_tags);
    if (c != null) {
      c.removeListener(notifyListeners);
      await c.stop();
      c.dispose();
    }
    notifyListeners();
  }
}
