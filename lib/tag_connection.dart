import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'background.dart';
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
enum LinkStatus { connected, searching, connecting, lost, offline, suspicious }

/// Kayıtlı tek bir cihazla olan bağlantıyı yönetir.
class TagConnection extends ChangeNotifier {
  TagConnection(this.saved) : device = BluetoothDevice.fromId(saved.id);

  SavedDevice saved;
  final BluetoothDevice device;

  /// Kayıtlı bilgiler (son görülme vb.) değişince çağrılır; TagManager kaydeder.
  void Function(SavedDevice)? onPersist;

  /// En son ne zaman bağlıydı (bağlanma ya da bağlantının kesilmesi anı).
  DateTime? get lastSeen => saved.lastSeenAt;

  BluetoothConnectionState state = BluetoothConnectionState.disconnected;
  int? rssi;
  int? battery;
  bool batterySupported = false;
  int buttonPresses = 0;
  bool ringing = false;
  bool trusted = false;
  bool suspicious = false;
  bool lostAlarm = false;
  List<String> gattLines = const [];
  final List<String> log = [];

  BluetoothCharacteristic? _alertChar;
  StreamSubscription? _connSub;
  StreamSubscription? _buttonSub;
  Timer? _rssiTimer;
  Timer? _alarmTimer;
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
    if (lostAlarm) return LinkStatus.lost;
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
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        mtu: null,
      );
    } catch (e) {
      if (!_cancelRequested) {
        lastError = 'Cihaz bulundu ama bağlanılamadı. Tekrar dene.';
        _log('Bağlanılamadı');
      }
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

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

  /// Kullanıcı bağlantıyı bilerek kesti: yanlış alarm verilmez (doküman §12).
  Future<void> disconnectManually() async {
    _hold = true;
    lostAlarm = false;
    _stopAlarm();
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
    _stopAlarm();
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
      if (lostAlarm) {
        lostAlarm = false;
        _stopAlarm();
        Background.cancelLost(saved.id);
        _log('Cihaz geri geldi, uyarı durdu');
      }
      await _setup();
    } else if (s == BluetoothConnectionState.disconnected) {
      _rssiTimer?.cancel();
      _ringTimer?.cancel();
      _buttonSub?.cancel();
      _alertChar = null;
      trusted = false;
      ringing = false;
      rssi = null;
      if (wasConnectedBefore) {
        _persist(saved.copyWith(lastSeenAt: DateTime.now()));
      }
      if (wasConnectedBefore && !_stopping && !_hold) {
        _log('Bağlantı kesildi');
        if (saved.alertOnDisconnect && appSettings.alertsEnabled) {
          lostAlarm = true;
          _persist(saved.copyWith(lastAlertAt: DateTime.now()));
          _startAlarm();
          // Uygulama kapalıyken de görünsün diye sistem bildirimi.
          if (appSettings.alertNotify) {
            Background.notifyLost(saved.id, saved.displayName);
          }
        }
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
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          rssi = await device.readRssi();
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

  void _startAlarm() {
    _alarmTimer?.cancel();
    var count = 0;
    void beep() {
      if (appSettings.alertVibrate) HapticFeedback.heavyImpact();
      if (appSettings.alertSound) SystemSound.play(SystemSoundType.alert);
    }

    beep();
    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      beep();
      if (++count >= 30) t.cancel();
    });
  }

  void _stopAlarm() {
    _alarmTimer?.cancel();
    _alarmTimer = null;
  }

  void dismissAlarm() {
    _stopAlarm();
    lostAlarm = false;
    Background.cancelLost(saved.id);
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
