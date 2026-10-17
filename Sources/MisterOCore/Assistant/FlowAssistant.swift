import Combine
import Foundation

/// Asistanın her kontrolden önce başlangıç ekranına dönebilmesi için. UIKit uygulaması
/// `MisterO` modülündedir (açık sayfaları kapatır, navigasyonu başlangıç ekranına geri alır).
@MainActor
public protocol ScreenNavigating: AnyObject {
    /// Testin başladığı ekranı hatırlar.
    func markStart()
    /// Başlangıç ekranı uygulamanın kök ekranı mı (navigasyonun ilki, üstünde açık sayfa yok)?
    /// Öyleyse kaydedilen senaryolar `resetApp` ile her yerden bu ekrana dönüp koşabilir.
    var startIsAppRoot: Bool { get }
    /// Başlangıç ekranına dönmeyi dener. Başarıyı asistan ekranı karşılaştırarak anlar.
    func returnToStart() async
}

/// Testçinin verdiği bilgileri (hesap, şifre…) oturumlar arasında saklar. UIKit uygulaması Keychain kullanır.
@MainActor
public protocol AssistantMemory: AnyObject {
    func load() -> [AssistantAnswer]
    func save(_ answers: [AssistantAnswer])
}

@MainActor
public final class InMemoryAssistantMemory: AssistantMemory {
    private var stored: [AssistantAnswer]

    public init(_ answers: [AssistantAnswer] = []) {
        stored = answers
    }

    public func load() -> [AssistantAnswer] { stored }
    public func save(_ answers: [AssistantAnswer]) { stored = answers }
}

@MainActor
public final class NoopNavigator: ScreenNavigating {
    public init() {}
    public func markStart() {}
    public var startIsAppRoot: Bool { false }
    public func returnToStart() async {}
}

/// Ekranı kendi başına test eden asistan.
///
/// 1. `explore()` o anki ekrana bakar ve birkaç kontrol planlar ("Boş formla giriş yapılamamalı"…).
/// 2. Kontrolleri onay beklemeden sırayla koşar; her birinden önce başlangıç ekranına döner.
///    Her adım gerçekten çalıştırılır, yalnızca geçen adımlar kontrolün akışına girer.
/// 3. Her kontrol bir sonuçla biter: geçti, sorun, bilgi bekliyor, sürdürülemedi.
/// 4. Testçi raporla konuşarak ilerler: bilgi verir (`answer`), yeniden dener (`retry`), yeni kontrol
///    ister (`addCheck`); geçen kontrolü senaryo, sorunu hata kaydı olarak dışa aktarır.
@MainActor
public final class FlowAssistant: ObservableObject {
    public struct Check: Identifiable, Equatable, Sendable {
        public enum Status: Equatable, Sendable {
            case pending
            case running
            case passed(String)
            case issue(String)
            case needsInput(String)
            case blocked(String)
            case skipped(String)

            public var isFinished: Bool {
                switch self {
                case .pending, .running: false
                default: true
                }
            }
        }

        /// Denenen bir adım (geçen ya da düşen).
        public struct Attempt: Equatable, Sendable {
            public let line: String
            public let passed: Bool
            public let note: String?
        }

        public let id: Int
        public internal(set) var plan: PlannedCheck
        /// Onarılan senaryo: kontrol geçerse adımları bu senaryoya yazılabilir.
        public let repairs: Scenario?
        public internal(set) var status: Status = .pending
        /// Geçen adımlar: kontrolün akışı.
        public internal(set) var steps: [String] = []
        public internal(set) var attempts: [Attempt] = []
        /// Şu an çalışan adım.
        public internal(set) var currentLine: String?
        /// Takip aracında açılan kayıt; aynı sorun için ikinci kayıt açılmasın diye saklanır.
        public internal(set) var issueReceipt: IssueReceipt?
        public internal(set) var issueError: String?
        /// Kontrol sorunla bittiği andaki ekranın PNG'si; hata kaydına `screenshot.png` olarak eklenir.
        public internal(set) var screenshot: Data?
        /// Taslak olarak (ya da onarım olarak) kaydedildi.
        public internal(set) var isSaved = false

        public var title: String { plan.title }
    }

    public enum Stage: Equatable, Sendable {
        case idle
        case planning
        case running
        case finished
        case failed(String)
    }

    public struct Summary: Equatable, Sendable {
        public var total = 0
        public var passed = 0
        public var issues = 0
        public var needsInput = 0
        public var blocked = 0
        public var skipped = 0
    }

