import Foundation
import Testing
@testable import MisterOCore

/// Planı ve her kontrolün kararlarını sırayla döndüren, aldığı bağlamları kaydeden sahte model.
actor ScriptedModel: FlowAssistantModel {
    nonisolated let availability = AssistantAvailability.available
    private let checks: [PlannedCheck]
    private var decisions: [String: [AssistantDecision]]
    private let delay: Duration
    private let refined: PlannedCheck?
    private(set) var contexts: [AssistantContext] = []

    init(plan: [PlannedCheck], decisions: [String: [AssistantDecision]], delay: Duration = .zero,
         refined: PlannedCheck? = nil) {
        self.checks = plan
        self.decisions = decisions
        self.delay = delay
        self.refined = refined
    }

    func plan(for context: PlanContext) async throws -> [PlannedCheck] {
        checks
    }

    func check(for request: String, context: PlanContext) async throws -> PlannedCheck {
        refined ?? HeuristicPlanner.check(for: request)
    }

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        try await Task.sleep(for: delay)
        contexts.append(context)
        guard var queue = decisions[context.check.title], !queue.isEmpty else {
            return AssistantDecision(action: .blocked, target: "-", message: "Senaryo bitti")
        }
        let next = queue.removeFirst()
        decisions[context.check.title] = queue
        return next
    }

    func add(_ decisions: [AssistantDecision], for title: String) {
        self.decisions[title, default: []] += decisions
    }
}

actor RecordingReporter: IssueReporter {
    nonisolated let name = "Test"
    private(set) var count = 0

    func open(_ report: BugReport) async throws -> IssueReceipt {
        count += 1
        return IssueReceipt(key: "QA-\(count)", url: nil)
    }
}

@MainActor
final class FakeNavigator: ScreenNavigating {
    var onReturn: () -> Void = {}
    var startIsAppRoot = false
    private(set) var marks = 0
    private(set) var returns = 0

    func markStart() { marks += 1 }

    func returnToStart() async {
        returns += 1
        onReturn()
    }
}

@MainActor
struct FlowAssistantTests {
    private let fast = InAppTestRunner.Configuration(
        elementTimeout: .milliseconds(60),
        pollInterval: .milliseconds(10),
        delayBetweenSteps: .zero
    )

    private func screen(_ driver: FakeDriver) -> @MainActor () -> [ScreenElement] {
        {
            driver.visible.sorted().map {
                ScreenElement(query: $0, identifier: $0, name: nil,
                              kind: $0.hasSuffix("_field") ? "UIKitTextField" : "Button · AX",
                              isEnabled: !driver.disabled.contains($0))
            }
        }
    }

    private func assistant(_ model: ScriptedModel, _ driver: FakeDriver,
                           navigator: FakeNavigator = FakeNavigator(),
                           resetApp: (@MainActor () async -> Void)? = nil,
                           appFacts: [AssistantAnswer] = [],
                           memory: (any AssistantMemory)? = nil) -> FlowAssistant {
        FlowAssistant(model: model, runner: InAppTestRunner(driver: driver, configuration: fast),
                      screen: screen(driver), navigator: navigator, resetApp: resetApp,
                      appFacts: appFacts, memory: memory, settleTime: .zero)
    }

