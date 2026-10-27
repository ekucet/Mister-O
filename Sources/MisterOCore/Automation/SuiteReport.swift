import Foundation

/// Bir suite koşusunun sonucu: konsola, dosyaya (JUnit, JSON, Markdown) ve sohbet/webhook'a bu yazılır.
public struct SuiteReport: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public enum Outcome: String, Codable, Sendable {
            case passed, failed, invalid, cancelled, notRun
        }

        public let id: String
        public let name: String
        public let tags: [String]
        public let outcome: Outcome
        /// Saniye.
        public let duration: Double?
        public let failure: String?
        public internal(set) var ticketKey: String?
        public internal(set) var ticketURL: URL?
        /// Kayıt bu koşuda açılmadı; aynı hata için açık olan bulundu.
        public internal(set) var ticketIsExisting: Bool?
    }

    /// "autorun · #smoke" ya da "manual".
    public let trigger: String
    public let environment: String
    public let startedAt: Date
    /// Saniye.
    public let duration: Double
    public internal(set) var items: [Item]
    public let total: Int
    public let passed: Int
    public let failed: Int

    public init(trigger: String, environment: String, startedAt: Date, duration: Double, items: [Item]) {
        self.trigger = trigger
        self.environment = environment
        self.startedAt = startedAt
        self.duration = duration
        self.items = items
        total = items.count
        passed = items.filter { $0.outcome == .passed }.count
        failed = items.filter { $0.outcome == .failed || $0.outcome == .invalid }.count
    }

    /// Suite'in son hâlinden.
    @MainActor
    public init(suite: ScenarioStore.Suite, runs: [Scenario.ID: ScenarioStore.Run], trigger: String,
                environment: String, startedAt: Date) {
        let items = suite.scenarios.map { scenario -> Item in
            let run = runs[scenario.id]
            let outcome: Item.Outcome = switch run?.state {
            case .passed: .passed
            case .failed: .failed
            case .invalidScript: .invalid
            case .cancelled: .cancelled
            default: .notRun
            }
            return Item(id: scenario.id, name: scenario.name, tags: scenario.tags, outcome: outcome,
                        duration: run?.elapsed?.seconds, failure: outcome == .passed ? nil : run?.failureMessage)
        }
        self.init(trigger: trigger, environment: environment, startedAt: startedAt,
                  duration: suite.elapsed?.seconds ?? 0, items: items)
    }

    public var hasFailures: Bool { failed > 0 }

    // MARK: - Biçimler

    /// "Mister-O · 4/5 passed · 19.66 s" ve düşenler; konsol ve Slack için.
    public var text: String {
        var lines = ["Mister-O · " + L("%ld/%ld passed", passed, total) + " · " + L("%.2f s", duration)
                     + " · \(trigger)", environment]
        for item in items where item.outcome != .passed {
            var line = "\(Self.symbol(item.outcome)) \(item.name)"
            if let failure = item.failure { line += " — \(failure)" }
            if let ticket = ticketText(item) { line += " → \(ticket)" }
            lines.append(line)
        }
        if !hasFailures {
            lines.append("✓ " + L("All scenarios passed."))
        }
        return lines.joined(separator: "\n")
    }

    /// GitHub Actions özet sayfası (`$GITHUB_STEP_SUMMARY`) için.
    public var markdown: String {
        var lines = ["### Mister-O · " + L("%ld/%ld passed", passed, total) + " · " + L("%.2f s", duration), "",
                     "`\(trigger)` · \(environment)", "",
                     "| | " + L("Scenario") + " | " + L("Time") + " | " + L("Result") + " |", "|---|---|---|---|"]
        for item in items {
            let time = item.duration.map { L("%.2f s", $0) } ?? "–"
            let result = ([item.failure] + [ticketText(item)]).compactMap { $0 }.joined(separator: " → ")
            lines.append("| \(Self.symbol(item.outcome)) | \(Self.cell(item.name)) | \(time) | \(Self.cell(result)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// CI araçlarının okuduğu JUnit XML.
    public var junitXML: String {
        let errors = items.filter { $0.outcome == .invalid }.count
        let skipped = items.filter { $0.outcome == .cancelled || $0.outcome == .notRun }.count
        let failures = items.filter { $0.outcome == .failed }.count
        let timestamp = ISO8601DateFormatter().string(from: startedAt)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites name="Mister-O" tests="\(total)" failures="\(failures)" errors="\(errors)" time="\(Self.seconds(duration))">
          <testsuite name="Mister-O" tests="\(total)" failures="\(failures)" errors="\(errors)" skipped="\(skipped)" time="\(Self.seconds(duration))" timestamp="\(timestamp)">

        """
        for item in items {
            let open = "    <testcase classname=\"\(Self.xml(item.tags.first ?? "Mister-O"))\" name=\"\(Self.xml(item.name))\" time=\"\(Self.seconds(item.duration ?? 0))\""
            let detail = Self.xml(([item.failure] + [ticketText(item)]).compactMap { $0 }.joined(separator: "\n"))
            switch item.outcome {
            case .passed:
                xml += open + "/>\n"
            case .failed:
                xml += open + ">\n      <failure message=\"\(Self.xml(item.failure ?? ""))\">\(detail)</failure>\n    </testcase>\n"
            case .invalid:
                xml += open + ">\n      <error message=\"\(Self.xml(item.failure ?? ""))\">\(detail)</error>\n    </testcase>\n"
            case .cancelled, .notRun:
                xml += open + ">\n      <skipped/>\n    </testcase>\n"
            }
        }
        return xml + "  </testsuite>\n</testsuites>\n"
    }

    /// `report.json`: tüm alanlar, CI betikleri `jq '.failed'` ile okur.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)) ?? Data()
    }

    // MARK: - Yardımcılar

    private func ticketText(_ item: Item) -> String? {
        guard let key = item.ticketKey ?? item.ticketURL?.absoluteString else { return nil }
        let link = [key, item.ticketURL.map(\.absoluteString)].compactMap { $0 }.uniqued().joined(separator: " ")
        return item.ticketIsExisting == true ? L("already reported: %@", link) : L("ticket: %@", link)
    }

    private static func symbol(_ outcome: Item.Outcome) -> String {
        switch outcome {
        case .passed: "✓"
        case .failed, .invalid: "✗"
        case .cancelled, .notRun: "–"
        }
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
