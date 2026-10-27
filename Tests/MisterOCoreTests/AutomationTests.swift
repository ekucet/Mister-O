import Foundation
import Testing
@testable import MisterOCore

struct AutorunTests {
    @Test func parsesTagsIDsAndAll() {
        let selection = AutorunSelection(parsing: "#smoke, login-success  #auth")
        #expect(selection == AutorunSelection(tags: ["smoke", "auth"], ids: ["login-success"]))
        #expect(AutorunSelection(parsing: "ALL") == .all)
        #expect(AutorunSelection(parsing: "*") == .all)
        #expect(AutorunSelection(parsing: " , ") == nil)
        #expect(AutorunSelection(parsing: "#") == nil)
        #expect(selection?.description == "#smoke, #auth, login-success")
    }

    @Test func matchesScenarios() {
        let selection = AutorunSelection(tags: ["smoke"], ids: ["b"])
        #expect(selection.matches(Scenario(id: "a", name: "A", tags: ["smoke"], script: "wait: 0")))
        #expect(selection.matches(Scenario(id: "b", name: "B", script: "wait: 0")))
        #expect(!selection.matches(Scenario(id: "c", name: "C", tags: ["auth"], script: "wait: 0")))
    }

    @Test func readsLaunchArgumentsBeforeTheEnvironment() throws {
        let defaults = try #require(UserDefaults(suiteName: "MisterO.tests.\(UUID().uuidString)"))
        #expect(Autorun.fromLaunch(environment: [:], defaults: defaults) == nil)

        let fromEnvironment = Autorun.fromLaunch(environment: ["MISTERO_AUTORUN": "#smoke", "MISTERO_EXIT": "1",
                                                               "MISTERO_TICKETS": "0"], defaults: defaults)
        #expect(fromEnvironment == Autorun(.tags("smoke"), opensTickets: false, exitsWhenDone: true))

        defaults.set("login-success", forKey: Autorun.argumentKey)
        defaults.set(false, forKey: Autorun.exitArgumentKey)
        let fromArguments = Autorun.fromLaunch(environment: ["MISTERO_AUTORUN": "#smoke", "MISTERO_EXIT": "1"],
                                               defaults: defaults)
        #expect(fromArguments == Autorun(.ids("login-success"), exitsWhenDone: false))
    }

