import 'package:flutter/material.dart';

import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connect_flow.dart';

/// Sayfa 07 — Cihaz Detayı
class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key, required this.conn});
  final TagConnection conn;

  Future<void> _remove(BuildContext context) async {
    if (await confirmRemove(context) && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      await tagManager.remove(conn.saved.id);
    }
  }

  void _push(BuildContext context, Widget page) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => page));

  Future<void> _calibrate(BuildContext context, TagConnection c) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesafe kalibrasyonu'),
        content: const Text(
          'Telefonu cihazdan yaklaşık 1 metre uzağa koy (arada engel olmasın) '
          've Başlat\'a bas. 5 saniye boyunca telefonu ve cihazı oynatma.',
          style: TextStyle(color: AppColors.text2),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );
    if (go != true) return;
    final m = await c.calibrate();
    if (!context.mounted) return;
    showSnack(
        context,
        m == null
            ? 'Ölçülemedi; cihazın bağlı olduğundan emin ol.'
            : 'Kalibre edildi (1 m = $m dBm).');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        final c = conn;
        final s = c.saved;
        final (statusText, statusColor) = statusOf(c);
        return Scaffold(
          appBar: AppBar(
            title: Text(s.displayName),
            actions: [
              IconButton(
                tooltip: 'Cihazı düzenle',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _push(context, EditDeviceScreen(conn: c)),
              ),
            ],
          ),
          body: ListView(
            padding: pagePadding(context, top: 8),
            children: [
              Center(
                child: s.isItag
                    ? TagIllustration(size: 104, glow: c.isConnected)
                    : DeviceAvatar(s.iconKey, size: 104, active: c.isConnected),
              ),
              const SizedBox(height: 18),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconFor(s.iconKey),
                        color: AppColors.accentLight, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(s.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Center(child: StatusLabel(statusText, statusColor)),
              if (!c.isConnected && c.lastSeen != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Son görülme: ${relativeTime(c.lastSeen)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.text2, fontSize: 13)),
                ),
              const SizedBox(height: 20),
              if (c.suspicious) ...[
                const _Notice(
                  color: AppColors.warn,
                  icon: Icons.gpp_maybe_outlined,
                  title: 'Şüpheli cihaz',
                  text: 'Bu kimlikle bağlanan cihaz kayıtlı takip cihazın '
                      'gibi davranmıyor; taklit olabilir. Bağlantı kesildi.',
                ),
                const SizedBox(height: AppDims.gap),
              ],
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Uzaklık',
                      value: c.isConnected ? distanceLabel(c.distanceM) : '—',
                      trailing: c.isConnected ? SignalBars(c.rssi) : null,
                    ),
                  ),
                  const SizedBox(width: AppDims.gap),
                  Expanded(
                    child: _StatTile(
                      label: 'Pil',
                      value: c.battery != null
                          ? '%${c.battery}'
                          : (c.isConnected && !c.batterySupported
                              ? 'Desteklenmiyor'
                              : 'Bilinmiyor'),
                      trailing: c.battery != null
                          ? const Icon(Icons.battery_std,
                              color: AppColors.ok, size: 20)
                          : null,
                    ),
                  ),
                ],
              ),
              if (c.isConnected)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.isCalibrated
                              ? 'Tahmini; duvar ve cep sapma yaratabilir.'
                              : 'Tahmini. Daha isabetli olması için kalibre et.',
                          style: const TextStyle(
                              color: AppColors.text2, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: c.calibrating
                            ? null
                            : () => _calibrate(context, c),
                        child: Text(c.calibrating
                            ? 'Ölçülüyor…'
                            : (c.isCalibrated
                                ? 'Yeniden kalibre et'
                                : 'Kalibre et')),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              ..._mainAction(context, c),
              const SizedBox(height: 16),
              NavRow(
                icon: Icons.info_outline,
                title: 'Cihaz Bilgileri',
                onTap: () => _push(context, DeviceInfoScreen(conn: c)),
              ),
              if (c.isConnected) ...[
                const SizedBox(height: 10),
                NavRow(
                  icon: Icons.link_off,
                  title: 'Bağlantıyı Kes',
                  subtitle: s.isItag
                      ? 'Kesince etiket öter; susturmak için üzerindeki '
                          'tuşa bir kez bas.'
                      : 'Bağlantıyı kapatır',
                  onTap: c.disconnectManually,
                  trailing: const SizedBox.shrink(),
                ),
              ],
              const SizedBox(height: 24),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.err,
                  side: BorderSide(color: AppColors.err.withValues(alpha: 0.4)),
                  backgroundColor: AppColors.err.withValues(alpha: 0.08),
                ),
                onPressed: () => _remove(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Cihazı Kaldır'),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _mainAction(BuildContext context, TagConnection c) {
    if (!c.isConnected) {
      if (c.isBusy) {
        // Arama/bağlanma sürüyor: ne olduğunu göster, iptal edilebilsin.
        return [
          AppCard(
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.isSearching ? 'Cihaz aranıyor…' : 'Bağlanılıyor…',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.isSearching
                            ? '30 sn boyunca aranır. Bulamazsa biraz yürüyüp '
                                'tekrar dene.'
                            : 'Cihazla iletişim kuruluyor',
                        style: const TextStyle(
                            color: AppColors.text2, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: c.cancelConnect,
            child: const Text('İptal Et'),
          ),
        ];
      }
      return [
        FilledButton.icon(
          onPressed: c.connectNow,
          icon: const Icon(Icons.link),
          label: const Text('Bağlan'),
        ),
        if (c.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(c.lastError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.err, fontSize: 13)),
          )
        else if (c.saved.isItag)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Ses çaldırmak için önce bağlan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
          ),
      ];
    }
    if (!c.saved.isItag) {
      return const [
        Text('Ses çaldırma bu cihazda kullanılamıyor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.text2, fontSize: 14)),
      ];
    }
    return [
      FilledButton.icon(
        style: c.ringing
            ? FilledButton.styleFrom(backgroundColor: AppColors.err)
            : null,
        onPressed: c.canRing
            ? () async {
                await c.setTagAlert(!c.ringing);
                if (context.mounted && c.ringing) {
                  showSnack(context, 'Ses komutu gönderildi (30 sn çalar)');
                }
              }
            : null,
        icon: Icon(c.ringing ? Icons.volume_off : Icons.volume_up),
        label: Text(c.canRing
            ? (c.ringing ? 'Sesi Durdur' : 'Ses Çaldır')
            : 'Hazırlanıyor…'),
      ),
    ];
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            ?trailing,
          ]),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppDims.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text,
                    style:
                        const TextStyle(color: AppColors.text2, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sayfa 10 — Cihazı Düzenle
class EditDeviceScreen extends StatelessWidget {
  const EditDeviceScreen({super.key, required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihazı Düzenle')),
      body: DeviceForm(
        initialName: conn.saved.displayName,
        initialIcon: conn.saved.iconKey,
        onSave: (name, icon) async {
          await tagManager
              .update(conn.saved.copyWith(displayName: name, iconKey: icon));
          if (context.mounted) Navigator.of(context).pop();
        },
        footer: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.err),
          onPressed: () async {
            if (await confirmRemove(context) && context.mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await tagManager.remove(conn.saved.id);
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Cihazı Kaldır'),
        ),
      ),
    );
  }
}

/// Sayfa 11 — Cihaz Bilgileri
class DeviceInfoScreen extends StatelessWidget {
  const DeviceInfoScreen({super.key, required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        final c = conn;
        final s = c.saved;
        final (statusText, _) = statusOf(c);
        final features = <(String, bool?)>[
          ('Ses', s.isItag),
          ('Pil', c.isConnected ? c.batterySupported : null),
          ('Sinyal', true),
          ('Düğme uyarısı', s.isItag),
        ];
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(k,
                        style: const TextStyle(
                            color: AppColors.text2, fontSize: 14)),
                  ),
                  Expanded(
                    child: Text(v,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Cihaz Bilgileri')),
          body: ListView(
            padding: pagePadding(context),
            children: [
              AppCard(
                child: Column(children: [
                  row('Kullanıcı adı', s.displayName),
                  row('Cihazın bildirdiği ad', s.advertisedName ?? 'Bilinmiyor'),
                  row('Cihaz türü', s.isItag ? 'BLE · Takip cihazı' : 'BLE · Genel cihaz'),
                  row('Bağlantı durumu', statusText),
                  row('Son bağlanma', formatDate(s.lastConnectedAt)),
                  row('İlk eklenme', formatDate(s.firstConnectedAt)),
                  row('Son görülme', c.isConnected ? 'Şu an' : formatDate(c.lastSeen)),
                  row('Firmware', 'Bilinmiyor'),
                ]),
              ),
              const SizedBox(height: 16),
              const Text('Desteklenen işlevler',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, ok) in features)
                    Chip(
                      avatar: Icon(
                        ok == null
                            ? Icons.help_outline
                            : (ok ? Icons.check_circle : Icons.cancel),
                        size: 18,
                        color: ok == null
                            ? AppColors.text2
                            : (ok ? AppColors.ok : AppColors.err),
                      ),
                      label: Text(name),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text('Teknik ayrıntılar',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Platform kimliği',
                          style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      SelectableText(s.id,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                      const SizedBox(height: 12),
                      const Text('BLE servisleri (GATT)',
                          style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      const SizedBox(height: 4),
                      if (c.gattLines.isEmpty)
                        const Text('Servis bilgisi için cihaza bağlan.',
                            style: TextStyle(fontSize: 13))
                      else
                        for (final l in c.gattLines)
                          Text(l,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                      const SizedBox(height: 12),
                      const Text('Bağlantı kaydı',
                          style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      const SizedBox(height: 4),
                      if (c.log.isEmpty)
                        const Text('Kayıt yok.', style: TextStyle(fontSize: 13))
                      else
                        for (final l in c.log.take(40))
                          Text(l, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
