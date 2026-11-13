# TPCM Find — Teknik Proje Raporu

13.11.2026

TPCM Find, ucuz bir Bluetooth 4.0 "Anti-Lost" iTag anahtarlığını bulmak için Flutter ile yazılmış bir Android uygulaması. Etikete yalnızca "Bağlan"a basınca bağlanır, etiketi öttürür ve yaklaşık uzaklığı metre olarak gösterir. Kod yaklaşık 3.800 satır: 3.650 satır Dart, 130 satır Kotlin.

---

## 1. Özet

| Konu | Durum |
| --- | --- |
| Platform | Android (çalışıyor, release APK 18.8 MB). iOS kodu hazır ama hiç derlenmedi. |
| Cihaz | Markasız iTag, BLE 4.0, düğme pili, üstünde bir tuş ve buzzer |
| Özellikler | Tarama, bağlanma, öttürme, tuş bildirimi, pil seviyesi, tahmini mesafe ve kalibrasyon, isim/simge, taklit cihaz kontrolü |
| Bilerek yapılmayanlar | Otomatik bağlanma, arka planda bağlı kalma, harita, kayıp modu, bildirimler |
| Ana tasarım kararı | Etiket her bağlantı kopuşunda öttüğü için sürekli bağlı kalınmaz, sadece istenince bağlanılır |

---

## 2. Mimari

```
┌──────────────────────────────────────────────────────────────────┐
│  ARAYÜZ (lib/screens/*.dart, lib/widgets.dart, lib/theme.dart)   │
│  Karşılama → İzinler → [Cihazlarım | Keşfet | Ayarlar]           │
│  Cihaz detayı, bağlanma ekranı, kaydetme formu                   │
└───────────────┬──────────────────────────────────────────────────┘
                │ ListenableBuilder ile dinler (ChangeNotifier)
┌───────────────▼──────────────────────────────────────────────────┐
│  İŞ MANTIĞI (lib/tag_connection.dart)                            │
│  TagManager  : kayıtlı cihaz listesi, Bluetooth açık/kapalı      │
│  TagConnection (cihaz başına bir tane):                          │
│     connectNow → tara → bağlan (3 deneme) → servisleri keşfet    │
│     setTagAlert (öttür), RSSI→mesafe, calibrate, düğme dinleme   │
│  ItagFingerprint: "bu gerçekten iTag mi?" kontrolü               │
└───────┬──────────────────────────────┬───────────────────────────┘
        │                              │
┌───────▼─────────────┐     ┌──────────▼─────────────────────────┐
│ KALICI VERİ         │     │ flutter_blue_plus (BLE eklentisi)   │
│ lib/models.dart     │     │ Dart ↔ Android BluetoothGatt /      │
│ SharedPreferences   │     │        iOS CoreBluetooth            │
│ (JSON listesi)      │     └──────────┬─────────────────────────┘
└─────────────────────┘                │ Platform kanalı
                                       │
┌──────────────────────────────────────▼───────────────────────────┐
│  ANDROID (MainActivity.kt)                                       │
│  "tpcm/permissions" MethodChannel: izin durumu / iste / ayarlar  │
│  Açılışta eski sürüm kalıntılarını temizler                      │
└──────────────────────────────────────┬───────────────────────────┘
                                       │ Bluetooth Low Energy (2.4 GHz)
                               ┌───────▼───────┐
                               │   iTag        │
                               └───────────────┘
```

**Durum yönetimi:** Ek bir kütüphane (Provider, Riverpod, Bloc) kullanılmadı. Flutter'ın kendi `ChangeNotifier` sınıfı yeterli oldu. `TagConnection` bir şey değiştiğinde `notifyListeners()` çağırır, ekranlar `ListenableBuilder` ile yeniden çizilir. Küçük bir uygulama için en sade yol bu.

**Global nesneler:** `tagManager` ve `appSettings` tek örnek (singleton) olarak tutulur. Büyük projelerde bunun yerine bağımlılık enjeksiyonu tercih edilir.

