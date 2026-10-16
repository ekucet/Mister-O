#if canImport(UIKit)
import UIKit

/// Paneli uygulamanın kendi hiyerarşisinin dışında, en üstte tutan pencere.
///
/// - Resolver bu pencereyi taramaz; panelin kendi butonları ("Çalıştır" gibi) akıştaki
///   sorgularla asla çakışmaz.
/// - Panel kapalıyken yalnızca baloncuğun üstündeki dokunuşları alır, gerisini alttaki
///   uygulamaya geçirir. Bölge SwiftUI hit-testing'ine değil `PanelModel`'e sorulur; iOS 18+'da
///   hosting view boş alanlarda da kendini döndürdüğü için klasik "rootView'sa nil dön" hilesi çalışmaz.
final class OverlayWindow: UIWindow {
    private let panel: PanelModel

    init(windowScene: UIWindowScene, panel: PanelModel) {
        self.panel = panel
        super.init(windowScene: windowScene)
        windowLevel = .alert + 1
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) kullanılmaz")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard panel.acceptsTouch(at: point, in: bounds.size) else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
