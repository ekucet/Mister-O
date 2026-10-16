#if canImport(UIKit)
import MisterOCore
import SwiftUI
import UIKit

/// SDK'nın giriş noktası. Yalnızca Test/Staging derlemelerinde çağırın.
///
/// SwiftUI:
///
///     WindowGroup {
///         ContentView()
///             #if STAGING
///             .misterOTestPanel()
///             #endif
///     }
///
/// UIKit (`SceneDelegate.scene(_:willConnectTo:options:)` içinde):
///
///     MisterO.install(in: windowScene)
@MainActor
public enum MisterO {
    /// Kurulu panelin runner'ı; akışı koddan başlatmak için de kullanılabilir.
    public private(set) static var runner: InAppTestRunner?
    /// Senaryo kataloğu ve toplu koşular.
    public private(set) static var scenarios: ScenarioStore?
    private static var overlay: OverlayWindow?

    /// - Parameters:
    ///   - scenarios: Testçinin panelde göreceği senaryo kataloğunun kaynağı.
    ///   - resetApp: Her senaryodan önce uygulamayı başlangıç durumuna getirir (navigasyonu köke al,
    ///     oturumu kapat…). Verilmezse senaryolar bir öncekinin bıraktığı ekrandan devam eder.
    ///   - enablesSwiftUIAccessibility: SwiftUI öğelerini bulabilmek için uygulama erişilebilirliğini
    ///     açar (private API, ayrıntı `AccessibilityBootstrap`'ta). Yalnızca UIKit ekranlarınız varsa `false` verin.
    public static func install(
        in scene: UIWindowScene,
        initialScript: String = SampleFlow.starter,
        scenarios feed: ScenarioFeed? = nil,
        resetApp: (@MainActor () async -> Void)? = nil,
        configuration: InAppTestRunner.Configuration = .default,
        enablesSwiftUIAccessibility: Bool = true
    ) {
        guard overlay == nil else { return }
        if enablesSwiftUIAccessibility {
            AccessibilityBootstrap.install()
        }

        let driver = UIKitDriver()
        let runner = InAppTestRunner(driver: driver, configuration: configuration)
        let store = ScenarioStore(feed: feed, runner: runner, resetApp: resetApp)
        let panel = PanelModel()
        let window = OverlayWindow(windowScene: scene, panel: panel)

        panel.prepareForRun = { [weak window, weak scene] in
            // Panel editörünün klavyesini kapat ve klavye odağını uygulamanın penceresine geri ver.
            window?.endEditing(true)
            scene?.windows.first { !($0 is OverlayWindow) && $0.windowLevel == .normal }?.makeKey()
        }

        let host = UIHostingController(rootView: TestPanelView(
            runner: runner, scenarios: store, panel: panel, resolver: driver.resolver, initialScript: initialScript
        ))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false

        self.runner = runner
        self.scenarios = store
        self.overlay = window

        if feed != nil {
            Task { await store.refresh() }
        }
    }

    public static func uninstall() {
        AccessibilityBootstrap.uninstall()
        scenarios?.cancel()
        runner?.cancel()
        overlay?.isHidden = true
        overlay = nil
        runner = nil
        scenarios = nil
    }
}

public enum SampleFlow {
    /// Panel ilk açıldığında editörde görünen kısa sözdizimi rehberi.
    public static let starter = """
    # Mister-O · her satır bir adım
    # tap: "accessibility_id veya buton metni"
    # type: "alan_id" -> "yazılacak metin"
    # wait: 1.5
    # assertVisible: "accessibility_id"

    tap: "login_button"
    """
}

public extension View {
    /// Mister-O test panelini bu görünümün sahnesine kurar (sahne başına bir kez).
    func misterOTestPanel(
        initialScript: String = SampleFlow.starter,
        scenarios: ScenarioFeed? = nil,
        resetApp: (@MainActor () async -> Void)? = nil,
        configuration: InAppTestRunner.Configuration = .default,
        enablesSwiftUIAccessibility: Bool = true
    ) -> some View {
        background(SceneHook { scene in
            MisterO.install(in: scene, initialScript: initialScript, scenarios: scenarios, resetApp: resetApp,
                            configuration: configuration, enablesSwiftUIAccessibility: enablesSwiftUIAccessibility)
        })
    }
}

/// SwiftUI görünümünün bağlı olduğu `UIWindowScene`'i yakalayan görünmez view.
private struct SceneHook: UIViewRepresentable {
    let onScene: @MainActor (UIWindowScene) -> Void

    func makeUIView(context: Context) -> SceneHookView {
        SceneHookView(onScene: onScene)
    }

    func updateUIView(_ uiView: SceneHookView, context: Context) {}
}

private final class SceneHookView: UIView {
    private let onScene: @MainActor (UIWindowScene) -> Void

    init(onScene: @escaping @MainActor (UIWindowScene) -> Void) {
        self.onScene = onScene
        super.init(frame: .zero)
        isHidden = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) kullanılmaz")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let scene = window?.windowScene else { return }
        // Yeni pencereyi mevcut layout geçişinin dışında oluştur.
        Task { @MainActor [onScene] in onScene(scene) }
    }
}
#endif
