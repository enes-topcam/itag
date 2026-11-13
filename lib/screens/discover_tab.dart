import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connect_flow.dart';
import 'home_shell.dart';

/// Sayfa 04 — Keşfet / Bluetooth (BLE) cihazları
class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key, required this.active});
  final bool active;

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  final Map<String, ScanResult> _seen = {};
  final _search = TextEditingController();
  bool _scanning = false;
  bool _scannedOnce = false;
  bool _showUnnamed = false;
  String? _error;
  late final StreamSubscription _scanSub;
  late final StreamSubscription _scanningSub;

  @override
  void initState() {
    super.initState();
    // Sadece kullanıcının başlattığı taramanın sonuçları (otomatik bağlanma
    // taramaları listeyi bozmasın).
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!_scanning) return;
      for (final r in results) {
        _seen[r.device.remoteId.str] = r;
      }
      if (mounted) setState(() {});
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (!s && _scanning) {
        _scanning = false;
        tagManager.resumeSearch();
        if (mounted) setState(() {});
      }
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(DiscoverTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !_scanning) _startScan();
    if (!widget.active && old.active && _scanning) FlutterBluePlus.stopScan();
  }

  @override
  void dispose() {
    _scanSub.cancel();
    _scanningSub.cancel();
    _search.dispose();
    super.dispose();
  }

  static String nameOf(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  static bool looksLikeTag(ScanResult r) {
    final n = nameOf(r).toLowerCase();
    return n.contains('tag') ||
        n.contains('anti') ||
        r.advertisementData.serviceUuids.contains(ItagUuids.buttonService);
  }

  Future<void> _turnOn() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {}
    } else {
      showSnack(context, "Bluetooth'u Denetim Merkezi'nden açabilirsin.");
    }
  }

  Future<void> _startScan() async {
    if (tagManager.adapterState == BluetoothAdapterState.off) return;
    await tagManager.pauseSearch();
    setState(() {
      _seen.clear();
      _scanning = true;
      _scannedOnce = true;
      _error = null;
    });
    try {
      // Sonsuz tarama yerine zaman sınırlı oturum (doküman §7).
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      _scanning = false;
      tagManager.resumeSearch();
      setState(() => _error = 'Tarama başlatılamadı. İzinleri kontrol et.');
    }
  }

  Future<void> _open(ScanResult r) async {
    final id = r.device.remoteId.str;
    final saved = tagManager.get(id);
    if (saved != null) {
      openDevice(context, saved);
      return;
    }
    await FlutterBluePlus.stopScan();
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConnectScreen(
        device: r.device,
        advertisedName: nameOf(r),
        looksLikeTag: looksLikeTag(r),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final all = _seen.values.toList();
    final hiddenUnnamed =
        _showUnnamed ? 0 : all.where((r) => nameOf(r).isEmpty).length;
    final list = all
        .where((r) => _showUnnamed || nameOf(r).isNotEmpty)
        .where((r) => q.isEmpty || nameOf(r).toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        int rank(ScanResult r) => looksLikeTag(r) ? 0 : 1;
        final d = rank(a) - rank(b);
        return d != 0 ? d : b.rssi - a.rssi;
      });

    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final btOff = tagManager.adapterState == BluetoothAdapterState.off;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth Cihazları'),
            actions: [
              IconButton(
                tooltip: _scanning ? 'Durdur' : 'Yeniden tara',
                icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.refresh),
                onPressed: btOff
                    ? null
                    : (_scanning ? FlutterBluePlus.stopScan : _startScan),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppDims.pad, 4, AppDims.pad, 10),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Cihaz ara…',
                    prefixIcon: Icon(Icons.search, color: AppColors.text2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppDims.pad),
                child: Row(
                  children: [
                    if (_scanning) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      const Text('Tarama devam ediyor…',
                          style: TextStyle(
                              color: AppColors.accentLight, fontSize: 13)),
                    ] else
                      Text(
                        _scannedOnce ? '${list.length} cihaz bulundu' : '',
                        style: const TextStyle(
                            color: AppColors.text2, fontSize: 13),
                      ),
                    const Spacer(),
                    FilterChip(
                      label: Text(_showUnnamed
                          ? 'İsimsizler gösteriliyor'
                          : 'İsimsizler ($hiddenUnnamed)'),
                      selected: _showUnnamed,
                      showCheckmark: false,
                      onSelected: (v) => setState(() => _showUnnamed = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (btOff) BluetoothOffBanner(onTurnOn: _turnOn),
              Expanded(child: _body(list, btOff)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(List<ScanResult> list, bool btOff) {
    if (btOff) {
      return const EmptyState(
        icon: Icons.bluetooth_disabled,
        title: 'Bluetooth kapalı',
        message: "Cihazları taramak için Bluetooth'u aç.",
      );
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Tarama hatası',
        message: _error,
        actionLabel: 'Yeniden Tara',
        onAction: _startScan,
      );
    }
    if (list.isEmpty) {
      if (_scanning) {
        return const EmptyState(
          icon: Icons.bluetooth_searching,
          title: 'Bluetooth cihazları taranıyor…',
          message: 'Takip cihazını uyandırmak için düğmesine bir kez bas.',
        );
      }
      return EmptyState(
        icon: Icons.bluetooth_searching,
        title: _scannedOnce
            ? 'Yakında cihaz bulunamadı.'
            : 'Yakındaki cihazları bul',
        message: 'Takip cihazını uyandırmak için düğmesine bir kez bas.',
        actionLabel: _scannedOnce ? 'Yeniden Tara' : 'Taramayı Başlat',
        onAction: _startScan,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppDims.pad, 0, AppDims.pad, 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ResultCard(
        result: list[i],
        name: nameOf(list[i]),
        isTag: looksLikeTag(list[i]),
        saved: tagManager.isSaved(list[i].device.remoteId.str),
        onTap: () => _open(list[i]),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.name,
    required this.isTag,
    required this.saved,
    required this.onTap,
  });
  final ScanResult result;
  final String name;
  final bool isTag;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.raised,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(isTag ? Icons.sell_outlined : Icons.bluetooth,
                color: isTag ? AppColors.accentLight : AppColors.text2),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name.isEmpty ? 'İsimsiz cihaz' : name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (saved) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Kayıtlı',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.accentLight)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text('BLE · Sinyal ${signalLabel(result.rssi).toLowerCase()}',
                      style: const TextStyle(
                          color: AppColors.text2, fontSize: 13)),
                  const SizedBox(width: 6),
                  SignalBars(result.rssi, height: 11),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          saved
              ? const Icon(Icons.chevron_right, color: AppColors.text2)
              : FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onTap,
                  child: const Text('Bağlan'),
                ),
        ],
      ),
    );
  }
}