    @Published public private(set) var stage: Stage = .idle
    @Published public private(set) var checks: [Check] = []
    /// Testçinin verdiği bilgiler; cihazda saklanır ve tüm kontrollerde kullanılır.
    @Published public private(set) var answers: [AssistantAnswer] = []
    /// Uygulamanın kurulumda verdiği test verileri (`testData`); testçi silemez.
    public let appFacts: [AssistantAnswer]
    @Published public private(set) var focus: String?
    /// Kaydı açılmakta olan kontroller.
    @Published public private(set) var openingIssues: Set<Check.ID> = []

    public let model: any FlowAssistantModel
    private let runner: InAppTestRunner
    private let screen: @MainActor () -> [ScreenElement]
    private let captureScreenshot: (@MainActor () -> Data?)?
    private let navigator: any ScreenNavigating
    private let resetApp: (@MainActor () async -> Void)?
    private let memory: (any AssistantMemory)?
    private let maxStepsPerCheck: Int
    private let maxFailuresInARow: Int
    private let settleTime: Duration
    private var startSignature: Set<String> = []
    private var nextID = 0
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - runner: Asistana ayrılmış runner (kısa bekleme süresiyle; asistan "öğe yok" cevabını hızlı almalı).
    ///   - screen: O anki ekrandaki öğeler (UIKit katmanında `ViewResolver.inspect()`).
    ///   - screenshot: O anki ekranın PNG'si; sorunla biten kontrollerde alınır ve hata kaydına eklenir.
    ///   - navigator: Kontroller arasında başlangıç ekranına dönmek için.
    ///   - resetApp: Dönüş başarısız olursa son çare; uygulamayı başlangıç durumuna getirir.
    ///   - settleTime: Her adımdan sonra ekran yeniden okunmadan önce beklenen süre.
    public init(
        model: any FlowAssistantModel,
        runner: InAppTestRunner,
        screen: @escaping @MainActor () -> [ScreenElement],
        screenshot: (@MainActor () -> Data?)? = nil,
        navigator: any ScreenNavigating = NoopNavigator(),
        resetApp: (@MainActor () async -> Void)? = nil,
        appFacts: [AssistantAnswer] = [],
        memory: (any AssistantMemory)? = nil,
        maxStepsPerCheck: Int = 8,
        maxFailuresInARow: Int = 3,
        settleTime: Duration = .milliseconds(700)
    ) {
        self.model = model
        self.runner = runner
        self.screen = screen
        self.captureScreenshot = screenshot
        self.navigator = navigator
        self.resetApp = resetApp
        self.appFacts = appFacts
        self.memory = memory
        self.answers = memory?.load() ?? []
        self.maxStepsPerCheck = maxStepsPerCheck
        self.maxFailuresInARow = maxFailuresInARow
        self.settleTime = settleTime
    }

    public var availability: AssistantAvailability { model.availability }

    public var isWorking: Bool {
        stage == .planning || stage == .running
    }

    /// Modele verilen tüm bilgiler: önce uygulamanınkiler, sonra testçininkiler.
    public var knownFacts: [AssistantAnswer] { appFacts + answers }

    public var summary: Summary {
        var summary = Summary(total: checks.count)
        for check in checks {
            switch check.status {
            case .passed: summary.passed += 1
            case .issue: summary.issues += 1
            case .needsInput: summary.needsInput += 1
            case .blocked: summary.blocked += 1
            case .skipped: summary.skipped += 1
            case .pending, .running: break
            }
        }
        return summary
    }

