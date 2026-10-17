#if canImport(UIKit)
import UIKit

/// Asistanın bulduğu sorunun ekran görüntüsü: uygulamanın anahtar penceresi. Mister-O'nun kendi penceresi
/// (`OverlayWindow`) hiç çizilmez; panel ya da baloncuk görüntüye girmez.
@MainActor
enum ScreenCapture {
    static func png(in scene: UIWindowScene) -> Data? {
        let windows = scene.windows.filter { !($0 is OverlayWindow) && !$0.isHidden }
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first(where: { $0.windowLevel == .normal })
        else { return nil }
        return png(of: window)
    }

    /// Ölçek en fazla 2x: kayıtta okunaklı kalır, webhook gövdesi (base64) gereksiz büyümez.
    static func png(of window: UIWindow) -> Data? {
        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(max(window.traitCollection.displayScale, 1), 2)
        return UIGraphicsImageRenderer(bounds: bounds, format: format).pngData { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
    }
}
#endif