---

## 3. Teknoloji Yığını

| Katman | Teknoloji | Sürüm | Neden |
| --- | --- | --- | --- |
| Dil | Dart | 3.11.4 | Flutter'ın dili |
| Arayüz çatısı | Flutter (Material 3) | 3.41.6 | Tek kod tabanından Android + iOS |
| BLE | flutter_blue_plus | 2.3.15 | En yaygın Flutter BLE paketi, Android ve iOS destekler |
| Kalıcı veri | shared_preferences | 2.5.6 | Birkaç cihazlık küçük veri, veritabanı gereksiz |
| Uygulama ikonu | flutter_launcher_icons | 0.14.4 | Tek PNG'den tüm Android/iOS boyutlarını üretir |
| Native köprü | Kotlin + MethodChannel | Kotlin 2.2.20 | İzin isteme (permission_handler derlenmedi) |
| Android derleme | Gradle + Android Gradle Plugin | Gradle 8.14, AGP 8.11.1, Java 17 | Flutter'ın Android şablonu |
| Sürüm kontrolü | Git (yerel) | — | 19 commit, uzak depo yok |

Projede denenip kaldırılan paketler: `permission_handler` (Gradle hatası) ve `flutter_map` + `geolocator` (harita özelliği kaldırıldı).

---

## 4. Bluetooth Low Energy Temelleri

### 4.1 Klasik Bluetooth ile BLE farkı

| | Klasik Bluetooth | Bluetooth Low Energy (BLE) |
| --- | --- | --- |
| Kullanım | Kulaklık, hoparlör (ses akışı) | Sensör, etiket, saat (küçük veri) |
| Güç | Yüksek | Çok düşük, iTag düğme pille aylarca çalışır |
| Eşleşme | Genelde zorunlu (PIN) | Zorunlu değil. iTag hiç eşleşme kullanmıyor |
| Veri modeli | Profiller (A2DP, HFP…) | GATT: servisler ve karakteristikler |

Telefonun Bluetooth ayarlarından iTag'e bağlanamamanın sebebi bu. Ayarlar ekranı klasik cihazları eşleştirmek için var. BLE cihazla konuşmak için ona hangi karakteristiğe ne yazacağını bilen bir uygulama gerekiyor.

### 4.2 Bir BLE bağlantısının yaşam döngüsü

1. **Advertising (yayın):** iTag, belirli aralıklarla "buradayım" paketi yayınlar. Pakette adı ve MAC adresi olur, aralık birkaç yüz ms ile birkaç saniye arasıdır.
2. **Scanning (tarama):** Telefon bu paketleri dinler. Her pakette **RSSI** (alınan sinyal gücü, dBm) da gelir.
3. **Connecting (bağlanma):** Telefon "bağlanmak istiyorum" isteği gönderir. Etiket bir sonraki yayın penceresinde cevap verirse bağlantı kurulur.
4. **Service discovery (servis keşfi):** Telefon, cihazın hangi servisleri sunduğunu sorar.
5. **Read / Write / Notify:** Karakteristikler okunur, yazılır veya bildirim için abone olunur.
6. **Disconnect (kopma):** Bağlantı biter. iTag bu anda öter.

### 4.3 GATT: servis ve karakteristik

GATT, bir klasör yapısı gibi düşünülebilir:

- **Servis:** Bir klasör, örneğin "Pil servisi".
- **Karakteristik:** İçindeki dosya, örneğin "Pil seviyesi". Her karakteristiğin bir UUID'si ve izinleri vardır (read, write, writeWithoutResponse, notify, indicate).
- **16 bitlik UUID'ler** (`180F` gibi) Bluetooth SIG'in standartlaştırdığı servislerdir. `FFE0` gibi değerler üreticiye özeldir.

### 4.4 iTag'in GATT haritası (gerçek cihazda doğrulandı)

