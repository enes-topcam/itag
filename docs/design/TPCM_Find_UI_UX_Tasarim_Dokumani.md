# TPCM Find — UI/UX Tasarım ve Uygulama Yapısı

> **Sürüm:** 1.0 · **Platform:** Android · **Dil:** Türkçe · **Tema:** Koyu (varsayılan) · **Amaç:** Bluetooth takip cihazlarını keşfetmek, uyumlu cihazlara bağlanmak, kaydetmek ve yönetmek.
>
> Bu belge, uygulamanın sayfa bazlı tasarımını, kullanıcı akışlarını, bileşenleri, durumları ve teknik davranışlarını tek yerde tanımlar. Tasarımın referansı: koyu zemin, mor vurgu rengi, büyük yuvarlatılmış kartlar, yalın ikonlar.

## 1. Ürün ve kapsam

**Uygulama adı (taslak):** TPCM Find  
**Geliştirici:** TPCM Studio  
**Hedef cihaz:** Bluetooth 4.0 “Anti-Lost” kare iTag benzeri takip cihazı.  
**Ana kullanıcı senaryosu:** Kullanıcı Bluetooth'u açar → yakındaki cihazları tarar → uyumlu cihaza bağlanır → cihazı “Cihazlarım”a kaydeder → adını/simgesini düzenler → destekleniyorsa cihazı öttürür → bağlantı ve son görülme bilgisini takip eder.

### Özelliklerin doğruluk sınırları

- **Tüm cihazları listelemek ≠ tüm cihazlara bağlanabilmek.** Yakındaki bulunabilir BLE ve klasik Bluetooth cihazları gösterilebilir; bağlanma ve komut kullanımı cihazın protokolüne ve Android izinlerine bağlıdır.
- **Ses çaldırma**, iTag modelinin desteklediği BLE servis/karakteristikleri ve komutlar doğrulandıktan sonra etkinleştirilir. Standart bir evrensel “öt” komutu varsayılmamalıdır.
- **Sinyal (RSSI)** yaklaşık yakınlık ipucudur; kesin metre ölçümü değildir.
- **Pil yüzdesi** yalnızca cihaz uygun veri sunuyorsa gösterilir. Aksi hâlde “Desteklenmiyor” yazılır.
- **Konum**, takip cihazında GPS olduğu anlamına gelmez. Telefonun, cihazı en son gördüğü sıradaki konum izni alınmışsa kaydedilen konumudur.
- **Bağlantı kopma uyarısı**, arka plan Bluetooth tarama/bağlantı kısıtları ve izinleri nedeniyle her koşulda anlık veya kesin çalışacağı vaadiyle sunulmamalıdır.
- Bazı ucuz iTag modelleri **iTracing/iSearching gibi özel protokoller** kullanabilir. Önce gerçek cihazda servis keşfi ve test yapılmalıdır.

## 2. Bilgi mimarisi ve gezinme

Alt gezinme menüsü (4 sekme): **Cihazlarım · Keşfet · Harita · Ayarlar**.

```text
TPCM Find
├── Açılış / İlk kurulum
│   ├── Karşılama
│   ├── Bluetooth / Yakındaki cihazlar izni
│   ├── Konum izni (yalnızca ihtiyaç duyulan özellik için)
│   └── Bildirim izni (uyarı özelliği için)
├── Cihazlarım (varsayılan ana sayfa)
│   ├── Kayıtlı cihaz listesi
│   ├── Cihaz ayrıntıları
│   │   ├── Ses çaldır / sesi durdur
│   │   ├── Son görülen konum
│   │   ├── Kayıp modu / bağlantı kopma uyarısı
│   │   ├── Cihaz bilgileri
│   │   ├── Cihazı düzenle
│   │   └── Cihazı kaldır
│   └── Yeni cihaz ekle → Keşfet
├── Keşfet (Bluetooth cihazları)
│   ├── BLE cihazları
│   ├── Klasik Bluetooth cihazları
│   ├── Filtreler / arama / yeniden tara
│   ├── Bağlanma durumu
│   └── Başarılı bağlantı → kaydetme akışı
├── Harita
│   ├── Konumu kaydedilmiş cihaz işaretleri
│   └── Cihazın son görüldüğü yerin ayrıntısı
└── Ayarlar
    ├── Bildirimler ve kopma uyarıları
    ├── Bluetooth / izin durumu
    ├── Tema ve dil
    ├── Veri ve gizlilik
    └── Hakkında
```

