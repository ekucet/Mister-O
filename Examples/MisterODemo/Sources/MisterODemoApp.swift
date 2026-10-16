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
                    assistantModel: DemoFlow.assistantModel
                )
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

    /// `nil` ise iOS 26+'da Apple'ın cihaz içi modeli kullanılır.
    static var assistantModel: (any FlowAssistantModel)? {
        ProcessInfo.processInfo.environment["MISTERO_ASSISTANT"] == "demo" ? DemoAssistantModel() : nil
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
                    }
                }
        }
    }
}
