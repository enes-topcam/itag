import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models.dart';
import '../tag_connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';

enum _Phase { connecting, success, unsupported, failed }

/// Sayfa 05 — Bağlanıyor / Bağlantı sonucu
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.device,
    required this.advertisedName,
    required this.looksLikeTag,
  });
  final BluetoothDevice device;
  final String advertisedName;
  final bool looksLikeTag;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  _Phase _phase = _Phase.connecting;
  bool _handedOff = false; // bağlantı kaydetme ekranına devredildi mi
  bool _cancelled = false;

  String get _title =>
      widget.advertisedName.isEmpty ? 'İsimsiz cihaz' : widget.advertisedName;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    if (!_handedOff) {
      widget.device.disconnect().catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _phase = _Phase.connecting;
      _cancelled = false;
    });
    try {
      // iTag bağlantı isteğine bazen geç yanıt verir; birkaç kez dene.
      for (var attempt = 1;; attempt++) {
        try {
          await widget.device.connect(
            license: License.nonprofit,
            timeout: const Duration(seconds: 15),
            mtu: null,
          );
          break;
        } catch (_) {
          if (!mounted || _cancelled || attempt >= 3) rethrow;
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
      final fp = ItagFingerprint(await widget.device.discoverServices());
      if (fp.looksLikeItag) {
        try {
          await fp.disableLinkLossBeep();
        } catch (_) {}
      }
      if (!mounted || _cancelled) return;
      setState(() =>
          _phase = fp.looksLikeItag ? _Phase.success : _Phase.unsupported);
    } catch (_) {
      if (!mounted || _cancelled) return;
      try {
        await widget.device.disconnect();
      } catch (_) {}
      setState(() => _phase = _Phase.failed);
    }
  }

  void _cancel() {
    _cancelled = true;
    Navigator.of(context).pop();
  }

  void _goSave({required bool isItag}) {
    _handedOff = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => SaveDeviceScreen(
        device: widget.device,
        advertisedName: widget.advertisedName,
        isItag: isItag,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihaz Ekle')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDims.pad),
          child: Column(
            children: [
              const Spacer(),
              widget.looksLikeTag
                  ? TagIllustration(
                      size: 120, glow: _phase == _Phase.success)
                  : Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bluetooth,
                          size: 54, color: AppColors.accentLight),
                    ),
              const SizedBox(height: 28),
              Text(_title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 28),
              ..._phaseContent(),
              const Spacer(),
              ..._actions(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _phaseContent() {
    Widget badge(IconData icon, Color color) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
          ),
          child: Icon(icon, color: color, size: 34),
        );
    Widget title(String t) => Text(t,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium);
    Widget sub(String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text2, fontSize: 14)),
        );

    switch (_phase) {
      case _Phase.connecting:
        return [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3.5),
          ),
          const SizedBox(height: 18),
          title('Bağlanıyor…'),
          sub('Cihazla iletişim kuruluyor'),
        ];
      case _Phase.success:
        return [
          badge(Icons.check, AppColors.ok),
          const SizedBox(height: 16),
          title('Bağlantı Başarılı!'),
          sub('Şimdi cihazına bir isim ve simge ver.'),
        ];
      case _Phase.unsupported:
        return [
          badge(Icons.info_outline, AppColors.warn),
          const SizedBox(height: 16),
          title('Bağlantı kuruldu'),
          sub('Bluetooth bağlantısı kurulabildi fakat iTag komutları '
              'desteklenmiyor. Takip özellikleri (ses çaldırma, düğme) '
              'bu cihazda kullanılamaz.'),
        ];
      case _Phase.failed:
        return [
          badge(Icons.close, AppColors.err),
          const SizedBox(height: 16),
          title('Bağlantı kurulamadı'),
          sub('Cihazın yakında ve açık olduğundan emin ol. Takip cihazını '
              'uyandırmak için düğmesine bir kez bas.'),
        ];
    }
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.connecting:
        return [
          OutlinedButton(onPressed: _cancel, child: const Text('İptal Et')),
        ];
      case _Phase.success:
        return [
          FilledButton(
            onPressed: () => _goSave(isItag: true),
            child: const Text('Devam'),
          ),
        ];
      case _Phase.unsupported:
        return [
          FilledButton(
            onPressed: () => _goSave(isItag: false),
            child: const Text('Genel Bluetooth cihazı olarak kaydet'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _cancel, child: const Text('Vazgeç')),
        ];
      case _Phase.failed:
        return [
          FilledButton(onPressed: _connect, child: const Text('Tekrar Dene')),
          const SizedBox(height: 10),
          OutlinedButton(
              onPressed: _cancel, child: const Text('Cihaz listesine dön')),
        ];
    }
  }
}

