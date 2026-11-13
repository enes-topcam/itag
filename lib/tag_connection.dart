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
  // Link Loss: bağlantı koparsa etiketin KENDİ çalacağı alarm seviyesi.
  // Biz bunu 0x00 yapıp kopma alarmını telefona bırakıyoruz; yoksa etiket
  // her kopmada (bağlanma denemeleri dahil) öter.
  static final linkLossService = Guid('1803');
  // Etiket üzerindeki düğme bildirimi (üreticiye özel)
  static final buttonService = Guid('FFE0');
  static final buttonChar = Guid('FFE1');
  // Pil
  static final batteryService = Guid('180F');
  static final batteryLevel = Guid('2A19');
}

/// Bağlanılan cihazın gerçekten bir iTag gibi görünüp görünmediğini kontrol
/// eder ("parmak izi"). Taklidi zorlaştırır ama tamamen engellemez.
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
        if (s.uuid == ItagUuids.linkLossService &&
            c.uuid == ItagUuids.alertLevel) {
          linkLossChar = c;
        }
      }
    }
  }

  BluetoothCharacteristic? linkLossChar;
  BluetoothCharacteristic? alertChar;
  BluetoothCharacteristic? buttonChar;
  BluetoothCharacteristic? batteryChar;

  bool get looksLikeItag => alertChar != null && buttonChar != null;

  static Future<void> _write(BluetoothCharacteristic c, int v) =>
      c.write([v], withoutResponse: c.properties.writeWithoutResponse);

  /// Etiketin kendi kopma alarmını kapatır. Varsa true döner.
  Future<bool> disableLinkLossBeep() async {
    final c = linkLossChar;
    if (c == null) return false;
    await _write(c, 0x00);
    return true;
  }

  /// "Bağlandım" sinyali: kısa bip-bip-bip.
  Future<void> connectedChirp() async {
    final c = alertChar;
    if (c == null) return;
    for (var i = 0; i < 3; i++) {
      await _write(c, 0x02);
      await Future.delayed(const Duration(milliseconds: 180));
      await _write(c, 0x00);
      await Future.delayed(const Duration(milliseconds: 220));
    }
  }

  /// Tüm servis/karakteristikleri okunabilir satırlar halinde döker.
  static List<String> describe(List<BluetoothService> services) {
    final out = <String>[];
    for (final s in services) {
      out.add('Servis ${s.uuid.str}');
      for (final c in s.characteristics) {
        final p = c.properties;
        final props = [
          if (p.read) 'read',
          if (p.write) 'write',
          if (p.writeWithoutResponse) 'writeNoResp',
          if (p.notify) 'notify',
          if (p.indicate) 'indicate',
        ].join(',');
        out.add('   └ ${c.uuid.str} [$props]');
      }
    }
    return out;
  }
}

/// Kayıtlı tek bir cihazla olan bağlantıyı yönetir.
///
/// - Otomatik bağlan açıksa [TagManager] cihazı görünce [connectNow] çağırır.
/// - Biz bağlıyken iTag reklam yayınını keser; başkası bağlanamaz.
/// - Otomatik bağlan açık bir cihaz beklenmedik şekilde koparsa alarm çalar.
class TagConnection extends ChangeNotifier {
  TagConnection(this.tag) : device = BluetoothDevice.fromId(tag.id);

  SavedTag tag;
  final BluetoothDevice device;

  BluetoothConnectionState state = BluetoothConnectionState.disconnected;
  int? rssi;
  int? battery;
  int buttonPresses = 0;
  bool ringing = false;
  bool trusted = false; // iTag parmak izi kontrolünden geçti mi
  bool suspicious = false; // kayıtlı iTag kimliğiyle sahte cihaz çıktı
  bool lostAlarm = false; // bağlantı beklenmedik şekilde koptu
  final List<String> log = [];

  BluetoothCharacteristic? _alertChar;
  StreamSubscription? _connSub;
  StreamSubscription? _buttonSub;
  Timer? _rssiTimer;
  Timer? _alarmTimer;
  bool _stopping = false; // cihaz siliniyor
  bool _hold = false; // kullanıcı bağlantıyı elle kesti
  bool _connecting = false;
  bool _dumped = false;
  final List<DateTime> _recentPresses = [];

