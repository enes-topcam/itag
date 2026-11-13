import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models.dart';
import '../permissions.dart';
import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';

const appVersion = '1.0.0';

/// Sayfa 12 — Ayarlar
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  void _push(BuildContext context, Widget page) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          NavRow(
            icon: Icons.notifications_none,
            title: 'Bildirimler ve Uyarılar',
            onTap: () => _push(context, const AlertSettingsPage()),
          ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.bluetooth,
            title: 'Bluetooth / İzinler',
            onTap: () => _push(context, const PermissionSettingsPage()),
          ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.dark_mode_outlined,
            title: 'Tema',
            trailing: const Text('Koyu',
                style: TextStyle(color: AppColors.text2)),
            onTap: () =>
                showSnack(context, 'Şimdilik yalnızca koyu tema var.'),
          ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.language,
            title: 'Dil',
            trailing: const Text('Türkçe',
                style: TextStyle(color: AppColors.text2)),
            onTap: () => showSnack(context, 'İngilizce ileride eklenecek.'),
          ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.shield_outlined,
            title: 'Veri ve Gizlilik',
            onTap: () => _push(context, const PrivacyPage()),
          ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.info_outline,
            title: 'Hakkında',
            subtitle: 'Sürüm $appVersion',
            onTap: () => _push(context, const AboutPage()),
          ),
        ],
      ),
    );
  }
}