/// Sayfa 06 — Cihazı ilk kez kaydet
class SaveDeviceScreen extends StatefulWidget {
  const SaveDeviceScreen({
    super.key,
    required this.device,
    required this.advertisedName,
    required this.isItag,
  });
  final BluetoothDevice device;
  final String advertisedName;
  final bool isItag;

  @override
  State<SaveDeviceScreen> createState() => _SaveDeviceScreenState();
}

class _SaveDeviceScreenState extends State<SaveDeviceScreen> {
  bool _saved = false;

  @override
  void dispose() {
    // Kaydetmeden çıkıldıysa bağlantıyı kapat: sadece bağlanmak kayıt yapmaz.
    if (!_saved) widget.device.disconnect().catchError((_) {});
    super.dispose();
  }

  Future<void> _save(String name, String iconKey) async {
    final now = DateTime.now();
    final d = SavedDevice(
      id: widget.device.remoteId.str,
      displayName: name,
      advertisedName:
          widget.advertisedName.isEmpty ? null : widget.advertisedName,
      iconKey: iconKey,
      isItag: widget.isItag,
      firstConnectedAt: now,
      lastConnectedAt: now,
      lastSeenAt: now,
    );
    _saved = true;
    // Bağlantı açık; TagConnection mevcut bağlantıyı devralır.
    await tagManager.add(d);
    if (!mounted) return;
    final nav = Navigator.of(context);
    homeTab.value = 0;
    nav.popUntil((r) => r.isFirst);
    final c = tagManager.get(d.id);
    if (c != null) openDevice(nav.context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihazını Kaydet')),
      body: DeviceForm(
        initialName: widget.advertisedName.isEmpty
            ? 'Yeni Cihaz'
            : widget.advertisedName,
        initialIcon: widget.isItag ? 'key' : 'star',
        onSave: _save,
      ),
    );
  }
}

/// Ad + simge formu (kaydet ve düzenle ekranlarında ortak).
class DeviceForm extends StatefulWidget {
  const DeviceForm({
    super.key,
    required this.initialName,
    required this.initialIcon,
    required this.onSave,
    this.footer,
  });
  final String initialName;
  final String initialIcon;
  final Future<void> Function(String name, String iconKey) onSave;
  final Widget? footer;

  @override
  State<DeviceForm> createState() => _DeviceFormState();
}

class _DeviceFormState extends State<DeviceForm> {
  late final _name = TextEditingController(text: widget.initialName);
  late String _icon = widget.initialIcon;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      setState(() => _error = 'Cihaz adı boş olamaz');
      return;
    }
    setState(() => _busy = true);
    await widget.onSave(n, _icon);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppDims.pad),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const TagIllustration(size: 104),
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 4),
                    ),
                    child: ClipOval(
                      child: Container(
                        color: AppColors.raised,
                        padding: const EdgeInsets.all(8),
                        child: Icon(iconFor(_icon),
                            color: AppColors.accentLight, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text('Cihaz adı',
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: 'Örn. Anahtar',
              errorText: _error,
              suffixIcon: IconButton(
                icon: const Icon(Icons.close, color: AppColors.text2),
                onPressed: () => _name.clear(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Bir simge seç',
              style: TextStyle(color: AppColors.text2, fontSize: 13)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final e in deviceIcons.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _icon = e.key),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _icon == e.key
                          ? AppColors.accent.withValues(alpha: 0.18)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _icon == e.key
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(e.value,
                        color: _icon == e.key
                            ? AppColors.accentLight
                            : AppColors.text),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Kaydet'),
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            widget.footer!,
          ],
        ],
      ),
    );
  }
}
