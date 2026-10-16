import Foundation
import Testing
@testable import MisterOCore

struct ScenarioCatalogTests {
    @Test func decodesStepsFlowAndOptionalFields() throws {
        let json = """
        {
          "scenarios": [
            {
              "id": "login",
              "name": "Başarılı giriş",
              "description": "Geçerli kullanıcı",
              "tags": ["smoke", "auth"],
              "steps": ["type: email_field -> a@b.c", "tap: login_button"]
            },
            { "name": "Profil Kaydı", "reset": false, "flow": "tap: Kaydet\\nwait: 1" }
          ]
        }
        """
        let scenarios = try ScenarioCatalog.decode(Data(json.utf8))

        #expect(scenarios.count == 2)
        #expect(scenarios[0].id == "login")
        #expect(scenarios[0].summary == "Geçerli kullanıcı")
        #expect(scenarios[0].tags == ["smoke", "auth"])
        #expect(scenarios[0].resetsApp)
        #expect(scenarios[0].script == "type: email_field -> a@b.c\ntap: login_button")
        #expect(scenarios[1].id == "profil-kaydı")
        #expect(scenarios[1].resetsApp == false)
        #expect(scenarios[1].script == "tap: Kaydet\nwait: 1")
    }

    @Test func readsAndWritesTheGoal() throws {
        let json = #"[{ "name": "Giriş", "goal": "Geçerli hesapla giriş yapılabilmeli", "steps": ["tap: a"] }]"#
        let scenario = try #require(try ScenarioCatalog.decode(Data(json.utf8)).first)
        #expect(scenario.goal == "Geçerli hesapla giriş yapılabilmeli")
        #expect(ScenarioCatalog.entry(for: scenario).contains(#""goal": "Geçerli hesapla giriş yapılabilmeli""#))
        #expect(try ScenarioCatalog.decode(Data(ScenarioCatalog.json(for: [scenario]).utf8)) == [scenario])
    }

    @Test func acceptsTopLevelArrayAndUniquesIDs() throws {
        let json = """
        [
          { "name": "Giriş", "steps": ["tap: a"] },
          { "name": "Giriş", "steps": ["tap: b"] }
        ]
        """
        let scenarios = try ScenarioCatalog.decode(Data(json.utf8))
        #expect(scenarios.map(\.id) == ["giris", "giris-2"])
    }

    @Test func describesErrorsWithPaths() {
        let missingName = #"{ "scenarios": [ { "steps": [] }, { "steps": [] } ] }"#
        let missingSteps = #"{ "scenarios": [ { "name": "Ödeme" } ] }"#

        #expect(throws: (any Error).self) { try ScenarioCatalog.decode(Data(missingName.utf8)) }
        do {
            _ = try ScenarioCatalog.decode(Data(missingName.utf8))
        } catch {
            #expect(ScenarioCatalog.describe(error) == "scenarios[0].name alanı eksik.")
        }
        do {
            _ = try ScenarioCatalog.decode(Data(missingSteps.utf8))
        } catch {
            #expect(ScenarioCatalog.describe(error) == "'Ödeme' senaryosunda 'steps' ya da 'flow' gerekli.")
        }
        do {
            _ = try ScenarioCatalog.decode(Data("{ oops".utf8))
        } catch {
            #expect(ScenarioCatalog.describe(error) == "Katalog geçerli bir JSON değil.")
        }
    }
}

@MainActor
final class Counter {
    var value = 0
}

@MainActor
struct ScenarioStoreTests {
    private let fast = InAppTestRunner.Configuration(
        elementTimeout: .milliseconds(80),
        pollInterval: .milliseconds(10),
        delayBetweenSteps: .zero
    )

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test func loadsAndValidatesCatalog() async {
        let feed = ScenarioFeed.inline([
            Scenario(name: "İyi", tags: ["smoke"], script: "tap: a\nwait: 0"),
            Scenario(name: "Bozuk", tags: ["smoke", "auth"], script: "tapp: a"),
        ])
        let store = ScenarioStore(feed: feed, runner: InAppTestRunner(driver: FakeDriver()), cacheDirectory: nil)

        await store.refresh()

        guard case .live = store.status else {
            Issue.record("canlı yüklenmeliydi: \(store.status)")
            return
        }
        #expect(store.scenarios.map(\.name) == ["İyi", "Bozuk"])
        #expect(store.tags == ["smoke", "auth"])
        #expect(store.validation(for: store.scenarios[0]) == .init(stepCount: 2, issues: []))
        #expect(store.validation(for: store.scenarios[1]).isValid == false)
    }