    private func waitUntilIdle(_ assistant: FlowAssistant) async {
        for _ in 0..<300 where assistant.isWorking {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func exploresReportsAndContinuesWithTheTester() async throws {
        let driver = FakeDriver()
        driver.visible = ["email_field", "password_field", "login_button"]
        driver.onTap = { if $0 == "login_button" { driver.visible = ["welcome_label"] } }

        let empty = PlannedCheck(title: "Boş formla giriş yapılamamalı", expectation: "Buton pasif olmalı")
        let valid = PlannedCheck(title: "Geçerli bilgilerle giriş", expectation: "Ana sayfa açılmalı", leavesScreen: true)
        let model = ScriptedModel(plan: [valid, empty], decisions: [
            empty.title: [
                .init(action: .assertDisabled, target: "login_button"),
                .init(action: .issue, target: "-", message: "Boş formda buton aktif."),
            ],
            valid.title: [.init(action: .ask, target: "-", message: "Hangi hesapla?")],
        ])
        let assistant = assistant(model, driver)

        assistant.explore()
        await waitUntilIdle(assistant)

        // Ekrandan ayrılan kontrol sona alınır.
        #expect(assistant.checks.map(\.title) == [empty.title, valid.title])
        #expect(assistant.checks[0].status == .issue("Boş formda buton aktif."))
        #expect(assistant.checks[0].attempts.first?.passed == false)
        #expect(assistant.checks[1].status == .needsInput("Hangi hesapla?"))
        #expect(assistant.stage == .finished)
        #expect(assistant.summaryText == "2 kontrol · 1 sorun · 1 bilgi bekliyor")

        let report = assistant.bugReport(for: assistant.checks[0], environment: "iPhone · iOS 27")
        #expect(report.title == "Boş formla giriş yapılamamalı: beklenen davranış görülmedi")
        #expect(report.actual == "Boş formda buton aktif.")
        #expect(report.text.contains("1. assertDisabled: login_button  ← Öğe aktif, pasif olması bekleniyordu"))
        #expect(report.text.contains("Beklenen: Buton pasif olmalı"))
        #expect(report.text.contains("Ortam: iPhone · iOS 27"))

        await model.add([
            .init(action: .type, target: "email_field", text: "qa@firma.com"),
            .init(action: .type, target: "password_field", text: "123456"),
            .init(action: .tap, target: "login_button"),
            .init(action: .assertVisible, target: "welcome_label"),
            .init(action: .pass, target: "-", message: "Ana sayfa açıldı."),
        ], for: valid.title)
        assistant.answer("qa@firma.com / 123456", for: assistant.checks[1].id)
        await waitUntilIdle(assistant)

        #expect(assistant.checks[1].status == .passed("Ana sayfa açıldı."))
        #expect(assistant.checks[1].steps == [
            "type: email_field -> qa@firma.com",
            "type: password_field -> 123456",
            "tap: login_button",
            "assertVisible: welcome_label",
        ])
        let contexts = await model.contexts
        #expect(contexts.last?.answers == [AssistantAnswer(question: "Hangi hesapla?", answer: "qa@firma.com / 123456")])
        #expect(contexts.first?.prompt.contains("- login_button | - | Button · AX") == true)

        let scenario = try #require(assistant.scenario(for: assistant.checks[1]))
        #expect(scenario.tags == ["taslak", "asistan"])
        // resetApp yok: senaryo kaydedildiği ekrandan başlamalı.
        #expect(scenario.resetsApp == false)
        #expect(scenario.script.hasPrefix("type: email_field -> qa@firma.com\n"))
        #expect(assistant.scenario(for: assistant.checks[0]) == nil)
    }

    @Test func draftsResetOnlyWhenTheTestStartedAtTheAppRoot() async throws {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let check = PlannedCheck(title: "a görünmeli", expectation: "-")
        let decisions = [check.title: [AssistantDecision(action: .assertVisible, target: "a"), .init(action: .pass, target: "-")]]

        for isRoot in [true, false] {
            let navigator = FakeNavigator()
            navigator.startIsAppRoot = isRoot
            let assistant = assistant(ScriptedModel(plan: [check], decisions: decisions), driver,
                                      navigator: navigator, resetApp: {})
            assistant.explore()
            await waitUntilIdle(assistant)
            #expect(try #require(assistant.scenario(for: assistant.checks[0])).resetsApp == isRoot)
        }
    }

