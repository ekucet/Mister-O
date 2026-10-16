#if MISTERO
import Foundation
import MisterO

/// Cihaz içi model olmayan ortamlarda (eski cihaz, simülatör) Asistan'ı denemek için kural tabanlı
/// sahte model. `MISTERO_ASSISTANT=demo` ortam değişkeniyle açılır. Planı SDK'nın kural tabanlı
/// planlayıcısı çıkarır; bu model giriş ekranındaki kontrolleri ve "alanları doldur, butona bas"
/// türü istekleri bir testçi gibi koşar.
struct DemoAssistantModel: FlowAssistantModel {
    let availability = AssistantAvailability.available

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        try await Task.sleep(for: .milliseconds(300))
        let screen = Dictionary(context.screen.map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })
        let title = context.check.title
        let step = context.steps.count

        if title.hasPrefix("Boş formla") {
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: "", message: "E-postayı boşaltıyorum.")
            case 1: return .init(action: .type, target: "password_field", text: "", message: "Şifreyi boşaltıyorum.")
            case 2 where context.lastIssue == nil:
                return .init(action: .assertDisabled, target: "login_button", message: "Butonun pasif olduğunu kontrol ediyorum.")
            case 2: return .init(action: .issue, target: "-", message: "Boş formda Giriş Yap butonu aktif.")
            default: return .init(action: .pass, target: "-", message: "Boş formda Giriş Yap pasif kalıyor.")
            }
        }

        if title.hasPrefix("Geçersiz bilgilerle") {
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: "a@", message: "Eksik bir e-posta deniyorum.")
            case 1: return .init(action: .type, target: "password_field", text: "123456", message: "Geçerli uzunlukta şifre yazıyorum.")
            case 2 where screen["login_button"]?.isEnabled == false:
                return .init(action: .pass, target: "-", message: "Geçersiz e-postayla Giriş Yap pasif kalıyor.")
            case 2: return .init(action: .tap, target: "login_button", message: "Buton aktif; basıp ne olduğuna bakıyorum.")
            default:
                if screen["welcome_label"] != nil {
                    return .init(action: .issue, target: "-",
                                 message: "Geçersiz e-postayla (a@) giriş yapılabildi; ana sayfa açıldı.")
                }
                return .init(action: .pass, target: "-", message: "Geçersiz e-postayla giriş yapılamadı.")
            }
        }

        if title.hasPrefix("Geçerli bilgilerle") {
            guard let email = Self.fact(in: context, matching: ["posta", "mail"]),
                  let password = Self.fact(in: context, matching: ["şifre", "parola", "password"]) else {
                return .init(action: .ask, target: "-",
                             message: "Geçerli bir e-posta ve şifre verir misiniz? (ör. qa@firma.com 123456)")
            }
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: email, message: "E-postayı yazıyorum.")
            case 1: return .init(action: .type, target: "password_field", text: password, message: "Şifreyi yazıyorum.")
            case 2: return .init(action: .tap, target: "login_button", message: "Giriş yapıyorum.")
            case 3: return .init(action: .assertVisible, target: "welcome_label", message: "Ana sayfayı doğruluyorum.")
            default: return .init(action: .pass, target: "-", message: "Giriş yapıldı, ana sayfa açıldı.")
            }
        }

        return fillAndSubmit(context)
    }

    /// "Alanları doldur, butona bas; ilerlemeli": boş alanları türlerine göre doldurur, son aktif butona
    /// basar; form ekrandan kalktıysa geçti, kalmadıysa sorun der.
    private func fillAndSubmit(_ context: AssistantContext) -> AssistantDecision {
        let fields = context.screen.filter(\.isTextInput)
        let filled = Set(context.steps.compactMap { line -> String? in
            guard line.hasPrefix("type: "), let arrow = line.range(of: " -> ") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 6)..<arrow.lowerBound])
        })
        let tapped = context.steps.contains { $0.hasPrefix("tap: ") }

        if !tapped, let field = fields.first(where: { !filled.contains($0.query) }) {
            return .init(action: .type, target: field.query, text: value(for: field, context),
                         message: "\(field.name ?? field.query) alanını dolduruyorum.")
        }
        if !tapped {
            guard let button = context.screen.last(where: { $0.isButton && $0.isEnabled }) else {
                return .init(action: .issue, target: "-", message: "Alanlar doldu ama basılabilecek aktif bir buton yok.")
            }
            return .init(action: .tap, target: button.query, message: "\(button.name ?? button.query) butonuna basıyorum.")
        }
        return fields.isEmpty
            ? .init(action: .pass, target: "-", message: "Butona basıldı, bir sonraki ekran açıldı.")
            : .init(action: .issue, target: "-", message: "Butona basıldı ama ekran değişmedi.")
    }

    private func value(for field: ScreenElement, _ context: AssistantContext) -> String {
        switch field.inputKind {
        case "email": Self.fact(in: context, matching: ["posta", "mail"]) ?? "qa+\(Int.random(in: 1000...9999))@example.com"
        case "password": Self.fact(in: context, matching: ["şifre", "parola", "password"]) ?? "Test1234!"
        case "phone": "5551234567"
        case "number": "42"
        case "name": "Test Kullanıcı"
        default: "Mister-O test"
        }
    }

    /// Bilinen test verilerinden sorusu anahtar kelimelerden birini içerenin cevabı.
    private static func fact(in context: AssistantContext, matching keys: [String]) -> String? {
        context.answers.last { fact in keys.contains { fact.question.lowercased().contains($0) } }?.answer
    }
}
#endif