| Servis | Karakteristik | İzinler | Ne işe yarar | Standart mı? |
| --- | --- | --- | --- | --- |
| `1800` Generic Access | `2A00` Device Name | read, notify | Cihaz adı | Evet |
| `1800` Generic Access | `2A01` Appearance | read | Cihaz türü | Evet |
| `180F` Battery | `2A19` Battery Level | read, notify | Pil yüzdesi (0–100) | Evet |
| `1802` Immediate Alert | `2A06` Alert Level | write, writeNoResp, notify | Öttürme: `0x00` sus, `0x01` hafif, `0x02` yüksek | Evet |
| `FFE0` (üretici) | `FFE1` | read, notify | Tuşa basılınca `[0x01]` gönderir | Hayır |

**Bu cihazda olmayanlar:**

- `1803` Link Loss servisi yok. Bu yüzden "kopunca ötme" kapatılamıyor.
- Firmware güncelleme (OTA) servisi yok.
- Mikrofon yok. Kutudaki "voice recording" ifadesi, telefonda ses kaydı başlatma gibi bir uygulama özelliğini anlatıyor. Etiket ses kaydedemez.

---

## 5. "Bağlan"a Basınca Ne Oluyor?

Kod: `TagConnection.connectNow()` ve `_setup()` (lib/tag_connection.dart).

1. **Bluetooth kontrolü:** Bluetooth kapalıysa Android'den "Bluetooth açılsın mı?" penceresi istenir (`FlutterBluePlus.turnOn()`) ve açılması 10 sn'ye kadar beklenir.
2. **Hedefli tarama, en fazla 30 sn:** `startScan(withRemoteIds: [MAC])` ile sadece bu etiket aranır. Kullanıcı bu sırada yürüyüp yaklaşabilir.
3. **Bağlanma, 3 deneme × 15 sn:** Etiket görülünce `device.connect()` çağrılır. Ucuz etiketler bazen ilk isteğe cevap vermez. Kayıtlarda ilk deneme 10 sn'de zaman aşımına uğradı, hemen ardından gelen deneme 3 sn'de bağlandı. Bu yüzden denemeler arasında 800 ms beklenerek tekrar denenir.
4. **Servis keşfi + parmak izi:** `discoverServices()` çalışır. Kayıtlı cihaz iTag ise `1802/2A06` ve `FFE0/FFE1` mutlaka bulunmalı. Bulunamazsa cihaz **"şüpheli"** sayılır ve bağlantı kesilir. Aynı MAC adresini taklit eden başka bir cihaza karşı basit bir önlem.
5. **Tuşa abone olma:** `FFE1` için `setNotifyValue(true)` çağrılır. Gelen her veri doğrulanır: tam olarak `[0x01]` olmalı ve 2 sn içinde en fazla 5 bildirim kabul edilir. Telefon titrer ve ses çalar.
6. **Pil:** `2A19` bir kez okunur. 100'den büyük değerler yok sayılır.
7. **RSSI zamanlayıcısı:** Her saniye `readRssi()` çağrılır ve mesafe güncellenir (bölüm 6).
8. **"Bağlandım" sinyali:** `2A06`'ya 3 kez `0x02` ve ardından `0x00` yazılır. Etiket bip-bip-bip yapar.

**Öttürme:** `2A06`'ya `0x02` yazılır. 30 sn sonra uygulama kendiliğinden `0x00` yazıp susturur.

**Bağlantıyı kesme:** Önce `0x00` yazılır, sonra `disconnect()` çağrılır. Etiket yine de öter. Bu, cihazın firmware'inde gömülü ve yazılımla kapatılamıyor. Susturmak için tuşuna basmak ya da tekrar bağlanmak gerekiyor.

---

## 6. Mesafe Tahmini

### 6.1 RSSI nedir?

