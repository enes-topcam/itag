import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';

/// iTag tipi ucuz BLE etiketlerin GATT UUID'leri (gerçek cihazda doğrulandı:
/// 1802/2A06 writeNoResp, 180F/2A19, FFE0/FFE1 notify [1]; 1803 YOK).
class ItagUuids {
  // Immediate Alert: etiketi öttürmek için (0x00 sus, 0x01 hafif, 0x02 yüksek)
  static final immediateAlertService = Guid('1802');
  static final alertLevel = Guid('2A06');
  // Link Loss: bazı modellerde var; varsa kendi kopma bip'ini kapatırız.
  static final linkLossService = Guid('1803');
  // Etiket üzerindeki düğme bildirimi (üreticiye özel)
  static final buttonService = Guid('FFE0');
  static final buttonChar = Guid('FFE1');
  // Pil
  static final batteryService = Guid('180F');
  static final batteryLevel = Guid('2A19');
}

/// Bağlanılan cihazın iTag gibi davranıp davranmadığını kontrol eder
/// ("parmak izi"). Taklidi zorlaştırır ama tamamen engellemez.
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
        ].join(', ');
        out.add('   └ ${c.uuid.str}  [$props]');
      }
    }
    return out;
  }
}

/// Arayüzde gösterilen bağlantı durumu (doküman §3 "Ortak durum bileşenleri").
enum LinkStatus { connected, searching, connecting, offline, suspicious }

/// Kayıtlı tek bir cihazla olan bağlantıyı yönetir.
class TagConnection extends ChangeNotifier {
  TagConnection(this.saved) : device = BluetoothDevice.fromId(saved.id);

  SavedDevice saved;
  final BluetoothDevice device;

  /// Kayıtlı bilgiler (son görülme vb.) değişince çağrılır; TagManager kaydeder.
  void Function(SavedDevice)? onPersist;

  /// En son ne zaman bağlıydı (bağlanma ya da bağlantının kesilmesi anı).
  DateTime? get lastSeen => saved.lastSeenAt;

  // ---- Mesafe tahmini ----------------------------------------------------
  //
  // Log-distance path loss modeli:  d = 10 ^ ((P1m − RSSI) / (10 · n))
  //   P1m: 1 metredeki sinyal gücü (kalibrasyonla ölçülür; yoksa varsayılan)
  //   n  : ortam zayıflama katsayısı (boş alan 2.0, iç mekan ~2.2-3)
  // Duvar, cep, vücut 2-3 kat sapma yaratabilir; arayüzde "≈" ile gösterilir.

  static const int defaultRssiAt1m = -60;
  static const double pathLossExponent = 2.2;
  static const int _rssiWindowSize = 7;
  final List<int> _rssiWindow = [];

  bool get isCalibrated => saved.rssiAt1m != null;

  /// Tahmini uzaklık (metre); bağlı değilse null.
  double? get distanceM {
    final r = rssi;
    if (r == null) return null;
    final p1m = saved.rssiAt1m ?? defaultRssiAt1m;
    return pow(10, (p1m - r) / (10 * pathLossExponent)).toDouble();
  }

  static int _median(List<int> xs) {
    final s = [...xs]..sort();
    return s[s.length ~/ 2];
  }

  bool calibrating = false;

