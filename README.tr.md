# Mister-O

[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue.svg)](#gereksinimler)
[![SPM](https://img.shields.io/badge/SPM-uyumlu-brightgreen.svg)](#kurulum)
[![Lisans: MIT](https://img.shields.io/badge/Lisans-MIT-lightgrey.svg)](LICENSE)

[English](README.md) · **Türkçe**

iOS için **uygulama içinde** çalışan bir UI test otomasyon SDK'sı. Test/Staging derlemelerinize
gömersiniz; testçi uygulamanın içindeki panele basit bir akış yazar, ▶︎'e basar ve adımların tek
tek çalışmasını izler. Mac, Xcode, terminal ya da `XCTest` gerekmez.

```yaml
# giriş akışı
type: "email_field" -> "tester@mistero.app"
type: "password_field" -> "123456"
tap: "login_button"
assertVisible: "welcome_label"
wait: 1.5
```

<p align="center">
  <img src="docs/images/elements.png" width="250" alt="Ekrandaki id'leri listeleyen Öğeler sekmesi">
  <img src="docs/images/passed.png" width="250" alt="Başarılı bir koşu">
  <img src="docs/images/failed.png" width="250" alt="Hata mesajıyla başarısız bir adım">
</p>

## Özellikler

- **Cihazda çalışır.** Testçi akışı bilgisayar olmadan yazar ve çalıştırır.
- **SwiftUI ve UIKit.** SwiftUI `Button`, `TextField`, `SecureField`, `NavigationLink` ve UIKit
  kontrollerini `accessibilityIdentifier`, label ya da görünen metinle bulur.
- **Kendisi bekler.** `tap`, `type` ve `assertVisible` öğe ekrana gelene ya da aktif olana kadar
  bekler; her geçişten sonra `wait` yazmanız gerekmez.
- **Net sonuç.** Her adım satır numarası, süresi ve hata mesajıyla Başarılı / Başarısız / Atlandı
  olarak görünür. Rapor tek dokunuşla kopyalanıp hata kaydına yapıştırılabilir.
- **Öğe listesi.** Ekrandaki id'leri listeler; birine dokununca akışa onun komutu eklenir.
- **Araya girmez.** Panel uygulamanın üstünde kendi penceresinde durur; akış çalışırken
  sürüklenebilir bir baloncuğa küçülür.

## Gereksinimler

- iOS 16 veya üzeri
- Xcode 16 veya üzeri (Swift 6 araç zinciri)

## Kurulum

Paketi Swift Package Manager ile ekleyin ve **yalnızca Test/Staging hedefinize** bağlayın.
SDK, SwiftUI öğelerini görebilmek için private bir API kullanır (bkz. [SwiftUI desteği](#swiftui-desteği-ve-private-api));
bu yüzden App Store derlemesine kesinlikle girmemelidir.

**Xcode:** *File → Add Package Dependencies…* → `https://github.com/ekucet/Mister-O.git` →
*Dependency Rule* olarak `0.1.0`'dan itibaren *Up to Next Major Version* seçin → `MisterO`
kütüphanesini yalnızca staging hedefine ekleyin.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/ekucet/Mister-O.git", from: "0.1.0"),
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

## Hızlı başlangıç

**SwiftUI:** paneli kök görünüme ekleyin:

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
                .misterOTestPanel()
                #endif
        }
    }
}
```

**UIKit:** sahne bağlanınca kurun:

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    // … pencerenizi kurun …
    #if STAGING
    MisterO.install(in: windowScene)
    #endif
}
```

Uygulamayı açtığınızda ekranın kenarında bir deney tüpü baloncuğu görünür.

## Panelin kullanımı

1. **Aç:** baloncuğa dokunun. Baloncuğu iki kenardan birine sürükleyebilirsiniz.
2. **Yaz:** akışı editöre yazın. Son yazılan akış kaydedilir ve uygulama yeniden açılınca geri gelir.
3. **Id'leri bul:** **Öğeler** sekmesinde o anki ekrandaki öğeler listelenir. Bir satıra dokunup
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
sınırının dışına kaymış view'lar sayılmaz.

**Bekleme ve hatalar**

`tap`, `type` ve `assertVisible`, öğe yokken ya da pasifken 5 saniyeye kadar her 200 ms'de bir
yeniden dener. Öğe hâlâ yoksa adım başarısız olur, örneğin
`Ekranda bulunamadı: "welcome_label" (5.00 sn beklendi)`. Varsayılan olarak koşu ilk hatada durur
ve kalan adımlar "Atlandı" olarak işaretlenir.

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
    configuration: .init(
        elementTimeout: .seconds(8),                 // öğe başına bekleme (varsayılan 5 sn)
        pollInterval: .milliseconds(200),            // ekranın yeniden taranma aralığı
        delayBetweenSteps: .milliseconds(400),       // adımlar arası kısa ara
        stopOnFailure: true                          // false ise hatadan sonra devam eder
    ),
    enablesSwiftUIAccessibility: true                // yalnızca UIKit kullanan uygulamalarda false
)
```

`MisterO.install(in:initialScript:configuration:enablesSwiftUIAccessibility:)` aynı parametreleri
alır. `MisterO.uninstall()` paneli kaldırır ve erişilebilirlik ayarını eski haline döndürür.

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

Runner ekranla `UIDriver` protokolü üzerinden konuşur. Bu sayede `InAppTestRunner(driver:configuration:)`
ile kendi sürücünüzü (örneğin unit testlerde sahte bir sürücü) kullanabilirsiniz.

## Nasıl çalışır

```
MisterOCore  (yalnızca Foundation, macOS'ta test edilir)
├── FlowParser          metin → [TestStep]; tüm hataları satır numarasıyla toplar
├── InAppTestRunner     @MainActor async/await motor: sıra, bekleme, zaman aşımı, iptal, rapor
└── UIDriver            runner'ın ekranla konuştuğu protokol

MisterO  (UIKit + SwiftUI)
├── UIKitDriver         UIDriver = ViewResolver + ActionExecutor
├── ViewResolver        UIWindow hiyerarşisini recursive tarar, öğeleri eşleştirir ve sıralar
├── ActionExecutor      tap / type'ı açık UIKit API'leriyle uygular
├── AccessibilityBootstrap  SwiftUI öğelerini resolver'a görünür kılar
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

## Sınırlar

- **Gesture recognizer'lar:** dokunuşu yalnızca `UITapGestureRecognizer` ile alan UIKit view'ları
  açık API ile tetiklenemez; adım "tıklanabilir değil" hatasıyla biter.
- **Gerçek dokunuş yok:** öğenin üstünü başka bir view kapatsa bile eylem çalışır. Eşitlikte en
  öndeki öğe seçilir ama hit-test kontrolü yapılmaz.
- **Süreç dışı UI:** sistem izin diyalogları, klavyenin kendisi, share sheet içeriği ve
  `WKWebView` içindeki web içeriğine erişilemez.
- **Şimdiye kadar test edilenler:** iOS 27 simülatöründe demo akışı SwiftUI `TextField` /
  `SecureField` / `Button` / `NavigationLink` ve UIKit `UITextField` / `UIButton(primaryAction:)`
  ile uçtan uca geçiyor. Gerçek cihaz, `UIAlertController` butonları ve iOS 16–26 henüz test edilmedi.

## Geliştirme

Parser ve runner testlerini Mac'te çalıştırın:

```bash
swift test
```

UIKit testleri dahil hepsini simülatörde çalıştırın:

```bash
xcodebuild test -scheme MisterO -destination 'platform=iOS Simulator,name=iPhone 17'
```

SwiftUI giriş ekranı ve bir UIKit ekranı içeren demo uygulaması `Examples/MisterODemo` altında.
Varsayılan akışı ikisini de dener:

```bash
open Examples/MisterODemo/MisterODemo.xcodeproj
```

Demo projesi `project.yml` dosyasından [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile
üretilir; o dosyayı değiştirdikten sonra `xcodegen generate` çalıştırın.

## Lisans

Mister-O [MIT Lisansı](LICENSE) ile yayınlanmıştır.
