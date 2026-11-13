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
  bool _dumped = false;
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

  /// Bağlantı durumunu dinlemeye başlar. Asıl bağlanmayı [TagManager]
  /// yapar: etiketi taramada görünce [connectNow] çağırır.
  ///
  /// Neden Android'in autoConnect'ini kullanmıyoruz? autoConnect, sistemin
  /// düşük güçlü arka plan taramasına dayanır; bağlanması dakikalar
  /// sürebilir, bazı telefonlarda (özellikle Samsung) hiç bağlanmaz.
  /// Hedefli tarama + doğrudan bağlantı saniyeler içinde bağlanır.
  void start() {
    _stopping = false;
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onState);
    _log('Etiket aranıyor...');
  }

  bool _connecting = false;

  /// Bağlanmaya çalışmalı mıyız?
  bool get needsConnection => !_stopping && !isConnected && !_connecting;

  Future<void> connectNow() async {
    if (!needsConnection) return;
    _connecting = true;
    _log('Etiket görüldü, bağlanılıyor...');
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        mtu: null,
      );
    } catch (e) {
      _log('Bağlanılamadı, tekrar denenecek');
    } finally {
      _connecting = false;
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
    final wasConnectedBefore = state == BluetoothConnectionState.connected;
    state = s;
    notifyListeners();
    if (s == BluetoothConnectionState.connected) {
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
      // Sadece gerçekten bağlıyken kopma alarm sayılır; başarısız bağlanma
      // denemeleri alarm çaldırmasın.
      if (wasConnectedBefore && !_stopping) {
        _log('BAĞLANTI KOPTU! Etiket uzakta olabilir.');
        lostAlarm = true;
        _startAlarm();
      }
      notifyListeners();
    }
  }

  Future<void> _setup() async {
    try {
      final services = await device.discoverServices();
      final fp = ItagFingerprint(services);
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
      if (!_dumped) {
        _dumped = true;
        // log en yeni üstte olduğu için ters sırayla ekle
        for (final l in ItagFingerprint.describe(services).reversed) {
          _log(l);
        }
        _log('--- GATT tablosu ---');
      }
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
      await fp.connectedChirp();
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

/// Uygulama genelinde tüm kayıtlı etiketlerin bağlantılarını tutar ve
/// bağlı olmayan kayıtlı etiketleri hedefli taramayla arayıp bağlar.
class TagManager extends ChangeNotifier {
  final Map<String, TagConnection> _conns = {};
  List<SavedTag> _tags = [];
  bool loaded = false;

  Timer? _loop;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _paused = false;

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

    // Sadece bu taramadan gelen sonuçlar (birikmiş eski sonuçlar değil).
    _scanSub = FlutterBluePlus.onScanResults.listen(_onScanResults);
    _loop = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _loop?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  /// "Etiket Ekle" ekranı kendi taramasını yaparken arka plan aramasını durdur.
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
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    final ids = _conns.values
        .where((c) => c.needsConnection)
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
      if (c != null && c.needsConnection) {
        // Bağlanırken taramayı kapat: Android'de aynı anda tarama +
        // bağlanma bağlantıyı yavaşlatıp bozabiliyor.
        await FlutterBluePlus.stopScan();
        await c.connectNow();
        return; // döngü bir sonraki tick'te diğerlerine bakar
      }
    }
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
