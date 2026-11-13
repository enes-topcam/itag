import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';

/// Sayfa 03 — Cihazlarım (ana ekran)
class DevicesTab extends StatelessWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final conns = tagManager.connections;
        return Scaffold(
          body: SafeArea(
            child: !tagManager.loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppDims.pad, 12, AppDims.pad, AppDims.pad),
                    children: [
                      _Header(count: conns.length),
                      const SizedBox(height: 16),
                      _Segment(count: conns.length),
                      const SizedBox(height: 16),
                      if (tagManager.adapterState ==
                          BluetoothAdapterState.off) ...[
                        BluetoothOffBanner(onTurnOn: () async {
                          try {
                            await FlutterBluePlus.turnOn();
                          } catch (_) {}
                        }),
                      ],
                      if (conns.isEmpty)
                        const SizedBox(
                          height: 360,
                          child: EmptyState(
                            icon: Icons.sell_outlined,
                            title: 'Henüz cihaz eklemedin.',
                            message:
                                'Yakındaki takip cihazını bulup bağlan; bağlandığın '
                                'cihazlar burada listelenir.',
                          ),
                        )
                      else
                        for (final c in conns) ...[
                          _DeviceCard(conn: c),
                          const SizedBox(height: AppDims.gap),
                        ],
                      _AddCard(),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cihazlarım',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text('$count kayıtlı cihaz',
                  style: const TextStyle(color: AppColors.text2, fontSize: 14)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cihaz ekle',
          icon: const Icon(Icons.add),
          onPressed: () => homeTab.value = 1,
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool selected, VoidCallback? onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.text2)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        seg('Cihazlarım ($count)', true, null),
        seg('Tüm Cihazlar', false, () => homeTab.value = 1),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    final c = conn;
    final (statusText, statusColor) = statusOf(c);
    final String detail;
    if (c.isConnected) {
      detail = 'Sinyal: ${signalLabel(c.rssi)}';
    } else if (c.lastSeen != null) {
      detail = 'Son görülme: ${relativeTime(c.lastSeen)}';
    } else {
      detail = 'Bağlı değil';
    }

    return AppCard(
      onTap: () => openDevice(context, c),
      child: Row(
        children: [
          DeviceAvatar(c.saved.iconKey, active: c.isConnected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.saved.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                StatusLabel(statusText, statusColor),
                const SizedBox(height: 2),
                Text(detail,
                    style:
                        const TextStyle(color: AppColors.text2, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (c.battery != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.battery_std,
                      size: 16, color: AppColors.ok),
                  Text(' %${c.battery}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.text2)),
                ]),
              const SizedBox(height: 6),
              if (c.isConnected) SignalBars(c.rssi),
            ],
          ),
          // Hızlı eylem: yalnızca bağlı ve ses doğrulanmışsa (doküman §6).
          if (c.canRing)
            IconButton(
              tooltip: c.ringing ? 'Sesi durdur' : 'Ses çal',
              icon: Icon(c.ringing ? Icons.volume_off : Icons.volume_up,
                  color: c.ringing ? AppColors.err : AppColors.accentLight),
              onPressed: () => c.setTagAlert(!c.ringing),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.chevron_right, color: AppColors.text2),
            ),
        ],
      ),
    );
  }
}

class _AddCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => homeTab.value = 1,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.raised,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.add, color: AppColors.accentLight),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yeni Cihaz Ekle',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('Yakındaki cihazları tara ve ekle',
                    style: TextStyle(color: AppColors.text2, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