  bool get isConnected => state == BluetoothConnectionState.connected;
  bool get isConnecting => _connecting;
  bool get canRing => isConnected && trusted && _alertChar != null;

  /// TagManager'ın bu cihazı arayıp otomatik bağlanması gerekiyor mu?
  bool get needsAutoConnect =>
      tag.autoConnect && !_stopping && !_hold && !isConnected && !_connecting;

  String get statusText {
    if (lostAlarm) return 'BAĞLANTI KOPTU';
    if (isConnected) return 'Bağlı · ${rssi ?? '-'} dBm';
    if (_connecting) return 'Bağlanıyor...';
    if (suspicious) return 'Şüpheli cihaz, bağlanılmadı';
    if (tag.autoConnect && !_hold) return 'Aranıyor...';
    return 'Bağlı değil';
  }

  void _log(String m) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    log.insert(0, '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $m');
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }

  void start() {
    _stopping = false;
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onState);
  }

  /// [manual]: kullanıcı "Bağlan"a bastı (elle kesme kilidini kaldırır).
  Future<void> connectNow({bool manual = false}) async {
    if (_stopping || isConnected || _connecting) return;
    if (manual) {
      _hold = false;
      suspicious = false;
    }
    _connecting = true;
    _log(manual ? 'Bağlanılıyor...' : 'Cihaz görüldü, bağlanılıyor...');
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        mtu: null,
      );
    } catch (e) {
      _log('Bağlanılamadı${tag.autoConnect ? ', tekrar denenecek' : ''}');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Kullanıcı bağlantıyı elle kesti: alarm çalmaz, otomatik bağlanmaz
  /// (tekrar "Bağlan"a basılana kadar).
  Future<void> disconnectManually() async {
    _hold = true;
    lostAlarm = false;
    _stopAlarm();
    _log('Bağlantı elle kesildi');
    try {
      await device.disconnect();
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopping = true;
    _stopAlarm();
    _rssiTimer?.cancel();
    _buttonSub?.cancel();
    _connSub?.cancel();
    try {
      await device.disconnect();
    } catch (_) {}
  }

  Future<void> _onState(BluetoothConnectionState s) async {
    final wasConnectedBefore = state == BluetoothConnectionState.connected;
    state = s;
    notifyListeners();
    if (s == BluetoothConnectionState.connected) {
      _log('Bağlandı');
      if (lostAlarm) {
        lostAlarm = false;
        _stopAlarm();
        _log('Cihaz geri geldi, alarm durdu');
      }
      await _setup();
    } else if (s == BluetoothConnectionState.disconnected) {
      _rssiTimer?.cancel();
      _buttonSub?.cancel();
      _alertChar = null;
      trusted = false;
      ringing = false;
      rssi = null;
      // Sadece gerçekten bağlıyken, kullanıcı kesmeden kopma alarm sayılır.
      if (wasConnectedBefore && !_stopping && !_hold) {
        _log('BAĞLANTI KOPTU!');
        if (tag.autoConnect) {
          lostAlarm = true;
          _startAlarm();
        }
      }
      notifyListeners();
    }
  }

  Future<void> _setup() async {
    try {
      final services = await device.discoverServices();
      final fp = ItagFingerprint(services);

      if (!_dumped) {
        _dumped = true;
        // log en yeni üstte olduğu için ters sırayla ekle
        for (final l in ItagFingerprint.describe(services).reversed) {
          _log(l);
        }
        _log('--- GATT tablosu ---');
      }

      if (tag.isItag) {
        if (!fp.looksLikeItag) {
          // Kayıtlı iTag kimliğiyle bağlanan cihaz beklenen servislere sahip
          // değil: taklit olabilir. Komut göndermeden ayrıl.
          suspicious = true;
          _hold = true;
          _log('UYARI: Cihaz iTag parmak izine uymuyor, bağlantı kesildi');
          await device.disconnect();
          return;
        }
        // İlk iş: etiketin kendi kopma bip'ini kapat.
        try {
          if (await fp.disableLinkLossBeep()) {
            _log('Etiketin kendi kopma alarmı kapatıldı (1803)');
          } else {
            _log('Etikette Link Loss (1803) servisi yok');
          }
        } catch (e) {
          _log('Link Loss yazılamadı: $e');
        }
        trusted = true;
        _alertChar = fp.alertChar;
        await fp.buttonChar!.setNotifyValue(true);
        _buttonSub?.cancel();
        _buttonSub = fp.buttonChar!.onValueReceived.listen(_onButton);
      }

      final b = fp.batteryChar;
      if (b != null && b.properties.read) {
        try {
          final v = await b.read();
          // Pil 0-100 aralığında olmalı; dışındaysa güvenme.
          if (v.length == 1 && v.first <= 100) battery = v.first;
        } catch (_) {}
      }

      _rssiTimer?.cancel();
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          rssi = await device.readRssi();
          notifyListeners();
        } catch (_) {}
      });
      _log(tag.isItag ? 'Hazır (iTag doğrulandı)' : 'Hazır');
      if (tag.isItag) await fp.connectedChirp();
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

/// Uygulama genelinde tüm kayıtlı cihazların bağlantılarını tutar ve
/// otomatik bağlan açık olan, bağlı olmayan cihazları hedefli taramayla
/// arayıp bağlar.
///
/// Neden Android'in autoConnect'ini kullanmıyoruz? O, sistemin düşük güçlü
/// arka plan taramasına dayanır; bağlanması dakikalar sürebilir, bazı
/// telefonlarda (özellikle Samsung) hiç bağlanmaz.
class TagManager extends ChangeNotifier {
  final Map<String, TagConnection> _conns = {};
  List<SavedTag> _tags = [];
  bool loaded = false;
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;

  Timer? _loop;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool _paused = false;

  List<TagConnection> get connections =>
      _tags.map((t) => _conns[t.id]!).toList();

  TagConnection? get(String id) => _conns[id];
  bool isSaved(String id) => _conns.containsKey(id);

  Future<void> init() async {
    // ÖNEMLİ: adapterStateNow ancak biri adapterState'i dinlerken güncellenir.
    // Dinlemezsek uygulama Bluetooth'u hep "bilinmiyor" sanıp hiç aramaz.
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      adapterState = s;
      notifyListeners();
      if (s == BluetoothAdapterState.on) _tick();
    });

    _tags = await TagStore.load();
    for (final t in _tags) {
      _attach(TagConnection(t));
    }
    loaded = true;
    notifyListeners();

    // Sadece aktif taramadan gelen sonuçlar.
    _scanSub = FlutterBluePlus.onScanResults.listen(_onScanResults);
    _loop = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  void _attach(TagConnection c) {
    c.addListener(notifyListeners);
    _conns[c.tag.id] = c;
    c.start();
  }

  @override
  void dispose() {
    _loop?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }

  /// Kullanıcı Bluetooth sekmesinde tarama yaparken otomatik aramayı durdur.
  Future<void> pauseSearch() async {
    _paused = true;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  }

  void resumeSearch() {
    _paused = false;
    _tick();
  }

  Future<void> _tick() async {
    if (_paused || FlutterBluePlus.isScanningNow) return;
    if (adapterState != BluetoothAdapterState.on) return;
    final ids = _conns.values
        .where((c) => c.needsAutoConnect)
        .map((c) => c.device.remoteId.str)
        .toList();
    if (ids.isEmpty) return;
    try {
      await FlutterBluePlus.startScan(
        withRemoteIds: ids,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }

  Future<void> _onScanResults(List<ScanResult> results) async {
    if (_paused) return;
    for (final r in results) {
      final c = _conns[r.device.remoteId.str];
      if (c != null && c.needsAutoConnect) {
        // Bağlanırken taramayı kapat: Android'de aynı anda tarama +
        // bağlanma bağlantıyı yavaşlatıp bozabiliyor.
        await FlutterBluePlus.stopScan();
        await c.connectNow();
        return; // diğerlerine bir sonraki tick'te bakılır
      }
    }
  }

  Future<void> add(SavedTag tag) async {
    if (isSaved(tag.id)) return;
    _tags = [..._tags, tag];
    await TagStore.save(_tags);
    _attach(TagConnection(tag));
    notifyListeners();
  }

  Future<void> update(SavedTag tag) async {
    _tags = [for (final t in _tags) t.id == tag.id ? tag : t];
    await TagStore.save(_tags);
    _conns[tag.id]?.tag = tag;
    notifyListeners();
    _tick();
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
