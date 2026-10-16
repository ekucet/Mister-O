import Foundation
import Testing
@testable import MisterOCore

/// Sırayla verilen kararları döndüren ve aldığı bağlamları kaydeden sahte model.
actor ScriptedModel: FlowAssistantModel {
    nonisolated let availability = AssistantAvailability.available
    private var decisions: [AssistantDecision]
    private(set) var contexts: [AssistantContext] = []

    init(_ decisions: [AssistantDecision]) {
        self.decisions = decisions
    }

    func nextDecision(for context: AssistantContext) async throws -> AssistantDecision {
        contexts.append(context)
        guard !decisions.isEmpty else { return AssistantDecision(action: .fail, message: "Senaryo bitti") }
        return decisions.removeFirst()
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
            driver.visible.sorted().map { ScreenElement(query: $0, identifier: $0, name: nil, kind: "UIView") }
        }
    }

    private func waitUntilSettled(_ assistant: FlowAssistant) async {
        for _ in 0..<300 where assistant.isWorking {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func asksThenProposesStepsAndExportsCatalogEntry() async throws {
        let driver = FakeDriver()
        driver.visible = ["email_field", "login_button"]
        driver.onTap = { if $0 == "login_button" { driver.visible.insert("welcome_label") } }
        let model = ScriptedModel([
            .init(action: .ask, target: "-", message: "Hangi e-posta?"),
            .init(action: .type, target: "email_field", text: "qa@firma.com", message: "E-postayı yazıyorum."),
            .init(action: .tap, target: "login_button"),
            .init(action: .assertVisible, target: "welcome_label"),
            .init(action: .finish, target: "-", message: "Giriş doğrulandı."),
        ])
        let assistant = FlowAssistant(model: model, runner: InAppTestRunner(driver: driver, configuration: fast),
                                      screen: screen(driver), settleTime: .zero)

        assistant.start(goal: "Giriş yapılabilmeli")
        await waitUntilSettled(assistant)
        #expect(assistant.phase == .awaitingAnswer("Hangi e-posta?"))

        assistant.answer("qa@firma.com")
        await waitUntilSettled(assistant)
        #expect(assistant.phase == .awaitingApproval(line: "type: email_field -> qa@firma.com", reason: "E-postayı yazıyorum."))

        for _ in 0..<3 {
            assistant.approve()
            await waitUntilSettled(assistant)
        }

        #expect(assistant.phase == .finished("Giriş doğrulandı."))
        #expect(assistant.steps == [
            "type: email_field -> qa@firma.com",
            "tap: login_button",
            "assertVisible: welcome_label",
        ])
        #expect(driver.actions == ["type email_field=qa@firma.com", "tap login_button"])

        let contexts = await model.contexts
        try #require(contexts.count == 5)
        #expect(contexts[1].answers == [.init(question: "Hangi e-posta?", answer: "qa@firma.com")])
        #expect(contexts[3].screen.map(\.query).contains("welcome_label"))
        #expect(contexts[1].prompt.contains("- Q: Hangi e-posta? A: qa@firma.com"))

        let json = try assistant.catalogEntry(name: "Başarılı giriş", tags: ["smoke"])
        let decoded = try ScenarioCatalog.decode(Data("[\(json)]".utf8))
        #expect(decoded.first?.id == "basarılı-giris")
        #expect(decoded.first?.script == assistant.script)
        #expect(json.contains("\"tap: login_button\""))
        let order = ["\"id\"", "\"name\"", "\"description\"", "\"tags\"", "\"steps\""]
            .compactMap { json.range(of: $0)?.lowerBound }
        #expect(order.count == 5 && order == order.sorted(), "\(json)")
    }

    @Test func autoAdvanceRunsWithoutApprovalAndFeedsFailuresBack() async throws {
        let driver = FakeDriver()
        driver.visible = ["a", "b"]
        let model = ScriptedModel([
            .init(action: .tap, target: "a"),
            .init(action: .tap, target: "missing"),        // ekranda yok → geçersiz hedef
            .init(action: .assertVisible, target: "b"),
            .init(action: .finish, target: "-", message: "Tamam"),
        ])
        let assistant = FlowAssistant(model: model, runner: InAppTestRunner(driver: driver, configuration: fast),
                                      screen: screen(driver), settleTime: .zero)
        assistant.autoAdvance = true

        assistant.start(goal: "a'ya bas, b görünsün")
        await waitUntilSettled(assistant)

        #expect(assistant.phase == .finished("Tamam"))
        #expect(assistant.steps == ["tap: a", "assertVisible: b"])
        let contexts = await model.contexts
        try #require(contexts.count == 4)
        #expect(contexts[2].lastIssue?.contains("no valid target") == true)
    }

    @Test func givesUpAfterRepeatedFailures() async throws {
        let driver = FakeDriver()
        driver.visible = ["label"]
        let model = ScriptedModel(Array(repeating: .init(action: .type, target: "label", text: "x"), count: 5))
        let assistant = FlowAssistant(model: model, runner: InAppTestRunner(driver: driver, configuration: fast),
                                      screen: screen(driver), maxFailuresInARow: 2, settleTime: .zero)
        assistant.autoAdvance = true

        assistant.start(goal: "label'a yaz")
        await waitUntilSettled(assistant)

        guard case .failed(let message) = assistant.phase else {
            Issue.record("başarısız olmalıydı: \(assistant.phase)")
            return
        }
        #expect(message.contains("Üst üste 2 adım"))
        #expect(assistant.steps.isEmpty)
        let contexts = await model.contexts
        try #require(contexts.count >= 2)
        #expect(contexts[1].lastIssue?.contains("'type: label -> x' failed") == true)
    }

    @Test func rejectionIsReportedToTheModel() async throws {
        let driver = FakeDriver()
        driver.visible = ["a", "b"]
        let model = ScriptedModel([
            .init(action: .tap, target: "a"),
            .init(action: .tap, target: "b"),
        ])
        let assistant = FlowAssistant(model: model, runner: InAppTestRunner(driver: driver, configuration: fast),
                                      screen: screen(driver), settleTime: .zero)

        assistant.start(goal: "b'ye bas")
        await waitUntilSettled(assistant)
        assistant.reject("a değil, b")
        await waitUntilSettled(assistant)

        #expect(assistant.phase == .awaitingApproval(line: "tap: b", reason: nil))
        #expect(driver.actions.isEmpty)
        let contexts = await model.contexts
        try #require(contexts.count == 2)
        #expect(contexts[1].lastIssue == "The tester rejected 'tap: a': a değil, b")
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
