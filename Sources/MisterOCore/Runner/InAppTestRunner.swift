import Combine
import Foundation
import os

/// Akış metnini satır satır koşturan ana motor.
///
/// Tüm iş `@MainActor` üzerinde, `async/await` ile yürür: UIKit erişimi ana thread'de kalır,
/// `wait` ve öğe beklemeleri ise `Task.sleep` ile ana thread'i bloklamadan yapılır.
/// `tap`, `type` ve `assert…` adımları öğe ekrana gelene kadar `elementTimeout` boyunca yeniden dener;
/// öğe ekranda yoksa ana listeyi kaydırarak da arar.
@MainActor
public final class InAppTestRunner: ObservableObject {
    public struct Configuration: Sendable {
        /// tap / type / assertVisible için öğenin ekrana gelmesini bekleme süresi.
        public var elementTimeout: Duration
        /// Bekleme sırasında ekranın yeniden taranma aralığı.
        public var pollInterval: Duration
        /// Adımlar arasındaki kısa ara (animasyonlar otursun, testçi akışı izleyebilsin).
        public var delayBetweenSteps: Duration
        /// İlk başarısız adımda koşuyu durdur.
        public var stopOnFailure: Bool
        /// Öğe ekranda yoksa ana listeyi (scroll view, `List`, `UITableView`…) kaydırarak ara.
        public var scrollsToFindElements: Bool
        /// Ekran yeni açıldıysa öğe birazdan gelir; kaydırmaya ancak bu kadar bekledikten sonra başlanır.
        var scrollDelay: Duration = .milliseconds(600)

        public init(
            elementTimeout: Duration = .seconds(5),
            pollInterval: Duration = .milliseconds(200),
            delayBetweenSteps: Duration = .milliseconds(400),
            stopOnFailure: Bool = true,
            scrollsToFindElements: Bool = true
        ) {
            self.elementTimeout = elementTimeout
            self.pollInterval = pollInterval
            self.delayBetweenSteps = delayBetweenSteps
            self.stopOnFailure = stopOnFailure
            self.scrollsToFindElements = scrollsToFindElements
        }

        public static let `default` = Configuration()
    }

    @Published public private(set) var state: RunState = .idle
    @Published public private(set) var results: [StepResult] = []
    @Published public private(set) var parseIssues: [FlowParseError.Issue] = []
    @Published public private(set) var elapsed: Duration?

    public var configuration: Configuration
    /// Akışlardaki `{{ad}}` yer tutucularının değerleri (kurulumdaki `testData`).
    public var variables: [String: String] = [:]

