import Foundation

/// Suite'lerin insansız tarafı: autorun'ı başlatır, her suite bitince sonucu konsola ve dosyalara yazar,
/// `ResultReporter`'lara gönderir; autorun'da düşen senaryolar için kayıt açar ve istenirse uygulamayı kapatır.
@MainActor
public final class SuiteAutomation {
    /// Son suite'in raporu.
    public private(set) var lastReport: SuiteReport?

    private let store: ScenarioStore
    private let issueReporter: (any IssueReporter)?
    private let resultReporters: [any ResultReporter]
    private let environment: @MainActor () -> String
    private let resultsDirectory: URL?
    private let log: (String) -> Void
    private let exit: (Int32) -> Void
    private var activeAutorun: Autorun?

    /// - Parameters:
    ///   - resultsDirectory: `junit.xml`, `report.json`, `summary.md` ve `summary.txt` buraya yazılır. CI betiği
    ///     dosyaları simülatördeki uygulama klasöründen (`Documents/MisterO/results`) alır.
    ///   - exit: `Autorun.exitsWhenDone` için; düşen varsa 1, yoksa 0, seçilen senaryo yoksa 2 ile çağrılır.
    public init(
        store: ScenarioStore,
        issueReporter: (any IssueReporter)? = nil,
        resultReporters: [any ResultReporter] = [],
        environment: @escaping @MainActor () -> String,
        resultsDirectory: URL? = SuiteAutomation.defaultResultsDirectory,
        log: @escaping (String) -> Void = { print($0) },
        exit: @escaping (Int32) -> Void = { Foundation.exit($0) }
    ) {
        self.store = store
        self.issueReporter = issueReporter
        self.resultReporters = resultReporters
        self.environment = environment
        self.resultsDirectory = resultsDirectory
        self.log = log
        self.exit = exit
        store.onSuiteFinished = { [weak self] suite in await self?.suiteFinished(suite) }
    }

    public static var defaultResultsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MisterO/results", isDirectory: true)
    }

    /// Seçilen senaryoları koşturur ve suite bitip raporlanana kadar bekler. Katalog önceden yüklenmiş olmalı.
    public func run(_ autorun: Autorun) async {
        let selected = store.allScenarios.filter { autorun.selection.matches($0) && store.validation(for: $0).isValid }
        log("Mister-O autorun · \(autorun.selection.description) · " + L(selected.count, one: "%ld scenario", other: "%ld scenarios"))
        guard !selected.isEmpty else {
            var reason = L("No scenario matches %@.", autorun.selection.description)
            if case .failed(let error) = store.status { reason += " " + error }
            log("MISTERO-RESULT-BEGIN\n\(reason)\nMISTERO-RESULT-END")
            if autorun.exitsWhenDone { exit(2) }
            return
        }
        activeAutorun = autorun
        defer { activeAutorun = nil }
        guard let task = store.startSuite(selected) else {
            log(L("Mister-O autorun skipped: another run is in progress."))
            return
        }
        await task.value
    }

    func suiteFinished(_ suite: ScenarioStore.Suite) async {
        let autorun = activeAutorun
        let environment = environment()
        var report = SuiteReport(suite: suite, runs: store.runs,
                                 trigger: autorun.map { "autorun · \($0.selection.description)" } ?? "manual",
                                 environment: environment, startedAt: store.suiteStartedAt ?? Date())

        if let autorun, autorun.opensTickets, let issueReporter {
            for index in report.items.indices where [.failed, .invalid].contains(report.items[index].outcome) {
                guard let scenario = suite.scenarios.first(where: { $0.id == report.items[index].id }) else { continue }
                await store.openIssue(for: scenario, environment: environment, using: issueReporter)
                if let receipt = store.runs[scenario.id]?.issueReceipt {
                    report.items[index].ticketKey = receipt.key
                    report.items[index].ticketURL = receipt.url
                    report.items[index].ticketIsExisting = receipt.isExisting
                } else if let error = store.runs[scenario.id]?.issueError {
                    log("Mister-O: \(error)")
                }
            }
        }

        write(report)
        log("MISTERO-RESULT-BEGIN\n\(report.text)\nMISTERO-RESULT-END")
        for reporter in resultReporters {
            do {
                try await reporter.send(report)
            } catch {
                log("Mister-O: " + L("Couldn't send the results: %@", error.localizedDescription))
            }
        }
        lastReport = report
        if autorun?.exitsWhenDone == true {
            exit(report.hasFailures ? 1 : 0)
        }
    }

    private func write(_ report: SuiteReport) {
        guard let resultsDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)
            try Data(report.junitXML.utf8).write(to: resultsDirectory.appendingPathComponent("junit.xml"), options: .atomic)
            try report.json.write(to: resultsDirectory.appendingPathComponent("report.json"), options: .atomic)
            try Data(report.markdown.utf8).write(to: resultsDirectory.appendingPathComponent("summary.md"), options: .atomic)
            try Data(report.text.utf8).write(to: resultsDirectory.appendingPathComponent("summary.txt"), options: .atomic)
        } catch {
            log("Mister-O: " + L("Couldn't write the results: %@", error.localizedDescription))
        }
    }
}
