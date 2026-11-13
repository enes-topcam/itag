import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'background.dart';
import 'tag_connection.dart';
import 'theme.dart';
import 'widgets.dart';

/// Cihazların son görülen konumlarını gösteren koyu temalı harita.
///
/// Altlık: OpenStreetMap'in kendi karoları (anahtarsız; atıf ve User-Agent
/// zorunlu, yoğun kullanım için uygun değil). Koyu tema için renkler ters
/// çevrilir. (CARTO 2026'da anahtar istemeye başladı — "API KEY REQUIRED".)
class TagMap extends StatelessWidget {
  const TagMap({super.key, required this.conns, this.height = 320});

  /// Konumu olan cihazlar (sighting.hasLocation == true).
  final List<TagConnection> conns;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final c in conns) LatLng(c.sighting!.lat!, c.sighting!.lng!),
    ];
    final fit = CameraFit.coordinates(
      coordinates: points,
      maxZoom: 16,
      padding: const EdgeInsets.all(60),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDims.cardRadius),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: fit,
            backgroundColor: AppColors.card,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              // OSM kullanım politikası: uygulamayı tanıtan User-Agent zorunlu.
              userAgentPackageName: 'com.itagtracker.itag_app',
              maxNativeZoom: 19,
              // OSM karoları açık renkli; koyu temaya uydurmak için renkleri
              // ters çevir.
              tileBuilder: darkModeTileBuilder,
            ),
            // Konumun yaklaşık hassasiyeti (ağ konumu ~20-100 m).
            CircleLayer(
              circles: [
                for (final c in conns)
                  if ((c.sighting!.accuracy ?? 0) > 0)
                    CircleMarker(
                      point: LatLng(c.sighting!.lat!, c.sighting!.lng!),
                      radius: c.sighting!.accuracy!,
                      useRadiusInMeter: true,
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderColor: AppColors.accent.withValues(alpha: 0.5),
                      borderStrokeWidth: 1,
                    ),
              ],
            ),
            MarkerLayer(
              markers: [
                for (final c in conns)
                  Marker(
                    point: LatLng(c.sighting!.lat!, c.sighting!.lng!),
                    width: 48,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: _Pin(iconKey: c.saved.iconKey),
                  ),
              ],
            ),
            // OSM lisansı gereği atıf (sade, koyu temaya uygun).
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('© OpenStreetMap katkıcıları',
                    style: TextStyle(fontSize: 10, color: AppColors.text2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.iconKey});
  final String iconKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8),
            ],
          ),
          child: Icon(iconFor(iconKey), color: Colors.white, size: 22),
        ),
        Container(width: 3, height: 10, color: Colors.white),
      ],
    );
  }
}

/// Son görülme bilgisi + yol tarifi kartı.
class SightingCard extends StatelessWidget {
  const SightingCard({super.key, required this.conn, this.onTap});
  final TagConnection conn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = conn.sighting;
    final hasLoc = s?.hasLocation ?? false;
    String detail;
    if (s == null) {
      detail = 'Bu cihaz için konum kaydı yok';
    } else if (!hasLoc) {
      detail = 'Son duyulma: ${relativeTime(s.seenAt)} · konum alınamadı';
    } else {
      detail = 'Son görüldü: ${relativeTime(s.seenAt)}';
      final acc = s.accuracy;
      if (acc != null && acc > 0) detail += ' · ~${acc.round()} m';
    }
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DeviceAvatar(conn.saved.iconKey, size: 42, active: hasLoc),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conn.saved.displayName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: const TextStyle(
                            color: AppColors.text2, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (hasLoc) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 54),
              child: Text(
                'Konum kaydı: ${formatDate(s!.locatedAt)} · telefonun konumu',
                style: const TextStyle(color: AppColors.text2, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.raised,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                final ok = await Background.openMap(
                    s.lat!, s.lng!, conn.saved.displayName);
                if (!ok && context.mounted) {
                  showSnack(context, 'Harita uygulaması açılamadı.');
                }
              },
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('Konuma Yol Tarifi'),
            ),
          ],
        ],
      ),
    );
  }
}
