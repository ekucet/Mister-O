#if MISTERO
import Foundation
import MisterO

/// Cihaz içi model olmayan ortamlarda (eski cihaz, simülatör) Asistan'ı denemek için kural tabanlı
/// sahte model. `MISTERO_ASSISTANT=demo` ortam değişkeniyle açılır. Planı SDK'nın kural tabanlı
/// planlayıcısı çıkarır; bu model giriş ekranındaki kontrolleri ve "alanları doldur, butona bas"
/// türü istekleri bir testçi gibi koşar. Mesajlarını panelin dilinde (`MisterOLanguage.current`) yazar.
struct DemoAssistantModel: FlowAssistantModel {
    let availability = AssistantAvailability.available

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        try await Task.sleep(for: .milliseconds(300))
        let screen = Dictionary(context.screen.map { ($0.query, $0) }, uniquingKeysWith: { first, _ in first })
        let title = context.check.title
        let step = context.steps.count

        // Kural tabanlı planlayıcının başlıkları, iki dilde.
        if title.hasPrefix("Boş formla") || title.contains("with an empty form") {
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: "", message: t("Clearing the e-mail.", "E-postayı boşaltıyorum."))
            case 1: return .init(action: .type, target: "password_field", text: "", message: t("Clearing the password.", "Şifreyi boşaltıyorum."))
            case 2 where context.lastIssue == nil:
                return .init(action: .assertDisabled, target: "login_button",
                             message: t("Checking that the button is disabled.", "Butonun pasif olduğunu kontrol ediyorum."))
            case 2: return .init(action: .issue, target: "-", message: t("Giriş Yap is enabled on an empty form.", "Boş formda Giriş Yap butonu aktif."))
            default: return .init(action: .pass, target: "-", message: t("Giriş Yap stays disabled on an empty form.", "Boş formda Giriş Yap pasif kalıyor."))
            }
        }

        if title.hasPrefix("Geçersiz bilgilerle") || title.contains("with invalid details") {
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: "a@", message: t("Trying an incomplete e-mail.", "Eksik bir e-posta deniyorum."))
            case 1: return .init(action: .type, target: "password_field", text: "123456",
                                 message: t("Typing a password of valid length.", "Geçerli uzunlukta şifre yazıyorum."))
            case 2 where screen["login_button"]?.isEnabled == false:
                return .init(action: .pass, target: "-",
                             message: t("Giriş Yap stays disabled with an invalid e-mail.", "Geçersiz e-postayla Giriş Yap pasif kalıyor."))
            case 2: return .init(action: .tap, target: "login_button",
                                 message: t("The button is enabled; tapping it to see what happens.", "Buton aktif; basıp ne olduğuna bakıyorum."))
            default:
                if screen["welcome_label"] != nil {
                    return .init(action: .issue, target: "-",
                                 message: t("Signed in with an invalid e-mail (a@); the home screen opened.",
                                            "Geçersiz e-postayla (a@) giriş yapılabildi; ana sayfa açıldı."))
                }
                return .init(action: .pass, target: "-", message: t("Couldn't sign in with an invalid e-mail.", "Geçersiz e-postayla giriş yapılamadı."))
            }
        }

        if title.hasPrefix("Geçerli bilgilerle") || title.contains("with valid details") {
            guard let email = Self.fact(in: context, matching: ["posta", "mail"]),
                  let password = Self.fact(in: context, matching: ["şifre", "parola", "password"]) else {
                return .init(action: .ask, target: "-",
                             message: t("Could you give me a valid e-mail and password? (e.g. qa@acme.com 123456)",
                                        "Geçerli bir e-posta ve şifre verir misiniz? (ör. qa@firma.com 123456)"))
            }
            switch step {
            case 0: return .init(action: .type, target: "email_field", text: email, message: t("Typing the e-mail.", "E-postayı yazıyorum."))
            case 1: return .init(action: .type, target: "password_field", text: password, message: t("Typing the password.", "Şifreyi yazıyorum."))
            case 2: return .init(action: .tap, target: "login_button", message: t("Signing in.", "Giriş yapıyorum."))
            case 3: return .init(action: .assertVisible, target: "welcome_label", message: t("Checking the home screen.", "Ana sayfayı doğruluyorum."))
            default: return .init(action: .pass, target: "-", message: t("Signed in; the home screen opened.", "Giriş yapıldı, ana sayfa açıldı."))
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
            let name = field.name ?? field.query
            return .init(action: .type, target: field.query, text: value(for: field, context),
                         message: t("Filling in \(name).", "\(name) alanını dolduruyorum."))
        }
        if !tapped {
            guard let button = context.screen.last(where: { $0.isButton && $0.isEnabled }) else {
                return .init(action: .issue, target: "-",
                             message: t("The fields are filled but there's no enabled button to tap.", "Alanlar doldu ama basılabilecek aktif bir buton yok."))
            }
            let name = button.name ?? button.query
            return .init(action: .tap, target: button.query, message: t("Tapping \(name).", "\(name) butonuna basıyorum."))
        }
        return fields.isEmpty
            ? .init(action: .pass, target: "-", message: t("Tapped the button; the next screen opened.", "Butona basıldı, bir sonraki ekran açıldı."))
            : .init(action: .issue, target: "-", message: t("Tapped the button but the screen didn't change.", "Butona basıldı ama ekran değişmedi."))
    }

    /// Panelin dilindeki metin.
    private func t(_ english: String, _ turkish: String) -> String {
        MisterOLanguage.current == .turkish ? turkish : english
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
