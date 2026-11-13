import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'tag_connection.dart';
import 'tag_store.dart';

final tagManager = TagManager();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tagManager.init();
  runApp(const ItagApp());
}

class ItagApp extends StatelessWidget {
  const ItagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTag Bulucu',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Ana ekran: kayıtlı etiketler
// ---------------------------------------------------------------------------

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final conns = tagManager.connections;
        return Scaffold(
          appBar: AppBar(title: const Text('Etiketlerim')),
          body: !tagManager.loaded
              ? const Center(child: CircularProgressIndicator())
              : conns.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Henüz kayıtlı etiket yok.\n'
                          'Aşağıdan "Etiket Ekle"ye basın.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final c in conns) _TagTile(conn: c),
                      ],
                    ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Etiket Ekle'),
            onPressed: () async {
              final tag = await Navigator.of(context).push<SavedTag>(
                MaterialPageRoute(builder: (_) => const AddTagScreen()),
              );
              if (tag != null) await tagManager.add(tag);
            },
          ),
        );
      },
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    final c = conn;
    final Color color;
    final String status;
    if (c.lostAlarm) {
      color = Colors.red;
      status = 'BAĞLANTI KOPTU';
    } else if (c.isConnected) {
      color = Colors.green;
      status = 'Bağlı · ${c.rssi ?? '-'} dBm';
    } else {
      color = Colors.grey;
      status = 'Aranıyor...';
    }
    return ListTile(
      leading: Icon(Icons.key, color: color),
      title: Text(c.tag.name),
      subtitle: Text(status, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TagDetailScreen(conn: c),
      )),
    );
  }
}

// ---------------------------------------------------------------------------
// Etiket ekleme: tara -> doğrula -> isim ver -> kaydet
// ---------------------------------------------------------------------------

class AddTagScreen extends StatefulWidget {
  const AddTagScreen({super.key});

  @override
  State<AddTagScreen> createState() => _AddTagScreenState();
}