**Gezinme kuralı:** Ana 4 sekmede alt menü görünür. Tam ekran bağlantı akışında ve düzenleme ekranında alt menü gizlenebilir; üstte geri oku vardır.

## 3. Tasarım sistemi

### Renkler

| Rol | Hex | Kullanım |
| --- | --- | --- |
| Ana zemin | `#0C0E16` | Uygulama arka planı |
| Kart zemin | `#191C29` | Cihaz kartları ve ayar satırları |
| Yükseltilmiş yüzey | `#232638` | Modal ve seçili alan |
| Mor vurgu | `#8067F7` | Birincil buton, seçili sekme |
| Açık mor | `#A798FF` | İkon, focus, küçük vurgular |
| Ana yazı | `#F7F7FA` | Başlık ve kritik bilgiler |
| İkincil yazı | `#9DA4B8` | Açıklama, yardımcı bilgi |
| Bağlı | `#33CE91` | Olumlu durum |
| Uyarı | `#F0B75E` | Bağlanıyor / düşük sinyal |
| Hata | `#F36B78` | Bağlanamadı / silme |
| Çizgi | `#2C3142` | Ayırıcı ve kenarlık |

### Tipografi ve bileşenler

- **Yazı tipi:** Android sistem fontu (Roboto) veya Google Sans benzeri okunaklı font.
- **Başlık:** 24–28 sp, kalın. **Kart başlığı:** 16–18 sp, orta/kalın. **Gövde:** 14–16 sp. **Açıklama:** 12–14 sp.
- **Kart yarıçapı:** 18–22 dp. **Buton yarıçapı:** 16–20 dp. **Standart kenar boşluğu:** 20 dp. **Kart arası:** 12 dp.
- **Birincil buton:** Mor dolgu, beyaz metin. **İkincil buton:** Koyu yüzey, açık metin. **Tehlikeli işlem:** Kırmızı metin + onay penceresi.
- **İkonlar:** Tutarlı çizgisel ikon ailesi; anahtar, çanta, cüzdan, etiket, Bluetooth, ses, harita pini, kalem, zil ve dişli.
- **Dokunma hedefleri:** En az 48×48 dp; durum sadece renk ile anlatılmaz, metin de gösterilir.

### Ortak durum bileşenleri

`Bağlı` (yeşil) · `Bağlanıyor…` (sarı) · `Bağlantı kesildi` (gri/kırmızı) · `Kayıtlı, çevrimdışı` · `Desteklenmiyor`.

**Önemli:** `Kayıtlı` cihazın uygulamanın veritabanında bulunmasıdır; `Bağlı` ise aktif Bluetooth oturumudur. Birbirinden ayrı gösterilir.

---

## 4. Sayfa 01 — Açılış / Karşılama

**Hedef:** Ürünü bir cümlede açıklamak ve kullanıcının kuruluma geçmesini sağlamak.

```text
┌──────────────────────────────┐
│                              │
│          ◎  (logo)           │
│                              │
│          TPCM Find           │
│     Eşyalarını kolayca bul   │
│                              │
│     [mor illüstrasyon alanı] │
│                              │
│       [ Başlayalım → ]       │
└──────────────────────────────┘
```

**Eylem:** Başlayalım → İlk kurulum izinleri. Sonraki açılışlarda doğrudan Cihazlarım ekranı. İzin istemeden önce hangi izinlerin neden gerektiği açıklanır.

## 5. Sayfa 02 — İzinler ve ilk kurulum

**Başlık:** “Cihazlarını bulmaya hazır mısın?”

Üç izin kartı: **Yakındaki cihazlar/Bluetooth** (tarama ve bağlantı), **Konum** (son görülen yeri kaydetme; Android sürümüne göre gerekli izinler), **Bildirimler** (kopma uyarısı).

```text
┌──────────────────────────────┐
│ ← Kurulum                    │
│                              │
│  Cihazlarını bulmaya         │
│  hazır mısın?                │
│                              │
│  [Bluetooth]  İzin ver       │
│  [Konum]      İsteğe bağlı   │
│  [Bildirim]   İsteğe bağlı   │
│                              │
│      [ Devam Et ]            │
└──────────────────────────────┘
```

