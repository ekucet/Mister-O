import Foundation

/// Katalogdaki tek bir test senaryosu.
public struct Scenario: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String?
    public let tags: [String]
    /// Çalışmadan önce uygulama başlangıç durumuna getirilsin mi (bir `resetApp` işleyicisi varsa).
    public let resetsApp: Bool
    /// `FlowParser`'ın okuduğu akış metni.
    public let script: String

    public init(
        id: String? = nil,
        name: String,
        summary: String? = nil,
        tags: [String] = [],
        resetsApp: Bool = true,
        script: String
    ) {
        self.id = id?.nonEmpty ?? Self.slug(name)
        self.name = name
        self.summary = summary?.nonEmpty
        self.tags = tags
        self.resetsApp = resetsApp
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
///       "steps": ["tap: login_button", "assertVisible: welcome_label"]
///     }
///
/// `steps` yerine çok satırlı tek bir `flow` metni de verilebilir.
extension Scenario: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, description, tags, reset, steps, flow
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
                debugDescription: "'\(name)' senaryosunda 'steps' ya da 'flow' gerekli."
            )
        }

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            name: name,
            summary: try container.decodeIfPresent(String.self, forKey: .description),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            resetsApp: try container.decodeIfPresent(Bool.self, forKey: .reset) ?? true,
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
                            tags: scenario.tags, resetsApp: scenario.resetsApp, script: scenario.script)
        }
    }

    /// Katalog hatalarını QA ekibinin anlayacağı dile çevirir (ör. "scenarios[2].name alanı eksik").
    public static func describe(_ error: any Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])) alanı eksik."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)) alanının tipi hatalı."
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? "Katalog geçerli bir JSON değil."
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
