#if MISTERO
import Foundation
import MisterO

/// Cihaz içi model olmayan ortamlarda (eski cihaz, simülatör) Asistan arayüzünü denemek için kural
/// tabanlı sahte model. `MISTERO_ASSISTANT=demo` ortam değişkeniyle açılır.
struct DemoAssistantModel: FlowAssistantModel {
    let availability = AssistantAvailability.available

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        try await Task.sleep(for: .milliseconds(400))
        let onScreen = Set(context.screen.map(\.query))

        guard let answer = context.answers.first?.answer else {
            return AssistantDecision(action: .ask, target: "-", message: "Hangi e-posta ile giriş yapayım?")
        }
        let isEmail = answer.contains("@")
        let email = isEmail ? answer : "tester@mistero.app"
        switch context.steps.count {
        case 0 where onScreen.contains("email_field"):
            return AssistantDecision(action: .type, target: "email_field", text: email,
                                     message: isEmail ? "E-postayı yazıyorum."
                                                      : "Bu bir e-posta gibi görünmüyor; demo hesabıyla devam ediyorum.")
        case 1 where onScreen.contains("password_field"):
            return AssistantDecision(action: .type, target: "password_field", text: "123456", message: "Şifreyi yazıyorum.")
        case 2 where onScreen.contains("login_button"):
            return AssistantDecision(action: .tap, target: "login_button", message: "Giriş butonuna basıyorum.")
        case 3 where onScreen.contains("welcome_label"):
            return AssistantDecision(action: .assertVisible, target: "welcome_label",
                                     message: "Ana sayfanın açıldığını doğruluyorum.")
        case 4:
            return AssistantDecision(action: .finish, target: "-", message: "Giriş yapıldı ve ana sayfa doğrulandı.")
        default:
            return AssistantDecision(action: .fail, target: "-", message: "Beklediğim ekranı bulamadım.")
        }
    }
}
#endif