    @Test func returnsToTheStartScreenBetweenChecks() async {
        let driver = FakeDriver()
        driver.visible = ["a", "b", "c"]
        driver.onTap = { if $0 == "a" { driver.visible = ["x", "y"] } }
        let navigator = FakeNavigator()
        navigator.onReturn = { driver.visible = ["a", "b", "c"] }

        let first = PlannedCheck(title: "a'ya bas", expectation: "x açılmalı")
        let second = PlannedCheck(title: "b görünmeli", expectation: "b ekranda")
        let model = ScriptedModel(plan: [first, second], decisions: [
            first.title: [.init(action: .tap, target: "a"), .init(action: .pass, target: "-")],
            second.title: [.init(action: .assertVisible, target: "b"), .init(action: .pass, target: "-")],
        ])
        let assistant = assistant(model, driver, navigator: navigator)

        assistant.explore()
        await waitUntilIdle(assistant)

        #expect(navigator.marks == 1)
        #expect(navigator.returns == 1)
        #expect(assistant.checks.map(\.status) == [.passed("Beklenen davranış görüldü."), .passed("Beklenen davranış görüldü.")])
    }

    @Test func fallsBackToResetAndSkipsWhenTheStartCannotBeReached() async {
        let driver = FakeDriver()
        driver.visible = ["a", "b"]
        driver.onTap = { _ in driver.visible = ["elsewhere"] }
        let checks = (1...3).map { PlannedCheck(title: "kontrol \($0)", expectation: "-") }
        let decisions = Dictionary(uniqueKeysWithValues: checks.map {
            ($0.title, [AssistantDecision(action: .tap, target: "a"), .init(action: .pass, target: "-")])
        })

        // Navigator dönemez ama resetApp başlangıca getirir: tüm kontroller koşar.
        let resets = Counter()
        let withReset = assistant(ScriptedModel(plan: checks, decisions: decisions), driver, resetApp: {
            resets.value += 1
            driver.visible = ["a", "b"]
        })
        withReset.explore()
        await waitUntilIdle(withReset)
        #expect(resets.value == 2)
        #expect(withReset.summary.passed == 3)

        // Hiçbir yolla dönülemezse kalanlar atlanır.
        driver.visible = ["a", "b"]
        let stuck = assistant(ScriptedModel(plan: checks, decisions: decisions), driver)
        stuck.explore()
        await waitUntilIdle(stuck)
        #expect(stuck.checks.map(\.status) == [
            .passed("Beklenen davranış görüldü."),
            .skipped("Başlangıç ekranına dönülemedi."),
            .skipped("Başlangıç ekranına dönülemedi."),
        ])
    }

    @Test func invalidTargetsAndRepeatedFailuresBlockTheCheck() async {
        let driver = FakeDriver()
        driver.visible = ["label"]
        let check = PlannedCheck(title: "yaz", expectation: "-")
        let model = ScriptedModel(plan: [check], decisions: [check.title: [
            .init(action: .tap, target: "uydurma"),
            .init(action: .type, target: "label", text: "x"),
            .init(action: .type, target: "label", text: "x"),
        ]])
        let assistant = assistant(model, driver)

        assistant.explore()
        await waitUntilIdle(assistant)

        guard case .blocked(let message) = assistant.checks.first?.status else {
            Issue.record("sürdürülemedi olmalıydı: \(String(describing: assistant.checks.first?.status))")
            return
        }
        #expect(message.contains("Üst üste 3 adım başarısız"))
        let contexts = await model.contexts
        #expect(contexts[1].lastIssue?.contains("no valid target") == true)
        #expect(contexts[2].lastIssue?.contains("'type: label -> x' failed") == true)
    }

    @Test func stopSkipsWhatIsLeft() async {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let checks = [PlannedCheck(title: "bir", expectation: "-"), PlannedCheck(title: "iki", expectation: "-")]
        let model = ScriptedModel(plan: checks, decisions: [:], delay: .milliseconds(300))
        let assistant = assistant(model, driver)

        assistant.explore()
        try? await Task.sleep(for: .milliseconds(50))
        assistant.stop()

        #expect(assistant.stage == .finished)
        #expect(assistant.checks.allSatisfy { $0.status == .skipped("Durduruldu.") })
    }

    @Test func openedIssuesAndSavedDraftsAreRememberedPerCheck() async {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let broken = PlannedCheck(title: "bozuk", expectation: "x görünmeli")
        let model = ScriptedModel(plan: [broken], decisions: [broken.title: [
            .init(action: .assertVisible, target: "a"),
            .init(action: .issue, target: "-", message: "x yok"),
        ]])
        let assistant = assistant(model, driver)
        assistant.explore()
        await waitUntilIdle(assistant)
        let id = assistant.checks[0].id

        let reporter = RecordingReporter()
        await assistant.openIssue(for: id, environment: "test", using: reporter)
        await assistant.openIssue(for: id, environment: "test", using: reporter)   // ikinci kez açılmaz
        #expect(await reporter.count == 1)
        #expect(assistant.checks[0].issueReceipt == IssueReceipt(key: "QA-1", url: nil))

        assistant.markSaved(id)
        #expect(assistant.checks[0].isSaved)

        // Yeniden koşulan kontrolün eski kaydı/işareti temizlenir.
        await model.add([.init(action: .pass, target: "-")], for: broken.title)
        assistant.retry(id)
        await waitUntilIdle(assistant)
        #expect(assistant.checks[0].issueReceipt == nil)
        #expect(assistant.checks[0].isSaved == false)
    }

    @Test func runsTheTesterRequestAsOneCheck() async {
        let driver = FakeDriver()
        driver.visible = ["email_field", "save_button"]
        driver.onTap = { if $0 == "save_button" { driver.visible = ["done_label"] } }
        let request = "Alanları doldur, Kaydet'e bas; sonraki ekran açılmalı"
        let refined = PlannedCheck(title: "Formu gönder", expectation: "Sonraki ekran açılmalı.", leavesScreen: true)
        let model = ScriptedModel(plan: [], decisions: [refined.title: [
            .init(action: .type, target: "email_field", text: "qa+1@example.com"),
            .init(action: .tap, target: "save_button"),
            .init(action: .assertVisible, target: "done_label"),
            .init(action: .pass, target: "-", message: "Sonraki ekran açıldı."),
        ]], refined: refined)
        let assistant = assistant(model, driver)

        assistant.addCheck(request)
        #expect(assistant.checks.first?.plan.expectation == "Sonraki ekran açılmalı.")  // kural tabanlı ilk hâl
        await waitUntilIdle(assistant)

        #expect(assistant.checks.count == 1)
        #expect(assistant.checks[0].title == "Formu gönder")
        #expect(assistant.checks[0].plan.request == request)
        #expect(assistant.checks[0].status == .passed("Sonraki ekran açıldı."))
        let contexts = await model.contexts
        #expect(contexts.first?.prompt.contains("Tester's request: \(request)") == true)
        #expect(assistant.scenario(for: assistant.checks[0])?.goal == request)
    }

    @Test func factsAreRememberedAndGivenToTheModel() async {
        let driver = FakeDriver()
        driver.visible = ["login_button"]
        let check = PlannedCheck(title: "giriş", expectation: "-")
        let memory = InMemoryAssistantMemory()
        let appFact = AssistantAnswer(question: "Test hesabı", answer: "qa@firma.com")
        let model = ScriptedModel(plan: [check], decisions: [check.title: [.init(action: .ask, target: "-", message: "Şifre?")]])
        let first = assistant(model, driver, appFacts: [appFact], memory: memory)

        first.explore()
        await waitUntilIdle(first)
        await model.add([.init(action: .pass, target: "-")], for: check.title)
        first.answer("123456", for: first.checks[0].id)
        await waitUntilIdle(first)

        let contexts = await model.contexts
        #expect(contexts.last?.answers == [appFact, AssistantAnswer(question: "Şifre?", answer: "123456")])

        // Uygulama yeniden açılmış gibi: bilgi hafızadan gelir.
        let second = assistant(model, driver, appFacts: [appFact], memory: memory)
        #expect(second.answers == [AssistantAnswer(question: "Şifre?", answer: "123456")])
        #expect(second.knownFacts.count == 2)
        second.forget(second.answers[0])
        #expect(memory.load().isEmpty)
        #expect(second.knownFacts == [appFact])
    }

    @Test func repairsAScenarioThatNoLongerWorks() async throws {
        let driver = FakeDriver()
        driver.visible = ["new_login_button"]
        let resets = Counter()
        let scenario = Scenario(id: "login", name: "Giriş", summary: "Ana sayfa açılmalı", tags: ["taslak"],
                                goal: "Giriş yapılabilmeli", script: "tap: login_button")
        let repairTitle = "Onar: Giriş"
        let model = ScriptedModel(plan: [], decisions: [repairTitle: [
            .init(action: .tap, target: "new_login_button"),
            .init(action: .pass, target: "-"),
        ]])
        let assistant = assistant(model, driver, resetApp: { resets.value += 1 })

        assistant.repair(scenario)
        await waitUntilIdle(assistant)

        #expect(resets.value == 1)
        let check = try #require(assistant.checks.first)
        #expect(check.repairs == scenario)
        #expect(check.steps == ["tap: new_login_button"])
        let contexts = await model.contexts
        #expect(contexts.first?.prompt.contains("Giriş yapılabilmeli") == true)
        #expect(contexts.first?.prompt.contains("tap: login_button") == true)

        // Taslak yerinde güncellenir; katalogdaki senaryo "(onarıldı)" taslağı olur.
        let defaults = try #require(UserDefaults(suiteName: "MisterO.tests.\(UUID().uuidString)"))
        let store = ScenarioStore(feed: nil, runner: InAppTestRunner(driver: driver), cacheDirectory: nil,
                                  draftsDefaults: defaults)
        store.saveDraft(scenario)
        let updated = store.saveRepair(of: scenario, steps: check.steps)
        #expect(updated.id == "login")
        #expect(store.drafts.map(\.script) == ["tap: new_login_button"])

        let catalogScenario = Scenario(id: "checkout", name: "Ödeme", script: "tap: pay")
        let copy = store.saveRepair(of: catalogScenario, steps: ["tap: pay_now"])
        #expect(copy.id == "checkout-onarildi")
        #expect(copy.name == "Ödeme (onarıldı)")
        #expect(copy.tags.contains("onarıldı"))
    }

    @Test func requestParsingFindsTheExpectation() {
        #expect(HeuristicPlanner.check(for: "E-postaya qa@firma.com yaz, Giriş Yap'a bas; ana sayfa açılmalı").expectation
                == "Ana sayfa açılmalı.")
        #expect(HeuristicPlanner.check(for: "alanları doldur, doğru butona bas, ilerlemeli, yoksa hata").expectation
                == "İlerlemeli.")
        #expect(HeuristicPlanner.check(for: "Sepete ürün ekle").expectation
                == "İstenen davranış gerçekleşmeli ve ekranda doğrulanmalı.")
        #expect(HeuristicPlanner.check(for: "Sepete ürün ekle").request == "Sepete ürün ekle")
    }

    @Test func promptShowsFieldKinds() {
        let context = AssistantContext(
            check: PlannedCheck(title: "x", expectation: "y"), answers: [], steps: [], lastIssue: nil,
            screen: [ScreenElement(query: "email_field", identifier: "email_field", name: "E-posta",
                                   kind: "UIKitTextField", inputKind: "email")]
        )
        #expect(context.prompt.contains("- email_field | E-posta | UIKitTextField | input: email | empty"))
    }

    @Test func heuristicPlannerCoversForms() {
        let form = [
            ScreenElement(query: "Giriş", identifier: nil, name: "Giriş", kind: "Header · AX"),
            ScreenElement(query: "email_field", identifier: "email_field", name: "E-posta", kind: "UIKitTextField"),
            ScreenElement(query: "password_field", identifier: "password_field", name: "Şifre", kind: "UIKitTextField"),
            ScreenElement(query: "login_button", identifier: "login_button", name: "Giriş Yap", kind: "Button · AX"),
        ]
        let plan = HeuristicPlanner.plan(PlanContext(focus: nil, screen: form))
        #expect(plan.count == 3)
        #expect(plan.map(\.leavesScreen) == [false, false, true])
        #expect(plan[0].title == "Boş formla “Giriş Yap” çalışmamalı")

        let buttons = (1...5).map { ScreenElement(query: "b\($0)", identifier: nil, name: "B\($0)", kind: "UIButton") }
        #expect(HeuristicPlanner.plan(PlanContext(focus: nil, screen: buttons)).count == 3)
        #expect(HeuristicPlanner.plan(PlanContext(focus: "sepeti boşalt", screen: form)).map(\.title) == ["sepeti boşalt"])
    }

    @Test func literalPicksTheSimplestSafeForm() throws {
        let samples = ["login_button", "Giriş Yap", "Kaydedildi: Mister O (1)", "a->b", " boşluk", "#1",
                       "it's", "", "say \"hi\"", "“quoted”"]
        let expected = ["login_button", "Giriş Yap", "Kaydedildi: Mister O (1)", "'a->b'", "' boşluk'", "'#1'",
                        "it's", "''", "say \"hi\"", "'“quoted”'"]
        #expect(samples.map(FlowParser.literal) == expected)

        for value in samples where !value.isEmpty {
            let steps = try FlowParser().parse("tap: \(FlowParser.literal(value))")
            #expect(steps.first?.command == .tap(ElementSelector(value)), "\(value)")
        }
    }
}

