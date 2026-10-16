#if canImport(UIKit)
import os
import UIKit

/// SwiftUI'nin erişilebilirlik ağacını üretmesini sağlar.
///
/// SwiftUI `Button`, `Text`, `NavigationLink` gibi öğeleri UIView olarak değil, erişilebilirlik
/// düğümleri olarak yayınlar ve bu düğümleri **yalnızca** "application accessibility" açıkken
/// (VoiceOver, Voice Control, XCUITest…) üretir. Kapalıyken hosting view'lar boş liste döner ve
/// resolver SwiftUI öğelerini, `.accessibilityIdentifier` değerlerini göremez.
///
/// ⚠️ Bu bayrak `libAccessibility`'deki **private** `_AXSApplicationAccessibilitySetEnabled` ile
/// açılır (KIF ve AccessibilitySnapshot da aynı yolu kullanır). Bayrak sistem geneli ve kalıcıdır;
/// bu yüzden uygulama ön plandayken açılır, arka plana geçince ya da `MisterO.uninstall()` ile
/// eski değerine döndürülür. SDK'yı App Store derlemelerine koymayın.
@MainActor
enum AccessibilityBootstrap {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void

    /// Değiştirmeden önceki sistem değeri; uygulama çökse bile bir sonraki açılışta doğru geri yüklensin diye diskte.
    private static let originalValueKey = "MisterO.originalApplicationAccessibility"
    private static let logger = Logger(subsystem: "MisterO", category: "Accessibility")

    private static let api: (isEnabled: Getter, setEnabled: Setter)? = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let getter = dlsym(handle, "_AXSApplicationAccessibilityEnabled"),
              let setter = dlsym(handle, "_AXSApplicationAccessibilitySetEnabled") else {
            return nil
        }
        return (unsafeBitCast(getter, to: Getter.self), unsafeBitCast(setter, to: Setter.self))
    }()

    private static var observers: [NSObjectProtocol] = []

    /// Bayrağı açar ve uygulama yaşam döngüsüne göre aç/kapa gözlemcilerini kurar.
    static func install() {
        guard observers.isEmpty else { return }
        activate()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { activate() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { restore() }
            },
        ]
    }

    static func uninstall() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        restore()
    }

    private static func activate() {
        guard let api else {
            logger.error("libAccessibility yüklenemedi; SwiftUI öğeleri bulunamayabilir.")
            return
        }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: originalValueKey) == nil {
            defaults.set(api.isEnabled(), forKey: originalValueKey)
        }
        if !api.isEnabled() {
            api.setEnabled(true)
        }
    }

    private static func restore() {
        let defaults = UserDefaults.standard
        guard let api, let original = defaults.object(forKey: originalValueKey) as? Bool else { return }
        if api.isEnabled() != original {
            api.setEnabled(original)
        }
        defaults.removeObject(forKey: originalValueKey)
    }
}
#endif