**Davranış:** Reddedilen izin için anlaşılır açıklama ve Ayarlar'a yönlendirme. Konum/bildirim izni olmadan temel Bluetooth yönetimi, Android sürümü izin verdiği ölçüde çalışmaya devam eder. Sistem Bluetooth kapalıysa açma çağrısı yapılır; sessizce açılmış varsayılmaz.

## 6. Sayfa 03 — Cihazlarım (ana ekran)

**Hedef:** Kayıtlı takip cihazlarını ve bağlantı durumlarını tek bakışta göstermek.

```text
┌──────────────────────────────┐
│ Cihazlarım             ＋  ♧ │
│ 3 kayıtlı cihaz             │
│                              │
│ ┌──────────────────────────┐ │
│ │ 🔑 Anahtar          ●    │ │
│ │ Bağlı · Yakında          │ │
│ │ Sinyal: İyi         ›    │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ 🎒 Çanta           ○    │ │
│ │ Son görülme: 2 dk önce  │ │
│ │ Bağlı değil        ›    │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ ＋ Yeni cihaz ekle        │ │
│ │ Yakındaki cihazları tara │ │
│ └──────────────────────────┘ │
│                              │
│ Cihazlar Keşfet Harita Ayar  │
└──────────────────────────────┘
```

**Kart içeriği:** Seçilen simge + takma ad + bağlantı durumu + varsa RSSI seviyesinin nitel göstergesi + varsa son görülme. Pil verisi yoksa pil sayısı gösterilmez. Bir karta bas → cihaz detayı. `+` → Keşfet. Boş durumda “Henüz kayıtlı cihazın yok” + “Cihaz ekle” çağrısı gösterilir.

**İsteğe bağlı hızlı eylem:** Cihaz bağlıysa ve ses özelliği doğrulandıysa kartın sağında küçük “Ses çal” simgesi; aksi durumda gizli/pasif.

## 7. Sayfa 04 — Keşfet / Tüm Bluetooth cihazları

**Hedef:** Telefonun bulabildiği yakındaki Bluetooth cihazlarını göstermek.

```text
┌──────────────────────────────┐
│ ← Bluetooth Cihazları   ↻   │
│                              │
│ [ Cihaz ara…             ]   │
│ [ Tümü | BLE | Klasik ]      │
│                              │
│ ● Tarama devam ediyor…      │
│                              │
│ ┌──────────────────────────┐ │
│ │ Anti-Lost Tag            │ │
│ │ BLE · Sinyal iyi         │ │
│ │               [ Bağlan ] │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ iTag_4F3D               │ │
│ │ BLE · Sinyal orta        │ │
│ │               [ Bağlan ] │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ Kablosuz Kulaklık        │ │
│ │ Klasik BT · Diğer cihaz  │ │
│ │              [ İncele ]  │ │
│ └──────────────────────────┘ │
│                              │
│ Cihazlar Keşfet Harita Ayar  │
└──────────────────────────────┘
```

**Liste tasarımı:** Cihazın yayınladığı ad (yoksa `İsimsiz cihaz`), tür (BLE/klasik), anlık RSSI seviyesi, kayıtlıysa `Kayıtlı` etiketi. Kimlik/adres bilgisi kullanıcıya yalnızca teknik ayrıntıda ve platform izin verdiğinde gösterilir.

**Teknik ayrım:** BLE cihazlarında GATT bağlantısı denenebilir; klasik cihazlarda uygun profil ve eşleştirme gereklidir. Kulaklık gibi alakasız cihazlar keşfedilebilir olsa da uygulama “desteklenen takip cihazı” olarak sunulmamalıdır. Liste **tüm erişilebilir cihazları** göstermeyi hedefler, **tüm cihazlarda ses çaldırmayı** değil.

**Durumlar:** Tarama var / sonuç yok / Bluetooth kapalı / izin yok / tarama hatası / cihaz zaten kayıtlı. Sonsuz tarama yerine zaman sınırlı oturum ve yeniden tara kullanılır.

## 8. Sayfa 05 — Bağlanıyor / Bağlantı sonucu

