import 'package:flutter/material.dart';

import '../map_view.dart';
import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';
import 'settings_tab.dart';

/// Sayfa 08 — Harita: kayıtlı cihazların son görülen konumları.
class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final conns = tagManager.connections;
        final located =
            conns.where((c) => c.sighting?.hasLocation ?? false).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Harita'),
            actions: [
              IconButton(
                tooltip: 'Yenile',
                icon: const Icon(Icons.refresh),
                onPressed: tagManager.reloadSightings,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: tagManager.reloadSightings,
            child: ListView(
              padding: pagePadding(context, top: 4),
              children: [
                if (located.isNotEmpty)
                  TagMap(conns: located, height: 340)
                else
                  const _NoLocationCard(),
                const SizedBox(height: 16),
                for (final c in conns) ...[
                  SightingCard(
                    conn: c,
                    onTap: () => openDevice(context, c),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Gösterilen yer, telefonun cihazı en son duyduğu andaki '
                  'kendi konumudur; cihazın canlı konumu değildir.',
                  style: TextStyle(color: AppColors.text2, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDims.cardRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.map_outlined, size: 44, color: AppColors.accentLight),
          const SizedBox(height: 12),
          const Text('Henüz kaydedilmiş konum yok',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Telefon cihazını duyduğunda konum kaydedilir. Bunun için konum '
            'izni gerekir; uygulama kapalıyken de kaydedilmesi için '
            '"Her zaman izin ver" seçilmelidir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text2, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LocationSettingsPage())),
            child: const Text('Konum ayarları'),
          ),
        ],
      ),
    );
  }
}
