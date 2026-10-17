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
    /// Ekranı kendi başına test eden asistan.
    public private(set) static var assistant: FlowAssistant?
    private static var overlay: OverlayWindow?

    /// - Parameters:
    ///   - scenarios: Testçinin panelde göreceği senaryo kataloğunun kaynağı.
    ///   - resetApp: Her senaryodan önce uygulamayı başlangıç durumuna getirir (navigasyonu köke al,
    ///     oturumu kapat…). Verilmezse senaryolar bir öncekinin bıraktığı ekrandan devam eder.
    ///   - assistantModel: Asistanın dil modeli. Verilmezse iOS 26+'da Apple'ın cihaz içi modeli kullanılır;
    ///     daha eski sistemlerde Asistan sekmesi nedenini açıklar.
    ///   - testData: Asistanın bilmesi gereken test verileri (staging test hesabı gibi). Örnek:
    ///     `["Test hesabı e-postası": "qa@firma.com", "Test hesabı şifresi": "…"]`. Asistan bunları sormaz.
    ///   - issueReporter: Asistanın bulduğu sorunları takip aracınızda kayda çevirir (örn. `WebhookIssueReporter`).
    ///     Sorunun ekran görüntüsü kayda eklenir.
    ///   - language: Panelin, raporların ve asistanın dili. Verilmezse cihazın dili (desteklenmiyorsa İngilizce).
    ///   - enablesSwiftUIAccessibility: SwiftUI öğelerini bulabilmek için uygulama erişilebilirliğini
    ///     açar (private API, ayrıntı `AccessibilityBootstrap`'ta). Yalnızca UIKit ekranlarınız varsa `false` verin.
    public static func install(
        in scene: UIWindowScene,
        initialScript: String? = nil,
        scenarios feed: ScenarioFeed? = nil,
        resetApp: (@MainActor () async -> Void)? = nil,
        assistantModel: (any FlowAssistantModel)? = nil,
        testData: [String: String] = [:],
        issueReporter: (any IssueReporter)? = nil,
        language: MisterOLanguage? = nil,
        configuration: InAppTestRunner.Configuration = .default,
        enablesSwiftUIAccessibility: Bool = true
    ) {
        guard overlay == nil else { return }
        // Önce dil: aşağıda oluşan her metin (başlangıç akışı, asistanın durumu) bu dilde olur.
        MisterOLanguage.current = language ?? .device
        if enablesSwiftUIAccessibility {
            AccessibilityBootstrap.install()
        }

        let driver = UIKitDriver()
        let runner = InAppTestRunner(driver: driver, configuration: configuration)
        let store = ScenarioStore(feed: feed, runner: runner, resetApp: resetApp)
        let assistant = makeAssistant(model: assistantModel, driver: driver, scene: scene, resetApp: resetApp,
                                      testData: testData)
        let panel = PanelModel()
        let window = OverlayWindow(windowScene: scene, panel: panel)

        panel.prepareForRun = { [weak window, weak scene] in
            // Panel editörünün klavyesini kapat ve klavye odağını uygulamanın penceresine geri ver.
            window?.endEditing(true)
            scene?.windows.first { !($0 is OverlayWindow) && $0.windowLevel == .normal }?.makeKey()
        }

        let host = UIHostingController(rootView: TestPanelView(
            runner: runner, scenarios: store, panel: panel, assistant: assistant, issueReporter: issueReporter,
            resolver: driver.resolver, initialScript: initialScript ?? SampleFlow.starter
        ))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false

        self.runner = runner
        self.scenarios = store
        self.assistant = assistant
        self.overlay = window

        if feed != nil {
            Task { await store.refresh() }
        }
    }

    public static func uninstall() {
        AccessibilityBootstrap.uninstall()
        assistant?.stop()
        scenarios?.cancel()
        runner?.cancel()
        overlay?.isHidden = true
        overlay = nil
        runner = nil
        scenarios = nil
        assistant = nil
    }

    private static func makeAssistant(
        model: (any FlowAssistantModel)?,
        driver: UIKitDriver,
        scene: UIWindowScene,
        resetApp: (@MainActor () async -> Void)?,
        testData: [String: String]
    ) -> FlowAssistant {
        // Asistanın kendi runner'ı: "öğe yok" ya da "pasif" cevabını 5 sn beklemeden almalı.
        let runner = InAppTestRunner(driver: driver, configuration: .init(
            elementTimeout: .seconds(2), pollInterval: .milliseconds(150), delayBetweenSteps: .zero
        ))
        let resolver = driver.resolver
        let facts = testData.sorted { $0.key < $1.key }.map { AssistantAnswer(question: $0.key, answer: $0.value) }
        return FlowAssistant(model: model ?? defaultAssistantModel(), runner: runner,
                             screen: { resolver.screenElements() },
                             screenshot: { [weak scene] in scene.flatMap(ScreenCapture.png(in:)) },
                             navigator: ScreenAnchor(), resetApp: resetApp,
                             appFacts: facts, memory: KeychainAssistantMemory())
    }

    private static func defaultAssistantModel() -> any FlowAssistantModel {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleFlowAssistantModel()
        }
        #endif
        return UnavailableAssistantModel(reason: L("The assistant needs iOS 26 and Apple Intelligence."))
    }
}

public enum SampleFlow {
    /// Panel ilk açıldığında editörde görünen kısa sözdizimi rehberi (panelin dilinde).
    public static var starter: String {
        """
        \(L("# Mister-O · one step per line"))
        \(L("# tap: \"accessibility_id or button text\""))
        \(L("# type: \"field_id\" -> \"text to type\""))
        # wait: 1.5
        # assertVisible: "accessibility_id"

        tap: "login_button"
        """
    }
}

public extension View {
    /// Mister-O test panelini bu görünümün sahnesine kurar (sahne başına bir kez).
    func misterOTestPanel(
        initialScript: String? = nil,
        scenarios: ScenarioFeed? = nil,
        resetApp: (@MainActor () async -> Void)? = nil,
        assistantModel: (any FlowAssistantModel)? = nil,
        testData: [String: String] = [:],
        issueReporter: (any IssueReporter)? = nil,
        language: MisterOLanguage? = nil,
        configuration: InAppTestRunner.Configuration = .default,
        enablesSwiftUIAccessibility: Bool = true
    ) -> some View {
        background(SceneHook { scene in
            MisterO.install(in: scene, initialScript: initialScript, scenarios: scenarios, resetApp: resetApp,
                            assistantModel: assistantModel, testData: testData, issueReporter: issueReporter,
                            language: language, configuration: configuration, enablesSwiftUIAccessibility: enablesSwiftUIAccessibility)
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
