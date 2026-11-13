import 'package:flutter/material.dart';

import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';

/// Sayfa 08 — Harita. Son görülen konum kaydı V1.1'de eklenecek; o zamana
/// kadar kayıtlı cihazları ve "konum kaydı yok" durumunu gösterir.
class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final conns = tagManager.connections;
        return Scaffold(
          appBar: AppBar(title: const Text('Harita')),
          body: ListView(
            padding: pagePadding(context),
            children: [
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppDims.cardRadius),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 44, color: AppColors.accentLight),
                        SizedBox(height: 12),
                        Text('Henüz kaydedilmiş konum yok',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 6),
                        Text(
                          'Son görülen konum bir sonraki sürümde gelecek. '
                          'Konum, telefonun cihazı en son gördüğü yerdir; '
                          'cihazın canlı konumu değildir.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: AppColors.text2, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (conns.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Cihazlar',
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                ),
              for (final c in conns) ...[
                AppCard(
                  onTap: () => openDevice(context, c),
                  child: Row(
                    children: [
                      DeviceAvatar(c.saved.iconKey,
                          size: 42, active: c.isConnected),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.saved.displayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              c.isConnected
                                  ? 'Şu an bağlı'
                                  : 'Bu cihaz için konum kaydı yok',
                              style: const TextStyle(
                                  color: AppColors.text2, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.text2),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}
