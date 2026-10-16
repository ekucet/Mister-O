import Foundation

/// Asistanın ekranda gördüğü bir öğe (Öğeler sekmesindeki satırın aynısı).
public struct ScreenElement: Equatable, Sendable {
    /// Akışta kullanılacak sorgu: identifier, yoksa görünen ad.
    public let query: String
    public let identifier: String?
    public let name: String?
    public let kind: String

    public init(query: String, identifier: String?, name: String?, kind: String) {
        self.query = query
        self.identifier = identifier
        self.name = name
        self.kind = kind
    }
}

public enum AssistantAction: String, CaseIterable, Sendable {
    case tap
    case type
    case assertVisible
    /// Testçiye soru sor (hesap bilgisi, beklenen sonuç…).
    case ask
    /// Hedefe ulaşıldı ve doğrulandı.
    case finish
    /// Hedefe bu ekrandan ulaşılamıyor.
    case fail
}

/// Modelin bir sonraki adım kararı.
public struct AssistantDecision: Equatable, Sendable {
    public var action: AssistantAction
    public var target: String?
    public var text: String?
    /// Eylemlerde kısa gerekçe; `ask`'te soru; `finish` / `fail`'de özet.
    public var message: String?

    public init(action: AssistantAction, target: String? = nil, text: String? = nil, message: String? = nil) {
        self.action = action
        self.target = target
        self.text = text
        self.message = message
    }
}

/// Modele her adımda verilen her şey. Oturum adımlar arasında taşınmaz: küçük modelin dar bağlamı
/// (iOS 26'da 4.096 token) dolmasın diye her adımda bu özet yeniden kurulur.
public struct AssistantContext: Sendable {
    public struct Answer: Equatable, Sendable {
        public let question: String
        public let answer: String
    }

    /// Bağlamı korumak için modele gösterilen en fazla öğe sayısı.
    public static let maxScreenElements = 40

    public let goal: String
    public let answers: [Answer]
    public let steps: [String]
    public let lastIssue: String?
    public let screen: [ScreenElement]

    public init(goal: String, answers: [Answer], steps: [String], lastIssue: String?, screen: [ScreenElement]) {
        self.goal = goal
        self.answers = answers
        self.steps = steps
        self.lastIssue = lastIssue
        self.screen = Array(screen.prefix(Self.maxScreenElements))
    }

    /// Modelin seçebileceği hedefler; `-` "hedef yok" demektir.
    public var targets: [String] {
        var seen = Set<String>()
        return ["-"] + screen.map(\.query).filter { seen.insert($0).inserted }
    }

    public static let instructions = """
    You are a QA assistant that builds UI test flows for an iOS app, one step at a time.
    You receive the tester's goal, answers the tester already gave, the steps already done and the \
    elements visible on the current screen. Choose exactly one next action:
    - tap: tap an element. target = an element from the screen list.
    - type: type text into a text field. target = a text field from the list, text = what to type.
    - assertVisible: check that an element proving the expected result is on screen.
    - ask: you need information only the tester knows (credentials, expected result, which item). \
    Put the question in message and use target "-".
    - finish: the goal is reached and the last step was an assertVisible that proves it. Use target "-".
    - fail: the goal cannot be reached from this screen. Explain why in message. Use target "-".
    Rules:
    - Copy target exactly from the screen list. Never invent element names.
    - Do not repeat a step that already succeeded unless the goal needs it again.
    - If the last step failed, choose a different element or ask the tester.
    - Do not guess passwords, e-mail addresses or other test data; ask for them.
    - Write message in Turkish, in one short sentence.
    """

    public var prompt: String {
        var lines = ["Goal: \(goal)"]

        lines.append("Tester answers:")
        lines += answers.isEmpty ? ["(none)"] : answers.map { "- Q: \($0.question) A: \($0.answer)" }

        lines.append("Steps done:")
        lines += steps.isEmpty ? ["(none)"] : steps.enumerated().map { "\($0.offset + 1). \($0.element)" }

        if let lastIssue {
            lines.append("Last problem: \(lastIssue)")
        }

        lines.append("Screen elements (target | visible name | kind):")
        lines += screen.isEmpty ? ["(none)"] : screen.map { element in
            let name = element.name.map { String($0.prefix(60)) } ?? "-"
            return "- \(element.query) | \(name) | \(element.kind)"
        }
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
/// (`AppleFlowAssistantModel`); başka bir model (şirket proxy'si, Mac'teki Ollama…) bu protokolle eklenebilir.
public protocol FlowAssistantModel: Sendable {
    var availability: AssistantAvailability { get }
    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision
}
