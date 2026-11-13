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
      home: const HomeShell(),
    );
  }
}

void openDevice(BuildContext context, TagConnection c) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DeviceDetailScreen(conn: c),
  ));
}

// ---------------------------------------------------------------------------
// Alt sekmeler
// ---------------------------------------------------------------------------

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 1; // açılışta Kayıtlı Cihazlar

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          BluetoothTab(active: _index == 0),
          SavedTab(onGoScan: () => setState(() => _index = 0)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching),
            label: 'Bluetooth',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: 'Kayıtlı Cihazlar',
          ),
        ],
      ),
    );
  }
}

class _BluetoothOffBanner extends StatelessWidget {
  const _BluetoothOffBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        if (tagManager.adapterState != BluetoothAdapterState.off) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          color: Colors.red.shade100,
          padding: const EdgeInsets.all(12),
          child: const Text('Bluetooth kapalı. Lütfen açın.'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sekme 1: Bluetooth (çevredeki tüm cihazlar)
// ---------------------------------------------------------------------------

class BluetoothTab extends StatefulWidget {
  const BluetoothTab({super.key, required this.active});
  final bool active;

  @override
  State<BluetoothTab> createState() => _BluetoothTabState();
}

class _BluetoothTabState extends State<BluetoothTab> {
  final Map<String, ScanResult> _seen = {};
  bool _userScan = false;
  String? _connectingId;
  late final StreamSubscription _scanSub;
  late final StreamSubscription _scanningSub;

  @override
  void initState() {
    super.initState();
    // Sadece kullanıcının başlattığı taramanın sonuçlarını topla
    // (otomatik bağlanma taramaları listeyi bozmasın).
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!_userScan) return;
      for (final r in results) {
        _seen[r.device.remoteId.str] = r;
      }
      if (mounted) setState(() {});
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (!s && _userScan) {
        _userScan = false;
        tagManager.resumeSearch();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(BluetoothTab old) {
    super.didUpdateWidget(old);
    // Sekmeye ilk geçişte otomatik tara.
    if (widget.active && !old.active && _seen.isEmpty && !_userScan) {
      _startScan();
    }
  }

  @override
  void dispose() {
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
        tagManager.adapterState != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    }
    await tagManager.pauseSearch();
    setState(() {
      _seen.clear();
      _userScan = true;
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      _userScan = false;
      tagManager.resumeSearch();
      _snack('Tarama başlatılamadı: $e');
    }
  }

  Future<void> _stopScan() => FlutterBluePlus.stopScan();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Cihaza bağlan; başarılıysa kayıtlı cihazlara ekle ve detayını aç.
  Future<void> _connect(ScanResult r) async {
    final id = r.device.remoteId.str;
    final existing = tagManager.get(id);
    if (existing != null) {
      openDevice(context, existing);
      return;
    }
    if (_connectingId != null) return;

    await _stopScan();
    setState(() => _connectingId = id);
    final d = r.device;
    try {
      await d.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        mtu: null,
      );
      final fp = ItagFingerprint(await d.discoverServices());
      final isItag = fp.looksLikeItag;
      final name = _nameOf(r);
      final tag = SavedTag(
        id: id,
        name: name.isNotEmpty ? name : (isItag ? 'iTag' : 'Bluetooth cihazı'),
        isItag: isItag,
        // iTag'ler varsayılan olarak otomatik bağlansın; diğerleri hayır.
        autoConnect: isItag,
      );
      // Bağlantı açık kalıyor; TagConnection mevcut bağlantıyı devralır.
      await tagManager.add(tag);
      if (!mounted) return;
      _snack('"${tag.name}" kayıtlı cihazlara eklendi');
      openDevice(context, tagManager.get(id)!);
    } catch (e) {
      try {
        await d.disconnect();
      } catch (_) {}
      _snack('Bağlanılamadı');
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _seen.values.toList()
      ..sort((a, b) {
        // iTag'ler, sonra isimliler üstte; her grupta sinyale göre.
        int rank(ScanResult r) =>
            _looksLikeItag(r) ? 0 : (_nameOf(r).isNotEmpty ? 1 : 2);
        final d = rank(a) - rank(b);
        return d != 0 ? d : b.rssi - a.rssi;
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Cihazları')),
      body: Column(
        children: [
          const _BluetoothOffBanner(),
          if (_userScan || _connectingId != null)
            const LinearProgressIndicator(),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _userScan
                            ? 'Taranıyor...'
                            : 'Çevredeki cihazları görmek için "Tara"ya basın.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListenableBuilder(
                    listenable: tagManager,
                    builder: (context, _) => ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final r = list[i];
                        final id = r.device.remoteId.str;
                        final name = _nameOf(r);
                        final itag = _looksLikeItag(r);
                        final saved = tagManager.isSaved(id);
                        return ListTile(
                          leading: Icon(
                            itag ? Icons.key : Icons.bluetooth,
                            color: itag ? Colors.indigo : Colors.grey,
                          ),
                          title: Text(name.isEmpty ? '(isimsiz cihaz)' : name),
                          subtitle: Text(saved ? '$id · Kayıtlı' : id),
                          trailing: _connectingId == id
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text('${r.rssi} dBm'),
                          enabled: _connectingId == null,
                          onTap: () => _connect(r),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan',
        onPressed: _userScan ? _stopScan : _startScan,
        icon: Icon(_userScan ? Icons.stop : Icons.search),
        label: Text(_userScan ? 'Durdur' : 'Tara'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sekme 2: Kayıtlı cihazlar
// ---------------------------------------------------------------------------

Future<bool> confirmDelete(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kayıtlı cihazı sil?'),
      content: Text('"$name" bu telefondan kaldırılacak ve bağlantısı kesilecek.'),
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
  return ok == true;
}

class SavedTab extends StatelessWidget {
  const SavedTab({super.key, required this.onGoScan});
  final VoidCallback onGoScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final conns = tagManager.connections;
        return Scaffold(
          appBar: AppBar(title: const Text('Kayıtlı Cihazlar')),
          body: Column(
            children: [
              const _BluetoothOffBanner(),
              Expanded(
                child: !tagManager.loaded
                    ? const Center(child: CircularProgressIndicator())
                    : conns.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Henüz kayıtlı cihaz yok.\n'
                                    'Bluetooth sekmesinden bir cihaza bağlanınca '
                                    'burada görünür.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: onGoScan,
                                    icon: const Icon(Icons.bluetooth_searching),
                                    label: const Text('Cihaz ara'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final c in conns) _SavedTile(conn: c),
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Silmek için sola kaydırın.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    final c = conn;
    final Color color = c.lostAlarm || c.suspicious
        ? Colors.red
        : c.isConnected
            ? Colors.green
            : Colors.grey;
    return Dismissible(
      key: ValueKey(c.tag.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDelete(context, c.tag.name),
      onDismissed: (_) => tagManager.remove(c.tag.id),
      child: ListTile(
        leading: Icon(c.tag.isItag ? Icons.key : Icons.bluetooth, color: color),
        title: Text(c.tag.name),
        subtitle: Text(c.statusText, style: TextStyle(color: color)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Switch(
              value: c.tag.autoConnect,
              onChanged: (v) =>
                  tagManager.update(c.tag.copyWith(autoConnect: v)),
            ),
          ],
        ),
        onTap: () => openDevice(context, c),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cihaz detayı
// ---------------------------------------------------------------------------

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key, required this.conn});
  final TagConnection conn;

  String _distanceHint(int? r) {
    if (r == null) return '-';
    if (r > -60) return 'Çok yakın';
    if (r > -75) return 'Yakın';
    if (r > -90) return 'Uzak';
    return 'Çok uzak';
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: conn.tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İsim değiştir'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Örn. Anahtarlık'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await tagManager.update(conn.tag.copyWith(name: name));
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (await confirmDelete(context, conn.tag.name) && context.mounted) {
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
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'İsim değiştir',
                onPressed: () => _rename(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Sil',
                onPressed: () => _delete(context),
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
                        'Cihaz uzakta olabilir. Yaklaşınca otomatik bağlanacak.'),
                    trailing: TextButton(
                      onPressed: c.dismissAlarm,
                      child: const Text('Sustur'),
                    ),
                  ),
                ),
              if (c.suspicious)
                Card(
                  color: Colors.orange.shade100,
                  child: const ListTile(
                    leading: Icon(Icons.gpp_maybe, color: Colors.orange),
                    title: Text('Şüpheli cihaz'),
                    subtitle: Text(
                        'Bu kimlikle bağlanan cihaz kayıtlı iTag gibi davranmıyor. '
                        'Taklit olabilir; bağlantı kesildi.'),
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
                        Expanded(
                          child: Text(c.statusText,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        if (c.trusted)
                          const Icon(Icons.verified_user,
                              size: 18, color: Colors.green),
                      ]),
                      const SizedBox(height: 8),
                      Text('Sinyal: ${c.rssi ?? '-'} dBm  (${_distanceHint(c.rssi)})'),
                      Text('Pil: ${c.battery != null ? '%${c.battery}' : 'bilinmiyor'}'),
                      if (c.tag.isItag)
                        Text('Düğmeye basılma: ${c.buttonPresses}'),
                      Text('Kimlik: ${c.tag.id}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Otomatik bağlan'),
                subtitle: const Text(
                    'Cihaz menzile girince kendiliğinden bağlanır; koparsa alarm çalar.'),
                value: c.tag.autoConnect,
                onChanged: (v) =>
                    tagManager.update(c.tag.copyWith(autoConnect: v)),
              ),
              const SizedBox(height: 8),
              if (c.isConnected)
                OutlinedButton.icon(
                  onPressed: c.disconnectManually,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Bağlantıyı kes'),
                )
              else
                OutlinedButton.icon(
                  onPressed:
                      c.isConnecting ? null : () => c.connectNow(manual: true),
                  icon: const Icon(Icons.link),
                  label: Text(c.isConnecting ? 'Bağlanıyor...' : 'Bağlan'),
                ),
              if (c.tag.isItag) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    backgroundColor: c.ringing ? Colors.red : null,
                  ),
                  onPressed: c.canRing ? () => c.setTagAlert(!c.ringing) : null,
                  icon: Icon(c.ringing ? Icons.volume_off : Icons.volume_up),
                  label: Text(c.ringing ? 'Sustur' : 'Etiketi Öttür'),
                ),
              ],
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
