import Foundation

/// Asistanın ekranda gördüğü bir öğe (Öğeler sekmesindeki satırın aynısı, durumuyla birlikte).
public struct ScreenElement: Equatable, Sendable {
    /// Akışta kullanılacak sorgu: identifier, yoksa görünen ad.
    public let query: String
    public let identifier: String?
    public let name: String?
    public let kind: String
    public let isEnabled: Bool
    /// Metin alanının içeriği (gizli alanlarda yalnızca dolu/boş bilgisi).
    public let value: String?
    /// Metin alanının beklediği veri: "email", "phone", "password", "code", "number", "url", "name", "text".
    public let inputKind: String?

    public init(query: String, identifier: String?, name: String?, kind: String,
                isEnabled: Bool = true, value: String? = nil, inputKind: String? = nil) {
        self.query = query
        self.identifier = identifier
        self.name = name
        self.kind = kind
        self.isEnabled = isEnabled
        self.value = value
        self.inputKind = inputKind
    }

    public var isTextInput: Bool {
        ["TextField", "TextView", "SearchField"].contains { kind.contains($0) }
    }

    public var isButton: Bool {
        !isTextInput && (kind.contains("Button") || kind.contains("Link"))
    }

    /// Modele gösterilen satır: `- login_button | Giriş Yap | Button · AX | disabled`
    var promptLine: String {
        var parts = [query, name.map { String($0.prefix(60)) } ?? "-", kind]
        if !isEnabled { parts.append("disabled") }
        if isTextInput {
            if let inputKind { parts.append("input: \(inputKind)") }
            parts.append(value.map { "value: \"\($0.prefix(40))\"" } ?? "empty")
        }
        return "- " + parts.joined(separator: " | ")
    }
}

/// Asistanın bildiği bir test bilgisi (hesap, şifre…). Testçinin cevapları ya da uygulamanın verdiği
/// `testData`; tüm kontrollerde kullanılır.
public struct AssistantAnswer: Equatable, Codable, Sendable {
    public let question: String
    public let answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// Asistanın bir ekranda koşacağı tek bir kontrol.
public struct PlannedCheck: Equatable, Sendable {
    /// "Boş formla giriş yapılamamalı"
    public var title: String
    /// "Giriş Yap butonu pasif kalmalı ya da hata görünmeli"
    public var expectation: String
    /// Başarılı olursa ekrandan ayrılır mı (örn. başarılı giriş); bu kontroller sona alınır.
    public var leavesScreen: Bool
    /// Testçinin kendi cümlesi ("alanları doldur, Kaydet'e bas; sonraki ekran açılmalı"). Başlık
    /// kısaltılsa da içindeki değerler kaybolmasın diye modele aynen gösterilir.
    public var request: String?

    public init(title: String, expectation: String, leavesScreen: Bool = false, request: String? = nil) {
        self.title = title
        self.expectation = expectation
        self.leavesScreen = leavesScreen
        self.request = request
    }
}

public enum AssistantAction: String, CaseIterable, Sendable {
    case tap
    case type
    case assertVisible
    case assertNotVisible
    case assertEnabled
    case assertDisabled
    /// Testçiden bilgi iste (hesap, şifre, hangi ürün…).
    case ask
    /// Beklenen davranış doğrulandı.
    case pass
    /// Uygulama beklendiği gibi davranmadı: olası hata.
    case issue
    /// Kontrol bu ekranda sürdürülemiyor.
    case blocked
}

/// Modelin bir sonraki adım kararı.
public struct AssistantDecision: Equatable, Sendable {
    public var action: AssistantAction
    public var target: String?
    public var text: String?
    /// Eylemlerde kısa gerekçe; `ask`'te soru; `pass` / `issue` / `blocked`'da özet.
    public var message: String?

    public init(action: AssistantAction, target: String? = nil, text: String? = nil, message: String? = nil) {
        self.action = action
        self.target = target
        self.text = text
        self.message = message
    }
}

/// Plan çıkarırken modele verilenler.
public struct PlanContext: Sendable {
    public static let maxChecks = 4
    /// Modele gösterilen en fazla öğe sayısı (küçük modelin dar bağlamı için).
    public static let maxScreenElements = 40

    /// Testçinin odak isteği ("sadece şifre alanını dene"); yoksa ekranın tamamı.
    public let focus: String?
    public let screen: [ScreenElement]
    public let answers: [AssistantAnswer]