  /// Telefon etiketten 1 m uzaktayken çağrılır: ~5 sn ölçer, ortancayı
  /// bu cihazın 1 m referansı olarak kaydeder. Ölçülen değeri döndürür.
  Future<int?> calibrate() async {
    if (!isConnected || calibrating) return null;
    calibrating = true;
    notifyListeners();
    final samples = <int>[];
    try {
      for (var i = 0; i < 12; i++) {
        try {
          samples.add(await device.readRssi());
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (samples.length < 5) return null;
      final m = _median(samples);
      _persist(saved.copyWith(rssiAt1m: m));
      _log('Kalibre edildi: 1 m = $m dBm');
      return m;
    } finally {
      calibrating = false;
      notifyListeners();
    }
  }

  BluetoothConnectionState state = BluetoothConnectionState.disconnected;
  int? rssi;
  int? battery;
  bool batterySupported = false;
  int buttonPresses = 0;
  bool ringing = false;
  bool trusted = false;
  bool suspicious = false;
  List<String> gattLines = const [];
  final List<String> log = [];

  BluetoothCharacteristic? _alertChar;
  StreamSubscription? _connSub;
  StreamSubscription? _buttonSub;
  Timer? _rssiTimer;
  Timer? _ringTimer;
  bool _stopping = false;
  bool _hold = false;
  bool _connecting = false;
  bool _searching = false;
  bool _cancelRequested = false;
  final List<DateTime> _recentPresses = [];

  /// Son "Bağlan" denemesi başarısızsa kullanıcıya gösterilecek mesaj.
  String? lastError;

  bool get isConnected => state == BluetoothConnectionState.connected;
  bool get isSearching => _searching;
  bool get isConnecting => _connecting;
  bool get isBusy => _searching || _connecting;
  bool get canRing => isConnected && trusted && _alertChar != null;

  LinkStatus get status {
    if (isConnected) return LinkStatus.connected;
    if (_searching) return LinkStatus.searching;
    if (_connecting) return LinkStatus.connecting;
    if (suspicious) return LinkStatus.suspicious;
    return LinkStatus.offline;
  }

  void _log(String m) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    log.insert(0, '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $m');
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }

  void _persist(SavedDevice d) {
    saved = d;
    onPersist?.call(d);
  }

  void start() {
    _stopping = false;
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onState);
  }

  /// Kullanıcı "Bağlan"a bastı. Uygulama cihaza YALNIZCA burada bağlanır
  /// (otomatik bağlanma yok).
  ///
  /// Neden? Bu iTag her bağlantı kopuşunda öter ve bunu kapatan bir ayarı
  /// yok. Hiç bağlanmazsak hiç ötmez; sadece kaybolunca bağlanıp buluruz.
  ///
  /// Akış: Bluetooth'u aç → cihazı 30 sn'ye kadar hedefli tara (kullanıcı bu
  /// sırada yürüyüp yaklaşabilir) → görünce doğrudan bağlan.
  Future<void> connectNow() async {
    if (_stopping || isConnected || isBusy) return;
    _hold = false;
    suspicious = false;
    _cancelRequested = false;
    lastError = null;
    _searching = true;
    notifyListeners();

    if (!await _ensureBluetoothOn()) {
      _searching = false;
      lastError = "Bluetooth kapalı. Bluetooth'u açıp tekrar dene.";
      _log('Bluetooth açılamadı');
      notifyListeners();
      return;
    }

    _log('Cihaz aranıyor…');
    final found = await _scanFor(const Duration(seconds: 30));
    _searching = false;
    if (_cancelRequested) {
      notifyListeners();
      return;
    }
    if (!found) {
      lastError = 'Cihaz bulunamadı. Biraz yürüyüp tekrar dene; cihazın '
          'pilinin bitmediğinden emin ol.';
      _log('30 sn içinde bulunamadı');
      notifyListeners();
      return;
    }

    _connecting = true;
    notifyListeners();
    _log('Cihaz bulundu, bağlanılıyor…');
    // Ucuz iTag'ler bağlantı isteğine bazen geç yanıt verir: kayıtlarda ilk
    // deneme 10 sn'de zaman aşımına uğrayıp hemen ardından gelen deneme 3 sn'de
    // bağlandı. Bu yüzden tek dokunuşta birkaç kez, daha uzun süreyle denenir.
    try {
      for (var attempt = 1; attempt <= _connectAttempts; attempt++) {
        if (_cancelRequested) break;
        connectAttempt = attempt;
        notifyListeners();
        try {
          await device.connect(
            license: License.nonprofit,
            timeout: const Duration(seconds: 15),
            mtu: null,
          );
          break; // bağlandı
        } catch (e) {
          if (_cancelRequested) break;
          _log('Bağlantı denemesi $attempt başarısız');
          if (attempt == _connectAttempts) {
            lastError = 'Cihaz bulundu ama bağlanılamadı. Cihaza biraz '
                'yaklaşıp tekrar dene.';
          } else {
            // Android BLE yığınının önceki denemeyi temizlemesine zaman tanı.
            await Future.delayed(const Duration(milliseconds: 800));
          }
        }
      }
    } finally {
      _connecting = false;
      connectAttempt = 0;
      notifyListeners();
    }
  }