    @Test func fallsBackToCacheWhenSourceFails() async {
        let directory = temporaryDirectory()
        let runner = InAppTestRunner(driver: FakeDriver())
        let online = ScenarioFeed(name: "uzak", cacheKey: "https://example.com/c.json") {
            [Scenario(name: "Önbellekteki", script: "tap: a")]
        }
        let offline = ScenarioFeed(name: "uzak", cacheKey: "https://example.com/c.json") {
            throw URLError(.notConnectedToInternet)
        }

        let first = ScenarioStore(feed: online, runner: runner, cacheDirectory: directory)
        await first.refresh()

        let second = ScenarioStore(feed: offline, runner: runner, cacheDirectory: directory)
        await second.refresh()
        #expect(second.scenarios.map(\.name) == ["Önbellekteki"])
        guard case .cached = second.status else {
            Issue.record("önbellekten gelmeliydi: \(second.status)")
            return
        }

        let noCache = ScenarioStore(feed: offline, runner: runner, cacheDirectory: temporaryDirectory())
        await noCache.refresh()
        #expect(noCache.scenarios.isEmpty)
        guard case .failed = noCache.status else {
            Issue.record("hata vermeliydi: \(noCache.status)")
            return
        }
    }

    @Test func suiteResetsBeforeEachScenarioAndContinuesAfterFailure() async {
        let driver = FakeDriver()
        driver.visible = ["a", "b"]
        let runner = InAppTestRunner(driver: driver, configuration: fast)
        let resets = Counter()
        let store = ScenarioStore(
            feed: nil, runner: runner,
            resetApp: { resets.value += 1 },
            settleTime: .zero, cacheDirectory: nil
        )
        let scenarios = [
            Scenario(name: "Bir", script: "tap: a"),
            Scenario(name: "İki", script: "tap: missing"),
            Scenario(name: "Üç", resetsApp: false, script: "tap: b"),
            Scenario(name: "Dört", script: "zoom: 1"),
        ]

        await store.runSuite(scenarios)

        #expect(resets.value == 3)
        #expect(driver.actions == ["tap a", "tap b"])
        #expect(scenarios.map { store.runs[$0.id]?.state } == [.passed, .failed, .passed, .invalidScript])
        #expect(store.runs[scenarios[1].id]?.failureMessage?.hasPrefix("Satır 1: Ekranda bulunamadı") == true)
        #expect(store.suite?.isRunning == false)
        #expect(store.suite?.wasCancelled == false)
        #expect(store.suiteReportText.contains("Suite · 2/4 başarılı"))
        #expect(store.suiteReportText.contains("✗ İki"))
    }

    @Test func cancellingStopsTheSuite() async {
        let driver = FakeDriver()
        driver.visible = ["a"]
        let store = ScenarioStore(feed: nil, runner: InAppTestRunner(driver: driver, configuration: fast),
                                  settleTime: .zero, cacheDirectory: nil)
        let scenarios = [
            Scenario(name: "Uzun", script: "wait: 5"),
            Scenario(name: "Sonraki", script: "tap: a"),
        ]

        store.startSuite(scenarios)
        #expect(store.isRunning)
        try? await Task.sleep(for: .milliseconds(50))
        store.cancel()
        while store.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.suite?.wasCancelled == true)
        #expect(store.runs[scenarios[0].id]?.state == .cancelled)
        #expect(store.runs[scenarios[1].id] == nil)
        #expect(driver.actions.isEmpty)
    }
}