    @Test func catalogCarriesAutorunAsTextOrObject() throws {
        let text = try ScenarioCatalog.decodeDocument(Data("""
        { "autorun": "#smoke", "scenarios": [{ "name": "A", "steps": ["wait: 0"] }] }
        """.utf8))
        #expect(text.autorun == .tags("smoke"))

        let object = try ScenarioCatalog.decodeDocument(Data("""
        { "autorun": { "ids": ["a"], "tags": ["auth"] }, "scenarios": [{ "id": "a", "name": "A", "flow": "wait: 0" }] }
        """.utf8))
        #expect(object.autorun == AutorunSelection(tags: ["auth"], ids: ["a"]))

        let none = try ScenarioCatalog.decodeDocument(Data(#"[{ "name": "A", "flow": "wait: 0" }]"#.utf8))
        #expect(none.autorun == nil)
        #expect(throws: (any Error).self) {
            try ScenarioCatalog.decodeDocument(Data(#"{ "autorun": "", "scenarios": [] }"#.utf8))
        }
    }

    @Test @MainActor func storeKeepsTheCatalogAutorunOffline() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let online = ScenarioFeed.custom(name: "uzak", cacheKey: "k") { [Scenario(name: "A", script: "wait: 0")] }
        let runner = InAppTestRunner(driver: FakeDriver())

        // `custom` kaynağı autorun taşımaz; önbellekteki JSON kaynağı taşır.
        let first = ScenarioStore(feed: online, runner: runner, cacheDirectory: directory)
        await first.refresh()
        #expect(first.catalogAutorun == nil)

        let cache = ScenarioCache(directory: directory)
        cache.save(ScenarioCatalog.Document(scenarios: [Scenario(name: "A", script: "wait: 0")], autorun: .all), for: "k")
        let offline = ScenarioStore(feed: ScenarioFeed.custom(name: "uzak", cacheKey: "k") {
            throw URLError(.notConnectedToInternet)
        }, runner: runner, cacheDirectory: directory)
        await offline.refresh()
        #expect(offline.catalogAutorun == .all)
    }
}

/// Bellekte tutulan defter.
final class MemoryLedger: IssueLedger, @unchecked Sendable {
    var entries: [String: IssueReceipt] = [:]

    func receipt(for fingerprint: String) -> IssueReceipt? {
        entries[fingerprint].map { IssueReceipt(key: $0.key, url: $0.url, isExisting: true) }
    }

    func record(_ receipt: IssueReceipt, for fingerprint: String) {
        entries[fingerprint] = receipt
    }
}

/// Arama yapabilen sahte takip aracı.
actor SearchingReporter: IssueReporter, IssueSearching {
    nonisolated let name = "Jira"
    var openIssues: [String: IssueReceipt] = [:]
    var searchFails = false
    private(set) var opened = 0

    func setSearchFails(_ value: Bool) { searchFails = value }
    func close(_ fingerprint: String) { openIssues[fingerprint] = nil }

    func open(_ report: BugReport) async throws -> IssueReceipt {
        opened += 1
        let receipt = IssueReceipt(key: "QA-\(opened)", url: nil)
        if let fingerprint = report.fingerprint { openIssues[fingerprint] = receipt }
        return receipt
    }

    func existingIssue(fingerprint: String) async throws -> IssueReceipt? {
        if searchFails { throw URLError(.notConnectedToInternet) }
        return openIssues[fingerprint]
    }
}

struct DeduplicationTests {
    private func report(_ fingerprint: String?) -> BugReport {
        BugReport(title: "t", steps: [], expected: "e", actual: "a", environment: "env", fingerprint: fingerprint)
    }

    @Test func fingerprintIsStable() {
        #expect(BugReport.fingerprint("login", "tap: login_button") == BugReport.fingerprint("login", "tap: login_button"))
        #expect(BugReport.fingerprint("login", "tap: a") != BugReport.fingerprint("login", "tap: b"))
    }

    @Test func ledgerStopsRepeatsForReportersThatCantSearch() async throws {
        let base = RecordingReporter()
        let ledger = MemoryLedger()
        let reporter = DeduplicatingIssueReporter(base, ledger: ledger)

        #expect(try await reporter.open(report("fp")) == IssueReceipt(key: "QA-1", url: nil))
        #expect(try await reporter.open(report("fp")) == IssueReceipt(key: "QA-1", url: nil, isExisting: true))
        #expect(try await reporter.open(report("other")).key == "QA-2")
        #expect(try await reporter.open(report(nil)).key == "QA-3")   // parmak izi yoksa her seferinde açılır
        #expect(await base.count == 3)
        #expect(reporter.name == "Test")
    }

    @Test func searchingReporterIsTheSourceOfTruth() async throws {
        let base = SearchingReporter()
        let ledger = MemoryLedger()
        let reporter = DeduplicatingIssueReporter(base, ledger: ledger)

        #expect(try await reporter.open(report("fp")).key == "QA-1")
        #expect(try await reporter.open(report("fp")) == IssueReceipt(key: "QA-1", url: nil, isExisting: true))

        // Kayıt kapandı: defterde olsa da yenisi açılır.
        await base.close("fp")
        #expect(try await reporter.open(report("fp")).key == "QA-2")

        // Arama düşerse defter devreye girer.
        await base.setSearchFails(true)
        #expect(try await reporter.open(report("fp")) == IssueReceipt(key: "QA-2", url: nil, isExisting: true))
        #expect(await base.opened == 2)
    }

    @Test func userDefaultsLedgerForgetsAfterItsLifetime() throws {
        let defaults = try #require(UserDefaults(suiteName: "MisterO.tests.\(UUID().uuidString)"))
        let clock = TestClock()
        let ledger = UserDefaultsIssueLedger(defaults: defaults, lifetime: 60, now: { clock.now })

        ledger.record(IssueReceipt(key: "QA-1", url: URL(string: "https://x/QA-1")), for: "fp")
        #expect(ledger.receipt(for: "fp") == IssueReceipt(key: "QA-1", url: URL(string: "https://x/QA-1"), isExisting: true))
        #expect(UserDefaultsIssueLedger(defaults: defaults, now: { clock.now }).receipt(for: "fp")?.key == "QA-1")
        clock.now += 61
        #expect(ledger.receipt(for: "fp") == nil)
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
struct SuiteAutomationTests {
    private let fast = InAppTestRunner.Configuration(
        elementTimeout: .milliseconds(60), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
    )

    actor Collector: ResultReporter {
        private(set) var reports: [SuiteReport] = []
        func send(_ report: SuiteReport) async throws { reports.append(report) }
    }

    private func setUp(_ scenarios: [Scenario], reporter: (any IssueReporter)? = nil) async
        -> (ScenarioStore, SuiteAutomation, Collector, Counter, URL, () -> [String]) {
        let driver = FakeDriver()
        driver.visible = ["a", "b"]
        let store = ScenarioStore(feed: .inline(scenarios), runner: InAppTestRunner(driver: driver, configuration: fast),
                                  settleTime: .zero, cacheDirectory: nil, draftsDefaults: nil, screenshot: { Data([1]) })
        await store.refresh()
        let collector = Collector()
        let exitCode = Counter()
        exitCode.value = -1
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logged = LogBox()
        let automation = SuiteAutomation(store: store, issueReporter: reporter, resultReporters: [collector],
                                         environment: { "iPhone · iOS 27" }, resultsDirectory: directory,
                                         log: { logged.lines.append($0) }, exit: { exitCode.value = Int($0) })
        return (store, automation, collector, exitCode, directory, { logged.lines })
    }

    private let scenarios = [
        Scenario(id: "ok", name: "Geçen", tags: ["smoke"], script: "tap: a"),
        Scenario(id: "broken", name: "Düşen", tags: ["smoke"], goal: "c görünmeli", script: "tap: a\ntap: c"),
        Scenario(id: "other", name: "Başka", tags: ["auth"], script: "tap: b"),
    ]

    @Test func autorunRunsTheSelectionOpensTicketsReportsAndExits() async throws {
        let base = RecordingReporter()
        let reporter = DeduplicatingIssueReporter(base, ledger: MemoryLedger())
        let (store, automation, collector, exitCode, directory, log) = await setUp(scenarios, reporter: reporter)

        await automation.run(Autorun(.tags("smoke"), exitsWhenDone: true))

        let report = try #require(await collector.reports.last)
        #expect(report.trigger == "autorun · #smoke")
        #expect(report.items.map(\.id) == ["ok", "broken"])
        #expect((report.total, report.passed, report.failed) == (2, 1, 1))
        #expect(report.items[1].ticketKey == "QA-1")
        #expect(report.items[1].ticketIsExisting == false)
        #expect(report.text.contains("✗ Düşen — Line 2: Not on screen: \"c\""))
        #expect(report.text.contains("→ ticket: QA-1"))
        #expect(store.runs["broken"]?.issueReceipt?.key == "QA-1")
        #expect(exitCode.value == 1)
        #expect(log().contains { $0.contains("MISTERO-RESULT-BEGIN") })

        for file in ["junit.xml", "report.json", "summary.md", "summary.txt"] {
            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path), "\(file)")
        }
        let saved = try JSONDecoder.iso.decode(SuiteReport.self, from: Data(contentsOf: directory.appendingPathComponent("report.json")))
        #expect(saved.failed == 1)

        // Aynı hata yeniden düşer: yeni kayıt açılmaz.
        await automation.run(Autorun(.tags("smoke")))
        let again = try #require(await collector.reports.last)
        #expect(again.items[1].ticketIsExisting == true)
        #expect(again.text.contains("already reported: QA-1"))
        #expect(await base.count == 1)
    }

    @Test func manualSuitesAreReportedWithoutTickets() async throws {
        let base = RecordingReporter()
        let (store, automation, collector, exitCode, _, _) = await setUp(scenarios, reporter: base)
        _ = automation

        await store.startSuite(scenarios)?.value

        let report = try #require(await collector.reports.last)
        #expect(report.trigger == "manual")
        #expect(report.failed == 1)
        #expect(report.items[1].ticketKey == nil)
        #expect(await base.count == 0)
        #expect(exitCode.value == -1)
    }

    @Test func nothingToRunExitsWithTwo() async {
        let (_, automation, collector, exitCode, _, log) = await setUp(scenarios)

        await automation.run(Autorun(.tags("yok"), exitsWhenDone: true))

        #expect(exitCode.value == 2)
        #expect(await collector.reports.isEmpty)
        #expect(log().contains { $0.contains("No scenario matches #yok.") })
    }
}

final class LogBox: @unchecked Sendable {
    var lines: [String] = []
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct SuiteReportTests {
    private let report = SuiteReport(
        trigger: "autorun · #smoke", environment: "iPhone · iOS 27", startedAt: Date(timeIntervalSince1970: 0),
        duration: 3.5, items: [
            .init(id: "a", name: "Giriş", tags: ["smoke"], outcome: .passed, duration: 1.25, failure: nil),
            .init(id: "b", name: "Sepet <&> \"indirim\"", tags: [], outcome: .failed, duration: 2,
                  failure: "Line 1: Not on screen: \"x\"", ticketKey: "QA-7", ticketURL: URL(string: "https://j/QA-7"),
                  ticketIsExisting: false),
            .init(id: "c", name: "Bozuk", tags: [], outcome: .invalid, duration: nil, failure: "Line 1: x"),
            .init(id: "d", name: "Atlandı", tags: [], outcome: .notRun, duration: nil, failure: nil),
        ])

    @Test func countsAndText() {
        #expect((report.total, report.passed, report.failed) == (4, 1, 2))
        #expect(report.text.hasPrefix("Mister-O · 1/4 passed · 3.50 s · autorun · #smoke\niPhone · iOS 27"))
        #expect(report.text.contains("✗ Sepet <&> \"indirim\" — Line 1: Not on screen: \"x\" → ticket: QA-7 https://j/QA-7"))
        #expect(!report.text.contains("Giriş"))
    }

    @Test func junitEscapesAndMarksEachOutcome() {
        let xml = report.junitXML
        #expect(xml.contains(#"<testsuites name="Mister-O" tests="4" failures="1" errors="1" time="3.500">"#))
        #expect(xml.contains(#"<testcase classname="smoke" name="Giriş" time="1.250"/>"#))
        #expect(xml.contains(#"name="Sepet &lt;&amp;&gt; &quot;indirim&quot;""#))
        #expect(xml.contains(#"<failure message="Line 1: Not on screen: &quot;x&quot;">"#))
        #expect(xml.contains("<error message=\"Line 1: x\">"))
        #expect(xml.contains("<skipped/>"))
    }

    @Test func markdownTable() {
        #expect(report.markdown.contains("| ✗ | Sepet <&> \"indirim\" | 2.00 s | Line 1: Not on screen: \"x\" → ticket: QA-7 https://j/QA-7 |"))
        #expect(report.markdown.contains("| – | Atlandı | – |  |"))
    }
}

struct ResultReporterTests {
    private let passing = SuiteReport(trigger: "manual", environment: "env", startedAt: Date(), duration: 1, items: [
        .init(id: "a", name: "A", tags: [], outcome: .passed, duration: 1, failure: nil),
    ])

    @Test func slackPostsTheSummaryText() throws {
        let reporter = SlackResultReporter(webhookURL: URL(string: "https://hooks.slack.com/services/x")!)
        let request = try #require(reporter.request(for: passing))
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
        #expect(body == ["text": passing.text])
        #expect(SlackResultReporter(webhookURL: request.url!, onlyFailures: true).request(for: passing) == nil)
    }

    @Test func webhookPostsTheWholeReport() throws {
        let request = WebhookResultReporter(url: URL(string: "https://example.com/r")!, headers: ["X-Key": "k"])
            .request(for: passing)
        #expect(request.value(forHTTPHeaderField: "X-Key") == "k")
        let decoded = try JSONDecoder.iso.decode(SuiteReport.self, from: request.httpBody ?? Data())
        #expect(decoded.passed == 1)
    }
}