  static const int _connectAttempts = 3;

  /// Şu anki bağlantı denemesi (1..3); bağlanmıyorken 0.
  int connectAttempt = 0;

  /// Arama/bağlanma sürerken kullanıcı vazgeçti.
  Future<void> cancelConnect() async {
    if (!isBusy) return;
    _cancelRequested = true;
    _hold = true;
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    if (_connecting) {
      try {
        await device.disconnect(); // bekleyen bağlantı isteğini iptal eder
      } catch (_) {}
    }
    _log('Arama iptal edildi');
    notifyListeners();
  }

  Future<bool> _ensureBluetoothOn() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return true;
    }
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn(); // sistem "Bluetooth açılsın mı?" sorar
      } catch (_) {
        return false;
      }
    }
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sadece bu cihazı arayan tarama; görünce true, süre dolunca false.
  Future<bool> _scanFor(Duration timeout) async {
    final found = Completer<bool>();
    final sub = FlutterBluePlus.onScanResults.listen((rs) {
      if (!found.isCompleted &&
          rs.any((r) => r.device.remoteId == device.remoteId)) {
        found.complete(true);
      }
    });
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(
        withRemoteIds: [device.remoteId.str],
        timeout: timeout,
      );
      // Tarama bitince (süre doldu ya da iptal) bulunamadı say.
      FlutterBluePlus.isScanning.where((s) => !s).first.then((_) {
        if (!found.isCompleted) found.complete(false);
      });
      return await found.future;
    } catch (_) {
      return false;
    } finally {
      await sub.cancel();
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    }
  }

  /// Kullanıcı "Bağlantıyı Kes"e bastı.
  Future<void> disconnectManually() async {
    _hold = true;
    _ringTimer?.cancel();
    // Kesmeden önce çalan sesi durdur. (Not: Bu, bizim iTag'in kopma bip'ini
    // ENGELLEMİYOR — 2026-11-13'te test edildi; etiket her kopuşta öter.)
    final c = _alertChar;
    if (c != null) {
      try {
        await c.write([0x00],
            withoutResponse: c.properties.writeWithoutResponse);
        await Future.delayed(const Duration(milliseconds: 300));
        _log('Kesmeden önce sessiz (0x00) komutu gönderildi');
      } catch (_) {}
    }
    _log('Bağlantı elle kesildi');
    try {
      await device.disconnect();
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopping = true;
    _ringTimer?.cancel();
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
      final now = DateTime.now();
      _persist(saved.copyWith(lastConnectedAt: now, lastSeenAt: now));
      await _setup();
    } else if (s == BluetoothConnectionState.disconnected) {
      _rssiTimer?.cancel();
      _ringTimer?.cancel();
      _buttonSub?.cancel();
      _alertChar = null;
      trusted = false;
      ringing = false;
      rssi = null;
      _rssiWindow.clear();
      if (wasConnectedBefore) {
        _persist(saved.copyWith(lastSeenAt: DateTime.now()));
      }
      if (wasConnectedBefore && !_stopping && !_hold) {
        _log('Bağlantı kesildi');
      }
      notifyListeners();
    }
  }

  Future<void> _setup() async {
    try {
      final services = await device.discoverServices();
      final fp = ItagFingerprint(services);
      gattLines = ItagFingerprint.describe(services);

      if (saved.isItag) {
        if (!fp.looksLikeItag) {
          suspicious = true;
          _hold = true;
          _log('UYARI: Cihaz kayıtlı iTag gibi davranmıyor, bağlantı kesildi');
          await device.disconnect();
          return;
        }
        try {
          if (await fp.disableLinkLossBeep()) {
            _log('Etiketin kendi kopma alarmı kapatıldı');
          }
        } catch (_) {}
        trusted = true;
        _alertChar = fp.alertChar;
        await fp.buttonChar!.setNotifyValue(true);
        _buttonSub?.cancel();
        _buttonSub = fp.buttonChar!.onValueReceived.listen(_onButton);
      }

      final b = fp.batteryChar;
      batterySupported = b != null && b.properties.read;
      if (batterySupported) {
        try {
          final v = await b!.read();
          if (v.length == 1 && v.first <= 100) battery = v.first;
        } catch (_) {}
      }

      _rssiTimer?.cancel();
      _rssiWindow.clear();
      _rssiTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        try {
          final raw = await device.readRssi();
          // RSSI çok oynak (±5-10 dB); son ölçümlerin ortancası sıçramaları
          // yok sayar, sayı her saniye zıplamaz.
          _rssiWindow.add(raw);
          if (_rssiWindow.length > _rssiWindowSize) _rssiWindow.removeAt(0);
          rssi = _median(_rssiWindow);
          notifyListeners();
        } catch (_) {}
      });
      _log(saved.isItag ? 'Hazır (iTag doğrulandı)' : 'Hazır');
      notifyListeners();
      if (saved.isItag) await fp.connectedChirp();
    } catch (e) {
      _log('Kurulum hatası: $e');
    }
  }

  void _onButton(List<int> value) {
    if (value.length != 1 || value.first != 0x01) {
      _log('Beklenmeyen veri yok sayıldı: $value');
      return;
    }
    final now = DateTime.now();
    _recentPresses
        .removeWhere((t) => now.difference(t) > const Duration(seconds: 2));
    _recentPresses.add(now);
    if (_recentPresses.length > 5) {
      _log('Çok hızlı bildirim, yok sayıldı');
      return;
    }
    buttonPresses++;
    _log('Cihazın düğmesine basıldı');
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  /// Ses çaldır: 30 sn sonra kendiliğinden durur (süreli çalma, doküman §10).
  Future<void> setTagAlert(bool on) async {
    final c = _alertChar;
    if (c == null || !trusted) return;
    try {
      await c.write([on ? 0x02 : 0x00],
          withoutResponse: c.properties.writeWithoutResponse);
      ringing = on;
      _ringTimer?.cancel();
      if (on) {
        _ringTimer = Timer(const Duration(seconds: 30), () => setTagAlert(false));
      }
      // Etiket geri bildirim vermediği için ihtiyatlı ifade (doküman §10).
      _log(on ? 'Ses komutu gönderildi' : 'Durdurma komutu gönderildi');
    } catch (e) {
      _log('Komut gönderilemedi: $e');
    }
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

/// Tüm kayıtlı cihazları ve bağlantı nesnelerini tutar. Otomatik bağlanma
/// YOK: bağlantıyı yalnızca kullanıcı "Bağlan" ile başlatır.
class TagManager extends ChangeNotifier {
  final Map<String, TagConnection> _conns = {};
  List<SavedDevice> _devices = [];
  bool loaded = false;
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  List<TagConnection> get connections =>
      _devices.map((d) => _conns[d.id]!).toList();

  TagConnection? get(String id) => _conns[id];
  bool isSaved(String id) => _conns.containsKey(id);

  Future<void> init() async {
    // adapterStateNow ancak biri adapterState'i dinlerken güncellenir.
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      adapterState = s;
      notifyListeners();
    });

    _devices = await DeviceStore.load();
    for (final d in _devices) {
      _attach(TagConnection(d));
    }
    loaded = true;
    notifyListeners();
  }

  void _attach(TagConnection c) {
    c.addListener(notifyListeners);
    c.onPersist = _persist;
    _conns[c.saved.id] = c;
    c.start();
  }

  void _persist(SavedDevice d) {
    _devices = [for (final x in _devices) x.id == d.id ? d : x];
    DeviceStore.save(_devices);
    notifyListeners();
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    super.dispose();
  }

  Future<void> add(SavedDevice d) async {
    if (isSaved(d.id)) return;
    _devices = [..._devices, d];
    await DeviceStore.save(_devices);
    _attach(TagConnection(d));
    notifyListeners();
  }

  Future<void> update(SavedDevice d) async {
    _conns[d.id]?.saved = d;
    _persist(d);
  }

  Future<void> remove(String id) async {
    final c = _conns.remove(id);
    _devices = _devices.where((d) => d.id != id).toList();
    await DeviceStore.save(_devices);
    if (c != null) {
      c.removeListener(notifyListeners);
      await c.stop();
      c.dispose();
    }
    notifyListeners();
  }

  Future<void> clearAll() async {
    for (final id in _conns.keys.toList()) {
      await remove(id);
    }
  }
}

final tagManager = TagManager();