**Hedef:** Bağlantı işlemini anlaşılır, iptal edilebilir ve güvenilir kılmak.

```text
┌──────────────────────────────┐
│ ← Cihaz Ekle                │
│                              │
│         [ iTag simgesi ]     │
│         Anti-Lost Tag        │
│                              │
│          ◌ Bağlanıyor…      │
│    Cihazla iletişim kuruluyor│
│                              │
│         [ İptal Et ]        │
└──────────────────────────────┘
```

**Başarılı durum:** Yeşil onay → “Bağlantı başarılı” → “Cihazını kaydet” ekranı. **Başarısız durum:** “Bağlantı kurulamadı” → Yeniden dene / Cihaz listesine dön. **Uyumsuz cihaz:** “Bluetooth bağlantısı kurulabildi fakat iTag komutları desteklenmiyor” → `Genel Bluetooth cihazı olarak kaydet` seçeneği; takip cihazı özellikleri gösterilmez.

**Kritik:** Sadece taramada görünmek kayıtlı cihaz yapmaz. Cihaz **en az bir kez başarıyla bağlandıktan** sonra kaydedilir. Takip özelliklerinin kullanılabilirliği ayrıca doğrulanır.

## 9. Sayfa 06 — Cihazı ilk kez kaydet

```text
┌──────────────────────────────┐
│ ← Cihazını Kaydet           │
│                              │
│         [◇ etiket görseli]  │
│                              │
│ Cihaz adı                    │
│ [ Anahtar                 ]  │
│                              │
│ Bir simge seç                │
│ [🔑] [🎒] [👛] [🚗]         │
│ [🐾] [⭐] [📦] [🏷️]         │
│                              │
│       [ Kaydet ]            │
└──────────────────────────────┘
```

**Varsayılan ad:** Cihazın reklam adı veya `Yeni Cihaz`. **Kaydet:** Kalıcı kayıt oluştur, cihazı Cihazlarım'a ekle ve cihaz detayına geç. Takma ad yalnızca uygulama içinde değiştirilir; cihazın Bluetooth reklam adının değiştiği iddia edilmez.

## 10. Sayfa 07 — Cihaz Detayı

**Hedef:** Seçili cihazın merkez kontrol ekranı.

```text
┌──────────────────────────────┐
│ ← Anahtar               ✎   │
│                              │
│         [◇ cihaz görseli]   │
│            Anahtar           │
│        ● Bağlı · Yakında    │
│                              │
│ ┌──────────┐ ┌────────────┐ │
│ │ Sinyal   │ │ Pil        │ │
│ │ İyi      │ │ Bilinmiyor │ │
│ └──────────┘ └────────────┘ │
│                              │
│       [ 🔊 Ses Çaldır ]     │
│                              │
│ [📍 Son Görülen Konum     ›] │
│ [🔔 Kopma Uyarısı        ◉] │
│ [ⓘ  Cihaz Bilgileri      ›] │
│                              │
│ [ Cihazı Kaldır ]           │
└──────────────────────────────┘
```

**Ana buton durumları:** `Ses Çaldır` → komut başarısı doğrulanırsa `Sesi Durdur` veya süreli çalma gösterilir. Cihaz desteklemiyorsa `Ses çaldırma bu cihazda desteklenmiyor`; çevrimdışıysa `Önce bağlan` ve `Yeniden bağlan` gösterilir. Cihazın gerçekten ses çıkardığına dair geri bildirim alınamıyorsa “Komut gönderildi” şeklinde ihtiyatlı mesaj kullanılmalıdır.

**Alt kartlar:** Cihaz bilgileri (BLE servisleri, desteklenen işlevler, son bağlantı zamanı), Son görülen konum, Kayıp/kopma uyarısı anahtarı. İsteğe bağlı `Bağlantıyı kes` eylemi.

## 11. Sayfa 08 — Harita / Son Görülen Konum

**Hedef:** Telefonun kaydettiği son görülme konumunu anlaşılır biçimde sunmak.

