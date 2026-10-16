#if canImport(FoundationModels)
import FoundationModels
import Testing
@testable import MisterOCore

/// Gerçek cihaz içi modelle çalışır; model hazır değilse (Apple Intelligence kapalı, indiriliyor,
/// desteklenmeyen cihaz) ya da simülatördeyse atlanır. Gerçek cihazda ya da modeli hazır bir Mac'te koşar.
struct AppleModelIntegrationTests {
    static var modelIsAvailable: Bool {
        #if targetEnvironment(simulator)
        // Simülatör "available" bildirse de üretim "Simulator is not supported" hatasıyla düşüyor.
        return false
        #else
        if #available(iOS 26.0, macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        return false
        #endif
    }

    private static let loginScreen = [
        ScreenElement(query: "Giriş", identifier: nil, name: "Giriş", kind: "Header · AX"),
        ScreenElement(query: "email_field", identifier: "email_field", name: "E-posta", kind: "UIKitTextField"),
        ScreenElement(query: "password_field", identifier: "password_field", name: "Şifre", kind: "UIKitTextField"),
        ScreenElement(query: "login_button", identifier: "login_button", name: "Giriş Yap", kind: "Button · AX"),
    ]

    /// Model gerektirmez: şema hataları (ör. aynı adlı iki tip) cihaza gitmeden yakalanır.
    @Test func decisionSchemaBuilds() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = AssistantContext(goal: "x", answers: [], steps: [], lastIssue: nil, screen: Self.loginScreen)
        _ = try AppleFlowAssistantModel.schema(targets: context.targets)
        _ = try AppleFlowAssistantModel.schema(targets: ["-"])
    }

    @Test(.enabled(if: modelIsAvailable))
    func asksForDataOrTypesIntoAField() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = AssistantContext(goal: "Giriş yapılabilmeli ve ana sayfa açılmalı", answers: [], steps: [],
                                       lastIssue: nil, screen: Self.loginScreen)
        let decision = try await AppleFlowAssistantModel().nextDecision(for: context)

        #expect([.ask, .type].contains(decision.action), "\(decision)")
        if decision.action == .type {
            #expect(["email_field", "password_field"].contains(decision.target ?? ""), "\(decision)")
        }
    }

    @Test(.enabled(if: modelIsAvailable))
    func usesTheTesterAnswerAndOnlyListedTargets() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = AssistantContext(
            goal: "Giriş yapılabilmeli",
            answers: [.init(question: "Hangi hesapla?", answer: "qa@firma.com, şifre 123456")],
            steps: ["type: email_field -> qa@firma.com", "type: password_field -> 123456"],
            lastIssue: nil, screen: Self.loginScreen
        )
        let decision = try await AppleFlowAssistantModel().nextDecision(for: context)

        #expect(context.targets.contains(decision.target ?? "-"), "\(decision)")
        #expect(decision.action == .tap && decision.target == "login_button", "\(decision)")
    }
}
#endif