class AlertSettingsPage extends StatelessWidget {
  const AlertSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appSettings, tagManager]),
      builder: (context, _) {
        final conns = tagManager.connections;
        return Scaffold(
          appBar: AppBar(title: const Text('Bildirimler ve Uyarılar')),
          body: ListView(
            padding: pagePadding(context),
            children: [
              NavRow(
                icon: Icons.notifications_active_outlined,
                title: 'Kopma uyarıları',
                subtitle: 'Tüm cihazlar için ana anahtar',
                trailing: Switch(
                  value: appSettings.alertsEnabled,
                  onChanged: (v) => appSettings.set(alertsEnabled: v),
                ),
              ),
              const SizedBox(height: 10),
              NavRow(
                icon: Icons.volume_up_outlined,
                title: 'Ses',
                trailing: Switch(
                  value: appSettings.alertSound,
                  onChanged: (v) => appSettings.set(alertSound: v),
                ),
              ),
              const SizedBox(height: 10),
              NavRow(
                icon: Icons.vibration,
                title: 'Titreşim',
                trailing: Switch(
                  value: appSettings.alertVibrate,
                  onChanged: (v) => appSettings.set(alertVibrate: v),
                ),
              ),
              const SizedBox(height: 10),
              NavRow(
                icon: Icons.notifications_outlined,
                title: 'Bildirim',
                subtitle: 'Bağlantı koptuğunda sistem bildirimi de gönder',
                trailing: Switch(
                  value: appSettings.alertNotify,
                  onChanged: (v) => appSettings.set(alertNotify: v),
                ),
              ),
              if (conns.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Cihaz bazında kayıp modu',
                    style: TextStyle(color: AppColors.text2, fontSize: 13)),
                const SizedBox(height: 10),
                for (final c in conns) ...[
                  NavRow(
                    icon: iconFor(c.saved.iconKey),
                    title: c.saved.displayName,
                    trailing: Switch(
                      value: c.saved.alertOnDisconnect,
                      onChanged: (v) => tagManager
                          .update(c.saved.copyWith(alertOnDisconnect: v)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 12),
              const Text(
                'Uygulama cihaza yalnızca sen "Bağlan" dediğinde bağlanır. '
                'Kopma uyarıları sadece cihaz bağlıyken çalışır. Bildirim için '
                'Ayarlar > Bluetooth / İzinler bölümünden bildirim izni '
                'verilmelidir.',
                style: TextStyle(color: AppColors.text2, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PermissionSettingsPage extends StatefulWidget {
  const PermissionSettingsPage({super.key});

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage>
    with WidgetsBindingObserver {
  Map<String, bool> _status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await Perms.status();
    if (mounted) setState(() => _status = s);
  }

  Widget _permRow(String group, IconData icon, String title, String desc) {
    final ok = _status[group] == true;
    return NavRow(
      icon: icon,
      title: title,
      subtitle: desc,
      trailing: ok
          ? const Icon(Icons.check_circle, color: AppColors.ok)
          : !Perms.supported
              ? const Text('Yakında', style: TextStyle(color: AppColors.text2))
              : TextButton(
                  onPressed: () async {
                    final granted = await Perms.request(group);
                    if (!granted) await Perms.openSettings();
                    await _refresh();
                  },
                  child: const Text('İzin ver'),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tagManager,
      builder: (context, _) {
        final on = tagManager.adapterState == BluetoothAdapterState.on;
        return Scaffold(
          appBar: AppBar(title: const Text('Bluetooth / İzinler')),
          body: ListView(
            padding: pagePadding(context),
            children: [
              NavRow(
                icon: on ? Icons.bluetooth : Icons.bluetooth_disabled,
                color: on ? null : AppColors.err,
                title: 'Bluetooth',
                subtitle: on ? 'Açık' : 'Kapalı',
                trailing: on
                    ? const Icon(Icons.check_circle, color: AppColors.ok)
                    : TextButton(
                        onPressed: () async {
                          if (Platform.isAndroid) {
                            try {
                              await FlutterBluePlus.turnOn();
                            } catch (_) {}
                          }
                        },
                        child: const Text('Aç'),
                      ),
              ),
              const SizedBox(height: 24),
              const Text('Uygulama izinleri',
                  style: TextStyle(color: AppColors.text2, fontSize: 13)),
              const SizedBox(height: 10),
              _permRow('bluetooth', Icons.bluetooth_searching,
                  'Yakındaki cihazlar', 'Tarama ve bağlantı için gerekli'),
              const SizedBox(height: 10),
              _permRow('notification', Icons.notifications_none,
                  'Bildirimler', 'Kopma uyarısı için (isteğe bağlı)'),
              const SizedBox(height: 20),
              if (Perms.supported)
                OutlinedButton.icon(
                  onPressed: Perms.openSettings,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Uygulama ayarlarını aç'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Veri ve Gizlilik')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          const AppCard(
            child: Text(
              'Cihaz kayıtların (isim, simge, son bağlantı zamanı) yalnızca '
              'bu telefonda saklanır. Konum kaydedilmez. TPCM Find hiçbir veriyi bir sunucuya '
              'göndermez; hesap veya bulut yedekleme yoktur.',
              style: TextStyle(color: AppColors.text2, fontSize: 14, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          NavRow(
            icon: Icons.delete_sweep_outlined,
            color: AppColors.err,
            title: 'Cihaz kayıtlarını temizle',
            subtitle: 'Tüm kayıtlı cihazlar kaldırılır',
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Tüm kayıtları temizle'),
                  content: const Text(
                      'Tüm kayıtlı cihazlar bu telefondan kaldırılacak ve '
                      'bağlantıları kesilecek.',
                      style: TextStyle(color: AppColors.text2)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Vazgeç')),
                    TextButton(
                        style:
                            TextButton.styleFrom(foregroundColor: AppColors.err),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Temizle')),
                  ],
                ),
              );
              if (ok == true) {
                await tagManager.clearAll();
                if (context.mounted) showSnack(context, 'Kayıtlar temizlendi.');
              }
            },
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hakkında')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          const SizedBox(height: 24),
          const Center(child: AppLogo(size: 88)),
          const SizedBox(height: 20),
          Text('TPCM Find',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          const Text('Sürüm $appVersion',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2)),
          const SizedBox(height: 4),
          const Text('TPCM Studio',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text2)),
          const SizedBox(height: 32),
          const AppCard(
            child: Text(
              'Bluetooth takip cihazlarını keşfetmek, bağlanmak ve yönetmek için '
              'geliştirildi. Sinyal gücü yaklaşık bir yakınlık ipucudur; kesin '
              'mesafe ölçümü değildir.',
              style: TextStyle(color: AppColors.text2, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
