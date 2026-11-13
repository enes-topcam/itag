import 'package:flutter/material.dart';

import '../models.dart';
import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connect_flow.dart';
import 'settings_tab.dart';

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
              if (!c.isConnected && s.lastSeenAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Son görülme: ${relativeTime(s.lastSeenAt)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.text2, fontSize: 13)),
                ),
              const SizedBox(height: 20),
              if (c.lostAlarm) ...[
                _Notice(
                  color: AppColors.err,
                  icon: Icons.warning_amber_rounded,
                  title: 'Bağlantı kesildi',
                  text: 'Cihaz uzakta olabilir. Menzile girince otomatik '
                      'bağlanılır.',
                  action: TextButton(
                      onPressed: c.dismissAlarm,
                      child: const Text('Uyarıyı sustur')),
                ),
                const SizedBox(height: AppDims.gap),
              ],
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
                      label: 'Sinyal',
                      value: c.isConnected ? signalLabel(c.rssi) : '—',
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
              const SizedBox(height: 16),
              ..._mainAction(context, c),
              const SizedBox(height: 16),
              NavRow(
                icon: Icons.location_on_outlined,
                title: 'Son Görülen Konum',
                onTap: () => _push(context, LastLocationScreen(conn: c)),
              ),
              const SizedBox(height: 10),
              NavRow(
                icon: Icons.notifications_none,
                title: 'Kayıp Modu',
                subtitle: 'Bağlantı kesilince uyar',
                onTap: () => _push(context, LostModeScreen(conn: c)),
                trailing: Switch(
                  value: s.alertOnDisconnect,
                  onChanged: (v) => tagManager
                      .update(s.copyWith(alertOnDisconnect: v)),
                ),
              ),
              const SizedBox(height: 10),
              NavRow(
                icon: Icons.autorenew,
                title: 'Otomatik Bağlan',
                subtitle: 'Menzile girince kendiliğinden bağlan',
                trailing: Switch(
                  value: s.autoConnect,
                  onChanged: (v) =>
                      tagManager.update(s.copyWith(autoConnect: v)),
                ),
              ),
              const SizedBox(height: 10),
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
                  subtitle: 'Uyarı vermeden bağlantıyı kapatır',
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
      return [
        FilledButton.icon(
          onPressed: c.isConnecting ? null : () => c.connectNow(manual: true),
          icon: c.isConnecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.text2))
              : const Icon(Icons.link),
          label: Text(c.isConnecting ? 'Bağlanıyor…' : 'Yeniden Bağlan'),
        ),
        if (c.saved.isItag)
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
    this.action,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

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
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sayfa 09 — Kayıp Modu / Kopma Uyarıları
class LostModeScreen extends StatelessWidget {
  const LostModeScreen({super.key, required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([conn, appSettings]),
      builder: (context, _) {
        final s = conn.saved;
        return Scaffold(
          appBar: AppBar(title: const Text('Kayıp Modu')),
          body: ListView(
            padding: pagePadding(context),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 30),
                    ],
                  ),
                  child: const Icon(Icons.notifications_active_outlined,
                      size: 40, color: AppColors.accentLight),
                ),
              ),
              const SizedBox(height: 18),
              Text('Bağlantı Uyarıları',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text('${s.displayName} ile bağlantı kesildiğinde seni uyarır.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text2)),
              const SizedBox(height: 24),
              NavRow(
                icon: Icons.notifications_none,
                title: 'Bağlantı kesilince uyar',
                trailing: Switch(
                  value: s.alertOnDisconnect,
                  onChanged: (v) =>
                      tagManager.update(s.copyWith(alertOnDisconnect: v)),
                ),
              ),
              if (!appSettings.alertsEnabled) ...[
                const SizedBox(height: 10),
                NavRow(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.warn,
                  title: 'Uyarılar genel olarak kapalı',
                  subtitle: 'Ayarlar > Bildirimler ve Uyarılar',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AlertSettingsPage())),
                ),
              ],
              const SizedBox(height: 20),
              const Text('Uyarı yöntemi',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Ses'),
                    selected: appSettings.alertSound,
                    onSelected: (v) => appSettings.set(alertSound: v),
                  ),
                  FilterChip(
                    label: const Text('Titreşim'),
                    selected: appSettings.alertVibrate,
                    onSelected: (v) => appSettings.set(alertVibrate: v),
                  ),
                  FilterChip(
                    label: const Text('Bildirim'),
                    selected: appSettings.alertNotify,
                    onSelected: (v) => appSettings.set(alertNotify: v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Uyarı yöntemi tüm cihazlar için geçerlidir.',
                  style: TextStyle(color: AppColors.text2, fontSize: 12)),
              const SizedBox(height: 20),
              AppCard(
                child: Row(children: [
                  const Text('Son uyarı',
                      style: TextStyle(color: AppColors.text2)),
                  const Spacer(),
                  Text(s.lastAlertAt == null
                      ? 'Henüz yok'
                      : formatDate(s.lastAlertAt)),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(AppDims.cardRadius),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.accentLight, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Uygulama kapalıyken uyarı bildirim olarak gelir '
                        '(Ayarlar\'da "Arka planda bağlı kal" açık olmalı). '
                        'Bluetooth arka plan kısıtları nedeniyle uyarılar '
                        'gecikebilir. Bağlantıyı kendin keserken uyarı verilmez.',
                        style: TextStyle(color: AppColors.text2, fontSize: 13),
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
                  row('Son görülme', c.isConnected ? 'Şu an' : formatDate(s.lastSeenAt)),
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

/// Sayfa 08 (cihaz) — Son Görülen Konum. Konum kaydı V1.1'de gelecek.
class LastLocationScreen extends StatelessWidget {
  const LastLocationScreen({super.key, required this.conn});
  final TagConnection conn;

  @override
  Widget build(BuildContext context) {
    final s = conn.saved;
    return Scaffold(
      appBar: AppBar(title: const Text('Son Görülen Konum')),
      body: s.lastLatitude == null
          ? EmptyState(
              icon: Icons.location_off_outlined,
              title: 'Bu cihazın kaydedilmiş son konumu yok.',
              message: 'Son görülen konum özelliği bir sonraki sürümde '
                  'gelecek. Bağlantı koptuğunda, izin verirsen telefonun o '
                  'anki konumu kaydedilecek; bu cihazın canlı konumu değildir.',
              actionLabel: 'Geri Dön',
              onAction: () => Navigator.of(context).pop(),
            )
          : const SizedBox.shrink(),
    );
  }
}
