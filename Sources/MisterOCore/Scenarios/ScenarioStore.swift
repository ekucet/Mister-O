import Combine
import Foundation

/// Senaryo kataloğunu yükler, doğrular ve senaryoları tek tek ya da toplu (suite) koşturur.
/// Asistanın ürettiği senaryolar cihazda **taslak** olarak saklanır, katalogla birlikte listelenir ve
/// QA ekibine katalog JSON'u olarak paylaşılabilir.
///
/// Toplu koşuda her senaryodan önce `resetApp` işleyicisi çağrılır; böylece 2. senaryo 1.'nin
/// bıraktığı ekrandan değil, bilinen başlangıç durumundan başlar. Bir senaryo başarısız olsa da
/// suite bir sonrakiyle devam eder.
@MainActor
public final class ScenarioStore: ObservableObject {
    public enum CatalogStatus: Equatable, Sendable {
        case idle
        case loading
        case live(Date)
        case cached(savedAt: Date, error: String)
        case failed(String)
    }

    public struct Validation: Equatable, Sendable {
        public let stepCount: Int
        public let issues: [FlowParseError.Issue]
        public var isValid: Bool { issues.isEmpty }
    }

    /// Bir senaryonun son koşusu.
    public struct Run: Equatable, Sendable {
        public let state: RunState
        public let steps: [StepResult]
        public let parseIssues: [FlowParseError.Issue]
        public let elapsed: Duration?

        /// Listede gösterilecek ilk hata.
        public var failureMessage: String? {
            for result in steps {
                if case .failed(let message) = result.status { return "Satır \(result.step.line): \(message)" }
            }
            return parseIssues.first?.description
        }
    }

    public struct Suite: Equatable, Sendable {
        public let scenarios: [Scenario]
        public internal(set) var currentIndex: Int?
        public internal(set) var isRunning = true
        public internal(set) var wasCancelled = false
        public internal(set) var elapsed: Duration?

        public var scenarioIDs: [Scenario.ID] { scenarios.map(\.id) }
    }

    /// Uzak/paket kataloğundaki senaryolar.
    @Published public private(set) var scenarios: [Scenario] = []
    /// Cihazda saklanan taslaklar (asistandan kaydedilenler).
    @Published public private(set) var drafts: [Scenario] = []
    @Published public private(set) var status: CatalogStatus = .idle
    @Published public private(set) var runs: [Scenario.ID: Run] = [:]
    @Published public private(set) var suite: Suite?
    /// Şu an hazırlanan ya da koşan senaryo.
    @Published public private(set) var activeScenarioID: Scenario.ID?
    /// `start` / `startSuite` ile başlatılmış bir iş sürüyor (senaryolar arası reset dahil).
    @Published private var hasTask = false

    public let feed: ScenarioFeed?
    private let runner: InAppTestRunner
    private let resetApp: (@MainActor () async -> Void)?
    private let settleTime: Duration
    private let cache: ScenarioCache?
    private let draftsDefaults: UserDefaults?
    private static let draftsKey = "MisterO.drafts"
    private var validations: [Scenario.ID: Validation] = [:]
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - resetApp: Uygulamayı senaryoların başladığı duruma getirir (navigasyonu köke al, oturumu kapat…).
    ///   - settleTime: Reset sonrası ekranın oturması için beklenen süre.
    public init(
        feed: ScenarioFeed?,
        runner: InAppTestRunner,
        resetApp: (@MainActor () async -> Void)? = nil,
        settleTime: Duration = .milliseconds(600),
        cacheDirectory: URL? = ScenarioCache.defaultDirectory,
        draftsDefaults: UserDefaults? = .standard
    ) {
        self.feed = feed
        self.runner = runner
        self.resetApp = resetApp
        self.settleTime = settleTime
        self.cache = cacheDirectory.map(ScenarioCache.init(directory:))
        self.draftsDefaults = draftsDefaults
        if let data = draftsDefaults?.data(forKey: Self.draftsKey),
           let stored = try? JSONDecoder().decode([Scenario].self, from: data) {
            drafts = stored
            for draft in stored { validations[draft.id] = Self.validate(draft) }
        }
    }

    public var isConfigured: Bool { feed != nil }

    /// Önce taslaklar, sonra katalog.
    public var allScenarios: [Scenario] { drafts + scenarios }

    public func isDraft(_ scenario: Scenario) -> Bool {
        drafts.contains { $0.id == scenario.id }
    }
    public var isRunning: Bool { hasTask || activeScenarioID != nil }

    /// Katalogdaki etiketler, ilk görüldükleri sırayla.
    public var tags: [String] {
        var seen = Set<String>()
        return allScenarios.flatMap(\.tags).filter { seen.insert($0).inserted }
    }

    public func validation(for scenario: Scenario) -> Validation {
        validations[scenario.id] ?? Self.validate(scenario)
    }

    // MARK: - Katalog

    public func refresh() async {
        guard let feed, status != .loading else { return }
        status = .loading
        do {
            let loaded = try await feed.load()
            apply(loaded)
            status = .live(Date())
            if let key = feed.cacheKey { cache?.save(loaded, for: key) }
        } catch {
            let message = ScenarioCatalog.describe(error)
            if let key = feed.cacheKey, let entry = cache?.load(for: key) {
                apply(entry.scenarios)
                status = .cached(savedAt: entry.savedAt, error: message)
            } else {
                // Elde liste varsa (önceki yükleme) korunur, yalnızca hata gösterilir.
                status = .failed(message)
            }
        }
    }

