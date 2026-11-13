import 'package:flutter/material.dart';

import 'tag_connection.dart';
import 'theme.dart';

/// Kullanıcının seçebileceği cihaz simgeleri (doküman §9).
const deviceIcons = <String, IconData>{
  'key': Icons.key_outlined,
  'bag': Icons.shopping_bag_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'car': Icons.directions_car_outlined,
  'pet': Icons.pets_outlined,
  'bike': Icons.pedal_bike_outlined,
  'luggage': Icons.luggage_outlined,
  'star': Icons.star_outline,
};

IconData iconFor(String key) => deviceIcons[key] ?? Icons.sell_outlined;

/// RSSI → nitel sinyal etiketi. Kesin mesafe değil, yaklaşık ipucu (doküman §1).
String signalLabel(int? rssi) {
  if (rssi == null) return 'Bilinmiyor';
  if (rssi > -65) return 'İyi';
  if (rssi > -80) return 'Orta';
  return 'Zayıf';
}

Color signalColor(int? rssi) {
  if (rssi == null) return AppColors.text2;
  if (rssi > -65) return AppColors.ok;
  if (rssi > -80) return AppColors.warn;
  return AppColors.err;
}

String proximityLabel(int? rssi) {
  if (rssi == null) return '';
  return rssi > -75 ? 'Yakında' : 'Uzakta';
}

String relativeTime(DateTime? t) {
  if (t == null) return 'Bilinmiyor';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return formatDate(t);
}

String formatDate(DateTime? t) {
  if (t == null) return 'Bilinmiyor';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// Durumun metni ve rengi. Durum sadece renkle anlatılmaz (doküman §3).
(String, Color) statusOf(TagConnection c) {
  switch (c.status) {
    case LinkStatus.connected:
      final p = proximityLabel(c.rssi);
      return (p.isEmpty ? 'Bağlı' : 'Bağlı · $p', AppColors.ok);
    case LinkStatus.connecting:
      return ('Bağlanıyor…', AppColors.warn);
    case LinkStatus.lost:
      return ('Bağlantı kesildi', AppColors.err);
    case LinkStatus.suspicious:
      return ('Şüpheli cihaz', AppColors.err);
    case LinkStatus.offline:
      return ('Kayıtlı, çevrimdışı', AppColors.text2);
  }
}

class StatusLabel extends StatelessWidget {
  const StatusLabel(this.text, this.color, {super.key, this.center = false});
  final String text;
  final Color color;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Yuvarlatılmış kare içinde cihaz simgesi.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar(this.iconKey, {super.key, this.size = 48, this.active = true});
  final String iconKey;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: active ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(iconFor(iconKey),
          size: size * 0.5,
          color: active ? AppColors.accentLight : AppColors.text2),
    );
  }
}

/// Kare iTag etiketinin sade çizimi (tasarımdaki beyaz cihaz görseli).
class TagIllustration extends StatelessWidget {
  const TagIllustration({super.key, this.size = 110, this.glow = false});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFD9DCE6)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: (glow ? AppColors.accent : Colors.black)
                .withValues(alpha: glow ? 0.45 : 0.35),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: size * 0.14,
            top: size * 0.14,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFC3C7D3), width: size * 0.015),
              ),
            ),
          ),
          Positioned(
            right: size * 0.2,
            top: size * 0.24,
            child: Container(
              width: size * 0.04,
              height: size * 0.04,
              decoration: const BoxDecoration(
                  color: Color(0xFF8A8F9E), shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Koyu kart (radius 20).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppDims.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }
}

/// Kart içinde simge + başlık + (alt yazı) + sağ öğe satırı.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color ?? AppColors.accentLight, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: c, fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: AppColors.text2, fontSize: 13)),
                ],
              ],
            ),
          ),
          trailing ??
              (onTap != null
                  ? const Icon(Icons.chevron_right, color: AppColors.text2)
                  : const SizedBox.shrink()),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.accentLight),
            ),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text2, fontSize: 14)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 52)),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bluetooth kapalı uyarı şeridi (doküman §17).
class BluetoothOffBanner extends StatelessWidget {
  const BluetoothOffBanner({super.key, required this.onTurnOn});
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDims.pad, 0, AppDims.pad, 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.bluetooth_disabled, color: AppColors.err),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("Cihazları taramak için Bluetooth'u aç.",
                  style: TextStyle(color: AppColors.text, fontSize: 14)),
            ),
            TextButton(onPressed: onTurnOn, child: const Text('Aç')),
          ],
        ),
      ),
    );
  }
}

/// Sayfa kenar boşluğu; alttaki sistem gezinme çubuğunun altında içerik
/// kalmasın diye onun yüksekliğini de ekler.
EdgeInsets pagePadding(BuildContext context, {double top = AppDims.pad}) =>
    EdgeInsets.fromLTRB(AppDims.pad, top, AppDims.pad,
        AppDims.pad + MediaQuery.paddingOf(context).bottom);

/// 4 çubuklu sinyal göstergesi.
class SignalBars extends StatelessWidget {
  const SignalBars(this.rssi, {super.key, this.height = 14});
  final int? rssi;
  final double height;

  @override
  Widget build(BuildContext context) {
    final r = rssi;
    final level = r == null
        ? 0
        : r > -60
            ? 4
            : r > -70
                ? 3
                : r > -80
                    ? 2
                    : 1;
    final color = signalColor(r);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 3.5,
            height: height * (0.3 + 0.175 * i),
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i <= level ? color : AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// TPCM Find logosu: iç içe halkalar.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.12),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.35),
            blurRadius: size * 0.5,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accentLight, width: size * 0.06),
          ),
          child: Center(
            child: Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentLight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmRemove(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cihazı kaldır'),
      content: const Text(
          'Bu cihaz kayıtlı listenden kaldırılacak. Tekrar eklemek için '
          'yeniden bağlanman gerekir.',
          style: TextStyle(color: AppColors.text2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.err),
          child: const Text('Kaldır'),
        ),
      ],
    ),
  );
  return ok == true;
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
