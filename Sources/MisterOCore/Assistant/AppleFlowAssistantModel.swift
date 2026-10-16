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

    public func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        let session = LanguageModelSession(instructions: AssistantContext.instructions)
        let response: LanguageModelSession.Response<GeneratedContent>
        do {
            response = try await session.respond(
                to: context.prompt,
                schema: try Self.schema(targets: context.targets),
                options: GenerationOptions(temperature: temperature)
            )
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

        let content = response.content
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

    /// Alan sırası bilerek böyle: önce kısa gerekçe, sonra karar. Küçük model "düşünüp" seçince daha isabetli.
    static func schema(targets: [String]) throws -> GenerationSchema {
        let action = DynamicGenerationSchema(name: "Action", anyOf: AssistantAction.allCases.map(\.rawValue))
        let target = DynamicGenerationSchema(name: "Target", anyOf: targets)
        let decision = DynamicGenerationSchema(
            name: "Decision",
            description: "The single next step of the UI test flow.",
            properties: [
                .init(name: "message", description: "Short Turkish reason; the question for ask; the summary for finish or fail.",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "action", schema: action),
                .init(name: "target", description: "Element to act on, copied from the screen list, or - for ask, finish and fail.",
                      schema: target),
                .init(name: "text", description: "Text to type for the type action, otherwise empty.",
                      schema: DynamicGenerationSchema(type: String.self)),
            ]
        )
        // Alt şemalar property'lerin içinde tanımlı; `dependencies` yalnızca isimle referans verilen şemalar
        // içindir. Buraya da eklenirse "two or more types named Action" hatası alınır.
        return try GenerationSchema(root: decision, dependencies: [])
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
