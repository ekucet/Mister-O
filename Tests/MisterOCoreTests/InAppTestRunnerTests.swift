import Testing
@testable import MisterOCore

@MainActor
final class FakeDriver: UIDriver {
    var visible: Set<String> = []
    var disabled: Set<String> = []
    var onTap: (String) -> Void = { _ in }
    private(set) var actions: [String] = []

    /// N'inci ekran sorgusunda ekranı değiştirir: "öğe birazdan gelir" testleri saate bağlı kalmasın
    /// (CI simülatöründe ana thread yavaşken `Task.sleep` tabanlı tetikler gecikiyordu).
    var changeAfterLookups: (count: Int, change: () -> Void)?
    private var lookups = 0

    private func lookUp() {
        lookups += 1
        if let pending = changeAfterLookups, lookups >= pending.count {
            changeAfterLookups = nil
            pending.change()
        }
    }

    func tap(_ selector: ElementSelector) throws {
        lookUp()
        guard visible.contains(selector.query) else { throw DriverError.elementNotFound(selector) }
        guard !disabled.contains(selector.query) else { throw DriverError.elementDisabled(selector) }
        actions.append("tap \(selector.query)")
        onTap(selector.query)
    }

    func typeText(_ text: String, into selector: ElementSelector) throws {
        lookUp()
        guard visible.contains(selector.query) else { throw DriverError.elementNotFound(selector) }
        guard selector.query.hasSuffix("_field") else { throw DriverError.notTextInput(selector) }
        actions.append("type \(selector.query)=\(text)")
    }

    func isVisible(_ selector: ElementSelector) -> Bool {
        lookUp()
        return visible.contains(selector.query)
    }

    func isEnabled(_ selector: ElementSelector) -> Bool? {
        lookUp()
        return visible.contains(selector.query) ? !disabled.contains(selector.query) : nil
    }

    /// Öğelerin metni; verilmezse sorgunun kendisi.
    var texts: [String: String] = [:]
    /// Listede aşağıda kalan sayfalar: her `scrollToFind` sıradakini görünür yapar.
    var pagesBelow: [[String]] = []
    var canGoBack = true
    private(set) var scrolls: [String] = []

    func texts(of selector: ElementSelector) -> [String]? {
        visible.contains(selector.query) ? [texts[selector.query] ?? selector.query] : nil
    }

    func scroll(_ direction: ScrollDirection, in selector: ElementSelector?) throws {
        scrolls.append("\(direction.rawValue) \(selector?.query ?? "-")")
    }

    func scrollToFind(_ search: inout ScrollSearch) -> Bool {
        guard !pagesBelow.isEmpty else { return false }
        search.steps += 1
        scrolls.append("find")
        visible.formUnion(pagesBelow.removeFirst())
        return true
    }

    func goBack() throws {
        guard canGoBack else { throw DriverError.nothingToGoBack }
        actions.append("back")
    }
}

@MainActor
struct InAppTestRunnerTests {
    private let fast = InAppTestRunner.Configuration(
        elementTimeout: .milliseconds(150),
        pollInterval: .milliseconds(10),
        delayBetweenSteps: .zero
    )

    @Test func runsStepsInOrderAndPasses() async {
        let driver = FakeDriver()
        driver.visible = ["email_field", "login_button"]
        driver.onTap = { if $0 == "login_button" { driver.visible.insert("welcome") } }
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        let state = await runner.run("""
        type: "email_field" -> "a@b.c"
        tap: "login_button"
        wait: 0.01
        assertVisible: "welcome"
        """)

        #expect(state == .passed)
        #expect(driver.actions == ["type email_field=a@b.c", "tap login_button"])
        #expect(runner.results.allSatisfy { $0.status == .passed && $0.duration != nil })
        #expect(runner.elapsed != nil)
    }

    /// Sonunda geçmesi gereken testler: uzun süre sınırı yalnızca bir şeyler ters giderse beklenir.
    private let patient = InAppTestRunner.Configuration(
        elementTimeout: .seconds(30), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
    )

    @Test func waitsForElementThatAppearsLater() async {
        let driver = FakeDriver()
        let runner = InAppTestRunner(driver: driver, configuration: patient)
        driver.changeAfterLookups = (5, { driver.visible.insert("late") })

        #expect(await runner.run("tap: late") == .passed)
        #expect(driver.actions == ["tap late"])
    }

    @Test func retriesDisabledControlUntilEnabled() async {
        let driver = FakeDriver()
        driver.visible = ["save"]
        driver.disabled = ["save"]
        let runner = InAppTestRunner(driver: driver, configuration: patient)
        driver.changeAfterLookups = (5, { driver.disabled.removeAll() })

        #expect(await runner.run("tap: save") == .passed)
    }

    @Test func failsAfterTimeoutAndSkipsTheRest() async throws {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        let state = await runner.run("""
        tap: a
        assertVisible: missing
        tap: a
        """)

        #expect(state == .failed)
        #expect(runner.results.map(\.status.symbol) == ["✓", "✗", "–"])
        guard case .failed(let message) = runner.results[1].status else {
            Issue.record("2. adım başarısız olmalıydı")
            return
        }
        #expect(message.contains("Not on screen: \"missing\""))
        #expect(driver.actions == ["tap a"])
        #expect(runner.reportText.contains("✗ [line 2] assertVisible: missing"))
    }

    @Test func nonRetryableErrorFailsImmediately() async {
        let driver = FakeDriver()
        driver.visible = ["label"]
        let runner = InAppTestRunner(driver: driver, configuration: .init(elementTimeout: .seconds(10)))

        let clock = ContinuousClock()
        let start = clock.now
        #expect(await runner.run("type: label -> x") == .failed)
        #expect(clock.now - start < .seconds(1))
    }