@MainActor
struct DraftTests {
    @Test func draftsPersistAndExportAsCatalog() throws {
        let defaults = try #require(UserDefaults(suiteName: "MisterO.tests.\(UUID().uuidString)"))
        let runner = InAppTestRunner(driver: FakeDriver())
        let store = ScenarioStore(feed: .inline([Scenario(name: "Katalogdaki", script: "tap: a")]), runner: runner,
                                  cacheDirectory: nil, draftsDefaults: defaults)
        let draft = Scenario(name: "Boş form", summary: "Buton pasif olmalı", tags: ["taslak", "asistan"],
                             resetsApp: false, script: "type: email_field -> ''\nassertDisabled: login_button")
        store.saveDraft(draft)
        store.saveDraft(draft)

        let reopened = ScenarioStore(feed: nil, runner: runner, cacheDirectory: nil, draftsDefaults: defaults)
        #expect(reopened.drafts == [draft])
        #expect(reopened.validation(for: draft).stepCount == 2)
        #expect(reopened.isDraft(draft))

        let exported = try ScenarioCatalog.decode(Data(reopened.draftsCatalogJSON.utf8))
        #expect(exported == [draft])
        #expect(reopened.draftsCatalogJSON.contains("\"reset\": false"))

        reopened.deleteDraft(draft.id)
        #expect(ScenarioStore(feed: nil, runner: runner, cacheDirectory: nil, draftsDefaults: defaults).drafts.isEmpty)
    }

    @Test func catalogEntryKeepsFieldOrder() {
        let entry = ScenarioCatalog.entry(for: Scenario(id: "x", name: "N", summary: "D", tags: ["t"],
                                                        script: "tap: a\n\nassertVisible: b"))
        #expect(entry == """
        {
          "id": "x",
          "name": "N",
          "description": "D",
          "tags": ["t"],
          "steps": [
            "tap: a",
            "assertVisible: b"
          ]
        }
        """)
    }
}