    public init(focus: String?, screen: [ScreenElement], answers: [AssistantAnswer] = []) {
        self.focus = focus
        self.screen = Array(screen.prefix(Self.maxScreenElements))
        self.answers = answers
    }

    public static let instructions = """
    You are an iOS QA tester. Look at the elements on the current screen and propose up to 4 quick \
    checks a tester would run here.
    - Each check must be doable on this screen by tapping, typing and looking at the result.
    - Prefer checks that find bugs: empty or invalid input, disabled buttons, error messages, and the \
    main happy path.
    - A check that leaves this screen (for example a successful submit) must set leavesScreen to true.
    - title: a short Turkish sentence that names the check. expectation: what should happen, in Turkish.
    - If the tester gave a focus, every check must be about it.
    """

    /// Testçinin cümlesini tek bir kontrole çevirmek için.
    public static let requestInstructions = """
    You turn a tester's request into one check for the current iOS screen.
    - title: the request as a short Turkish sentence. Keep any values the tester gave.
    - expectation: what should happen if the app works, as the tester described it, in Turkish. If the \
    tester didn't say, infer the most likely result (for example the next screen opens).
    - leavesScreen: true if success most likely opens another screen.
    """

    public var prompt: String {
        var lines = ["Focus: \(focus ?? "(the whole screen)")"]
        if !answers.isEmpty {
            lines.append("Facts from the tester:")
            lines += answers.map { "- \($0.question) → \($0.answer)" }
        }
        lines.append("Screen elements (target | visible name | kind | state):")
        lines += screen.isEmpty ? ["(none)"] : screen.map(\.promptLine)
        return lines.joined(separator: "\n")
    }
}

/// Bir kontrolün her adımında modele verilenler. Oturum adımlar arasında taşınmaz: küçük modelin dar
/// bağlamı (iOS 26'da 4.096 token) dolmasın diye her adımda bu özet yeniden kurulur.
public struct AssistantContext: Sendable {
    public let check: PlannedCheck
    public let answers: [AssistantAnswer]
    public let steps: [String]
    public let lastIssue: String?
    public let screen: [ScreenElement]

    public init(check: PlannedCheck, answers: [AssistantAnswer], steps: [String], lastIssue: String?,
                screen: [ScreenElement]) {
        self.check = check
        self.answers = answers
        self.steps = steps
        self.lastIssue = lastIssue
        self.screen = Array(screen.prefix(PlanContext.maxScreenElements))
    }

    /// Modelin seçebileceği hedefler; `-` "hedef yok" demektir.
    public var targets: [String] {
        var seen = Set<String>()
        return ["-"] + screen.map(\.query).filter { seen.insert($0).inserted }
    }

    public static let instructions = """
    You are an iOS QA tester running one check on the current app, one step at a time. Each turn you \
    get the check, what should happen, facts from the tester, the steps already done and the elements \
    visible now. Choose exactly one next action:
    - tap, type: act on an element. type also needs text; type an empty text to clear a field.
    - assertVisible, assertNotVisible, assertEnabled, assertDisabled: verify the expected result.
    - pass: the expected behavior is confirmed, by a verify step or clearly by the element states.
    - issue: the app clearly did NOT behave as expected. Describe what happened.
    - ask: you need data only the tester knows (an account, a password, which item). Put the question \
    in message.
    - blocked: the check cannot continue here. Explain why.
    Rules:
    - Copy target exactly from the screen list. Use "-" for ask, pass, issue and blocked.
    - Elements marked disabled cannot be tapped.
    - Use the facts first. Fill ordinary fields yourself with realistic test data that fits the field \
    (its input kind and name), for example a unique e-mail like qa+4821@example.com when signing up.
    - Ask only for data that must already exist in the system: an existing account and its password, \
    a verification code, an existing order number.
    - Obviously invalid values such as "abc" or "a@" are fine for negative checks.
    - Finish within 8 steps. Write message in Turkish, in one short sentence.
    """

