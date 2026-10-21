# Mister-O

[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue.svg)](docs/rehber.md)
[![SPM](https://img.shields.io/badge/SPM-uyumlu-brightgreen.svg)](#kurulum)
[![Lisans: MIT](https://img.shields.io/badge/Lisans-MIT-lightgrey.svg)](LICENSE)

[English](README.md) · **Türkçe**

iOS uygulamanızın içinde çalışan UI testleri. Mister-O'yu bir staging derlemesine ekleyin; testçiler
uygulamanın içinde bir panel bulur: hazır senaryoları koşar, kısa akışlar yazar ya da ekranı cihaz içi
bir yapay zekâ asistanına test ettirir. Mac, Xcode ya da `XCTest` gerekmez.

<p align="center">
  <img src="docs/images/assistant.png" width="180" alt="Hata bulup kayıt açan asistan raporu">
  <img src="docs/images/scenarios.png" width="180" alt="Suite koşusundan sonra senaryo kataloğu">
  <img src="docs/images/failed.png" width="180" alt="Hata mesajıyla başarısız bir adım">
  <img src="docs/images/elements.png" width="180" alt="Ekrandaki id'leri listeleyen Öğeler sekmesi">
</p>

## Ne yapar

- **Düz metin akışlar:** `tap`, `type`, `assertText`, `scroll`, `back` ve birkaç komut daha. Adımlar
  öğeyi bekler, uzun listelerde kaydırarak bulur ve uyarı butonlarına basar.
- **Senaryo kataloğu:** GitHub'da ya da sunucunuzda tek bir JSON dosyası. Testçi tek bir senaryoyu,
  bir etiketi ya da hepsini tek dokunuşla koşar.
- **Yapay zekâ test asistanı:** o anki ekranı ya da tarif ettiğiniz kontrolü test eder, formları
  gerçekçi verilerle doldurur, geçen kontrolleri senaryo olarak kaydeder, bozulanları onarır.
- **Tek dokunuşla kayıt:** düşen kontroller ve senaryolar adımları ve ekran görüntüsüyle Jira, Linear
  ya da GitHub Issues'a gider.
- **SwiftUI ve UIKit**, Türkçe ya da İngilizce.

## Kurulum

Paketi Swift Package Manager ile ekleyin:

```swift
.package(url: "https://github.com/ekucet/Mister-O.git", from: "0.4.0")
```

`MisterO` kütüphanesini **yalnızca bir staging target'ına** bağlayın, App Store derlemesine asla:
Mister-O, SwiftUI öğelerini görmek ve uyarı butonlarına basmak için private API kullanır.
[Staging target'ı kurmak](docs/rehber.md#staging-targetı-kurmak) XcodeGen ve Xcode için adımları
anlatır.

## Hızlı başlangıç

**SwiftUI:** paneli kök görünümünüze ekleyin. Tüm parametreler isteğe bağlıdır; yalnızca
`.misterOTestPanel()` de paneli getirir.

```swift
import SwiftUI
#if STAGING
import MisterO
#endif

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if STAGING
                .misterOTestPanel(
                    scenarios: .remote(URL(string: "https://raw.githubusercontent.com/acme/qa/main/mistero.json")!),
                    resetApp: { await AppState.shared.signOut() },          // her senaryodan önce çalışır
                    testData: ["Test hesabı e-postası": "qa@acme.com",     // {{Test hesabı e-postası}} olarak kullanılır
                               "Test hesabı şifresi": "…"],
                    issueReporter: WebhookIssueReporter(url: URL(string: "https://hooks.acme.com/mistero")!)
                )
                #endif
        }
    }
}
```

**UIKit:** `scene(_:willConnectTo:options:)` içinde aynı parametrelerle `MisterO.install(in: windowScene)`
çağırın.

Staging derlemesini çalıştırın. Ekranın kenarında bir deney tüpü baloncuğu çıkar; paneli açmak için ona
dokunun.

## Akış yazmak

```yaml
type: email_field -> {{Test hesabı e-postası}}
type: password_field -> {{Test hesabı şifresi}}
tap: login_button
assertText: welcome_label -> "Hoş geldin"
tap: Ayarlar
tap: delete_account_button      # bulana kadar listeyi kaydırır
tap: "Sil"                      # uyarının butonu
back
```

| Komut | Örnek |
|---|---|
| `tap` | `tap: login_button` |
| `type` | `type: email_field -> "qa@acme.com"` |
| `wait` | `wait: 1.5` |
| `assertVisible` · `assertNotVisible` | `assertVisible: welcome_label` |
| `assertEnabled` · `assertDisabled` | `assertDisabled: login_button` |
| `assertText` | `assertText: welcome_label -> "Hoş geldin"` |
| `scroll` | `scroll: down` |
| `back` | `back` |

Öğeler `accessibilityIdentifier`, erişilebilirlik etiketi ya da görünen metinle bulunur. Id'ler, metin
ya da dil değişse de akışları çalışır tutar:

```swift
Button("Giriş Yap", action: signIn)
    .accessibilityIdentifier("login_button")
```

## Senaryo kataloğu

QA ekibiniz senaryoları bir kez yazar; testçiler **Senaryolar** sekmesinden seçer.

```json
{
  "scenarios": [
    {
      "name": "Başarılı giriş",
      "tags": ["smoke"],
      "goal": "Test hesabıyla giriş yap; ana sayfa açılmalı.",
      "steps": [
        "type: email_field -> {{Test hesabı e-postası}}",
        "type: password_field -> {{Test hesabı şifresi}}",
        "tap: login_button",
        "assertVisible: welcome_label"
      ]
    }
  ]
}
```

`.remote(url)`, `.bundled("ad")`, `.inline([...])` ya da kendi kaynağınızla yükleyin. Uzak kataloglar
çevrimdışı kullanım için önbelleğe alınır.

## Yapay zekâ test asistanı

**Asistan** sekmesinde **Bu ekranı test et**'e basın ya da kontrolü tarif edin: *"Alanları doldur,
Devam'a bas; sonraki ekran açılmalı."* Asistan kontrolü koşar, kısa bir rapor yazar, yalnızca
uyduramayacağı verileri sorar ve geçen kontrolleri taslak senaryo olarak kaydeder. **Asistanla onar**,
ekran değiştiği için bozulan bir senaryoyu düzeltir.

iOS 26 ve sonrasında Apple Intelligence ile Apple'ın cihaz içi modelini kullanır (API anahtarı yok,
cihazdan bir şey çıkmaz) ya da bağladığınız herhangi bir modeli. Gerçek model henüz fiziksel bir
cihazda çalıştırılmadı; döngü sahte bir modelle test ediliyor.

## Kayıt açmak

Bir `issueReporter` verirseniz düşen kontrollerde ve senaryolarda **Kayıt aç** butonu çıkar. Kayıtta
adımlar, beklenen ve gerçekleşen sonuç, cihaz ve ekran görüntüsü olur. `WebhookIssueReporter` JSON'u
Jira Automation'a, Zapier'e ya da kendi sunucunuza gönderir; uygulamada takip aracı token'ı durmaz.
Bu ödünleşimi kabul ederseniz `JiraIssueReporter` doğrudan Jira Cloud'u çağırır.

## Daha fazlası

Geri kalan her şey [rehberde](docs/rehber.md):
[panel](docs/rehber.md#panelin-kullanımı) ·
[akış yazmak](docs/rehber.md#akış-yazmak) ·
[senaryo kataloğu](docs/rehber.md#senaryo-kataloğu) ·
[asistan](docs/rehber.md#yapay-zekâ-test-asistanı) ·
[kayıt açmak](docs/rehber.md#kayıt-açmak-jira-linear-github-issues) ·
[yapılandırma](docs/rehber.md#yapılandırma) ·
[nasıl çalışır](docs/rehber.md#nasıl-çalışır) ·
[private API](docs/rehber.md#swiftui-desteği-ve-private-api) ·
[sınırlar](docs/rehber.md#sınırlar) ·
[geliştirme](docs/rehber.md#geliştirme)

## Lisans

Mister-O [MIT Lisansı](LICENSE) ile yayınlanmıştır.
