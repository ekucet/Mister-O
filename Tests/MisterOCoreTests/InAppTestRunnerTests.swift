import Testing
@testable import MisterOCore

@MainActor
final class FakeDriver: UIDriver {
    var visible: Set<String> = []
    var disabled: Set<String> = []
    var onTap: (String) -> Void = { _ in }
    private(set) var actions: [String] = []

    func tap(_ selector: ElementSelector) throws {
        guard visible.contains(selector.query) else { throw DriverError.elementNotFound(selector) }
        guard !disabled.contains(selector.query) else { throw DriverError.elementDisabled(selector) }
        actions.append("tap \(selector.query)")
        onTap(selector.query)
    }

    func typeText(_ text: String, into selector: ElementSelector) throws {
        guard visible.contains(selector.query) else { throw DriverError.elementNotFound(selector) }
        guard selector.query.hasSuffix("_field") else { throw DriverError.notTextInput(selector) }
        actions.append("type \(selector.query)=\(text)")
    }

    func isVisible(_ selector: ElementSelector) -> Bool {
        visible.contains(selector.query)
    }

    func isEnabled(_ selector: ElementSelector) -> Bool? {
        visible.contains(selector.query) ? !disabled.contains(selector.query) : nil
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

    @Test func waitsForElementThatAppearsLater() async {
        let driver = FakeDriver()
        let runner = InAppTestRunner(driver: driver, configuration: .init(
            elementTimeout: .seconds(2), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
        ))
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            driver.visible.insert("late")
        }

        #expect(await runner.run("tap: late") == .passed)
        #expect(driver.actions == ["tap late"])
    }

    @Test func retriesDisabledControlUntilEnabled() async {
        let driver = FakeDriver()
        driver.visible = ["save"]
        driver.disabled = ["save"]
        let runner = InAppTestRunner(driver: driver, configuration: .init(
            elementTimeout: .seconds(2), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
        ))
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            driver.disabled.removeAll()
        }

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
        let runner = InAppTestRunner(driver: driver, configuration: .init(
            elementTimeout: .seconds(2), pollInterval: .milliseconds(10), delayBetweenSteps: .zero
        ))
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            driver.visible.remove("error")
        }

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
}
