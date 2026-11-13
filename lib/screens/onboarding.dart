import 'package:flutter/material.dart';

import '../models.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';

/// Sayfa 01 — Açılış / Karşılama
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, Color(0xFF1B1640)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDims.pad),
            child: Column(
              children: [
                const Spacer(flex: 2),
                const AppLogo(size: 104),
                const SizedBox(height: 32),
                Text('TPCM Find',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 32)),
                const SizedBox(height: 8),
                const Text('Eşyalarını kolayca bul',
                    style: TextStyle(color: AppColors.text2, fontSize: 16)),
                const Spacer(flex: 2),
                const TagIllustration(size: 120, glow: true),
                const Spacer(flex: 2),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PermissionsScreen()),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Başlayalım'),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sayfa 02 — İzinler ve ilk kurulum
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<String, bool> _status = {};
  final Set<String> _denied = {};

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
    // Kullanıcı Ayarlar'dan izin verip geri dönmüş olabilir.
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await Perms.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _request(String group) async {
    final ok = await Perms.request(group);
    if (!ok) _denied.add(group);
    await _refresh();
  }

  Future<void> _finish() async {
    await appSettings.set(onboarded: true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final btOk = _status['bluetooth'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Kurulum')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDims.pad),
          children: [
            Text('Cihazlarını bulmaya\nhazır mısın?',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            const Text(
              'TPCM Find aşağıdaki izinleri yalnızca belirtilen özellikler için '
              'kullanır. İstediğin zaman Ayarlar\'dan değiştirebilirsin.',
              style: TextStyle(color: AppColors.text2, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _PermCard(
              icon: Icons.bluetooth,
              title: 'Yakındaki cihazlar',
              desc: 'Takip cihazlarını taramak ve bağlanmak için gerekli.',
              required: true,
              granted: btOk,
              denied: _denied.contains('bluetooth'),
              onRequest: () => _request('bluetooth'),
            ),
            const SizedBox(height: AppDims.gap),
            _PermCard(
              icon: Icons.location_on_outlined,
              title: 'Konum',
              desc: 'Cihazı en son gördüğün yeri kaydetmek için. '
                  'Cihazın kendisinde GPS yoktur.',
              granted: _status['location'] == true,
              denied: _denied.contains('location'),
              unsupported: !Perms.supported,
              onRequest: () => _request('location'),
            ),
            const SizedBox(height: AppDims.gap),
            _PermCard(
              icon: Icons.notifications_none,
              title: 'Bildirimler',
              desc: 'Bağlantı koptuğunda seni uyarabilmek için.',
              granted: _status['notification'] == true,
              denied: _denied.contains('notification'),
              unsupported: !Perms.supported,
              onRequest: () => _request('notification'),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _finish,
              child: const Text('Devam Et'),
            ),
            if (!btOk) ...[
              const SizedBox(height: 10),
              const Text(
                'Bluetooth izni olmadan cihaz taranamaz. İzni daha sonra '
                'Ayarlar > Bluetooth / İzinler bölümünden verebilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text2, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  const _PermCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
    required this.denied,
    required this.onRequest,
    this.required = false,
    this.unsupported = false,
  });
  final IconData icon;
  final String title;
  final String desc;
  final bool granted;
  final bool denied;
  final bool required;
  final bool unsupported;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    Widget action;
    if (granted) {
      action = const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: AppColors.ok, size: 18),
        SizedBox(width: 4),
        Text('Verildi', style: TextStyle(color: AppColors.ok)),
      ]);
    } else if (unsupported) {
      action = const Text('Yakında',
          style: TextStyle(color: AppColors.text2, fontSize: 13));
    } else if (denied) {
      action = TextButton(
          onPressed: Perms.openSettings, child: const Text('Ayarlar'));
    } else {
      action = TextButton(onPressed: onRequest, child: const Text('İzin ver'));
    }

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.accentLight),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text(required ? 'Gerekli' : 'İsteğe bağlı',
                      style: TextStyle(
                          fontSize: 11,
                          color: required ? AppColors.warn : AppColors.text2)),
                ]),
                const SizedBox(height: 4),
                Text(desc,
                    style:
                        const TextStyle(color: AppColors.text2, fontSize: 13)),
                if (denied && !granted)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'İzin reddedildi. Ayarlar\'dan açabilirsin.',
                      style: TextStyle(color: AppColors.err, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          action,
        ],
      ),
    );
  }
}