```text
┌──────────────────────────────┐
│ ← Son Görülen Konum         │
│ ┌──────────────────────────┐ │
│ │                          │ │
│ │         HARİTA           │ │
│ │           📍             │ │
│ │                          │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ 🔑 Anahtar               │ │
│ │ Son görüldü: 11:06      │ │
│ │ Telefonun kayıt konumu   │ │
│ │   [ Yol Tarifi Aç ]      │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

**Tüm cihazlar haritası:** Harita sekmesinde konumu kayıtlı cihazların işaretleri gösterilir; kayıt olmayan cihazlar için “Bu cihaz için konum kaydı yok” durumu. **Cihaz haritası:** Tek cihazın pini + son görülme zamanı + harici navigasyonla yol tarifi. Konum izni yoksa izin isteme veya konumsuz devam seçeneği.

**Metin kuralı:** `Canlı konum`, `GPS ile izleniyor`, `kesin adres` ifadeleri kullanılmaz. Cihazdan konum alınmaz; telefonun kaydıdır.

## 12. Sayfa 09 — Kayıp Modu / Kopma Uyarıları

```text
┌──────────────────────────────┐
│ ← Kopma Uyarısı             │
│                              │
│              🔔             │
│      Bağlantı Uyarıları      │
│                              │
│ Bağlantı kesilince uyar  [●]│
│                              │
│ Uyarı yöntemi               │
│ [Bildirim] [Ses] [Titreşim]  │
│                              │
│ Son uyarı: Henüz yok        │
│                              │
│ ℹ Bluetooth arka plan       │
│ kısıtları nedeniyle uyarılar│
│ gecikebilir.                 │
└──────────────────────────────┘
```

**Davranış:** Kullanıcı bilinçli olarak kapatırsa uyarı gelmez. Beklenen bağlantı kesilmelerinde (kullanıcının `Bağlantıyı Kes` seçmesi) yanlış alarm verilmez. Eşik/gecikme opsiyonu daha sonra eklenebilir; sürekli zayıf sinyalle uyarı spam'i yapılmaz.

## 13. Sayfa 10 — Cihazı Düzenle

```text
┌──────────────────────────────┐
│ ← Cihazı Düzenle            │
│                              │
│         [◇ cihaz]           │
│                              │
│ Cihaz adı                    │
│ [ Anahtar                 ]  │
│                              │
│ Simge                        │
│ [🔑] [🎒] [👛] [🚗]         │
│ [🐾] [⭐] [📦] [🏷️]         │
│                              │
│        [ Kaydet ]           │
└──────────────────────────────┘
```

**Kurallar:** Ad boş olamaz; makul karakter sınırı (ör. 30) uygulanır. Kaydedince kartlar, bildirimler ve harita etiketleri güncellenir. Cihazı kaldırma işlemi ayrı bir kırmızı eylem ve onay penceresi kullanır: “Bu cihaz kayıtlı listenden kaldırılacak. Tekrar eklemek için yeniden bağlanman gerekir.”

## 14. Sayfa 11 — Cihaz Bilgileri

**Alanlar:** Kullanıcı adı, cihazın bildirdiği ad, cihaz türü (BLE/klasik), bağlantı durumu, son bağlanma, ilk eklenme, son görülen zaman, desteklenen işlevler (`Ses`, `Pil`, `Sinyal`, `Uyarı`), varsa firmware bilgisi. BLE servis UUID bilgisi “Teknik ayrıntılar” genişletilebilir alanında.

**Kural:** Bilgi okunamadıysa `Bilinmiyor` gösterilir; MAC gibi tanımlayıcılar gizlilik açısından gereksiz yere paylaşılmaz.

## 15. Sayfa 12 — Ayarlar

```text
┌──────────────────────────────┐
│ Ayarlar                      │
│                              │
│ Bildirimler ve Uyarılar   › │
│ Bluetooth / İzinler       › │
│ Tema                Koyu  › │
│ Dil                 Türkçe› │
│ Veri ve Gizlilik         ›  │
│ Hakkında          v1.0.0 › │
│                              │
│ Cihazlar Keşfet Harita Ayar  │
└──────────────────────────────┘
```

**Alt sayfalar:**

- **Bildirimler:** Global kopma bildirimi anahtarı, ses/titreşim ve her cihazın kendi tercihlerine bağlantı.
- **Bluetooth ve izinler:** Bluetooth açık/kapalı durumu; Android uygulama izinleri; izin reddedilirse sistem ayarları bağlantısı.
- **Tema:** Koyu / Açık / Sistem (ilk sürüm sadece koyu da olabilir).
- **Dil:** Türkçe (ileride İngilizce).
- **Veri ve gizlilik:** Cihaz kayıtlarının yerelde saklandığı açıklaması; cihaz kayıtlarını temizle; son görülme konum kayıtlarını sil.
- **Hakkında:** TPCM Find, sürüm, TPCM Studio, gizlilik politikası bağlantısı.

**Not:** Kullanıcı hesabı ve bulut yedekleme ilk sürüm için gerekli değil; gerçekten uygulanmadan arayüze eklenmemeli.

---

## 16. Ana kullanıcı akışları

### A. Yeni cihaz bağlama

```text
Cihazlarım → [+] → Keşfet → Tara → Cihaz seç
→ Bağlanıyor → [Başarılı]
→ Cihaz adını ve simgesini belirle → Kaydet
→ Cihazlarım + Cihaz Detayı
```

**Başarısızlık:** `Tekrar dene`, `Geri dön`, `İzinleri kontrol et`. **Uyumsuzluk:** Bağlanabilirse genel cihaz olarak kaydet; desteklenmeyen komutları gizle.

### B. Kayıtlı cihaza tekrar bağlanma

```text
Cihazlarım → [Çevrimdışı cihaz] → Cihaz Detayı
→ Yeniden Bağlan → Bağlandı → Kontroller aktif
```

### C. Cihazı öttürme

```text
Cihazlarım → Cihaz Detayı → Ses Çaldır
→ BLE komutu (uygunsa) → gönderim sonucu
→ Sesi Durdur / otomatik süre sonu
```

### D. Son görülen yeri bulma

```text
Cihazlarım → Cihaz Detayı → Son Görülen Konum
→ Harita → Yol Tarifi Aç
```

### E. Ad veya simge değiştirme

```text
Cihazlarım → Cihaz Detayı → Düzenle
→ Ad / Simge → Kaydet → Güncellenmiş cihaz kartı
```

## 17. Durum ve hata ekranları

| Durum | Kullanıcı metni | Eylem |
| --- | --- | --- |
| Hiç kayıtlı cihaz yok | “Henüz cihaz eklemedin.” | `Cihaz Ekle` |
| Tarama sonucu yok | “Yakında cihaz bulunamadı.” | `Yeniden Tara` |
| Bluetooth kapalı | “Cihazları taramak için Bluetooth'u aç.” | `Bluetooth'u Aç` |
| İzin yok | “Yakındaki cihazları bulmak için izin gerekli.” | `İzin Ver` |
| Bağlantı başarısız | “Cihazla bağlantı kurulamadı.” | `Tekrar Dene` |
| Cihaz çevrimdışı | “Bu cihaz şu anda bağlı değil.” | `Yeniden Bağlan` |
| Ses komutu desteklenmiyor | “Bu cihazda ses çaldırma kullanılamıyor.” | `Cihaz Bilgileri` |
| Konum kaydı yok | “Bu cihazın kaydedilmiş son konumu yok.” | `Geri Dön` |
| Pil verisi yok | “Pil bilgisi desteklenmiyor.” | — |
| Cihaz kaldırma | “Cihazı kayıtlı listenden kaldırmak istiyor musun?” | `Vazgeç` / `Kaldır` |

