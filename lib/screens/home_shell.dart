import 'package:flutter/material.dart';

import '../tag_connection.dart';
import 'device_detail.dart';
import 'devices_tab.dart';
import 'discover_tab.dart';
import 'settings_tab.dart';

/// Alt menü sekmeleri: 0 Cihazlarım · 1 Keşfet · 2 Ayarlar
/// (Harita sekmesi kaldırıldı: Bluetooth sürekli açık tutulmayacağı için
/// telefon etiketi duyamaz, son görülen konum anlamsız kalıyordu.)
final homeTab = ValueNotifier<int>(0);

void openDevice(BuildContext context, TagConnection c) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DeviceDetailScreen(conn: c),
  ));
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: homeTab,
      builder: (context, index, _) => Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            const DevicesTab(),
            DiscoverTab(active: index == 1),
            const SettingsTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => homeTab.value = i,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.sell_outlined),
              selectedIcon: Icon(Icons.sell),
              label: 'Cihazlarım',
            ),
            NavigationDestination(
              icon: Icon(Icons.bluetooth_searching),
              label: 'Keşfet',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Ayarlar',
            ),
          ],
        ),
      ),
    );
  }
}
