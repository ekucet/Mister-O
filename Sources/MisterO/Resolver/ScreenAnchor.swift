#if canImport(UIKit)
import MisterOCore
import Security
import UIKit

/// Asistanın kontroller arasında başlangıç ekranına dönmesini sağlar: testin başladığı view
/// controller'ı hatırlar; dönerken üstünde açılan sayfaları kapatır ve navigasyonu ona geri alır.
/// SwiftUI `NavigationStack` de altta `UINavigationController` kullandığı için aynı yol çalışır.
@MainActor
final class ScreenAnchor: ScreenNavigating {
    private weak var anchor: UIViewController?
    private(set) var startIsAppRoot = false

    func markStart() {
        anchor = Self.visibleViewController()
        startIsAppRoot = anchor.map(Self.isAppRoot) ?? false
    }

    /// Navigasyonun ilk ekranı ve üstünde/altında modal yok.
    private static func isAppRoot(_ controller: UIViewController) -> Bool {
        guard controller.presentingViewController == nil else { return false }
        guard let navigation = controller.navigationController else { return true }
        return navigation.viewControllers.first === controller && navigation.presentingViewController == nil
    }

    func returnToStart() async {
        guard let anchor else { return }
        if anchor.presentedViewController != nil {
            anchor.dismiss(animated: false)
        }
        if let navigation = anchor.navigationController, navigation.topViewController !== anchor,
           navigation.viewControllers.contains(anchor) {
            navigation.popToViewController(anchor, animated: false)
        }
    }

    /// Uygulama penceresinde şu an görünen en üstteki içerik view controller'ı.
    static func visibleViewController() -> UIViewController? {
        let window = ViewResolver.applicationWindows().last { $0.windowLevel == .normal && $0.rootViewController != nil }
        var current = window?.rootViewController
        while let controller = current {
            if let presented = controller.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let navigation = controller as? UINavigationController, let top = navigation.topViewController {
                current = top
            } else if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
                current = selected
            } else if let container = controller.children.first(where: { $0 is UINavigationController || $0 is UITabBarController }) {
                // SwiftUI hosting controller'ı NavigationStack'i bir child UINavigationController olarak tutar.
                current = container
            } else {
                return controller
            }
        }
        return nil
    }
}

/// Testçinin verdiği bilgileri (hesap, şifre…) cihazın Keychain'inde saklar; uygulama yeniden açıldığında
/// asistan aynı soruyu tekrar sormaz. Yalnızca bu cihazda kalır (iCloud'a eşitlenmez).
@MainActor
final class KeychainAssistantMemory: AssistantMemory {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "MisterO.assistant",
        kSecAttrAccount as String: "facts",
    ]

    func load() -> [AssistantAnswer] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return []
        }
        return (try? JSONDecoder().decode([AssistantAnswer].self, from: data)) ?? []
    }

    func save(_ answers: [AssistantAnswer]) {
        SecItemDelete(query as CFDictionary)
        guard !answers.isEmpty, let data = try? JSONEncoder().encode(answers) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

enum DeviceEnvironment {
    /// Hata kayıtları için: "iPhone (Simülatör) · iOS 27.0 · app.mistero.demo 1.0 (1)"
    @MainActor static var summary: String {
        let device = UIDevice.current
        var model = device.model
        #if targetEnvironment(simulator)
        model += " (" + L("Simulator") + ")"
        #endif
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(model) · \(device.systemName) \(device.systemVersion) · \(Bundle.main.bundleIdentifier ?? "?") \(version) (\(build))"
    }
}
#endif
