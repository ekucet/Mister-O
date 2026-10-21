#if canImport(FoundationModels)
import FoundationModels
import Testing
@testable import MisterOCore

/// Şema ve cevap ayrıştırma testleri model gerektirmez. Gerçek modeli çağıranlar model hazır değilse
/// (Apple Intelligence kapalı, indiriliyor, desteklenmeyen cihaz) ya da simülatördeyse atlanır.
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
        ScreenElement(query: "login_button", identifier: "login_button", name: "Giriş Yap", kind: "Button · AX",
                      isEnabled: false),
    ]

    @Test func schemasBuild() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        _ = try AppleFlowAssistantModel.planSchema()
        _ = try AppleFlowAssistantModel.decisionSchema(targets: ["-", "email_field", "login_button"])
        _ = try AppleFlowAssistantModel.decisionSchema(targets: ["-"])
        #expect(AssistantAction.allCases.contains(.scroll) && AssistantAction.allCases.contains(.back))
    }

    @Test func decodesPlanAndDecision() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let plan = try AppleFlowAssistantModel.decodePlan(GeneratedContent(json: """
        {"checks": [{"title": "Boş form", "expectation": "Buton pasif", "leavesScreen": false},
                    {"title": "Giriş", "expectation": "Ana sayfa", "leavesScreen": true}]}
        """))
        #expect(plan == [PlannedCheck(title: "Boş form", expectation: "Buton pasif"),
                         PlannedCheck(title: "Giriş", expectation: "Ana sayfa", leavesScreen: true)])

        let decision = try AppleFlowAssistantModel.decodeDecision(GeneratedContent(json: """
        {"message": "Butonu kontrol ediyorum.", "action": "assertDisabled", "target": "login_button", "text": ""}
        """))
        #expect(decision == AssistantDecision(action: .assertDisabled, target: "login_button", text: "",
                                              message: "Butonu kontrol ediyorum."))

        let scroll = try AppleFlowAssistantModel.decodeDecision(GeneratedContent(json: """
        {"message": "Gönder butonu aşağıda olabilir.", "action": "scroll", "target": "-", "text": "down"}
        """))
        #expect(scroll == AssistantDecision(action: .scroll, target: "-", text: "down",
                                            message: "Gönder butonu aşağıda olabilir."))
        #expect(FlowAssistant.line(for: scroll, allowedTargets: ["-"]) == "scroll: down")

        let back = try AppleFlowAssistantModel.decodeDecision(GeneratedContent(json: """
        {"message": "Sayfayı kapatıyorum.", "action": "back", "target": "-", "text": ""}
        """))
        #expect(back.action == .back)
        #expect(FlowAssistant.line(for: back, allowedTargets: ["-"]) == "back")

        #expect(throws: AssistantModelError.self) {
            try AppleFlowAssistantModel.decodeDecision(GeneratedContent(json: """
            {"message": "", "action": "dance", "target": "-", "text": ""}
            """))
        }
    }

    @Test(.enabled(if: modelIsAvailable))
    func plansChecksForALoginScreen() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let plan = try await AppleFlowAssistantModel().plan(for: PlanContext(focus: nil, screen: Self.loginScreen))
        #expect((1...PlanContext.maxChecks).contains(plan.count), "\(plan)")
    }

    @Test(.enabled(if: modelIsAvailable))
    func picksOnlyListedTargets() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = AssistantContext(
            check: PlannedCheck(title: "Boş formla giriş yapılamamalı", expectation: "Giriş Yap pasif kalmalı"),
            answers: [], steps: [], lastIssue: nil, screen: Self.loginScreen
        )
        let decision = try await AppleFlowAssistantModel().nextDecision(for: context)
        #expect(context.targets.contains(decision.target ?? "-"), "\(decision)")
    }
}
#endif
