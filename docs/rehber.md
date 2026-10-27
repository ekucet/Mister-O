# Mister-O rehberi

[English](guide.md) · **Türkçe** · [README](../README.tr.md)

Tam başvuru kaynağı: Staging target'ıyla kurulum, tüm komutlar, senaryo kataloğu, asistan, kayıt açma,
yapılandırma ve işleyiş. İki dakikalık başlangıç için [README](../README.tr.md)'ye bakın.

Gereksinimler: iOS 16 veya üzeri, Xcode 16 veya üzeri (Swift 6). Asistanın varsayılan modeli için iOS 26
ve Apple Intelligence gerekir.

## Kurulum

Paketi Swift Package Manager ile ekleyin ve **yalnızca Test/Staging hedefinize** bağlayın.
SDK, SwiftUI öğelerini görebilmek için private bir API kullanır (bkz. [SwiftUI desteği](#swiftui-desteği-ve-private-api));
bu yüzden App Store derlemesine kesinlikle girmemelidir.

**Xcode:** *File → Add Package Dependencies…* → `https://github.com/ekucet/Mister-O.git` →
*Dependency Rule* olarak `0.5.0`'dan itibaren *Up to Next Major Version* seçin → `MisterO`
kütüphanesini yalnızca staging hedefine ekleyin.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/ekucet/Mister-O.git", from: "0.5.0"),
],
targets: [
    .target(name: "MyAppStaging", dependencies: [
        .product(name: "MisterO", package: "Mister-O"),
    ]),
]
```

Ardından staging derlemesine bir derleme koşulu ekleyin; örneğin *Build Settings → Active
Compilation Conditions* içine `STAGING`.

> Çağrıları yalnızca `#if STAGING` ile sarmak yetmeyebilir: `-ObjC` gibi linker bayrakları
> kullanılmayan kodu da binary'ye taşıyabilir. Güvenli yol, paketi yalnızca staging hedefine bağlamaktır.

### Staging target'ı kurmak

Güvenli kurulum, aynı uygulamayı Mister-O ile birlikte derleyen ikinci bir uygulama target'ıdır. App Store
target'ı paketi hiç görmez. Staging target'ına **aynı bundle ID**'yi verin; böylece giriş, push
bildirimleri, Firebase ve uygulama içi satın almalar yeni bir ayar gerektirmeden çalışır. Bir cihazda o
zaman ya staging ya da mağaza derlemesi kurulu olur, ikisi birden olmaz.

**XcodeGen:** uygulama target'ının ayarlarını bir şablona taşıyın ve Mister-O'yu da bağlayan bir staging
target'ı ekleyin:

```yaml
packages:
  MisterO:
    url: https://github.com/ekucet/Mister-O.git
    from: 0.5.0

targetTemplates:
  App:
    type: application
    platform: iOS
    sources: [MyApp]
    # MyApp'te daha önce olan her şey: ayarlar, entitlements, diğer paketler…

targets:
  MyApp:
    templates: [App]
  MyAppStaging:
    templates: [App]
    scheme: {}
    dependencies:
      - package: MisterO
    settings:
      base:
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) STAGING
        INFOPLIST_KEY_CFBundleDisplayName: MyApp QA   # isteğe bağlı, iki derlemeyi ayırt etmek için
```

**Xcode:**

1. Uygulama target'ına sağ tıklayın → **Duplicate**. Kopyanın ve şemasının adını değiştirin (örneğin
   `MyApp Staging`).
2. Xcode `MyApp copy-Info.plist` oluşturduysa kopyanın *Info.plist File* ayarını orijinal dosyaya
   çevirin ve kopya dosyayı silin.
3. Kopyanın *General → Frameworks, Libraries, and Embedded Content* bölümüne `MisterO`'yu ekleyin.
   Orijinal target'ta olmadığından emin olun.
4. Kopyanın *Build Settings → Active Compilation Conditions* ayarına her yapılandırma için `STAGING`
   ekleyin.