    /// "3 kontrol · 1 geçti · 1 sorun · 1 bilgi bekliyor"
    public var summaryText: String {
        let s = summary
        var parts = ["\(s.total) kontrol"]
        if s.passed > 0 { parts.append("\(s.passed) geçti") }
        if s.issues > 0 { parts.append("\(s.issues) sorun") }
        if s.needsInput > 0 { parts.append("\(s.needsInput) bilgi bekliyor") }
        if s.blocked > 0 { parts.append("\(s.blocked) sürdürülemedi") }
        if s.skipped > 0 { parts.append("\(s.skipped) atlandı") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Testçi eylemleri

    /// O anki ekranı test et: kontrolleri planla ve hepsini koş.
    public func explore(focus: String? = nil) {
        guard !isWorking else { return }
        task?.cancel()
        self.focus = focus?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        checks = []
        markStart()
        stage = .planning
        task = Task { await self.planAndRun() }
    }

    /// "Şunu test et": testçinin cümlesini tek bir kontrol olarak koşar ("alanları doldur, Kaydet'e bas;
    /// sonraki ekran açılmalı"). Model cümleyi başlık ve beklenen sonuca ayırır; değerler korunur.
    public func addCheck(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isWorking else { return }
        if checks.isEmpty || startSignature.isEmpty { markStart() }
        let check = makeCheck(HeuristicPlanner.check(for: request))
        checks.append(check)
        stage = .running
        task?.cancel()
        task = Task {
            await self.refine(check.id, request: request)
            await self.runPending()
        }
    }

    /// Düşen bir senaryoyu amacıyla yeniden koşar; geçerse yeni adımlar `Check.repairs` üzerinden kaydedilebilir.
    public func repair(_ scenario: Scenario) {
        guard !isWorking else { return }
        let goal = scenario.goal ?? [scenario.name, scenario.summary].compactMap { $0 }.joined(separator: ". ")
        let oldSteps = scenario.script.split(whereSeparator: \.isNewline).joined(separator: "; ")
        let plan = PlannedCheck(
            title: "Onar: \(scenario.name)",
            expectation: scenario.summary ?? "Senaryonun amacı gerçekleşmeli ve ekranda doğrulanmalı.",
            leavesScreen: true,
            request: "\(goal)\n(Eski adımlar, artık çalışmıyor olabilir: \(oldSteps))"
        )
        defer { nextID += 1 }
        checks.append(Check(id: nextID, plan: plan, repairs: scenario))
        stage = .running
        task?.cancel()
        task = Task {
            if scenario.resetsApp, let resetApp = self.resetApp {
                await resetApp()
                try? await Task.sleep(for: self.settleTime)
            }
            self.markStart()
            await self.runPending()
        }
    }

    /// Kontrolün taslak/onarım olarak kaydedildiğini işaretler (rapor kapanana kadar hatırlanır).
    public func markSaved(_ id: Check.ID) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].isSaved = true
    }

    /// Sorunu takip aracında kayda çevirir; açılan kayıt kontrolde saklanır.
    public func openIssue(for id: Check.ID, environment: String, using reporter: any IssueReporter) async {
        guard let check = checks.first(where: { $0.id == id }), check.issueReceipt == nil,
              !openingIssues.contains(id) else { return }
        openingIssues.insert(id)
        defer { openingIssues.remove(id) }
        let report = bugReport(for: check, environment: environment)
        do {
            let receipt = try await reporter.open(report)
            update(id) { $0.issueReceipt = receipt; $0.issueError = nil }
        } catch {
            update(id) { $0.issueError = error.localizedDescription }
        }
    }

