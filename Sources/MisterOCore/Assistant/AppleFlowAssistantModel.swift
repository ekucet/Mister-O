#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple'ın cihaz içi dil modeliyle çalışan asistan (iOS 26+, Apple Intelligence destekli cihazlar).
///
/// Model, dinamik bir şemayla "guided generation" yapar: `action` yalnızca izin verilen eylemlerden,
/// `target` yalnızca o an ekranda bulunan öğelerden seçilebilir. Böylece model id uyduramaz ve
/// sözdizimi hatalı satır üretemez. Veri cihazdan çıkmaz.
@available(iOS 26.0, macOS 26.0, *)
public struct AppleFlowAssistantModel: FlowAssistantModel {
    public var temperature: Double

    public init(temperature: Double = 0.2) {
        self.temperature = temperature
    }

    public var availability: AssistantAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("Bu cihaz Apple Intelligence'ı desteklemiyor.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Ayarlar → Apple Intelligence'tan özelliği açın.")
            case .modelNotReady:
                return .unavailable("Model henüz hazır değil; indirme sürüyor olabilir.")
            @unknown default:
                return .unavailable("Cihaz içi model kullanılamıyor.")
            }
        }
    }

    public func plan(for context: PlanContext) async throws -> [PlannedCheck] {
        let content = try await respond(instructions: PlanContext.instructions, prompt: context.prompt,
                                        schema: try Self.planSchema())
        return try Self.decodePlan(content)
    }

    public func check(for request: String, context: PlanContext) async throws -> PlannedCheck {
        let prompt = "Request: \(request)\n" + context.prompt
        let content = try await respond(instructions: PlanContext.requestInstructions, prompt: prompt,
                                        schema: try GenerationSchema(root: Self.checkSchema(), dependencies: []))
        return try Self.decodeCheck(content)
    }

    public func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        let content = try await respond(instructions: AssistantContext.instructions, prompt: context.prompt,
                                        schema: try Self.decisionSchema(targets: context.targets))
        return try Self.decodeDecision(content)
    }

    /// Her çağrı yeni bir oturumdur; bağlam adımlar arasında taşınmaz.
    private func respond(instructions: String, prompt: String, schema: GenerationSchema) async throws -> GeneratedContent {
        let session = LanguageModelSession(instructions: instructions)
        do {
            return try await session.respond(to: prompt, schema: schema,
                                             options: GenerationOptions(temperature: temperature)).content
        } catch let error as LanguageModelSession.GenerationError {
            throw AssistantModelError(Self.describe(error))
        } catch {
            #if targetEnvironment(simulator)
            // Simülatör modeli "available" bildirse de güvenlik filtresi "Simulator is not supported" diyebiliyor.
            throw AssistantModelError("Apple'ın cihaz içi modeli bu simülatörde yanıt üretemedi; gerçek bir cihazda deneyin. (\(error.localizedDescription))")
            #else
            throw error
            #endif
        }
    }

    // MARK: - Şemalar

    static func checkSchema() -> DynamicGenerationSchema {
        DynamicGenerationSchema(
            name: "Check",
            properties: [
                .init(name: "title", description: "Short Turkish sentence naming the check.",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "expectation", description: "What should happen, in Turkish.",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "leavesScreen", description: "True if a successful run leaves this screen.",
                      schema: DynamicGenerationSchema(type: Bool.self)),
            ]
        )
    }

    static func planSchema() throws -> GenerationSchema {
        let check = checkSchema()
        let plan = DynamicGenerationSchema(
            name: "Plan",
            properties: [
                .init(name: "checks", schema: DynamicGenerationSchema(arrayOf: check, minimumElements: 1,
                                                                      maximumElements: PlanContext.maxChecks)),
            ]
        )
        return try GenerationSchema(root: plan, dependencies: [])
    }

    /// Alan sırası bilerek böyle: önce kısa gerekçe, sonra karar. Küçük model "düşünüp" seçince daha isabetli.
    static func decisionSchema(targets: [String]) throws -> GenerationSchema {
        let decision = DynamicGenerationSchema(
            name: "Decision",
            description: "The single next step of the check.",
            properties: [
                .init(name: "message", description: "Short Turkish reason; the question for ask; the result for pass, issue or blocked.",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "action", schema: DynamicGenerationSchema(name: "Action", anyOf: AssistantAction.allCases.map(\.rawValue))),
                .init(name: "target", description: "Element copied from the screen list, or - for ask, pass, issue and blocked.",
                      schema: DynamicGenerationSchema(name: "Target", anyOf: targets)),
                .init(name: "text", description: "Text to type for the type action, otherwise empty.",
                      schema: DynamicGenerationSchema(type: String.self)),
            ]
        )
        // Alt şemalar property'lerin içinde tanımlı; `dependencies` yalnızca isimle referans verilen şemalar
        // içindir. Buraya da eklenirse "two or more types named Action" hatası alınır.
        return try GenerationSchema(root: decision, dependencies: [])
    }

    // MARK: - Cevabı okuma (model olmadan test edilir)

    static func decodePlan(_ content: GeneratedContent) throws -> [PlannedCheck] {
        try content.value([GeneratedContent].self, forProperty: "checks").map(decodeCheck)
    }

    static func decodeCheck(_ content: GeneratedContent) throws -> PlannedCheck {
        PlannedCheck(
            title: try content.value(String.self, forProperty: "title"),
            expectation: try content.value(String.self, forProperty: "expectation"),
            leavesScreen: try content.value(Bool.self, forProperty: "leavesScreen")
        )
    }

    static func decodeDecision(_ content: GeneratedContent) throws -> AssistantDecision {
        let rawAction = try content.value(String.self, forProperty: "action")
        guard let action = AssistantAction(rawValue: rawAction) else {
            throw AssistantModelError("Model tanınmayan bir eylem döndü: \(rawAction)")
        }
        return AssistantDecision(
            action: action,
            target: try content.value(String.self, forProperty: "target"),
            text: try content.value(String.self, forProperty: "text"),
            message: try content.value(String.self, forProperty: "message")
        )
    }

    private static func describe(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "Modelin bağlam sınırı aşıldı; hedefi kısaltın ya da daha sade bir ekranda deneyin."
        case .guardrailViolation:
            "Apple'ın güvenlik filtresi bu isteği reddetti."
        case .unsupportedLanguageOrLocale:
            "Model bu dili ya da bölgeyi desteklemiyor."
        default:
            "Model yanıt üretemedi (\(error.localizedDescription))."
        }
    }
}
#endif