class _AddTagScreenState extends State<AddTagScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  bool _verifying = false;
  late final StreamSubscription _scanSub;
  late final StreamSubscription _scanningSub;

  @override
  void initState() {
    super.initState();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      final list = r
          .where((x) => _looksLikeItag(x) && !tagManager.isSaved(x.device.remoteId.str))
          .toList()
        ..sort((a, b) => b.rssi - a.rssi);
      setState(() => _results = list);
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      setState(() => _scanning = s);
    });
    _startScan();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _scanSub.cancel();
    _scanningSub.cancel();
    super.dispose();
  }

  static String _nameOf(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  static bool _looksLikeItag(ScanResult r) {
    final n = _nameOf(r).toLowerCase();
    return n.contains('tag') ||
        r.advertisementData.serviceUuids.contains(ItagUuids.buttonService);
  }

  Future<void> _startScan() async {
    if (Platform.isAndroid &&
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      _snack('Tarama başlatılamadı: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Cihaza kısa süreli bağlanıp gerçekten iTag olduğunu doğrular.
  Future<bool> _verify(BluetoothDevice d) async {
    try {
      await d.connect(
          license: License.nonprofit, timeout: const Duration(seconds: 15));
      final fp = ItagFingerprint(await d.discoverServices());
      // Doğrulandığını kullanıcıya göstermek için kısa bir bip.
      if (fp.looksLikeItag) {
        await fp.alertChar!.write([0x01],
            withoutResponse: fp.alertChar!.properties.writeWithoutResponse);
        await Future.delayed(const Duration(milliseconds: 600));
        await fp.alertChar!.write([0x00],
            withoutResponse: fp.alertChar!.properties.writeWithoutResponse);
      }
      return fp.looksLikeItag;
    } catch (e) {
      _snack('Bağlanılamadı: $e');
      return false;
    } finally {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _onPick(ScanResult r) async {
    await FlutterBluePlus.stopScan();
    setState(() => _verifying = true);
    final ok = await _verify(r.device);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (!ok) {
      _snack('Bu cihaz iTag olarak doğrulanamadı.');
      return;
    }
    final name = await _askName(_nameOf(r).isEmpty ? 'iTag' : _nameOf(r));
    if (name == null || !mounted) return;
    Navigator.of(context)
        .pop(SavedTag(id: r.device.remoteId.str, name: name));
  }

  Future<String?> _askName(String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiket bulundu (bip sesi duydun mu?)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Bu etikete bir isim ver', hintText: 'Örn. Anahtarlık'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              Navigator.pop(ctx, t.isEmpty ? initial : t);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Etiket Ekle')),
      body: Column(
        children: [
          if (_scanning || _verifying) const LinearProgressIndicator(),
          if (_verifying)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Doğrulanıyor... etiket kısa bir bip sesi çıkaracak.'),
            ),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Yeni etiket bulunamadı.\n'
                        'Etiketin düğmesine bir kez basıp uyandırın.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final r in _results)
                        ListTile(
                          leading: const Icon(Icons.key, color: Colors.indigo),
                          title: Text(_nameOf(r).isEmpty ? '(isimsiz)' : _nameOf(r)),
                          subtitle: Text(r.device.remoteId.str),
                          trailing: Text('${r.rssi} dBm'),
                          enabled: !_verifying,
                          onTap: () => _onPick(r),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scanning ? FlutterBluePlus.stopScan : _startScan,
        child: Icon(_scanning ? Icons.stop : Icons.refresh),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Etiket detayı
// ---------------------------------------------------------------------------

class TagDetailScreen extends StatelessWidget {
  const TagDetailScreen({super.key, required this.conn});
  final TagConnection conn;

  String _distanceHint(int? r) {
    if (r == null) return '-';
    if (r > -60) return 'Çok yakın';
    if (r > -75) return 'Yakın';
    if (r > -90) return 'Uzak';
    return 'Çok uzak';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiketi sil?'),
        content: Text('"${conn.tag.name}" bu telefondan kaldırılacak.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      await tagManager.remove(conn.tag.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        final c = conn;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.tag.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Etiketi sil',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (c.lostAlarm)
                Card(
                  color: Colors.red.shade100,
                  child: ListTile(
                    leading: const Icon(Icons.warning, color: Colors.red),
                    title: const Text('Bağlantı koptu!'),
                    subtitle: const Text(
                        'Etiket uzakta olabilir. Yaklaşınca otomatik bağlanacak.'),
                    trailing: TextButton(
                      onPressed: c.dismissAlarm,
                      child: const Text('Sustur'),
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          c.isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_searching,
                          color: c.isConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(c.isConnected ? 'Bağlı' : 'Aranıyor...',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (c.trusted) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.verified_user,
                              size: 18, color: Colors.green),
                        ],
                      ]),
                      const SizedBox(height: 8),
                      Text('Sinyal: ${c.rssi ?? '-'} dBm  (${_distanceHint(c.rssi)})'),
                      Text('Pil: ${c.battery != null ? '%${c.battery}' : 'bilinmiyor'}'),
                      Text('Düğmeye basılma: ${c.buttonPresses}'),
                      Text('Kimlik: ${c.tag.id}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  backgroundColor: c.ringing ? Colors.red : null,
                ),
                onPressed: c.canRing ? () => c.setTagAlert(!c.ringing) : null,
                icon: Icon(c.ringing ? Icons.volume_off : Icons.volume_up),
                label: Text(c.ringing ? 'Sustur' : 'Etiketi Öttür'),
              ),
              const SizedBox(height: 24),
              Text('Kayıt', style: Theme.of(context).textTheme.titleSmall),
              const Divider(),
              ...c.log.map((l) => Text(l, style: const TextStyle(fontSize: 12))),
            ],
          ),
        );
      },
    );
  }
}