Testçiler için staging şemasını çalıştırın ya da arşivleyin (Xcode ya da TestFlight'ın dahili
grupları). App Store için orijinal şemayı arşivleyin. Staging derlemelerini harici TestFlight
incelemesine göndermeyin: private API içerirler (bkz. [SwiftUI desteği](#swiftui-desteği-ve-private-api)).

Ardından paneli [README](../README.tr.md#hızlı-başlangıç)'deki gibi kodda kurun.

## Panelin kullanımı

Panelde üç sekme var:

| Sekme | Ne için |
|---|---|
| **Asistan** | [Yapay zekâ test asistanı](#yapay-zekâ-test-asistanı) o anki ekranı ya da tarif ettiğiniz kontrolü test eder |
| **Senaryolar** | [Senaryo kataloğunu](#senaryo-kataloğu) ve asistanın kaydettiği taslakları çalıştırır |
| **Gelişmiş** | Akışı elle yazar, koşu logunu okur ve ekrandaki öğeleri incelersiniz |

Asistanın modeli kullanılabiliyorsa panel Asistan sekmesiyle; değilse katalog tanımlıysa Senaryolar,
o da yoksa Gelişmiş sekmesiyle açılır. Gelişmiş sekmesinde akışı elle yazmak:

1. **Aç:** baloncuğa dokunun. Baloncuğu iki kenardan birine sürükleyebilirsiniz.
2. **Yaz:** akışı editöre yazın. Son yazılan akış kaydedilir ve uygulama yeniden açılınca geri gelir.
3. **Id'leri bul:** **Log**'dan **Öğeler**'e geçince o anki ekrandaki öğeler listelenir. Bir satıra dokunup
   onun için `tap`, `assertVisible` ya da `type` satırı ekleyebilirsiniz.
4. **Çalıştır:** **Çalıştır**'a basın. Akış önce kontrol edilir; bir satırda hata varsa hiçbir
   adım çalışmaz ve hata satır numarasıyla gösterilir.
5. **İzle:** panel bir ilerleme halkasına küçülür, uygulama görünür kalır. Canlı log için halkaya
   dokunun; durdurmak için **Durdur**'a basın.
6. **Sonucu oku:** koşu bitince panel açılır ve ilk başarısız adıma kayar. Kopyala butonu düz
   metin bir rapor kopyalar.

## Akış yazmak

| Komut | Örnek | Ne yapar |
|---|---|---|
| `tap` | `tap: "login_button"` | Öğeye tıklar |
| `type` | `type: "email_field" -> "merhaba"` | Alanı temizleyip metni yazar; `""` yalnızca temizler |
| `wait` | `wait: 2` | Verilen saniye kadar bekler (0–300, `1.5` ya da `1,5`) |
| `assertVisible` | `assertVisible: "welcome_label"` | Öğenin görünür olduğunu doğrular |
| `assertNotVisible` | `assertNotVisible: "error_label"` | Öğenin ekranda olmadığını doğrular (kaybolmasını bekler) |
| `assertEnabled` | `assertEnabled: "save_button"` | Öğenin aktif olduğunu doğrular |
| `assertDisabled` | `assertDisabled: "login_button"` | Öğenin pasif olduğunu doğrular |
| `assertText` | `assertText: "welcome_label" -> "Hoş geldin"` | Öğenin metninin verilen metni içerdiğini doğrular (büyük/küçük harf duyarsız) |
| `scroll` | `scroll: down` · `scroll: "settings_list" -> up` | Ekranın ana listesini ya da öğenin içinde durduğu listeyi bir sayfa kaydırır: `up`, `down`, `left` ya da `right` |
| `back` | `back` | Bir ekran geri gider ya da açık sayfayı veya uyarıyı kapatır |

**Yazım kuralları**

- Her satır bir adımdır. Boş satırlar ve `#` ile başlayan satırlar atlanır; satır sonunda
  ` # yorum` yazılabilir.
- Komut adları büyük/küçük harf duyarsızdır. YAML listesi gibi `- tap: ...` yazımı da çalışır.
- Değerler tırnaklı (`"..."`, `'...'`) ya da tırnaksız (`tap: Giriş Yap`) yazılabilir. `->` ya da
  ` #` içeren değerleri tırnaklayın. Tırnak içinde `\"`, `\\` ve `\n` kullanılabilir.
- Klavyenin akıllı tırnakları (“ ” ‘ ’) ve `→` oku kabul edilir.

**Öğe eşleştirme**

Sorgu, görünür her öğeyle şu sırayla karşılaştırılır. Birden çok öğe eşleşirse en güçlü
eşleşme, eşitlikte en öndeki öğe seçilir.

1. `accessibilityIdentifier` (tam eşleşme)
2. `accessibilityLabel`
3. Görünen metin: buton başlığı, label metni, text field içeriği ya da placeholder
4. Aynı metinler, büyük/küçük harf duyarsız

Yalnızca **görünür** öğeler eşleşir. Gizli view'lar, tamamen saydam view'lar ve scroll view
sınırının dışına kaymış view'lar, kaydırma onları ekrana getirene kadar sayılmaz (aşağıya bakın).

**Bekleme ve hatalar**

`tap`, `type` ve `assert…` komutları; öğe yokken, pasifken ya da metni farklıyken 5 saniyeye kadar her
200 ms'de bir yeniden dener. Hâlâ beklendiği gibi değilse adım başarısız olur, örneğin
`Ekranda bulunamadı: "welcome_label" (5.00 sn beklendi)`. Varsayılan olarak koşu ilk hatada durur
ve kalan adımlar "Atlandı" olarak işaretlenir.

**Kaydırma**

Öğe ekranda yoksa `tap`, `type` ve `assert…` komutları (`assertNotVisible` hariç) onu ana listede
kaydırarak arar: bir testçinin yapacağı gibi önce sayfa sayfa aşağı, sonra yukarı. Ana liste, üstü
kapalı olmayan en büyük kaydırılabilir alandır: `UIScrollView`, `UITableView`, `UICollectionView`,
SwiftUI `ScrollView` ya da `List`. Kaydırma 0,6 sn sonra başlar; böylece hâlâ yüklenen bir ekran
kaydırılıp kaçırılmaz. Liste kaydıkça süre de dolmaz. `configuration: .init(scrollsToFindElements: false)`
ile kapatabilirsiniz. Yatay bir carousel gibi diğer durumlar için `scroll` kullanın:
`scroll: "featured_carousel" -> right`.

**Uyarılar, onay pencereleri ve sayfalar**

Uyarı ve onay penceresi butonlarına (`UIAlertController`, SwiftUI `.alert` ve `.confirmationDialog`)
diğer butonlar gibi başlıklarıyla basılır:

```yaml
tap: delete_account_button
tap: "Sil"                  # uyarının butonu
assertText: account_status -> "Hesap silindi"
back                        # ayarlar ekranından çık
```

`back` navigasyonda bir geri gider. En üstte bir sheet, tam ekran sayfa ya da uyarı varsa onu kapatır
(uyarı hiçbir butona basılmadan kapanır). Geri gidilecek yer yoksa adım başarısız olur.

**Akışta test verisi**

`{{ad}}`, [`testData`](#test-verisi-ve-asistanın-hatırladıkları) içindeki `ad` değeriyle değişir:

```yaml
type: email_field -> {{Test hesabı e-postası}}
type: password_field -> {{Test hesabı şifresi}}
```

Şifre akışlara ve katalog JSON'una yazılmaz; raporlarda değer değil yer tutucu görünür. Adlar büyük/küçük
harf duyarsızdır. Bilinmeyen bir ad içeren akış çalışmaz; hata mesajı tanımlı adları listeler.

## Senaryo kataloğu

Testçi akışları elle yazmak yerine QA ekibinin önceden tanımladığı senaryoları çalıştırabilir.
Senaryoları bir JSON dosyasına koyun ve paneli o dosyaya yönlendirin:

```swift
.misterOTestPanel(
    scenarios: .remote(URL(string: "https://raw.githubusercontent.com/acme/qa-flows/main/mistero.json")!),
    resetApp: { appModel.resetToLogin() }
)
```

Testçinin yaptığı:

1. Paneli açar. **Senaryolar** sekmesinde tüm senaryolar adım sayıları ve etiketleriyle listelenir.
2. İsterse bir etiket seçer, örneğin `#smoke`.
3. **Tümünü çalıştır**'a ya da tek bir satırdaki ▶︎'e basar.
4. Panel küçülür, baloncukta senaryo ilerlemesi görünür, örneğin `3/20`.
5. Koşu bitince panel `17/20 başarılı · 3 başarısız · 2 dk 14 sn` gibi bir özet gösterir. Başarısız
   satırlarda ilk hata yazar. Bir satıra dokununca adımları, düştüğü andaki ekran görüntüsü,
   **Kayıt aç** ([takip aracı bağladıysanız](#kayıt-açmak-jira-linear-github-issues)), **Hata kaydı** ve
   **Paylaş** açılır; **Editöre al** onu editöre yükler. Kopyala butonu tüm suite raporunu kopyalar.
6. Senaryo ekran değiştiği için bozulduysa (butonun adı değişti, yeni bir alan geldi) başarısız
   satırdaki **Asistanla onar** onu asistana devreder. Bkz.
   [Başarısız bir senaryoyu onarmak](#başarısız-bir-senaryoyu-onarmak).

Başarısız bir senaryo ilk hatalı adımda durur, suite bir sonraki senaryoyla devam eder.

### Katalog biçimi

```json
{
  "scenarios": [
    {
      "id": "login-success",
      "name": "Başarılı giriş",
      "description": "Geçerli hesapla giriş yapar ve ana sayfayı doğrular.",
      "tags": ["smoke", "auth"],
      "goal": "Test hesabıyla giriş yap; ana sayfa açılmalı.",
      "steps": [
        "type: email_field -> {{Test hesabı e-postası}}",
        "type: password_field -> {{Test hesabı şifresi}}",
        "tap: login_button",
        "assertVisible: welcome_label"
      ]
    },
    {
      "name": "Hoş geldin mesajı",
      "tags": ["auth"],
      "flow": "tap: login_button\nassertVisible: 'Hoş geldin, tester@example.com'"
    }
  ]
}
```

| Alan | Zorunlu | Anlamı |
|---|---|---|
| `name` | evet | Listede görünen ad |
| `steps` ya da `flow` | evet | Akış: satırlardan oluşan bir dizi ya da çok satırlı tek bir metin |
| `id` | hayır | Kalıcı kimlik. Yoksa `name`'den türetilir |
| `description` | hayır | Adın altında görünen kısa açıklama |
| `tags` | hayır | Filtrelemek ve bir alt kümeyi çalıştırmak için |
| `reset` | hayır | `false` ise bu senaryodan önce `resetApp` çağrılmaz. Varsayılan `true` |
| `goal` | hayır | Senaryonun neyi kanıtlaması gerektiği, düz cümleyle. Adımlar artık çalışmadığında asistan senaryoyu buna göre onarır |

JSON metinlerinin içinde `"` kaçışıyla uğraşmamak için tırnaksız değer (`tap: login_button`) ya da
tek tırnak (`'Hoş geldin, …'`) kullanın. Katalog yüklenirken kontrol edilir. Yazım hatası olan
senaryo kırmızıyla işaretlenir, çalıştırılamaz ve **Tümünü çalıştır**'a dahil edilmez.

### Katalog nereden gelir

| Kaynak | Ne için |
|---|---|
| `.remote(url, headers:)` | GitHub raw dosyaları, gist'ler, S3, kendi sunucunuz |
| `.bundled("ad")` | Staging uygulamasının içine konan `ad.json` |
| `.inline([Scenario])` | Kodda tanımlanan senaryolar |
| `.custom(name:cacheKey:) { … }` | Diğer her şey: Firebase Remote Config, kendi API'niz… |

`.remote` ile en son başarıyla yüklenen katalog cihazda saklanır. Kaynağa ulaşılamazsa testçi
önbellekteki listeyi **Çevrimdışı** etiketiyle görür. Yenile butonu kataloğu yeniden yükler.

Özel bir repo için token'ı `headers: ["Authorization": "Bearer …"]` ile verin. Staging derlemesindeki
her şey dışarı çıkarılabilir; bu yüzden yalnızca o repoyu okuyabilen bir token kullanın.

### Her senaryoyu bilinen bir durumdan başlatmak

Suite'teki senaryolar art arda çalışır. Önlem alınmazsa 2. senaryo, 1. senaryonun bıraktığı ekrandan
başlar. `resetApp` her senaryodan önce çalışır (senaryoda `"reset": false` yoksa) ve uygulamayı
senaryoların beklediği duruma getirmelidir; örneğin navigasyonu köke almak ve oturumu kapatmak:

```swift
.misterOTestPanel(scenarios: catalog, resetApp: {
    router.path = []
    await session.signOut()
})
```

Reset'ten sonra Mister-O ekranın oturması için 0,6 sn bekler. `resetApp` vermezseniz kataloğu, her
senaryo bir öncekinin bittiği yerden devam edecek şekilde sıralayın.

## Otomatik koşu

Senaryolar kimse paneli açmadan koşabilir: uygulama açılınca, CI'da her PR'da ya da QA katalogdan açtığında.
Sonuçlar konsola, dosyalara ve Slack'e gider; düşen senaryolar kayda dönüşür ve aynı kayıt ikinci kez
açılmaz.

### Koşuyu başlatmak

Koşuyu başlatmanın üç yolu var; ilk bulunan geçerlidir:

| Nerede | Örnek | Ne için |
|---|---|---|
| Başlatma argümanı ya da ortam değişkeni | `-MisterOAutorun "#smoke"` · `MISTERO_AUTORUN=#smoke` | CI, Xcode şeması |
| Kurulumda `autorun:` | `.misterOTestPanel(autorun: .tags("smoke"))` | QA derlemesinin her açılışı |
| Katalogda `"autorun"` | `{ "autorun": "#smoke", "scenarios": [ … ] }` | QA, yeni derleme gerekmeden GitHub'dan açıp kapatır |

Seçim `all`, `#etiket` ya da virgülle ayrılmış senaryo kimlikleridir: `"#smoke, checkout-paypal"`.
Katalogda nesne de olabilir: `{ "tags": ["smoke"], "ids": ["checkout-paypal"] }`. Mister-O kataloğu
bekler, ilk ekrana bir saniye tanır, sonra seçimi suite olarak koşar; baloncuk ilerlemeyi elle başlatılmış
bir koşudaki gibi gösterir.

| Değişken | Argüman | Etkisi |
|---|---|---|
| `MISTERO_EXIT=1` | `-MisterOExit YES` | Koşu raporlanınca uygulamayı kapatır. Senaryo düştüyse çıkış kodu 1, hiçbiri eşleşmediyse 2 |
| `MISTERO_TICKETS=0` | | Bu koşuda kayıt açılmaz |

### Sonuçlar

Otomatik ya da **Tümünü çalıştır** ile başlatılmış her suite bir rapor üretir:

- **Konsol:** `MISTERO-RESULT-BEGIN` ile `MISTERO-RESULT-END` arasında.
- **Dosyalar:** uygulamanın `Documents/MisterO/results` klasöründe `junit.xml`, `report.json`, `summary.md`
  ve `summary.txt`.
- **`resultReporters`:** raporun gönderileceği diğer yerler.

```swift
.misterOTestPanel(
    resultReporters: [SlackResultReporter(webhookURL: URL(string: "https://hooks.slack.com/services/…")!)]
)
```

```
Mister-O · 4/5 passed · 19.66 s · autorun · #smoke
iPhone (Simulator) · iOS 27.0 · app.mistero.demo 1.0 (1)
✗ Kampanya bandı — Line 1: Not on screen: "campaign_banner" (waited 5.00 s) → ticket: QA-71 https://…/QA-71
```

`SlackResultReporter` bu metni bir Slack Incoming Webhook'una gönderir; Mattermost ve Discord'un `/slack`
adresi de aynı biçimi kabul eder. `onlyFailures: true` her şey geçerken sessiz kalır. `WebhookResultReporter`
raporun tamamını JSON olarak gönderir (`total`, `passed`, `failed` ve her senaryonun sonucu, hatası ve
kaydıyla `items`). Başka bir yer için `ResultReporter`'a uyun.

### Tekrarsız kayıt

Otomatik koşuda düşen her senaryo, panelin de kullandığı `issueReporter` ile kayda dönüşür; rapor kayda
bağlantı verir. Zaten kayıtlı bir hata ikinci kez kayıt açmaz:

- Her hatanın bir **parmak izi** vardır: senaryonun kimliği ve düştüğü adım. Dil ve süre onu değiştirmez.
- `JiraIssueReporter` kayıtlara `mistero` ve `mistero-<parmak izi>` etiketlerini koyar ve önce bu etiketle
  açık bir kayıt arar. Biri kaydı kapatır da hata geri gelirse yeni kayıt açılır.
- `WebhookIssueReporter` gövdede `fingerprint` gönderir; otomasyonunuz onunla arayabilir. Jira
  Automation'da *Create issue*'dan önce `labels = mistero-{{webhookData.fingerprint}}` ile bir *Lookup issues*
  eylemi ekleyin. Cihaz da her parmak izi için açtığı kaydı 7 gün hatırlar.

Paneldeki **Kayıt aç** da aynı kontrolden geçer; kayıt varsa *Zaten kayıtlı: QA-42* der.

### CI'da (GitHub Actions)

Staging uygulamasını simülatör için derleyin ve bu repodaki action'a verin:

```yaml
jobs:
  ui-scenarios:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - name: Staging uygulamasını derle
        run: |
          xcodebuild build -project MyApp.xcodeproj -scheme MyAppStaging \
            -destination "generic/platform=iOS Simulator" -derivedDataPath build
      - name: Mister-O senaryoları
        uses: ekucet/Mister-O/ci@0.5.0
        with:
          app: build/Build/Products/Debug-iphonesimulator/MyAppStaging.app
          scenarios: "#smoke"
          env: |
            SLACK_WEBHOOK=${{ secrets.SLACK_WEBHOOK }}
```

Action en yeni iPhone simülatörünü seçer, uygulamayı kurar ve `MISTERO_AUTORUN` ile `MISTERO_EXIT` vererek
başlatır. Ardından sonuç dosyalarını ve konsol günlüğünü `mistero-results/`'a kopyalar, tabloyu iş
özetine ekler ve bir senaryo düştüyse işi başarısız sayar.

| Girdi | Varsayılan | Anlamı |
|---|---|---|
| `app` | zorunlu | Simülatör için derlenmiş staging uygulaması |
| `scenarios` | `all` | `all`, `#etiket` ya da kimlikler |
| `bundle-id` | uygulamadan | |
| `device` | en yeni iPhone | Simülatör UDID'si ya da adı |
| `timeout` | `900` | Uygulama durdurulmadan önceki saniye |
| `results` | `mistero-results` | Sonuç klasörü |
| `open-tickets` | `true` | Düşenler için uygulamanın `issueReporter`'ıyla kayıt aç |
| `env` | | Uygulamaya verilecek ek ortam değişkenleri, satır başına `KEY=VALUE` |

Çıktılar: `total`, `passed`, `failed`, `results`. `env`'deki değişkenler uygulamaya ortam değişkeni olarak
ulaşır; paneli kurduğunuz yerde okuyun, örneğin `ProcessInfo.processInfo.environment["SLACK_WEBHOOK"]`.
Dosyaları saklamak isterseniz `results` klasörünü `actions/upload-artifact` ile yükleyin. Aynı betik
yerelde de çalışır:

```bash
INPUT_APP=build/Build/Products/Debug-iphonesimulator/MyAppStaging.app INPUT_SCENARIOS="#smoke" ci/run.sh
```

Bu reponun kendi CI'ı demo'nun `#smoke` senaryolarını bu şekilde koşar. Asistan henüz CI'da koşamıyor:
Apple'ın modeli simülatörde çalışmıyor.

## Yapay zekâ test asistanı

> **Not:** Asistan döngüsü, rapor ve demo akışı test edildi. Apple'ın cihaz içi modeli henüz bir
> cihazda uçtan uca çalıştırılmadı (bkz. [Durum](#durum)).

Paneli herhangi bir ekranda açın ve **Asistan** sekmesine geçin. İki şekilde başlayabilirsiniz:

- **Bu ekranı test et:** Asistan ekrandaki öğelere bakar ve en fazla dört kontrolü kendisi planlar;
  örneğin *"Boş formla giriş yapılamamalı"*, *"Geçersiz bilgilerle giriş yapılamamalı"*, *"Geçerli
  bilgilerle giriş yapılabilmeli"*. Önce bir odak da verebilirsiniz, örneğin *"sadece şifre alanı"*.
- **Kontrolü tarif edin:** *ya da tarif edin…* alanına kendi cümlenizle yazın:
  *"Alanları doldur, Devam'a bas; sonraki ekran açılmalı, açılmazsa fail."*
  Ne olması gerektiğini söyleyen kısım (Türkçede *-malı/-meli*, İngilizcede *should/must*) beklenen
  sonuç olur. Asistan alanları her birine uyan verilerle doldurur, butona basar ve sonucu doğrular.
  Bunun için akış yazmanız gerekmez.

Sonra:

1. Asistan kontrolleri kendisi koşar; bu sırada panel bir ilerleme baloncuğuna küçülür. Her kontrolden
   önce açık sayfaları kapatıp navigasyonu geri alarak başlangıç ekranına döner; son çare olarak
   `resetApp`'i kullanır.
2. Kısa bir rapor çıkar, örneğin `3 kontrol · 2 geçti · 1 sorun`.
3. Raporla devam edersiniz:
   - **Sorun:** Bir takip aracı [bağladıysanız](#kayıt-açmak-jira-linear-github-issues) **Kayıt aç (Jira)**
     kaydı açar. **Hata kaydı** adımları, beklenen ve gerçekleşen sonucu ve cihaz bilgisini kopyalar;
     **Paylaş** istediğiniz yere gönderir.
   - **Bilgi bekliyor:** Asistan uyduramayacağı bir veriyi sorar, örneğin *"Geçerli bir e-posta ve
     şifre verir misiniz?"* Cevap verince kontrol yeniden koşar; cevabınız hatırlanır.
   - **Geçti:** **Taslağa kaydet** kontrolü taslak senaryoya çevirir. Taslaklar Senaryolar sekmesinde
     hemen görünür ve QA lead'e katalog JSON'u olarak paylaşılabilir.
   - **Şunu da dene:** Yeni bir kontrolü tarif edin, asistan onu da koşsun.

Demo'nun giriş ekranında asistan, demo uygulamadaki gerçek bir hatayı buluyor: e-posta kontrolü
yalnızca "@" işaretine baktığı için "a@" ile giriş yapılabiliyor. Demo test hesabını
[`testData`](#test-verisi-ve-asistanın-hatırladıkları) olarak verdiği için asistanın soru sormasına
gerek kalmıyor:

```
Mister-O asistan raporu · 3 kontrol · 2 geçti · 1 sorun
✓ Boş formla “Giriş Yap” çalışmamalı
    Boş formda Giriş Yap pasif kalıyor.
✗ Geçersiz bilgilerle “Giriş Yap” çalışmamalı
    Geçersiz e-postayla (a@) giriş yapılabildi; ana sayfa açıldı.
✓ Geçerli bilgilerle “Giriş Yap” çalışmalı
    Giriş yapıldı, ana sayfa açıldı.
```

### Test verisi ve asistanın hatırladıkları

Asistan sıradan alanları gerçekçi verilerle kendisi doldurur. Mister-O her metin alanının ne tür bir
girdi beklediğini `textContentType`, `keyboardType` ve `isSecureTextEntry`'den okuyup modele söyler:
`email`, `password`, `phone`, `number`, `name`, `username`, `code`, `url`, `postal code`, `address` ya da
`text`. Kayıt formuna `qa+4821@example.com` gibi benzersiz bir adres yazılır; olumsuz bir kontrolde ise
bilerek `a@` gibi değerler denenir.

Asistan yalnızca sisteminizde önceden var olması gereken verileri sorar: mevcut bir hesap ve şifresi,
doğrulama kodu, sipariş numarası. Bunları baştan `testData` ile verin:

```swift
.misterOTestPanel(
    testData: [
        "Test hesabı e-postası": "qa@acme.com",
        "Test hesabı şifresi": "…",
    ]
)
```

Anahtarlar modelin okuduğu açıklamalar, değerler yazacağı verilerdir. **Bildiklerim** altında kilit
simgesiyle listelenirler. Testçinin sohbette verdiği cevaplar cihazın Keychain'inde saklanır; sonraki
kontrollerde ve uygulama yeniden açıldığında da kullanılır. **Unut** birini, **Hepsini unut** tüm
cevapları siler. `testData`'daki her şey staging derlemesinin içine girer; yalnızca test hesapları
kullanın.

### Başarısız bir senaryoyu onarmak

Bir senaryo, örneğin bir butonun adı değiştiği ya da yeni bir alan eklendiği için başarısız olursa
Senaryolar sekmesindeki satırında **Asistanla onar** çıkar. Asistan senaryonun `goal` alanını (yoksa
adını ve açıklamasını) ve ipucu olarak eski adımları alır; senaryo `resetApp` kullanıyorsa uygulamayı
reset'ler ve amaca o anki ekranda ulaşmaya çalışır.

Kontrol geçerse **Senaryoyu güncelle** yeni adımları kaydeder. Taslak olduğu yerde güncellenir.
Katalogdaki bir senaryo içinse "… (onarıldı)" adında, `onarıldı` etiketli bir taslak kopya oluşur;
çünkü kataloğun kendisi sizin reponuzda durur. **Taslakları paylaş** ile gönderip kataloğa ekleyin.
Kontrol bunun yerine sorun bildirirse senaryo büyük ihtimalle gerçek bir hata yakalamıştır; rapordan
kayıt açabilirsiniz.

### Kayıt açmak (Jira, Linear, GitHub Issues…)

Bir `issueReporter` verirseniz asistan raporundaki her sorunda ve Senaryolar sekmesindeki her düşen
senaryoda **Kayıt aç** butonu çıkar. Açılan kaydın anahtarı ve bağlantısı yanında görünür, örneğin
*Kayıt açıldı: QA-42*. Her sorun bir kez açılır; açılamazsa hata gösterilir ve testçi yeniden deneyebilir.

Düşen senaryonun kaydı; koşan adımları (düşeni hatasıyla), beklenen sonuç olarak senaryonun `goal`'ünü
(yoksa açıklamasını) ve düştüğü anda, sıradaki senaryonun reset'inden önce alınan ekran görüntüsünü içerir.

Bir kontrol sorunla bittiğinde ya da bir senaryo düştüğünde Mister-O uygulamanın anahtar penceresinin ekran görüntüsünü alır.
Mister-O'nun kendi paneli ve baloncuğu görüntüye girmez. Sorun kartında küçük resim olarak görünür ve
takip aracına `BugReport.attachments` içinde `screenshot.png` olarak gider.

Hazır gelen `WebhookIssueReporter`, hata kaydını seçtiğiniz bir URL'ye JSON olarak gönderir:

```swift
.misterOTestPanel(
    issueReporter: WebhookIssueReporter(
        name: "Jira",                                        // buton başlığı: "Kayıt aç (Jira)"
        url: URL(string: "https://hooks.example.com/mistero")!,
        headers: ["Authorization": "Bearer …"]               // isteğe bağlı
    )
)
```

```json
{
  "title": "Geçersiz bilgilerle “Giriş Yap” çalışmamalı: beklenen davranış görülmedi",
  "steps": ["type: email_field -> a@", "type: password_field -> 123456", "tap: login_button"],
  "expected": "Hata görünmeli ya da “Giriş Yap” pasif kalmalı; ekran değişmemeli.",
  "actual": "Geçersiz e-postayla (a@) giriş yapılabildi; ana sayfa açıldı.",
  "environment": "iPhone (Simülatör) · iOS 27.0 · app.mistero.demo 1.0 (1)",
  "description": "Aynı rapor düz metin olarak, kaydın gövdesine hazır",
  "attachments": [
    { "filename": "screenshot.png", "mimeType": "image/png", "data": "iVBORw0KGgoAAAANSUhEUg…" }
  ]
}
```

`data` dosyanın base64 hâlidir; ekran görüntüsü yoksa `attachments` boş gelir. Diğer alanlar öncekiyle
aynıdır. Ekran görüntüsü gövdeyi epey büyütür; webhook'unuz bunu kaldıramıyorsa
`includesAttachments: false` verin.

Cevap `key` ve `url` (ya da Jira'nın `self`) alanları olan bir JSON ise rapor kayda bağlantı verir.
Webhook'u nereye yönlendirebilirsiniz:

- **Jira:** *Incoming webhook* tetikleyicili ve `{{webhookData.title}}`, `{{webhookData.description}}`
  kullanan bir *Create issue* eylemli Automation kuralı. Automation kural koşmadan cevap verdiği için
  raporda anahtar olmadan *Kayıt açıldı* yazar. Automation base64 ekran görüntüsünü eke çeviremez; bu
  yolda kayıt ekran görüntüsü olmadan açılır.
- **Zapier, Make ya da n8n:** Linear, GitHub Issues, Azure DevOps ya da başka bir yerde kayıt açan bir
  webhook tetikleyicisi.
- **Kendi sunucunuz:** takip aracının API'siyle kaydı açar, `attachments`'ı yükler ve
  `{"key": …, "url": …}` döner. Uygulamaya token koymadan ekran görüntüsünü Jira'ya taşımanın yolu budur.

Webhook, takip aracının kimlik bilgilerini uygulamanın dışında tutar: staging derlemesindeki her şey
dışarı çıkarılabilir, webhook ise yalnızca kayıt açabilir. Önerilen yol bu yüzden webhook'tur.

#### Doğrudan Jira Cloud'a

`JiraIssueReporter` isteğe bağlıdır; Jira Cloud REST API v3'ü uygulamanın içinden çağırır:

```swift
#if STAGING
.misterOTestPanel(
    issueReporter: JiraIssueReporter(
        baseURL: URL(string: "https://firmaniz.atlassian.net")!,
        projectKey: "QA",
        issueType: "Bug",                                    // kayıt türünün projedeki adı
        authorization: JiraIssueReporter.basicAuthorization(email: "mistero-bot@firmaniz.com",
                                                            apiToken: "…")
    )
)
#endif
```

1. `POST /rest/api/3/issue` kaydı açar. Özet raporun başlığıdır; açıklama (Atlassian Document Format)
   adımları, beklenen ve gerçekleşen sonucu ve cihazı listeler.
2. `POST /rest/api/3/issue/{key}/attachments` (`X-Atlassian-Token: no-check` ile) ekran görüntüsünü
   yükler.

Rapor `…/browse/QA-42`'ye bağlantı verir. Jira kaydı reddederse (yanlış proje anahtarı ya da kayıt
türü gibi) hata Jira'nın yazdığı gibi gösterilir. Yalnızca yükleme düşerse kayıt yine açılmış sayılır;
ikinci dokunuş aynı kaydı tekrar açmaz ve rapor nedeni anahtarın altında yazar. `authorization`,
`Authorization` başlığının tam değeridir; `Bearer …` da olur. Jira Data Center'da REST v3 yoktur; orada
webhook kullanın.

> [!WARNING]
> Token uygulamanın içine girer. Staging derlemesindeki her şey dışarı çıkarılabilir: binary, içindeki
> metinler, ortam değişkenleri, Keychain. Token'ı ele geçiren, o hesabın Jira'da yapabildiği her şeyi
> yapabilir; yalnızca kayıt açmakla kalmaz. Webhook'u tercih edin. `JiraIssueReporter` kullanacaksanız
> yalnızca o projede kayıt açabilen ayrı bir hesabın token'ını verin, release derlemelerine sokmayın ve
> bir derleme dışarı sızarsa token'ı iptal edin.

Başka takip araçları için `IssueReporter`'a uyun. Ekran görüntüsü `report.attachments`'tadır:

```swift
struct LinearReporter: IssueReporter {
    let name = "Linear"

    func open(_ report: BugReport) async throws -> IssueReceipt {
        // report.title ve report.text ile kaydı açın, report.attachments'ı yükleyin;
        // anahtarını ve bağlantısını döndürün.
    }
}
```

`issueReporter` vermezseniz testçi yine **Hata kaydı** ve **Paylaş**'ı kullanabilir.

### Küçük bir modelle nasıl güvenilir kalır

- **Seçenekler yalnızca ekrandan:** Guided generation, eylemi `tap`, `type`, dört `assert…` komutu,
  `scroll`, `back`, `ask`, `pass`, `issue` ve `blocked` ile; hedefi de o an ekranda bulunan öğelerle
  sınırlar. Model id uyduramaz ya da hatalı satır yazamaz.
- **Göremediğini kaydırarak arar:** Liste yalnızca ekrandakileri gösterir. Aradığı öğe listede yoksa
  (uzun bir formun altındaki gönder butonu gibi) model aşağı ya da yukarı kaydırıp yeniden bakar. Yeni
  bir şey göstermeyen kaydırma başarısız adım sayılır; böylece model sona geldiğinde kaydırmayı
  sürdürmez. `back` bir ekran geri gider ya da açık sayfayı kapatır.
- **Durumu görür:** Her öğe türüyle, pasif olup olmadığıyla ve metin alanlarında o anki değeriyle gelir.
- **Her seferinde tek adım:** Her tur kısa bir özetle yeni bir oturum açar; böylece küçük bağlam
  penceresi (iOS 26'da 4.096 token) dolmaz.
- **Her şey çalıştırılır:** Her adım gerçekten koşar. Başarısız adımlar modele geri bildirilir. Bir
  kontrol üst üste üç başarısız adımda ya da toplam sekiz adımda durur. Her adımdan sonra ekranın
  oturması için 0,7 sn beklenir.
- **Yedek plan:** Model plan döndürmezse ya da özel bir model planlama yapmıyorsa, kural tabanlı bir
  planlayıcı tipik form kontrollerini önerir.

### Taslaklar ve reset

Kaydedilen kontrol, `taslak` ve `asistan` etiketli bir taslak senaryo olur. Test uygulamanın kök
ekranında başladıysa ve `resetApp` verdiyseniz, taslak koşmadan önce uygulamayı reset'ler. Aksi hâlde
"reset yok" olarak işaretlenir ve kaydedildiği ekrandan koşturulmalıdır. Kontrolün tarifi taslağın
`goal` alanında saklanır; böylece taslak sonradan [onarılabilir](#başarısız-bir-senaryoyu-onarmak).
Asistanın `testData`'dan yazdığı değerler taslağa `{{ad}}` yer tutucusu olarak kaydedilir; taslaklar
şifre taşımaz.

### Gereksinimler

Varsayılan model Apple'ın cihaz içi modelidir (Foundation Models). iOS 26 veya üzeri, Apple
Intelligence destekleyen bir cihaz ve açık Apple Intelligence gerekir. Model kullanılamıyorsa sekme
nedenini açıklar. Türkçe desteklenen diller arasında. Her şey cihazda çalışır: API anahtarı, internet
ya da ücret yok.

### Başka bir model kullanmak

`FlowAssistantModel` protokolüne uyan herhangi bir tipi verebilirsiniz; örneğin daha büyük bir modele
giden şirket içi bir proxy. `plan(for:)` ve `check(for:context:)` isteğe bağlıdır; yazılmazsa kural
tabanlı planlayıcı ekranı planlar ve tarif edilen kontrolü bir başlığa ve beklenen sonuca çevirir.

```swift
struct ProxyModel: FlowAssistantModel {
    var availability: AssistantAvailability { .available }

    func plan(for context: PlanContext) async throws -> [PlannedCheck] {
        // context.prompt'u servisinize gönderip cevabı eşleyin.
    }

    func check(for request: String, context: PlanContext) async throws -> PlannedCheck {
        // Testçinin cümlesini bir başlığa ve beklenen sonuca çevirin.
    }

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        // context.prompt ve context.targets'ı servisinize gönderip cevabı eşleyin.
    }
}

.misterOTestPanel(assistantModel: ProxyModel())
```

Uzak bir model kullanırsanız ekrandaki öğe adları ve testçinin cevapları cihazdan çıkar.

### Durum

- Asistan (plan sırası, sorunlar, soru ve yeniden koşma, başlangıç ekranına dönüş, durdurma, hata
  kaydı, taslaklar, tarif edilen kontroller, hatırlanan bilgiler, onarım, kayıt açma, ekran görüntüsü)
  sahte bir modelle birim testleriyle kapsanıyor. `WebhookIssueReporter` ve `JiraIssueReporter`'ın
  gönderdiği istekler birim testleriyle doğrulanıyor; `JiraIssueReporter` henüz gerçek bir Jira
  sitesinde denenmedi.
- iOS 27 simülatöründe demo'nun kural tabanlı modeli (`MISTERO_ASSISTANT=demo`) tüm döngüyü koştu:
  `testData` sayesinde soru sormadan üç kontrol, "a@" hatasının bulunması ve yerel bir webhook üzerinden
  kayda çevrilmesi, tarif edilen bir "alanları doldur, devam et" kontrolü, kaydedilip koşturulan
  taslaklar ve başarısız bir katalog senaryosunun "(onarıldı)" taslağına onarılması.
- Apple modelinin cevaplarını ayrıştırma ve şemaları kurma, model olmadan birim testleriyle doğrulanıyor.
  Gerçek modeli çağıran iki entegrasyon testi, model yoksa atlanıyor.
- iOS simülatörü modeli "kullanılabilir" olarak bildiriyor, ancak üretim Apple'ın güvenlik filtresinden
  "Simulator is not supported" hatasıyla düşüyor; bu yüzden gerçek model bir cihazda denenmeli.

## Uygulamanızı test edilebilir yapmak

Id'ler, metin ya da dil değişse bile akışları sağlam tutar:

```swift
// SwiftUI
TextField("E-posta", text: $email)
    .accessibilityIdentifier("email_field")
Button("Giriş Yap", action: signIn)
    .accessibilityIdentifier("login_button")
```

```swift
// UIKit
emailField.accessibilityIdentifier = "email_field"
```

Görünen metinle eşleştirme (`tap: "Giriş Yap"`) de çalışır, ancak metin ya da cihaz dili
değişince bozulur.

## Yapılandırma

```swift
.misterOTestPanel(
    initialScript: "tap: \"login_button\"",          // panel ilk açıldığında editörde görünür
    scenarios: .bundled("mistero-scenarios"),        // senaryo kataloğu (yukarıya bakın)
    resetApp: { router.path = [] },                  // her senaryodan önce çalışır
    assistantModel: nil,                             // nil = iOS 26+'da Apple'ın cihaz içi modeli
    testData: ["Test e-postası": "qa@acme.com"],     // asistanın uyduramayacağı veriler
    issueReporter: WebhookIssueReporter(url: hook),  // sorunlarda "Kayıt aç" butonu
    autorun: .tags("smoke"),                         // açılışta koş (bkz. Otomatik koşu)
    resultReporters: [SlackResultReporter(webhookURL: slack)], // suite sonuçlarının gideceği yer
    language: nil,                                   // nil = cihazın dili; ya da .turkish, .english
    configuration: .init(
        elementTimeout: .seconds(8),                 // öğe başına bekleme (varsayılan 5 sn)
        pollInterval: .milliseconds(200),            // ekranın yeniden taranma aralığı
        delayBetweenSteps: .milliseconds(400),       // adımlar arası kısa ara
        stopOnFailure: true,                         // false ise hatadan sonra devam eder
        scrollsToFindElements: true                  // öğeyi bulmak için ana listeyi kaydır
    ),
    enablesSwiftUIAccessibility: true                // yalnızca UIKit kullanan uygulamalarda false
)
```

`MisterO.install(in:initialScript:scenarios:resetApp:assistantModel:testData:issueReporter:autorun:resultReporters:language:configuration:enablesSwiftUIAccessibility:)`
aynı parametreleri alır. `MisterO.uninstall()` paneli kaldırır ve erişilebilirlik ayarını eski haline döndürür.

### Dil

Panel, asistanın raporu ve mesajları, hata kayıtları, takip aracında açılan kayıtlar ve akış hataları
Türkçe ya da İngilizcedir. Mister-O cihazın dilini izler; desteklenmeyen bir dilde İngilizceye döner.
Bir dili sabitlemek için `language:` verin; örneğin Türk bir QA ekibi İngilizce bir derlemeyi test
ederken:

```swift
.misterOTestPanel(language: .turkish)
```

Asistanın modeline kontrolleri ve mesajları aynı dilde yazması söylenir; kaydettiği taslakların
etiketleri de bu dildedir (`taslak`, `asistan`, `onarıldı` ya da `draft`, `assistant`, `repaired`).
Yeni bir dil eklemek için anahtarları İngilizce metin olan
`Sources/MisterOCore/Resources/<kod>.lproj/Localizable.strings` dosyasını ve `MisterOLanguage`'a bir
`case` ekleyin.

## Akışı koddan çalıştırmak

Kurulu runner `MisterO.runner` olarak erişilebilir ve main actor üzerinde çalışır:

```swift
if let runner = MisterO.runner {
    let state = await runner.run("""
    tap: "login_button"
    assertVisible: "welcome_label"
    """)
    print(state, runner.reportText)
}
```

Katalog `MisterO.scenarios` olarak erişilebilir:

```swift
if let catalog = MisterO.scenarios {
    await catalog.runSuite(catalog.scenarios.filter { $0.tags.contains("smoke") })
    print(catalog.suiteReportText)
}
```

Runner ekranla `UIDriver` protokolü üzerinden konuşur. Bu sayede `InAppTestRunner(driver:configuration:)`
ile kendi sürücünüzü (örneğin unit testlerde sahte bir sürücü) kullanabilirsiniz.

## Nasıl çalışır

```
MisterOCore  (yalnızca Foundation, macOS'ta test edilir)
├── FlowParser          metin → [TestStep]; tüm hataları satır numarasıyla toplar
├── InAppTestRunner     @MainActor async/await motor: sıra, bekleme, zaman aşımı, iptal, rapor
├── UIDriver            runner'ın ekranla konuştuğu protokol
├── ScenarioFeed        senaryo kataloğunun kaynağı (uzak, paket, kod içi, özel)
├── ScenarioStore       kataloğu yükler, önbelleğe alır, doğrular; tek senaryo ya da suite koşturur
├── FlowAssistant       ekran için kontrol planlar, koşar, raporlar, testçiyle devam eder
├── FlowAssistantModel  asistanın arkasındaki dil modeli için protokol
├── AppleFlowAssistantModel  guided generation ile Apple'ın cihaz içi modeli (iOS 26+)
├── IssueReporter       bulunan sorunu kayda çevirir (WebhookIssueReporter, JiraIssueReporter)
├── SuiteAutomation     autorun, sonuç dosyaları, ResultReporter'lar, tekrarsız kayıt
└── SuiteReport         bir suite'in sonucu: metin, JUnit XML, JSON ve Markdown

MisterO  (UIKit + SwiftUI)
├── UIKitDriver         UIDriver = ViewResolver + ActionExecutor
├── ViewResolver        UIWindow hiyerarşisini recursive tarar, öğeleri eşleştirir ve sıralar
├── ActionExecutor      tap / type'ı açık UIKit API'leriyle uygular
├── Scroller            ana listeyi bulur ve sayfa sayfa kaydırır
├── AccessibilityBootstrap  SwiftUI öğelerini resolver'a görünür kılar
├── ScreenAnchor        asistanı başlangıç ekranına döndürür; cevaplar için Keychain hafızası
├── ScreenCapture       kayıt için uygulamanın anahtar penceresinin görüntüsü (overlay hariç)
└── Panel               ayrı bir overlay penceresinde SwiftUI paneli
```

Mister-O sentetik dokunuş üretmez; UIKit'in açık API'lerini kullanır:

| Öğe | Nasıl tetiklenir |
|---|---|
| `UIButton` ve diğer `UIControl`'ler | `sendActions(for: .touchUpInside)`. `UIButton` `primaryAction`'ı kendisi tetikler; diğer kontrollere ayrıca `.primaryActionTriggered` gönderilir |
| `UISwitch` | değeri çevirir ve `.valueChanged` gönderir |
| `UITableViewCell` / `UICollectionViewCell` | satırı seçer ve delegate'in `didSelect…` metodunu çağırır |
| SwiftUI `Button`, `NavigationLink`, … | erişilebilirlik öğesinde `accessibilityActivate()` |
| Metin alanı (UIKit, SwiftUI `TextField` / `SecureField` / `TextEditor`) | `becomeFirstResponder()` + `UIKeyInput.insertText(_:)` |
| Uyarı ve onay penceresi butonları | butonun `UIAlertAction`'ı, UIKit'in private `_dismissWithAction:` metoduyla (aşağıya bakın) |
| Kaydırma | scroll view'da `setContentOffset(_:animated:)`, sayfa başına yüksekliğin %80'i |
| `back` | navigasyonda `popViewController(animated:)` ya da en üstteki sayfada `dismiss(animated:)` |

`insertText` gerçek klavye girişi gibi davranır: delegate'ler, `.editingChanged` ve SwiftUI `@State`
binding'leri güncellenir. Pasif bir kontrol (UIKit `isEnabled == false` ya da SwiftUI `.disabled`)
hata değil "henüz değil" sayılır ve zaman aşımına kadar yeniden denenir.

Resolver panelin kendi penceresini taramaz. Bu yüzden panelin butonları akıştaki sorgularla
asla çakışmaz.

## SwiftUI desteği ve private API

SwiftUI, `Button`, `Text` gibi görünümleri `UIView` olarak değil erişilebilirlik öğeleri olarak
sunar ve bu öğeleri yalnızca uygulama erişilebilirliği açıkken (VoiceOver, XCUITest vb.) üretir.
Kapalıyken resolver SwiftUI öğelerini ve `.accessibilityIdentifier` değerlerini göremez.

`AccessibilityBootstrap` bu ayarı `libAccessibility` içindeki **private**
`_AXSApplicationAccessibilitySetEnabled` fonksiyonuyla açar. KIF ve AccessibilitySnapshot da aynı
yöntemi kullanır.

- Ayar **sistem genelinde ve kalıcıdır**. Mister-O onu yalnızca uygulamanız ön plandayken açar.
  Uygulama arka plana geçtiğinde ya da `MisterO.uninstall()` çağrıldığında eski değerine döndürür.
  Eski değer diskte saklandığı için uygulama çökse bile doğru geri yüklenir.
- Private API olduğu için **SDK'yı App Store derlemelerine koymayın**. Harici TestFlight incelemesi
  de bunu işaretleyebilir.
- Yalnızca UIKit kullanan uygulamalarda kapatabilirsiniz: `.misterOTestPanel(enablesSwiftUIAccessibility: false)`.

Uyarı butonları ikinci private parçadır. UIKit'te bir `UIAlertAction`'ı tetiklemenin açık yolu yok; bu
yüzden Mister-O, gerçek bir dokunuşun izlediği yolu, `UIAlertController`'ın `_dismissWithAction:`
metodunu çağırır: uyarı kapanır ve butonun handler'ı çalışır. İleride bir iOS sürümü bu metodu kaldırırsa
Mister-O uyarıyı kapatıp action'ın handler'ını kendisi çağırır; o da yoksa adım "tıklanamıyor" hatasıyla
düşer.

## Sınırlar

- **Gesture recognizer'lar:** dokunuşu yalnızca `UITapGestureRecognizer` ile alan UIKit view'ları
  açık API ile tetiklenemez; adım "tıklanabilir değil" hatasıyla biter.
- **Gerçek dokunuş yok:** öğenin üstünü başka bir view kapatsa bile eylem çalışır. Eşitlikte en
  öndeki öğe seçilir ama hit-test kontrolü yapılmaz.
- **Süreç dışı UI:** sistem izin diyalogları, girişten sonra çıkan "Parolayı kaydet" penceresi,
  klavyenin kendisi, share sheet içeriği ve `WKWebView` içindeki web içeriğine erişilemez. Bu
  pencereler programatik adımları engellemez, ama testçinin elle kapatması gerekebilir.
- **Şimdiye kadar test edilenler:** iOS 27 simülatöründe demo; SwiftUI `TextField` / `SecureField` /
  `Button` / `NavigationLink` / `Toggle` / `List`, `.alert`, `.confirmationDialog`, `.sheet` ve UIKit
  `UITextField` / `UIButton(primaryAction:)` ile uçtan uca geçiyor. Uzun bir `List`'i iki yöne kaydırma,
  `back`, test verisi yer tutucuları, `resetApp`'li bir suite, uzak katalog, çevrimdışı önbellek ve düşen
  senaryolar için kayıt açma da orada denendi. Gerçek cihaz ve iOS 16–26 henüz test edilmedi.

## Geliştirme

Parser ve runner testlerini Mac'te çalıştırın:

```bash
swift test
```

UIKit testleri dahil hepsini simülatörde çalıştırın:

```bash
xcodebuild test -scheme MisterO -destination 'platform=iOS Simulator,name=iPhone 17'
```

SwiftUI giriş ekranı; uyarı, onay penceresi ve sheet içeren uzun bir ayarlar listesi ve bir UIKit ekranı
olan demo uygulaması `Examples/MisterODemo` altında. İçinde 5 senaryoluk bir katalog
(`Sources/mistero-scenarios.json`; biri bilerek başarısız olur) ve bir `resetApp` işleyicisi var. Kataloğu bir URL'den yüklemek için `MISTERO_SCENARIOS_URL` ortam
değişkenini verin. Apple modelinin olmadığı yerlerde Asistan sekmesini kural tabanlı bir yedek modelle
denemek için `MISTERO_ASSISTANT=demo`, **Kayıt aç**'ı kendi webhook'unuzla denemek için
`MISTERO_ISSUE_WEBHOOK` olarak bir URL verin:

```bash
open Examples/MisterODemo/MisterODemo.xcodeproj
```

Ekrana dokunmadan koşu için [otomatik koşu](#otomatik-koşu)yu kullanın. `MISTERO_RESULTS_WEBHOOK`, demo'nun
sonuçlarını bir Slack webhook'una gönderir:

```bash
SIMCTL_CHILD_MISTERO_AUTORUN="#smoke" SIMCTL_CHILD_MISTERO_EXIT=1 \
  xcrun simctl launch --console booted app.mistero.demo
```

Panel simülatörün dilini izler. Diğer dili görmek için şemanın başlatma argümanlarına
`-AppleLanguages (en)` ya da `-AppleLanguages (tr)` ekleyin.

Demo projesi `project.yml` dosyasından [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile
üretilir; o dosyayı değiştirdikten sonra `xcodegen generate` çalıştırın.

## Lisans

Mister-O [MIT Lisansı](../LICENSE) ile yayınlanmıştır.
