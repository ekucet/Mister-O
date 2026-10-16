import SwiftUI
#if MISTERO
import MisterO
#endif

@main
struct MisterODemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if MISTERO
                .misterOTestPanel(initialScript: DemoFlow.login)
                #endif
        }
    }
}

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
}

enum Route: Hashable {
    case welcome(email: String)
    case uikit
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            LoginView { email in path.append(.welcome(email: email)) }
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
