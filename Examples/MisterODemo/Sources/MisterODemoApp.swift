import SwiftUI
#if MISTERO
import MisterO
#endif

@main
struct MisterODemoApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                #if MISTERO
                .misterOTestPanel(
                    initialScript: DemoFlow.login,
                    scenarios: DemoFlow.catalog,
                    // Her senaryo giriş ekranından başlasın.
                    resetApp: { model.reset() },
                    assistantModel: DemoFlow.assistantModel,
                    // Asistan staging test hesabını bilsin; geçerli giriş için sormasın.
                    testData: ["Test hesabı e-postası": "tester@mistero.app", "Test hesabı şifresi": "123456"],
                    issueReporter: DemoFlow.issueReporter
                )
                .task { await DemoFlow.autorun() }
                #endif
        }
    }
}

#if MISTERO
enum DemoFlow {
    static let login = """
    # Demo: SwiftUI giriş + UIKit ekranı
    type: "email_field" -> "tester@mistero.app"
    type: "password_field" -> "123456"
    tap: "login_button"
    assertVisible: "welcome_label"
    tap: "UIKit Ekranı"
    type: "nickname_field" -> "Mister O"
    tap: "Kaydet"
    assertVisible: "Kaydedildi: Mister O (1)"
    wait: 1
    """

    /// `MISTERO_ISSUE_WEBHOOK` verilirse sorunlar bu webhook'a gönderilir (Jira Automation, Zapier…).
    static var issueReporter: (any IssueReporter)? {
        guard let raw = ProcessInfo.processInfo.environment["MISTERO_ISSUE_WEBHOOK"], let url = URL(string: raw) else {
            return nil
        }
        return WebhookIssueReporter(name: "Jira", url: url)
    }

    /// `nil` ise iOS 26+'da Apple'ın cihaz içi modeli kullanılır.
    static var assistantModel: (any FlowAssistantModel)? {
        ProcessInfo.processInfo.environment["MISTERO_ASSISTANT"] == "demo" ? DemoAssistantModel() : nil
    }

    /// `MISTERO_AUTORUN=id1,id2` verilirse açılışta bu senaryolar koşar ve rapor konsola yazılır
    /// (`xcrun simctl launch --console`). Elle dokunmadan duman testi için.
    @MainActor static func autorun() async {
        guard let raw = ProcessInfo.processInfo.environment["MISTERO_AUTORUN"] else { return }
        let ids = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        while [nil, .idle, .loading].contains(MisterO.scenarios?.status) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let store = MisterO.scenarios else { return }
        let selected = ids.compactMap { id in store.allScenarios.first { $0.id == id } }
        await store.runSuite(selected)
        print("MISTERO-REPORT-BEGIN\n\(store.suiteReportText)")
        for scenario in selected {
            for result in store.runs[scenario.id]?.steps ?? [] {
                print("  [\(scenario.id)] \(result.status.symbol) \(result.step.source)")
            }
        }
        print("MISTERO-REPORT-END")
    }

    /// Paketteki mistero-scenarios.json; `MISTERO_SCENARIOS_URL` verilirse uzaktan yüklenir.
    static var catalog: ScenarioFeed {
        if let raw = ProcessInfo.processInfo.environment["MISTERO_SCENARIOS_URL"], let url = URL(string: raw) {
            return .remote(url)
        }
        return .bundled("mistero-scenarios")
    }
}
#endif

enum Route: Hashable {
    case welcome(email: String)
    case uikit
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    @Published var path: [Route] = []

    func reset() {
        path = []
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            LoginView { email in model.path.append(.welcome(email: email)) }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .welcome(let email):
                        WelcomeView(email: email)
                    case .uikit:
                        ProfileScreen()
                            .navigationTitle("UIKit")
                    case .settings:
                        SettingsView()
                    }
                }
        }
    }
}