## 18. Veri modeli (öneri)

```kotlin
data class SavedDevice(
    val id: String,                 // Uygulama içi kalıcı UUID
    val transport: Transport,       // BLE veya CLASSIC
    val displayName: String,        // Kullanıcının verdiği isim
    val advertisedName: String?,    // Reklamda görülen ad
    val iconKey: String,
    val deviceIdentifier: String?,  // Platformun izin verdiği tanımlayıcı
    val firstConnectedAt: Long,
    val lastConnectedAt: Long?,
    val lastSeenAt: Long?,
    val lastLatitude: Double?,
    val lastLongitude: Double?,
    val alertOnDisconnect: Boolean,
    val supportedFeatures: Set<DeviceFeature>
)

enum class Transport { BLE, CLASSIC }
enum class DeviceFeature { PLAY_SOUND, STOP_SOUND, BATTERY, RSSI, ALERT }
```

**Veritabanı:** Room (yerel kayıtlar). **Tercihler:** DataStore. **Bluetooth:** Android Bluetooth APIs (BLE Scan + GATT; Classic discovery ve uygun profile göre bağlantı). **UI:** Jetpack Compose + Material 3. **Gezinme:** Navigation Compose. **Eşzamanlılık:** Kotlin Coroutines/Flow. **Konum:** Android location API, yalnızca izin ve özellik etkinse. **Harita:** Kullanılacak harita SDK'sı lisans/maliyet ve çevrimdışı gereksinimine göre ayrıca seçilir.