RSSI (Received Signal Strength Indicator), telefonun aldığı sinyalin gücüdür ve dBm cinsinden negatif bir sayıdır. −50 güçlü, −90 zayıf sinyaldir. Uzaklık arttıkça RSSI düşer ama düz bir çizgi halinde değil, logaritmik olarak.

### 6.2 Formül: log-distance path loss modeli

```
d = 10 ^ ((P1m − RSSI) / (10 · n))
```

| Sembol | Anlamı | Değer |
| --- | --- | --- |
| `d` | Tahmini uzaklık (metre) | Sonuç |
| `RSSI` | Ölçülen sinyal (dBm) | Saniyede bir okunur |
| `P1m` | 1 metredeki RSSI | Varsayılan −60, kalibrasyonla ölçülür |
| `n` | Ortam katsayısı | 2.2 (boş alanda 2, iç mekânda 2–4) |

**Örnek:** P1m = −60 ve RSSI = −73 ise d = 10^(13/22) ≈ 3.9 m.

### 6.3 Gürültüyü azaltma: ortanca (median) filtre

RSSI her ölçümde ±5–10 dB oynar. Bu, mesafenin bir anda 2 katına çıkmış gibi görünmesi demek. Uygulama son 7 ölçümün **ortancasını** kullanır.

- **Neden ortalama değil?** Tek bir aşırı değer ortalamayı bozar, ortancayı bozmaz.
- **Bedeli:** Değer yaklaşık 3–4 sn geriden gelir.

### 6.4 Kalibrasyon

Her etiketin anteni ve pili farklıdır, bu yüzden P1m cihaza göre değişir. "Kalibre et"e basınca uygulama 400 ms arayla 12 RSSI ölçer (yaklaşık 5 sn). Bunların ortancası o etiketin `rssiAt1m` değeri olarak kaydedilir.

### 6.5 Sınırları

- Vücut, cep, duvar ve araba gövdesi sinyali 10–20 dB düşürebilir. Etiket 2 m uzaktayken 10 m görünebilir.
- Telefonun tutuluş yönü de etkiler.
- Bu yüzden ekranda "≈" işareti var ve 10 m'den sonra 5 m'lik adımlarla yuvarlanıyor. Asıl işe yarayan bilgi değerin **yönü**: sayı küçülüyorsa yaklaşıyorsun.

---

## 7. Güvenlik

**Tehdit modeli:** iTag'de eşleşme (pairing) ve şifreleme yok. Menzildeki (~10–30 m) herhangi bir telefon, herhangi bir iTag uygulamasıyla bu etikete bağlanıp onu öttürebilir. Bu, cihazın donanım ve firmware sınırı. Uygulama bunu çözemez.

| Risk | Önlem | Etkisi |
| --- | --- | --- |
| Başkası etiketi öttürür | Yok (cihaz izin veriyor) | Sadece rahatsızlık; veri yok |
| Başkası bağlıyken biz bağlanamayız | BLE etiketler genelde tek bağlantı kabul eder | Nadiren, kısa süreli |
| Aynı MAC'i taklit eden sahte cihaz | Parmak izi kontrolü (bölüm 5, adım 4) | Zorlaştırır, tam engellemez |
| Sahte tuş bildirimi yağmuru | Veri doğrulama + 2 sn'de en fazla 5 bildirim | Uygulamanın kilitlenmesini önler |
| Etiket üzerinden dinleme | Mümkün değil, mikrofon yok | — |
| Takip edilme | Etiket MAC'ini sürekli yayınlar ve MAC sabit | Biri tarayıcıyla etiketi (yani anahtarı) görebilir. Ucuz etiketlerin hepsinde böyle |
| Uygulama verisi | Sadece telefonda; sunucu, hesap, konum yok | Sızacak veri yok |

**Android izinleri en az seviyede tutuldu:**

- Android 12+ için sadece `BLUETOOTH_SCAN` (`neverForLocation` işaretiyle, yani konum için kullanılmadığı beyan edilir) ve `BLUETOOTH_CONNECT`.
- Konum izni yalnızca Android 11 ve altında isteniyor, çünkü orada BLE taraması için zorunlu.