    private func apply(_ loaded: [Scenario]) {
        for scenario in loaded { validations[scenario.id] = Self.validate(scenario) }
        scenarios = loaded
    }

    // MARK: - Taslaklar

    /// Taslak kaydeder; aynı id'li taslak varsa günceller.
    public func saveDraft(_ scenario: Scenario) {
        validations[scenario.id] = Self.validate(scenario)
        if let index = drafts.firstIndex(where: { $0.id == scenario.id }) {
            drafts[index] = scenario
        } else {
            drafts.insert(scenario, at: 0)
        }
        persistDrafts()
    }

    /// Asistanın onardığı adımları kaydeder. Taslak yerinde güncellenir; katalogdaki senaryo uzak dosyada
    /// değiştirilemediği için "(onarıldı)" adlı yeni bir taslak olur ve QA ekibine paylaşılır.
    @discardableResult
    public func saveRepair(of original: Scenario, steps: [String]) -> Scenario {
        let script = steps.joined(separator: "\n")
        let repaired = isDraft(original)
            ? Scenario(id: original.id, name: original.name, summary: original.summary, tags: original.tags,
                       resetsApp: original.resetsApp, goal: original.goal, script: script)
            : Scenario(id: "\(original.id)-onarildi", name: "\(original.name) (onarıldı)", summary: original.summary,
                       tags: original.tags + ["taslak", "onarıldı"], resetsApp: original.resetsApp,
                       goal: original.goal, script: script)
        runs[repaired.id] = nil
        saveDraft(repaired)
        return repaired
    }

    public func deleteDraft(_ id: Scenario.ID) {
        drafts.removeAll { $0.id == id }
        runs[id] = nil
        persistDrafts()
    }

    /// Taslakların katalog dosyası biçimi; QA ekibi `scenarios` dizisine ekler.
    public var draftsCatalogJSON: String {
        ScenarioCatalog.json(for: drafts)
    }

    private func persistDrafts() {
        guard let draftsDefaults, let data = try? JSONEncoder().encode(drafts) else { return }
        draftsDefaults.set(data, forKey: Self.draftsKey)
    }

    private static func validate(_ scenario: Scenario) -> Validation {
        do {
            return Validation(stepCount: try FlowParser().parse(scenario.script).count, issues: [])
        } catch {
            return Validation(stepCount: 0, issues: error.issues)
        }
    }

    // MARK: - Koşu

    /// Tek senaryoyu arka planda başlatır.
    public func start(_ scenario: Scenario) {
        launch { await self.run(scenario) }
    }

    /// Senaryoları sırayla arka planda koşturur.
    public func startSuite(_ scenarios: [Scenario]) {
        launch { await self.runSuite(scenarios) }
    }

    public func cancel() {
        task?.cancel()
    }

    @discardableResult
    public func run(_ scenario: Scenario) async -> RunState {
        guard !runner.isRunning else { return runner.state }
        activeScenarioID = scenario.id
        defer { activeScenarioID = nil }

        if scenario.resetsApp, let resetApp {
            await resetApp()
            try? await Task.sleep(for: settleTime)
        }
        let state = await runner.run(scenario.script)
        runs[scenario.id] = Run(state: state, steps: runner.results, parseIssues: runner.parseIssues,
                                elapsed: runner.elapsed)
        return state
    }

    public func runSuite(_ list: [Scenario]) async {
        let clock = ContinuousClock()
        let start = clock.now
        for scenario in list {
            runs[scenario.id] = nil
        }
        suite = Suite(scenarios: list)

        for (index, scenario) in list.enumerated() {
            if Task.isCancelled {
                suite?.wasCancelled = true
                break
            }
            suite?.currentIndex = index
            if await run(scenario) == .cancelled {
                suite?.wasCancelled = true
                break
            }
        }

        suite?.currentIndex = nil
        suite?.elapsed = clock.now - start
        suite?.isRunning = false
    }

    private func launch(_ operation: @escaping @MainActor () async -> Void) {
        guard task == nil, !runner.isRunning else { return }
        hasTask = true
        task = Task {
            await operation()
            task = nil
            hasTask = false
        }
    }

    // MARK: - Rapor

    /// Son suite'in hata kaydına yapıştırılabilecek özeti.
    public var suiteReportText: String {
        guard let suite else { return "" }
        let passed = suite.scenarioIDs.filter { runs[$0]?.state == .passed }.count
        var lines = ["Mister-O · Suite · \(passed)/\(suite.scenarioIDs.count) başarılı"
                     + (suite.elapsed.map { " · \($0.compactText)" } ?? "")
                     + (suite.wasCancelled ? " · durduruldu" : "")]

        for scenario in suite.scenarios {
            let name = scenario.name
            guard let run = runs[scenario.id] else {
                lines.append("– \(name) (çalışmadı)")
                continue
            }
            let symbol = run.state == .passed ? "✓" : run.state == .cancelled ? "–" : "✗"
            lines.append("\(symbol) \(name)" + (run.elapsed.map { " · \($0.secondsText)" } ?? ""))
            if run.state != .passed, let failure = run.failureMessage {
                lines.append("    → \(failure)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