**Benzersiz kimlik notu:** Cihaz adresinin her koşulda kalıcı/değişmez olduğu varsayılmamalı; BLE random address kullanan cihazlarda eşleştirme ve yeniden keşif stratejisi gereklidir.

## 19. İlk sürüm (MVP) ve sonraki sürümler

### MVP — Önce tamamlanacak

- [ ] Karşılama ve Android izin akışları
- [ ] BLE ve klasik Bluetooth cihaz tarama listesi
- [ ] BLE bağlantı / bağlantı başarısızlığı durumları
- [ ] Başarıyla bağlanan cihazı kaydetme (Room)
- [ ] Kayıtlı cihazlar listesi ve yeniden bağlanma
- [ ] Cihaz takma adı / simgesi düzenleme ve kayıt silme
- [ ] Gerçek iTag donanımında doğrulanmışsa `Ses Çaldır`
- [ ] Bağlantı durumu ve gerçek RSSI bilgisi
- [ ] Boş / hata / izin ekranları

### V1.1 — Doğrulama ve izin gerektirenler

- [ ] Kullanıcı etkinleştirirse bağlantı kopma bildirimi
- [ ] İzinli son görülme konumu ve harita
- [ ] Destekleniyorsa pil verisi
- [ ] Arka plan davranışı ve pil optimizasyonu testleri

### Daha sonra

- [ ] Açık tema, İngilizce
- [ ] Widget / hızlı işlemler
- [ ] Cihaz gruplama / gelişmiş filtreler
- [ ] İhtiyaç varsa yedekleme

## 20. Geliştirme için kabul kriterleri

1. Kullanıcı tarama sonucunda hem BLE hem erişilebilir klasik cihazları uygun tür etiketiyle ayırt edebilmelidir.
2. Uygulama bir cihazı **başarılı bağlantı olmadan** “Kayıtlı cihazlarım”a eklememelidir.
3. Kaydedilen cihaz uygulama kapatılıp açıldığında adı ve simgesiyle görünmelidir.
4. `Kayıtlı` ve `Bağlı` durumları kullanıcıya karıştırılmadan sunulmalıdır.
5. Ses komutu yalnızca test edilip desteklendiği bilinen cihazlarda gösterilmelidir.
6. Bluetooth kapalı, izin reddedilmiş, cihaz bulunamamış ve bağlantı kopmuş senaryolarında net kullanıcı geri bildirimi olmalıdır.
7. Son konum yalnızca telefonun son kayıt konumu olarak etiketlenmeli, cihazın canlı konumu olduğu iddia edilmemelidir.
8. Ekranlar küçük Android telefonlarda taşmadan, büyük telefonlarda da aşırı genişlemeden görünmelidir.
9. Kullanıcının bir cihazı silmesi onay gerektirmeli ve kayıt veritabanından kalkmalıdır.
10. Gerçek Anti-Lost cihazında hangi GATT özelliklerinin çalıştığı test kaydında belgelenmelidir.

## 21. Tasarım görseli ve uygulama notu

Bu dokümanın ekran tarifleri, hazırlanan **TPCM Find koyu temalı çoklu ekran konseptindeki** görsel dili temel alır. Konsept resmindeki örnek pil yüzdeleri, bağlantı durumları ve harita verileri **temsili** olup gerçek cihazda doğrulanmış özellikler değildir. Tasarım uygulanırken yukarıdaki yetenek kontrol kuralları esas alınmalıdır.

**Önerilen geliştirme sırası:** Proje iskeleti ve tema → izinler → keşif → bağlantı → yerel kayıt → cihaz detayı → gerçek ses komutu testi → gelişmiş uyarı ve harita.
