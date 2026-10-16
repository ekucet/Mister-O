import Combine
import Foundation

/// Testçinin anlattığı hedeften, uygulamayı adım adım gezerek doğrulanmış bir akış çıkarır.
///
/// Her turda o anki ekran modele verilir, model tek bir adım önerir. Adım çalıştırılır ve yalnızca
/// başarılı olursa akışa eklenir; ardından yeni ekranla bir sonraki tura geçilir. Böylece sonraki
/// ekranların id'leri de o ekrana gelindiğinde öğrenilir ve çıkan akışın her adımı bir kez geçmiş olur.
///
/// - Onaylı mod (varsayılan): her adım testçinin onayıyla çalışır.
/// - Otomatik mod (`autoAdvance`): asistan onay beklemeden ilerler; testi baştan sona modelin
///   koşması demektir. Sonuç kararını da model verir, bu yüzden kalıcı testler için çıkan akışı
///   kataloğa almak daha güvenilirdir.
@MainActor
public final class FlowAssistant: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case thinking
        case awaitingApproval(line: String, reason: String?)
        case awaitingAnswer(String)
        case running(String)
        case finished(String)
        case failed(String)
    }

    public struct Message: Identifiable, Equatable, Sendable {
        public enum Role: Equatable, Sendable {
            case tester
            case assistant
            case step(passed: Bool)
            case note
        }

        public let id: Int
        public let role: Role
        public let text: String
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var messages: [Message] = []
    /// Başarıyla çalışmış, akışa giren adımlar.
    @Published public private(set) var steps: [String] = []
    @Published public private(set) var goal = ""
    /// Onay beklemeden ilerle.
    @Published public var autoAdvance = false

    public let model: any FlowAssistantModel
    private let runner: InAppTestRunner
    private let screen: @MainActor () -> [ScreenElement]
    private let maxSteps: Int
    private let maxFailuresInARow: Int
    private let settleTime: Duration
    private var answers: [AssistantContext.Answer] = []
    private var lastIssue: String?
    private var failuresInARow = 0
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - screen: O anki ekrandaki öğeleri döner (UIKit katmanında `ViewResolver.inspect()`).
    ///   - settleTime: Her adımdan sonra ekran yeniden okunmadan önce beklenen süre. Navigasyon
    ///     animasyonu sürerken okunursa yeni ekranın öğeleri henüz görünmez.
    public init(
        model: any FlowAssistantModel,
        runner: InAppTestRunner,
        screen: @escaping @MainActor () -> [ScreenElement],
        maxSteps: Int = 25,
        maxFailuresInARow: Int = 3,
        settleTime: Duration = .milliseconds(700)
    ) {
        self.model = model
        self.runner = runner
        self.screen = screen
        self.maxSteps = maxSteps
        self.maxFailuresInARow = maxFailuresInARow
        self.settleTime = settleTime
    }

    public var availability: AssistantAvailability { model.availability }

    /// Model düşünüyor ya da bir adım çalışıyor.
    public var isWorking: Bool {
        switch phase {
        case .thinking, .running: true
        default: false
        }
    }

    /// Doğrulanmış akış metni.
    public var script: String { steps.joined(separator: "\n") }

    // MARK: - Testçi eylemleri

    public func start(goal: String) {
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return }
        task?.cancel()
        self.goal = goal
        messages = []
        steps = []
        answers = []
        lastIssue = nil
        failuresInARow = 0
        append(.tester, goal)
        launch { await $0.think() }
    }

    public func answer(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .awaitingAnswer(let question) = phase, !text.isEmpty else { return }
        answers.append(.init(question: question, answer: text))
        append(.tester, text)
        launch { await $0.think() }
    }

    public func approve() {
        guard case .awaitingApproval(let line, _) = phase else { return }
        launch(.running(line)) { assistant in
            await assistant.execute(line)
            await assistant.think()
        }
    }

    /// Önerilen adımı istemedi; modele nedeniyle birlikte geri bildirilir.
    public func reject(_ feedback: String = "") {
        guard case .awaitingApproval(let line, _) = phase else { return }
        let feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        lastIssue = "The tester rejected '\(line)'" + (feedback.isEmpty ? "." : ": \(feedback)")
        append(.tester, feedback.isEmpty ? "Başka bir adım öner." : feedback)
        launch { await $0.think() }
    }

    /// Bitmiş ya da durmuş bir oturumu yeni bir istekle sürdürür ("şimdi bir de sepeti kontrol et").
    public func continueWith(_ instruction: String) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !isWorking else { return }
        goal += "\nThen: \(instruction)"
        lastIssue = nil
        failuresInARow = 0
        append(.tester, instruction)
        launch { await $0.think() }
    }

    public func stop() {
        task?.cancel()
        task = nil
        runner.cancel()
        if case .finished = phase { return }
        phase = .failed("Durduruldu.")
        append(.note, "Durduruldu.")
    }

    // MARK: - Döngü

    /// Fazı hemen günceller (arayüz anında tepki versin, çift dokunuş ikinci bir tur başlatmasın),
    /// sonra işi arka planda sürdürür.
    private func launch(_ immediatePhase: Phase = .thinking,
                        _ operation: @escaping @MainActor (FlowAssistant) async -> Void) {
        task?.cancel()
        phase = immediatePhase
        task = Task { await operation(self) }
    }

    /// Kullanıcı girdisi gerekene ya da hedefe ulaşılana kadar tur atar.
    private func think() async {
        while !Task.isCancelled {
            guard steps.count < maxSteps else {
                finish(failing: "Adım sınırına (\(maxSteps)) ulaşıldı.")
                return
            }
            guard failuresInARow < maxFailuresInARow else {
                finish(failing: "Üst üste \(maxFailuresInARow) adım başarısız oldu. Hedefi netleştirip tekrar deneyin.")
                return
            }

            phase = .thinking
            let context = AssistantContext(goal: goal, answers: answers, steps: steps, lastIssue: lastIssue,
                                           screen: screen())
            let decision: AssistantDecision
            do {
                decision = try await model.nextDecision(for: context)
            } catch {
                if Task.isCancelled { return }
                finish(failing: "Model hata verdi: \(error.localizedDescription)")
                return
            }
            if Task.isCancelled { return }

            switch decision.action {
            case .ask:
                let question = decision.message?.nonEmpty ?? "Devam etmek için bilgiye ihtiyacım var."
                append(.assistant, question)
                phase = .awaitingAnswer(question)
                return

            case .finish:
                let summary = decision.message?.nonEmpty ?? "Hedefe ulaşıldı."
                append(.assistant, summary)
                phase = .finished(summary)
                return

            case .fail:
                finish(failing: decision.message?.nonEmpty ?? "Hedefe bu ekrandan ulaşılamıyor.")
                return

            case .tap, .type, .assertVisible:
                guard let line = Self.line(for: decision, allowedTargets: context.targets) else {
                    lastIssue = "Your last answer had no valid target from the screen list."
                    failuresInARow += 1
                    continue
                }
                if autoAdvance {
                    await execute(line)
                    continue
                }
                if let reason = decision.message?.nonEmpty {
                    append(.assistant, reason)
                }
                phase = .awaitingApproval(line: line, reason: decision.message?.nonEmpty)
                return
            }
        }
    }

    private func execute(_ line: String) async {
        phase = .running(line)
        let state = await runner.run(line)
        if Task.isCancelled { return }

        if state == .passed {
            steps.append(line)
            lastIssue = nil
            failuresInARow = 0
            append(.step(passed: true), line)
        } else {
            let reason = runner.results.lazy.compactMap { result -> String? in
                if case .failed(let message) = result.status { return message }
                return nil
            }.first ?? runner.parseIssues.first?.message ?? state.title
            lastIssue = "'\(line)' failed: \(reason)"
            failuresInARow += 1
            append(.step(passed: false), "\(line) — \(reason)")
        }
        try? await Task.sleep(for: settleTime)
    }

    private func finish(failing message: String) {
        append(.note, message)
        phase = .failed(message)
    }

    private func append(_ role: Message.Role, _ text: String) {
        messages.append(Message(id: messages.count, role: role, text: text))
    }

    /// Model kararını akış satırına çevirir; hedef ekranda yoksa `nil`.
    static func line(for decision: AssistantDecision, allowedTargets: [String]) -> String? {
        guard let target = decision.target?.trimmingCharacters(in: .whitespaces), target != "-",
              allowedTargets.contains(target) else { return nil }
        let selector = FlowParser.literal(target)
        switch decision.action {
        case .tap: return "tap: \(selector)"
        case .assertVisible: return "assertVisible: \(selector)"
        case .type: return "type: \(selector) -> \(FlowParser.literal(decision.text ?? ""))"
        case .ask, .finish, .fail: return nil
        }
    }

    // MARK: - Dışa aktarma

    /// Kataloğa yapıştırılacak JSON kaydı (`scenarios` dizisinin bir elemanı). Alan sırası katalog
    /// örnekleriyle aynı tutulur; `JSONEncoder` her platformda sırayı korumadığı için elle yazılır.
    public func catalogEntry(name: String, tags: [String] = []) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func json(_ value: String) throws -> String {
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }

        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = goal.replacingOccurrences(of: "\nThen: ", with: ", sonra ")
        let tagList = try tags.map(json).joined(separator: ", ")
        let stepLines = try steps.map { "    \(try json($0))" }.joined(separator: ",\n")
        return """
        {
          "id": \(try json(Scenario.slug(name))),
          "name": \(try json(name)),
          "description": \(try json(description)),
          "tags": [\(tagList)],
          "steps": [
        \(stepLines)
          ]
        }
        """
    }
}