    private let driver: any UIDriver
    private var parser: FlowParser { FlowParser(variables: variables) }
    private var currentTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "MisterO", category: "Runner")

    public init(driver: any UIDriver, configuration: Configuration = .default) {
        self.driver = driver
        self.configuration = configuration
    }

    public var isRunning: Bool { state == .running }

    /// Akışı çalıştırmadan doğrular; hatalar `parseIssues` üzerinden gösterilir.
    @discardableResult
    public func validate(_ script: String) -> Bool {
        guard !isRunning else { return false }
        do {
            _ = try parser.parse(script)
            parseIssues = []
            return true
        } catch {
            showParseFailure(error)
            return false
        }
    }

    /// UI'dan "ateşle ve unut" başlatma. `cancel()` ile durdurulabilir.
    public func start(_ script: String) {
        guard currentTask == nil else { return }
        currentTask = Task {
            await run(script)
            currentTask = nil
        }
    }

    public func cancel() {
        currentTask?.cancel()
    }

    /// Akışı baştan sona koşturur ve son durumu döner.
    @discardableResult
    public func run(_ script: String) async -> RunState {
        guard !isRunning else { return state }

        let steps: [TestStep]
        do {
            steps = try parser.parse(script)
        } catch {
            showParseFailure(error)
            return state
        }

        parseIssues = []
        results = steps.map(StepResult.init(step:))
        elapsed = nil
        state = .running
        logger.info("Akış başladı: \(steps.count) adım")

        let clock = ContinuousClock()
        let runStart = clock.now
        var outcome = RunState.passed

        for index in results.indices {
            if Task.isCancelled {
                outcome = .cancelled
                break
            }

            results[index].status = .running
            let stepStart = clock.now
            let status = await perform(results[index].step.command)
            results[index].status = status
            results[index].duration = clock.now - stepStart
            log(results[index])

            if Task.isCancelled {
                outcome = .cancelled
                break
            }
            if case .failed = status {
                outcome = .failed
                if configuration.stopOnFailure { break }
            }
            if index < results.count - 1 {
                try? await Task.sleep(for: configuration.delayBetweenSteps)
            }
        }

        for index in results.indices where results[index].status == .pending || results[index].status == .running {
            results[index].status = .skipped
        }
        elapsed = clock.now - runStart
        state = outcome
        logger.info("Akış bitti: \(outcome.title, privacy: .public)")
        return outcome
    }

    /// Hata raporuna yapıştırılabilecek düz metin özet.
    public var reportText: String {
        var lines = ["Mister-O · \(state.title)" + (elapsed.map { " · \($0.secondsText)" } ?? "")]
        lines += parseIssues.map { "⚠︎ \($0)" }
        for result in results {
            var line = "\(result.status.symbol) [\(L("line %ld", result.step.line))] \(result.step.source)"
            if case .failed(let message) = result.status {
                line += "\n    → \(message)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Adım yürütme

    private func perform(_ command: TestCommand) async -> StepResult.Status {
        do {
            try await execute(command)
            return .passed
        } catch is CancellationError {
            return .skipped
        } catch let error as DriverError where error.isRetryable {
            return .failed(L("%@ (waited %@)", error.localizedDescription, configuration.elementTimeout.secondsText))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func execute(_ command: TestCommand) async throws {
        switch command {
        case .tap(let selector):
            try await retrying(revealing: selector) { try driver.tap(selector) }

        case .typeText(let selector, let text):
            try await retrying(revealing: selector) { try driver.typeText(text, into: selector) }

        case .wait(let seconds):
            try await Task.sleep(for: .seconds(seconds))

        case .assertVisible(let selector):
            try await retrying(revealing: selector) {
                guard driver.isVisible(selector) else { throw DriverError.elementNotFound(selector) }
            }

        case .assertNotVisible(let selector):
            try await retrying {
                guard !driver.isVisible(selector) else { throw DriverError.stillVisible(selector) }
            }

        case .assertEnabled(let selector):
            try await retrying(revealing: selector) {
                guard let enabled = driver.isEnabled(selector) else { throw DriverError.elementNotFound(selector) }
                guard enabled else { throw DriverError.elementDisabled(selector) }
            }

        case .assertDisabled(let selector):
            try await retrying(revealing: selector) {
                guard let enabled = driver.isEnabled(selector) else { throw DriverError.elementNotFound(selector) }
                guard !enabled else { throw DriverError.elementEnabled(selector) }
            }

        case .assertText(let selector, let expected):
            try await retrying(revealing: selector) {
                guard let texts = driver.texts(of: selector) else { throw DriverError.elementNotFound(selector) }
                guard texts.contains(where: { Self.text($0, contains: expected) }) else {
                    throw DriverError.textMismatch(selector, expected: expected, actual: texts.first ?? "")
                }
            }

        case .scroll(let direction, let selector):
            try await retrying { try driver.scroll(direction, in: selector) }

        case .back:
            try driver.goBack()
        }
    }

    /// Büyük/küçük harf duyarsız "içerir". Türkçe metinde "GELDİN" ile "geldin", "ÇIKIŞ" ile "çıkış" de eşleşir.
    static func text(_ text: String, contains expected: String) -> Bool {
        let wanted = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return true }
        return [Locale(identifier: "en_US"), Locale(identifier: "tr_TR")].contains { locale in
            text.lowercased(with: locale).contains(wanted.lowercased(with: locale))
        }
    }

    /// Yeniden denenebilir sürücü hatalarında zaman aşımına kadar ekranı tekrar tarar. `revealing` verilirse
    /// ve öğe ekranda yoksa ana listeyi her denemede bir sayfa kaydırır (önce aşağı, sonra yukarı); liste
    /// kaydıkça süre dolmaz, uzun listeler de sonuna kadar aranır.
    private func retrying(revealing selector: ElementSelector? = nil, _ attempt: () throws -> Void) async throws {
        let clock = ContinuousClock()
        let scrollStart = clock.now + configuration.scrollDelay
        var deadline = clock.now + configuration.elementTimeout
        var search = ScrollSearch()
        var canScroll = selector != nil && configuration.scrollsToFindElements
        while true {
            do {
                try attempt()
                return
            } catch let error as DriverError where error.isRetryable && clock.now < deadline {
                if canScroll, case .elementNotFound = error, clock.now >= scrollStart {
                    if driver.scrollToFind(&search) {
                        deadline = max(deadline, clock.now + configuration.pollInterval * 3)
                    } else {
                        canScroll = false
                    }
                }
                try await Task.sleep(for: configuration.pollInterval)
            }
        }
    }

    private func showParseFailure(_ error: FlowParseError) {
        parseIssues = error.issues
        results = []
        elapsed = nil
        state = .invalidScript
    }

    private func log(_ result: StepResult) {
        let line = result.step.line
        let source = result.step.source
        switch result.status {
        case .passed:
            logger.info("✓ [\(line)] \(source, privacy: .public)")
        case .failed(let message):
            logger.error("✗ [\(line)] \(source, privacy: .public) — \(message, privacy: .public)")
        case .pending, .running, .skipped:
            break
        }
    }
}