    public var prompt: String {
        var lines = [
            "Check: \(check.title)",
            "Expected: \(check.expectation)",
        ]
        if let request = check.request, request != check.title {
            lines.append("Tester's request: \(request)")
        }
        if !answers.isEmpty {
            lines.append("Facts from the tester:")
            lines += answers.map { "- \($0.question) → \($0.answer)" }
        }
        lines.append("Steps done:")
        lines += steps.isEmpty ? ["(none)"] : steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if let lastIssue {
            lines.append("Last problem: \(lastIssue)")
        }
        lines.append("Screen elements (target | visible name | kind | state):")
        lines += screen.isEmpty ? ["(none)"] : screen.map(\.promptLine)
        return lines.joined(separator: "\n")
    }
}

public enum AssistantAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public struct AssistantModelError: LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Asistanın arkasındaki dil modeli. Varsayılan uygulama Apple'ın cihaz içi modelidir
/// (`AppleFlowAssistantModel`); başka bir model (şirket proxy'si, ağdaki bir Mac…) bu protokolle eklenebilir.
public protocol FlowAssistantModel: Sendable {
    var availability: AssistantAvailability { get }
    /// Ekran için kontrol listesi. Varsayılan uygulama model kullanmayan `HeuristicPlanner`'dır.
    func plan(for context: PlanContext) async throws -> [PlannedCheck]
    /// Testçinin cümlesini tek bir kontrole çevirir (başlık, beklenen sonuç). Varsayılan uygulama kural tabanlıdır.
    func check(for request: String, context: PlanContext) async throws -> PlannedCheck
    /// Bir kontrolün sıradaki adımı.
    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision
}

extension FlowAssistantModel {
    public func plan(for context: PlanContext) async throws -> [PlannedCheck] {
        HeuristicPlanner.plan(context)
    }

    public func check(for request: String, context: PlanContext) async throws -> PlannedCheck {
        HeuristicPlanner.check(for: request)
    }
}

/// Model kullanmadan ekrandaki öğelere bakarak tipik kontrolleri çıkarır. Modeli olmayan
/// özel arka uçların ve modelin boş plan döndürdüğü durumların yedeğidir.
public enum HeuristicPlanner {
    /// "E-postaya x yaz, Giriş Yap'a bas; ana sayfa açılmalı" → beklenen: "Ana sayfa açılmalı."
    /// Beklenen sonuç, "-malı/-meli" (ya da should/must) içeren son cümlecikten alınır.
    public static func check(for request: String) -> PlannedCheck {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let clauses = text.split(whereSeparator: { ";.,\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let expectation = clauses.last { clause in
            clause.lowercased().split(separator: " ").contains { word in
                word.hasSuffix("malı") || word.hasSuffix("meli") || word.hasSuffix("malıdır")
                    || word.hasSuffix("melidir") || word == "should" || word == "must"
            }
        }
        return PlannedCheck(
            title: text,
            // Türkçe büyük harf: "ilerlemeli" → "İlerlemeli" (varsayılan yerelde "I" olurdu).
            expectation: expectation.map { $0.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + $0.dropFirst() + "." }
                ?? "İstenen davranış gerçekleşmeli ve ekranda doğrulanmalı.",
            leavesScreen: true,
            request: text
        )
    }

    public static func plan(_ context: PlanContext) -> [PlannedCheck] {
        if let focus = context.focus?.nonEmpty {
            return [check(for: focus)]
        }

        let screen = context.screen
        let lastField = screen.lastIndex(where: \.isTextInput)
        let buttons = screen.enumerated().filter { $0.element.isButton }
        // Form varsa: alanlardan sonra gelen ilk buton gönder butonudur.
        if let lastField, let submit = buttons.first(where: { $0.offset > lastField })?.element ?? buttons.last?.element {
            let name = "“\(submit.name ?? submit.query)”"
            return [
                PlannedCheck(title: "Boş formla \(name) çalışmamalı",
                             expectation: "\(name) pasif kalmalı ya da bir hata mesajı görünmeli."),
                PlannedCheck(title: "Geçersiz bilgilerle \(name) çalışmamalı",
                             expectation: "Hata görünmeli ya da \(name) pasif kalmalı; ekran değişmemeli."),
                PlannedCheck(title: "Geçerli bilgilerle \(name) çalışmalı",
                             expectation: "Bir sonraki ekran açılmalı.", leavesScreen: true),
            ]
        }

        return buttons.prefix(3).map { _, button in
            let name = "“\(button.name ?? button.query)”"
            return PlannedCheck(title: "\(name) bir şey yapmalı",
                                expectation: "Dokununca yeni bir ekran ya da görünür bir değişiklik olmalı.",
                                leavesScreen: true)
        }
    }
}