    @Test func continuesAfterFailureWhenConfigured() async {
        let driver = FakeDriver()
        driver.visible = ["b"]
        var config = fast
        config.stopOnFailure = false
        let runner = InAppTestRunner(driver: driver, configuration: config)

        #expect(await runner.run("tap: a\ntap: b") == .failed)
        #expect(runner.results.map(\.status.symbol) == ["✗", "✓"])
    }

    @Test func stateAssertionsWaitForTheExpectedState() async {
        let driver = FakeDriver()
        driver.visible = ["error", "save", "submit"]
        driver.disabled = ["submit"]
        let runner = InAppTestRunner(driver: driver, configuration: patient)
        driver.changeAfterLookups = (5, { driver.visible.remove("error") })

        #expect(await runner.run("""
        assertNotVisible: error
        assertEnabled: save
        assertDisabled: submit
        """) == .passed)

        let quick = InAppTestRunner(driver: driver, configuration: fast)
        #expect(await quick.run("assertDisabled: save") == .failed)
        #expect(quick.reportText.contains("Element is enabled, it should be disabled: \"save\""))
        #expect(await quick.run("assertEnabled: missing") == .failed)
        #expect(await quick.run("assertNotVisible: save") == .failed)
    }

    @Test func invalidScriptNeverTouchesTheDriver() async {
        let driver = FakeDriver()
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        #expect(runner.validate("tap: ok") == true)
        #expect(runner.validate("tapp: x") == false)
        #expect(await runner.run("tap: a\nzoom: 2") == .invalidScript)
        #expect(runner.parseIssues.map(\.line) == [2])
        #expect(runner.results.isEmpty)
        #expect(driver.actions.isEmpty)
    }

    @Test func cancellationStopsTheRun() async {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        let task = Task { await runner.run("wait: 5\ntap: a") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        #expect(await task.value == .cancelled)
        #expect(runner.results.map(\.status.symbol) == ["–", "–"])
        #expect(driver.actions.isEmpty)
    }

    // MARK: - Kaydırma, metin, geri, değişkenler

    private var scrolling: InAppTestRunner.Configuration {
        var configuration = InAppTestRunner.Configuration(
            elementTimeout: .milliseconds(150), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
        )
        configuration.scrollDelay = .zero
        return configuration
    }

    @Test func scrollsTheListToFindAnElementBelowTheFold() async {
        let driver = FakeDriver()
        driver.pagesBelow = [["row_10"], ["row_20"], ["delete_button"]]
        var configuration = patient
        configuration.scrollDelay = .zero
        let runner = InAppTestRunner(driver: driver, configuration: configuration)

        #expect(await runner.run("tap: delete_button") == .passed)
        #expect(driver.scrolls == ["find", "find", "find"])
        #expect(driver.actions == ["tap delete_button"])
    }

    @Test func givesUpWhenTheListEndsAndDoesNotScrollForNotVisible() async {
        let driver = FakeDriver()
        driver.pagesBelow = [["row_10"]]
        let runner = InAppTestRunner(driver: driver, configuration: scrolling)

        #expect(await runner.run("assertNotVisible: row_10") == .passed)
        #expect(driver.scrolls.isEmpty)

        #expect(await runner.run("tap: missing") == .failed)
        #expect(driver.scrolls == ["find"])

        var off = scrolling
        off.scrollsToFindElements = false
        driver.pagesBelow = [["late"]]
        #expect(await InAppTestRunner(driver: driver, configuration: off).run("tap: late") == .failed)
        #expect(driver.scrolls == ["find"])
    }

    @Test func assertTextLooksForTheTextInsideTheElement() async {
        let driver = FakeDriver()
        driver.visible = ["welcome_label"]
        driver.texts = ["welcome_label": "Hoş geldin, tester@mistero.app"]
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        #expect(await runner.run(#"assertText: welcome_label -> "HOŞ GELDİN""#) == .passed)
        #expect(await runner.run("assertText: welcome_label -> Güle güle") == .failed)
        guard case .failed(let message) = runner.results[0].status else {
            Issue.record("düşmeliydi")
            return
        }
        #expect(message.hasPrefix(#""welcome_label" shows "Hoş geldin, tester@mistero.app", expected "Güle güle""#))
    }

    @Test func scrollAndBackCommandsGoToTheDriver() async {
        let driver = FakeDriver()
        let runner = InAppTestRunner(driver: driver, configuration: fast)

        #expect(await runner.run("scroll: down\nscroll: \"settings_list\" -> left\nback") == .passed)
        #expect(driver.scrolls == ["down -", "left settings_list"])
        #expect(driver.actions == ["back"])

        driver.canGoBack = false
        #expect(await runner.run("back") == .failed)
        #expect(runner.results[0].status == .failed("Nothing to go back from: no previous screen or open sheet"))
    }

    @Test func fillsVariablesFromTestDataButKeepsThePlaceholderInTheReport() async {
        let driver = FakeDriver()
        driver.visible = ["password_field"]
        let runner = InAppTestRunner(driver: driver, configuration: fast)
        runner.variables = ["Test hesabı şifresi": "s3cret"]

        #expect(await runner.run("type: password_field -> {{test hesabı şifresi}}") == .passed)
        #expect(driver.actions == ["type password_field=s3cret"])
        #expect(runner.reportText.contains("{{test hesabı şifresi}}"))
        #expect(!runner.reportText.contains("s3cret"))
    }

}
