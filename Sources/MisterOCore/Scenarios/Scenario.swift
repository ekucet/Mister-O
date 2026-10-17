import Foundation

/// Katalogdaki tek bir test senaryosu.
public struct Scenario: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String?
    public let tags: [String]
    /// Çalışmadan önce uygulama başlangıç durumuna getirilsin mi (bir `resetApp` işleyicisi varsa).
    public let resetsApp: Bool
    /// Senaryonun düz cümleyle amacı. Adımlar UI değiştiği için düşerse asistan bu cümleyle senaryoyu onarır.
    public let goal: String?
    /// `FlowParser`'ın okuduğu akış metni.
    public let script: String

    public init(
        id: String? = nil,
        name: String,
        summary: String? = nil,
        tags: [String] = [],
        resetsApp: Bool = true,
        goal: String? = nil,
        script: String
    ) {
        self.id = id?.nonEmpty ?? Self.slug(name)
        self.name = name
        self.summary = summary?.nonEmpty
        self.tags = tags
        self.resetsApp = resetsApp
        self.goal = goal?.nonEmpty
        self.script = script
    }

    /// "Başarılı Giriş" → "basarılı-giris"
    static func slug(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }
}

/// Katalog dosyasındaki bir kayıt:
///
///     {
///       "id": "login-success",              // isteğe bağlı; yoksa addan türetilir
///       "name": "Başarılı giriş",
///       "description": "Geçerli kullanıcıyla giriş yapar.",
///       "tags": ["smoke", "auth"],
///       "reset": true,                      // isteğe bağlı; varsayılan true
///       "goal": "Geçerli hesapla giriş yapılabilmeli",  // isteğe bağlı; asistanla onarmak için
///       "steps": ["tap: login_button", "assertVisible: welcome_label"]
///     }
///
/// `steps` yerine çok satırlı tek bir `flow` metni de verilebilir.
extension Scenario: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, tags, reset, goal, steps, flow
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)

        let script: String
        if let steps = try container.decodeIfPresent([String].self, forKey: .steps) {
            script = steps.joined(separator: "\n")
        } else if let flow = try container.decodeIfPresent(String.self, forKey: .flow) {
            script = flow
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps, in: container,
                debugDescription: L("Scenario '%@' needs 'steps' or 'flow'.", name)
            )
        }

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: name,
            summary: try container.decodeIfPresent(String.self, forKey: .description),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            resetsApp: try container.decodeIfPresent(Bool.self, forKey: .reset) ?? true,
            goal: try container.decodeIfPresent(String.self, forKey: .goal),
            script: script
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(summary, forKey: .description)
        try container.encode(tags, forKey: .tags)
        try container.encode(resetsApp, forKey: .reset)
        try container.encodeIfPresent(goal, forKey: .goal)
        try container.encode(script, forKey: .flow)
    }
}

/// Katalog dosyası: `{ "scenarios": [ … ] }` ya da doğrudan `[ … ]`.
public enum ScenarioCatalog {
    public static func decode(_ data: Data) throws -> [Scenario] {
        struct Root: Decodable {
            let scenarios: [Scenario]
        }
        let decoder = JSONDecoder()
        let scenarios: [Scenario]
        do {
            scenarios = try decoder.decode(Root.self, from: data).scenarios
        } catch let rootError {
            // Kök dizi biçimini de kabul et; o da olmazsa asıl (nesne) hatasını göster.
            guard let array = try? decoder.decode([Scenario].self, from: data) else { throw rootError }
            scenarios = array
        }
        return uniquingIDs(scenarios)
    }

    /// Aynı id'li kayıtlar sonuçların karışmaması için "-2", "-3"… ile ayrılır.
    static func uniquingIDs(_ scenarios: [Scenario]) -> [Scenario] {
        var seen: [String: Int] = [:]
        return scenarios.map { scenario in
            let count = seen[scenario.id, default: 0] + 1
            seen[scenario.id] = count
            guard count > 1 else { return scenario }
            return Scenario(id: "\(scenario.id)-\(count)", name: scenario.name, summary: scenario.summary,
                            tags: scenario.tags, resetsApp: scenario.resetsApp, goal: scenario.goal,
                            script: scenario.script)
        }
    }

    /// Senaryoları katalog dosyası biçiminde yazar: `{ "scenarios": [ … ] }`. Alan sırası sabittir
    /// (id, name, description, tags, reset, steps); `JSONEncoder` her platformda sırayı korumaz.
    public static func json(for scenarios: [Scenario]) -> String {
        let entries = scenarios.map { entry(for: $0, indent: "    ") }.joined(separator: ",\n")
        return "{\n  \"scenarios\": [\n\(entries)\n  ]\n}"
    }

    /// Kataloğun `scenarios` dizisine yapıştırılacak tek kayıt.
    public static func entry(for scenario: Scenario, indent: String = "") -> String {
        var fields = [
            "\"id\": \(literal(scenario.id))",
            "\"name\": \(literal(scenario.name))",
        ]
        if let summary = scenario.summary {
            fields.append("\"description\": \(literal(summary))")
        }
        fields.append("\"tags\": [\(scenario.tags.map(literal).joined(separator: ", "))]")
        if !scenario.resetsApp {
            fields.append("\"reset\": false")
        }
        if let goal = scenario.goal {
            fields.append("\"goal\": \(literal(goal))")
        }
        let steps = scenario.script.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { "    \(literal($0))" }
        fields.append("\"steps\": [\n" + steps.joined(separator: ",\n") + "\n  ]")

        let body = "{\n" + fields.map { "  " + $0 }.joined(separator: ",\n") + "\n}"
        return body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { indent + $0 }
            .joined(separator: "\n")
    }

    private static func literal(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "\"\""
    }

    /// Katalog hatalarını QA ekibinin anlayacağı dile çevirir (ör. "scenarios[2].name is missing.").
    public static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return L("%@ is missing.", path(context.codingPath + [key]))
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return L("%@ has the wrong type.", path(context.codingPath))
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? L("The catalog isn't valid JSON.")
                : context.debugDescription
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private static func path(_ codingPath: [any CodingKey]) -> String {
        codingPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : self
    }
}