---

## 8. Android'e Özgü Konular

### 8.1 İzinler ve native köprü (MethodChannel)

`permission_handler` paketi bu projenin Gradle/Kotlin sürümüyle derlenmedi. Paketi kullanmak yerine Kotlin'de küçük bir köprü yazıldı:

```
Dart: Perms.request('bluetooth')
  → MethodChannel('tpcm/permissions').invokeMethod('request', {group})
    → Kotlin: requestPermissions([BLUETOOTH_SCAN, BLUETOOTH_CONNECT])
      → onRequestPermissionsResult → result.success(true/false)
  ← Dart'a bool döner
```

Bu, Flutter'ın Dart'tan platform koduna erişmek için kullandığı standart yöntem. Asenkron çalışır ve mesajlar standart bir kodlayıcıyla (StandardMessageCodec) taşınır.

### 8.2 Debug ve release derleme farkı

| | Debug APK | Release APK |
| --- | --- | --- |
| Boyut | 184 MB | 18.8 MB |
| Dart kodu | JIT (çalışırken derlenir) + hot reload | AOT (önceden makine koduna derlenir) |
| Hız | Yavaş, ilk açılış ağır | Hızlı |
| İkon fontu | Tamamı | Tree-shaking: 1.6 MB → 7 KB (%99.6 küçüldü) |
| İçerik | Tüm işlemci mimarileri + hata ayıklama bilgisi | Sadece arm64 (`--target-platform android-arm64`) |

Derleme komutu:

```
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 8.3 İmzalama

Android her APK'nın imzalı olmasını ister. Bir uygulama ancak aynı anahtarla imzalanmış bir sürümün üstüne kurulabilir.

- Şu an release sürümü de bilgisayardaki debug anahtarıyla imzalanıyor: `C:\Users\user\.android\debug.keystore`.
- Bu anahtar kaybolursa güncelleme kurulamaz. Uygulamayı silip yeniden kurmak gerekir ve kayıtlı cihazlar gider. **Anahtarı yedekle.**
- Play Store'a yüklenecekse ayrı bir release anahtarı (upload key) oluşturulmalı.

### 8.4 adb (Android Debug Bridge)

Geliştirme boyunca telefonla bilgisayar arasında adb kullanıldı:

- `adb install -r`: Uygulamayı verileri silmeden günceller.
- `adb logcat`: Sistem kayıtlarını gösterir. Bağlanma sorunu bu kayıtlardaki `BluetoothGatt`, `gatt_api` ve `GATT_CONN` satırlarından teşhis edildi.
- `adb shell am start`: Uygulamayı açar.
- `adb shell uiautomator dump` ve `screencap`: Ekran içeriğini okur ve ekran görüntüsü alır.

---

## 9. Denenip Kaldırılanlar

Bu projenin en öğretici kısmı bu bölüm. Birçok özellik çalışır hale getirildi ama cihazın davranışı ya da kullanım amacı yüzünden kaldırıldı.

| Özellik | Nasıl yapılmıştı | Neden kaldırıldı |
| --- | --- | --- |
| Otomatik bağlanma | Önce Android `autoConnect: true`, sonra hedefli tarama + doğrudan bağlantı | Samsung'da `autoConnect` çok yavaş ya da hiç bağlanmıyordu. Asıl sebep ise etiketin her kopuşta ötmesi |
| Arka planda bağlı kalma | Foreground service + uygulama düzeyinde Flutter motoru + telefon açılınca başlatma (BootReceiver) | Sürekli bağlı kalma istenmedi; ayrıca pil tüketiyordu |
| Harita / son görülen konum | Bağlanmadan dinleme (PendingIntent ile BLE tarama), ağ konumu, OpenStreetMap | Bluetooth sürekli açık tutulmayacağı için veri toplanamıyordu |
| Kayıp modu + bildirimler | Bağlıyken kopunca telefon alarmı ve sistem bildirimi | Sürekli bağlı kalınmadığı için anlamı kalmadı |
| Etiketin kopma bip'ini kapatma | `1803` Link Loss'a `0x00` yazma; kesmeden önce `0x00` gönderme | Bu iTag'de `1803` yok, bip firmware'de gömülü. Her yol test edildi, hiçbiri işe yaramadı |

**Sonuç:** Etiketin kendi davranışı (her kopuşta ötmesi) bütün mimariyi belirledi. Donanım projelerinde önce cihazın gerçek davranışını ölçmek, sonra tasarlamak gerekir.

---

## 10. Karşılaşılan Hatalar ve Dersler

| Sorun | Kök neden | Çözüm | Ders |
| --- | --- | --- | --- |
| Uygulama "Aranıyor…" ekranında kalıyordu | `adapterStateNow` değeri, `adapterState` akışını kimse dinlemediği için hiç güncellenmiyordu | `TagManager` akışı sürekli dinliyor | Bir kütüphanenin "anlık değer" alanının nasıl güncellendiğini dokümandan doğrula |
| `permission_handler` derlenmedi | Gradle / Kotlin DSL uyumsuzluğu | Paket yerine 130 satırlık Kotlin köprüsü | Küçük bir iş için bağımlılık eklemek bazen kendi kodunu yazmaktan pahalıdır |
| Türkçe karakterler bozuldu (ş → ÅŸ) | PowerShell 5.1 dosyayı UTF-8 yerine Windows-1254 kodlamasıyla okuyup yazdı | Bayt düzeyinde geri dönüştürme | Kaynak dosyaları kodlamayı bilmeyen araçlarla yeniden yazma |
| Alttaki içerik sistem çubuğunun altında kalıyordu | Uygulama ekranın en altına kadar (edge-to-edge) çiziliyor; liste, gezinme çubuğunun payını bırakmıyordu | `pagePadding()` ile alt boşluk eklendi | `MediaQuery.padding` / `SafeArea` |
| Harita "API KEY REQUIRED" | CARTO karoları anahtar istiyordu | OSM karoları + koyu filtre (sonra harita kaldırıldı) | Ücretsiz servislerin kullanım şartlarını oku |
| İkon aracı iOS proje dosyasını bozdu | `flutter_launcher_icons`, `project.pbxproj` dosyasına yanlış bir ayar yazdı | `git checkout` ile geri alındı | Kod üreten araçlardan sonra `git diff`'e bak |
| "Cihaz bulundu ama bağlanamadı" | Etiket ilk bağlantı isteğine 10 sn içinde cevap vermiyordu | 3 deneme × 15 sn | Gerçek cihazlarda yeniden deneme şarttır; teşhisi logcat'ten yap |

---

## 11. iPhone İçin Kalanlar

Kod iOS'u düşünerek yazıldı ama hiç derlenmedi. Dikkat edilecek noktalar:

- **Cihaz kimliği:** iOS MAC adresini göstermez, her telefon cihaza kendi UUID'sini verir. Bu yüzden etiket abinin iPhone'unda yeniden eklenmeli. Android'deki kayıt taşınamaz.
- **Bluetooth açma:** iOS'ta uygulama Bluetooth'u kendisi açamaz. Kullanıcı Denetim Merkezi'nden açmalı.
- **İzin:** İlk Bluetooth erişiminde sistem `NSBluetoothAlwaysUsageDescription` metniyle izin sorar. Bu metin `Info.plist` içinde hazır.
- **Kurulum seçenekleri:**
  - Ücretsiz Apple ID: 7 günde bir yenilemek gerekir.
  - Yıllık 99 $ Apple Developer hesabı: TestFlight ile kurulur.
  - Her iki durumda da derleme için Mac ya da Codemagic gibi bulut Mac servisi gerekir.

---

## 12. Öğrenme Listesi

Bu projeden sonra anlatabilmen gereken kavramlar:

**Bluetooth / Gömülü**

- [ ] BLE ile klasik Bluetooth farkı; advertising, scanning, connection
- [ ] GATT: servis, karakteristik, UUID, read / write / writeWithoutResponse / notify
- [ ] Bluetooth SIG standart servisleri: 1802 Immediate Alert, 1803 Link Loss, 180F Battery
- [ ] RSSI, dBm ve log-distance path loss modeli
- [ ] Neden ucuz BLE cihazların çoğunda eşleşme ve şifreleme yok; BLE güvenlik modları

**Flutter / Dart**

- [ ] Widget ağacı, StatelessWidget ve StatefulWidget farkı
- [ ] `ChangeNotifier` + `ListenableBuilder` ile durum yönetimi
- [ ] Dart'ta asenkron programlama: `Future`, `async/await`, `Stream`, `Completer`, `Timer`
- [ ] Platform kanalları (MethodChannel) ile native koda erişim
- [ ] JIT ve AOT derleme; debug, profile ve release modları; tree-shaking

**Android**

- [ ] İzin modeli: çalışma zamanı izinleri, Android 12'deki Bluetooth izin değişikliği
- [ ] Activity yaşam döngüsü, foreground service, BroadcastReceiver
- [ ] APK imzalama ve keystore
- [ ] Gradle derleme sistemi, `build.gradle.kts`
- [ ] adb ve logcat ile hata ayıklama

**Genel mühendislik**

- [ ] Sinyal işleme: ortalama ve ortanca filtre farkı
- [ ] Tehdit modelleme: neyi koruyabiliriz, neyi koruyamayız
- [ ] Karakter kodlaması: UTF-8, Windows-1254, BOM
- [ ] Git: commit, diff, checkout ile geri alma
- [ ] Gereksinim değişince özellik kaldırmak ve eski verileri temizlemek (migration)

---

## 13. Kaynaklar ve İleri Okuma

- [flutter_blue_plus paketi (pub.dev)](https://pub.dev/packages/flutter_blue_plus)
- [Android: Bluetooth Low Energy genel bakış](https://developer.android.com/develop/connectivity/bluetooth/ble/ble-overview)
- [Android: Bluetooth izinleri](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Flutter: Platform kanalları](https://docs.flutter.dev/platform-integration/platform-channels)
- [Bluetooth SIG: Assigned Numbers (UUID listesi)](https://www.bluetooth.com/specifications/assigned-numbers/)
- [Flutter: Uygulama durumu yönetimi](https://docs.flutter.dev/data-and-backend/state-mgmt/simple)

### Dosya haritası

| Dosya | Satır | Görevi |
| --- | --- | --- |
| `lib/tag_connection.dart` | 629 | BLE bağlantısı, öttürme, mesafe, parmak izi, cihaz yöneticisi |
| `lib/screens/device_detail.dart` | 545 | Cihaz sayfası, düzenleme, teknik bilgiler |
| `lib/widgets.dart` | 461 | Ortak bileşenler, durum metinleri, mesafe etiketi |
| `lib/screens/connect_flow.dart` | 441 | İlk bağlanma ve kaydetme akışı |
| `lib/screens/discover_tab.dart` | 383 | Tarama ve listeleme (aynı isimler tek satırda) |
| `lib/screens/settings_tab.dart` | 267 | Ayarlar, izinler, gizlilik, hakkında |
| `lib/screens/onboarding.dart` | 250 | Karşılama ve izin ekranı |
| `lib/screens/devices_tab.dart` | 239 | Ana ekran: Cihazlarım |
| `lib/theme.dart` | 158 | Koyu tema, renkler, ölçüler |
| `lib/models.dart` | 146 | Kayıtlı cihaz modeli, kalıcı veri, ayarlar |
| `android/.../MainActivity.kt` | 131 | İzin köprüsü, eski sürüm temizliği |