    private func update(_ id: Check.ID, _ change: (inout Check) -> Void) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        change(&checks[index])
    }

    /// Kaydedilen bir bilgiyi unutur.
    public func forget(_ answer: AssistantAnswer) {
        answers.removeAll { $0 == answer }
        memory?.save(answers)
    }

    public func forgetAll() {
        answers = []
        memory?.save(answers)
    }

    /// Bilgi bekleyen kontrole cevap verir ve kontrolü yeniden koşar.
    public func answer(_ text: String, for id: Check.ID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking, let index = checks.firstIndex(where: { $0.id == id }),
              case .needsInput(let question) = checks[index].status else { return }
        answers.append(AssistantAnswer(question: question, answer: text))
        memory?.save(answers)
        checks[index].status = .pending
        launchPending()
    }

    public func retry(_ id: Check.ID) {
        guard !isWorking, let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].status = .pending
        launchPending()
    }

    public func stop() {
        task?.cancel()
        task = nil
        runner.cancel()
        for index in checks.indices where !checks[index].status.isFinished {
            checks[index].status = .skipped("Durduruldu.")
            checks[index].currentLine = nil
        }
        if isWorking {
            stage = checks.isEmpty ? .idle : .finished
        }
    }

    /// Raporu temizler; kaydedilen bilgiler kalır (`forgetAll` ile silinir).
    public func reset() {
        stop()
        checks = []
        focus = nil
        startSignature = []
        stage = .idle
    }

    // MARK: - Döngü

    private func markStart() {
        navigator.markStart()
        startSignature = Set(screen().map(\.query))
    }

    private func makeCheck(_ plan: PlannedCheck) -> Check {
        defer { nextID += 1 }
        return Check(id: nextID, plan: plan, repairs: nil)
    }

    /// Modelden cümlenin daha net bir başlık/beklenen sonuç hâlini ister; olmazsa kural tabanlı hâli kalır.
    private func refine(_ id: Check.ID, request: String) async {
        let context = PlanContext(focus: request, screen: screen(), answers: knownFacts)
        guard var refined = try? await model.check(for: request, context: context), !Task.isCancelled,
              let index = checks.firstIndex(where: { $0.id == id }), checks[index].status == .pending else { return }
        refined.request = request
        if refined.title.trimmingCharacters(in: .whitespaces).isEmpty { refined.title = request }
        checks[index].plan = refined
    }

    private func launchPending() {
        task?.cancel()
        stage = .running
        task = Task { await self.runPending() }
    }

    private func planAndRun() async {
        let context = PlanContext(focus: focus, screen: screen(), answers: knownFacts)
        var planned: [PlannedCheck]
        do {
            planned = try await model.plan(for: context)
        } catch {
            if Task.isCancelled { return }
            stage = .failed("Kontroller planlanamadı: \(error.localizedDescription)")
            return
        }
        if Task.isCancelled { return }
        if planned.isEmpty {
            planned = HeuristicPlanner.plan(context)
        }
        planned = Array(planned.prefix(PlanContext.maxChecks))
        // Ekrandan ayrılan kontroller (başarılı giriş gibi) sona: önce ekranda kalanlar koşar.
        planned = planned.filter { !$0.leavesScreen } + planned.filter(\.leavesScreen)
        guard !planned.isEmpty else {
            stage = .failed("Bu ekranda test edilecek bir şey bulunamadı.")
            return
        }
        checks = planned.map(makeCheck)
        await runPending()
    }

    private func runPending() async {
        stage = .running
        while let index = checks.firstIndex(where: { $0.status == .pending }) {
            if Task.isCancelled { return }
            guard await returnToStart() else {
                for pending in checks.indices where checks[pending].status == .pending {
                    checks[pending].status = .skipped("Başlangıç ekranına dönülemedi.")
                }
                break
            }
            if Task.isCancelled { return }
            await run(index)
        }
        if !Task.isCancelled {
            stage = .finished
        }
    }

    private func returnToStart() async -> Bool {
        if isAtStart() { return true }
        await navigator.returnToStart()
        try? await Task.sleep(for: settleTime)
        if isAtStart() { return true }
        if let resetApp {
            await resetApp()
            try? await Task.sleep(for: settleTime)
            if isAtStart() { return true }
        }
        return false
    }

    /// Başlangıç ekranındaki öğelerin en az %60'ı görünüyorsa aynı ekrandayız.
    private func isAtStart() -> Bool {
        guard !startSignature.isEmpty else { return true }
        let current = Set(screen().map(\.query))
        return Double(startSignature.intersection(current).count) / Double(startSignature.count) >= 0.6
    }

    private func run(_ index: Int) async {
        checks[index].status = .running
        checks[index].steps = []
        checks[index].attempts = []
        checks[index].issueReceipt = nil
        checks[index].issueError = nil
        checks[index].screenshot = nil
        checks[index].isSaved = false
        var lastIssue: String?
        var failures = 0

        for _ in 0..<maxStepsPerCheck {
            if Task.isCancelled { return }
            let context = AssistantContext(check: checks[index].plan, answers: knownFacts, steps: checks[index].steps,
                                           lastIssue: lastIssue, screen: screen())
            let decision: AssistantDecision
            do {
                decision = try await model.nextDecision(for: context)
            } catch {
                if Task.isCancelled { return }
                checks[index].status = .blocked("Model hata verdi: \(error.localizedDescription)")
                return
            }
            if Task.isCancelled { return }

            switch decision.action {
            case .ask:
                checks[index].status = .needsInput(decision.message?.nonEmpty ?? "Devam etmek için bilgiye ihtiyacım var.")
                return
            case .pass:
                checks[index].status = .passed(decision.message?.nonEmpty ?? "Beklenen davranış görüldü.")
                return
            case .issue:
                checks[index].screenshot = captureScreenshot?()
                checks[index].status = .issue(decision.message?.nonEmpty ?? "Beklenen davranış görülmedi.")
                return
            case .blocked:
                checks[index].status = .blocked(decision.message?.nonEmpty ?? "Kontrol sürdürülemedi.")
                return
            case .tap, .type, .assertVisible, .assertNotVisible, .assertEnabled, .assertDisabled:
                break
            }

            guard let line = Self.line(for: decision, allowedTargets: context.targets) else {
                lastIssue = "Your last answer had no valid target from the screen list."
                failures += 1
                if failures >= maxFailuresInARow {
                    checks[index].status = .blocked("Asistan bu ekranda geçerli bir adım bulamadı.")
                    return
                }
                continue
            }

            checks[index].currentLine = line
            let failure = await execute(line)
            if Task.isCancelled { return }
            checks[index].currentLine = nil
            checks[index].attempts.append(.init(line: line, passed: failure == nil, note: failure))

            if let failure {
                lastIssue = "'\(line)' failed: \(failure)"
                failures += 1
                if failures >= maxFailuresInARow {
                    checks[index].status = .blocked("Üst üste \(failures) adım başarısız oldu: \(failure)")
                    return
                }
            } else {
                checks[index].steps.append(line)
                lastIssue = nil
                failures = 0
            }
            try? await Task.sleep(for: settleTime)
        }
        checks[index].status = .blocked("Adım sınırına (\(maxStepsPerCheck)) ulaşıldı.")
    }

    /// Adımı çalıştırır; geçerse `nil`, düşerse nedenini döner.
    private func execute(_ line: String) async -> String? {
        let state = await runner.run(line)
        guard state != .passed else { return nil }
        for result in runner.results {
            if case .failed(let message) = result.status { return message }
        }
        return runner.parseIssues.first?.message ?? state.title
    }

    /// Model kararını akış satırına çevirir; hedef ekranda yoksa `nil`.
    static func line(for decision: AssistantDecision, allowedTargets: [String]) -> String? {
        guard let target = decision.target?.trimmingCharacters(in: .whitespaces), target != "-",
              allowedTargets.contains(target) else { return nil }
        let selector = FlowParser.literal(target)
        return switch decision.action {
        case .tap: "tap: \(selector)"
        case .type: "type: \(selector) -> \(FlowParser.literal(decision.text ?? ""))"
        case .assertVisible: "assertVisible: \(selector)"
        case .assertNotVisible: "assertNotVisible: \(selector)"
        case .assertEnabled: "assertEnabled: \(selector)"
        case .assertDisabled: "assertDisabled: \(selector)"
        case .ask, .pass, .issue, .blocked: nil
        }
    }

    // MARK: - Dışa aktarma

    /// Kontrolün geçen adımlarından senaryo (Taslaklar'a kaydedilir). Test kök ekranda başladıysa ve
    /// `resetApp` varsa senaryo her koşudan önce reset'lenir; aksi hâlde kaydedildiği ekrandan başlamalıdır.
    public func scenario(for check: Check) -> Scenario? {
        guard !check.steps.isEmpty else { return nil }
        return Scenario(name: check.title, summary: check.plan.expectation, tags: ["taslak", "asistan"],
                        resetsApp: resetApp != nil && navigator.startIsAppRoot,
                        goal: check.plan.request?.components(separatedBy: "\n(").first ?? check.title,
                        script: check.steps.joined(separator: "\n"))
    }

    /// Hata kaydının parçaları; takip aracına (`IssueReporter`) bu gönderilir.
    public func bugReport(for check: Check, environment: String) -> BugReport {
        let actual: String = switch check.status {
        case .issue(let message), .blocked(let message), .passed(let message),
             .needsInput(let message), .skipped(let message): message
        case .pending, .running: "-"
        }
        let steps = check.attempts.map { attempt in
            attempt.line + (attempt.passed ? "" : "  ← \(attempt.note ?? "başarısız")")
        }
        let attachments = check.screenshot.map { [BugReport.Attachment(filename: "screenshot.png", mimeType: "image/png",
                                                                       data: $0)] } ?? []
        return BugReport(title: "\(check.title): beklenen davranış görülmedi", steps: steps,
                         expected: check.plan.expectation, actual: actual, environment: environment,
                         attachments: attachments)
    }

    /// Tüm raporun düz metni.
    public var reportText: String {
        var lines = ["Mister-O asistan raporu · \(summaryText)"]
        if let focus { lines.append("Odak: \(focus)") }
        for check in checks {
            let (symbol, message): (String, String?) = switch check.status {
            case .passed(let message): ("✓", message)
            case .issue(let message): ("✗", message)
            case .needsInput(let message): ("?", message)
            case .blocked(let message): ("!", message)
            case .skipped(let message): ("–", message)
            case .pending, .running: ("·", nil)
            }
            lines.append("\(symbol) \(check.title)")
            if let message { lines.append("    \(message)") }
        }
        return lines.joined(separator: "\n")
    }
}
