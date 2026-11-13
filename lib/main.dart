import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// iTag tipi ucuz BLE etiketlerin standart UUID'leri.
class ItagUuids {
  // Immediate Alert: etiketi öttürmek için (0x00 sus, 0x01 hafif, 0x02 yüksek)
  static final immediateAlertService = Guid('1802');
  // Link Loss: bağlantı koparsa etiket kendisi ötsün mü
  static final linkLossService = Guid('1803');
  static final alertLevel = Guid('2A06');
  // Etiket üzerindeki düğme bildirimi
  static final buttonService = Guid('FFE0');
  static final buttonChar = Guid('FFE1');
  // Pil
  static final batteryService = Guid('180F');
  static final batteryLevel = Guid('2A19');
}

void main() {
  runApp(const ItagApp());
}

class ItagApp extends StatelessWidget {
  const ItagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTag Bulucu',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ScanScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarama ekranı
// ---------------------------------------------------------------------------

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late final StreamSubscription _scanSub;
  late final StreamSubscription _scanningSub;
  late final StreamSubscription _adapterSub;

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      setState(() => _adapterState = s);
    });
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      final list = [...r]..sort((a, b) {
          // iTag olabilecekleri üste al, sonra sinyal gücüne göre sırala
          final ai = _looksLikeItag(a) ? 0 : 1;
          final bi = _looksLikeItag(b) ? 0 : 1;
          if (ai != bi) return ai - bi;
          return b.rssi - a.rssi;
        });
      setState(() => _results = list);
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      setState(() => _scanning = s);
    });
  }

  @override
  void dispose() {
    _scanSub.cancel();
    _scanningSub.cancel();
    _adapterSub.cancel();
    super.dispose();
  }

  static String _nameOf(ScanResult r) {
    final n = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : r.advertisementData.advName;
    return n;
  }

  static bool _looksLikeItag(ScanResult r) {
    final n = _nameOf(r).toLowerCase();
    return n.contains('tag') ||
        r.advertisementData.serviceUuids.contains(ItagUuids.buttonService);
  }

  // Not: Bluetooth izinlerini flutter_blue_plus tarama/bağlanma sırasında
  // kendisi ister (Android), iOS'ta da sistem kendisi sorar.
  Future<void> _startScan() async {
    if (Platform.isAndroid &&
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _snack('Tarama başlatılamadı: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final btOff = _adapterState == BluetoothAdapterState.off;
    return Scaffold(
      appBar: AppBar(title: const Text('iTag Bulucu')),
      body: Column(
        children: [
          if (btOff)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: const Text('Bluetooth kapalı. Lütfen açın.'),
            ),
          if (_scanning) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Cihaz bulunamadı.\n'
                        'iTag\'in düğmesine bir kez basarak uyandırın, '
                        'sonra "Tara"ya basın.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      final name = _nameOf(r);
                      final itag = _looksLikeItag(r);
                      return ListTile(
                        leading: Icon(
                          itag ? Icons.key : Icons.bluetooth,
                          color: itag ? Colors.indigo : Colors.grey,
                        ),
                        title: Text(name.isEmpty ? '(isimsiz cihaz)' : name),
                        subtitle: Text(r.device.remoteId.str),
                        trailing: Text('${r.rssi} dBm'),
                        onTap: () async {
                          await FlutterBluePlus.stopScan();
                          if (!context.mounted) return;
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DeviceScreen(
                              device: r.device,
                              name: name.isEmpty ? 'iTag' : name,
                            ),
                          ));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? FlutterBluePlus.stopScan : _startScan,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? 'Durdur' : 'Tara'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cihaz ekranı
// ---------------------------------------------------------------------------

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.device, required this.name});

  final BluetoothDevice device;
  final String name;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  BluetoothConnectionState _state = BluetoothConnectionState.disconnected;
  BluetoothCharacteristic? _alertChar;
  BluetoothCharacteristic? _buttonChar;
  int? _battery;
  int? _rssi;
  int _buttonPresses = 0;
  bool _ringing = false;
  final List<String> _log = [];

  StreamSubscription? _connSub;
  StreamSubscription? _buttonSub;
  Timer? _rssiTimer;

  BluetoothDevice get _d => widget.device;

  @override
  void initState() {
    super.initState();
    _connSub = _d.connectionState.listen((s) async {
      setState(() => _state = s);
      if (s == BluetoothConnectionState.connected) {
        _addLog('Bağlandı');
        await _setup();
      } else if (s == BluetoothConnectionState.disconnected) {
        _addLog('Bağlantı koptu');
        _rssiTimer?.cancel();
        _alertChar = null;
        _buttonChar = null;
      }
    });
    _connect();
  }

  @override
  void dispose() {
    _rssiTimer?.cancel();
    _buttonSub?.cancel();
    _connSub?.cancel();
    _d.disconnect();
    super.dispose();
  }

  void _addLog(String m) {
    final t = TimeOfDay.now().format(context);
    setState(() => _log.insert(0, '$t  $m'));
  }

  Future<void> _connect() async {
    try {
      _addLog('Bağlanılıyor...');
      await _d.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _addLog('Bağlanamadı: $e');
    }
  }

  Future<void> _setup() async {
    try {
      final services = await _d.discoverServices();
      for (final s in services) {
        _addLog('Servis: ${s.uuid.str}');
        for (final c in s.characteristics) {
          if (s.uuid == ItagUuids.immediateAlertService &&
              c.uuid == ItagUuids.alertLevel) {
            _alertChar = c;
          }
          if (s.uuid == ItagUuids.buttonService &&
              c.uuid == ItagUuids.buttonChar) {
            _buttonChar = c;
          }
          if (s.uuid == ItagUuids.batteryService &&
              c.uuid == ItagUuids.batteryLevel) {
            try {
              final v = await c.read();
              if (v.isNotEmpty) setState(() => _battery = v.first);
            } catch (_) {}
          }
        }
      }

      if (_buttonChar != null) {
        await _buttonChar!.setNotifyValue(true);
        _buttonSub?.cancel();
        _buttonSub = _buttonChar!.onValueReceived.listen(_onButtonPressed);
        _addLog('Düğme dinleniyor');
      } else {
        _addLog('Düğme karakteristiği (FFE1) bulunamadı');
      }
      if (_alertChar == null) {
        _addLog('Alarm karakteristiği (1802/2A06) bulunamadı');
      }

      _rssiTimer?.cancel();
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final r = await _d.readRssi();
          if (mounted) setState(() => _rssi = r);
        } catch (_) {}
      });
      setState(() {});
    } catch (e) {
      _addLog('Kurulum hatası: $e');
    }
  }

  void _onButtonPressed(List<int> value) {
    setState(() => _buttonPresses++);
    _addLog('Düğmeye basıldı! (veri: $value)');
    // Şimdilik titreşim + sistem sesi. Sonraki adımda gerçek alarm sesi ekleyeceğiz.
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('iTag düğmesine basıldı!')),
      );
    }
  }

  Future<void> _setAlert(int level) async {
    final c = _alertChar;
    if (c == null) return;
    try {
      final noResp = c.properties.writeWithoutResponse;
      await c.write([level], withoutResponse: noResp);
      setState(() => _ringing = level != 0);
      _addLog(level == 0 ? 'Susturuldu' : 'Öttürülüyor');
    } catch (e) {
      _addLog('Yazma hatası: $e');
    }
  }

  String get _distanceHint {
    final r = _rssi;
    if (r == null) return '-';
    if (r > -60) return 'Çok yakın';
    if (r > -75) return 'Yakın';
    if (r > -90) return 'Uzak';
    return 'Çok uzak';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _state == BluetoothConnectionState.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: connected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(connected ? 'Bağlı' : 'Bağlı değil',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text('Sinyal: ${_rssi ?? '-'} dBm  ($_distanceHint)'),
                  Text('Pil: ${_battery != null ? '%$_battery' : 'bilinmiyor'}'),
                  Text('Düğmeye basılma: $_buttonPresses'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!connected)
            FilledButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar bağlan'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                backgroundColor: _ringing ? Colors.red : null,
              ),
              onPressed: _alertChar == null ? null : () => _setAlert(_ringing ? 0 : 2),
              icon: Icon(_ringing ? Icons.volume_off : Icons.volume_up),
              label: Text(_ringing ? 'Sustur' : 'iTag\'i Öttür'),
            ),
          const SizedBox(height: 24),
          Text('Kayıt', style: Theme.of(context).textTheme.titleSmall),
          const Divider(),
          ..._log.map((l) => Text(l, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
