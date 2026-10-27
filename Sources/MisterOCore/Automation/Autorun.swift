import Foundation

/// Kendiliğinden koşacak senaryolar: hepsi, etiketler (`#smoke`) ya da kimlikler (`login-success`).
///
///     "#smoke"                     → smoke etiketli senaryolar
///     "#smoke, profile-save"       → smoke etiketliler ve profile-save
///     "all" ya da "*"              → hepsi
public struct AutorunSelection: Equatable, Codable, Sendable {
    public var all: Bool
    public var tags: [String]
    public var ids: [String]

    public init(all: Bool = false, tags: [String] = [], ids: [String] = []) {
        self.all = all
        self.tags = tags
        self.ids = ids
    }

    public static let all = AutorunSelection(all: true)

    public static func tags(_ tags: String...) -> AutorunSelection {
        AutorunSelection(tags: tags)
    }

    public static func ids(_ ids: String...) -> AutorunSelection {
        AutorunSelection(ids: ids)
    }

    /// `"#smoke, login-success"` biçimindeki metni okur; boşsa `nil`.
    public init?(parsing text: String) {
        let parts = text.split { $0 == "," || $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        self.init()
        for part in parts {
            switch part.lowercased() {
            case "all", "*": all = true
            default:
                if part.hasPrefix("#") {
                    let tag = String(part.dropFirst())
                    if !tag.isEmpty { tags.append(tag) }
                } else {
                    ids.append(part)
                }
            }
        }
        guard all || !tags.isEmpty || !ids.isEmpty else { return nil }
    }

    public var isEmpty: Bool { !all && tags.isEmpty && ids.isEmpty }

    public func matches(_ scenario: Scenario) -> Bool {
        all || ids.contains(scenario.id) || scenario.tags.contains { tags.contains($0) }
    }

    /// `"#smoke, login-success"`; raporlarda ve günlükte görünür.
    public var description: String {
        all ? "all" : (tags.map { "#\($0)" } + ids).joined(separator: ", ")
    }

    // MARK: - Katalog
    //
    // Katalogda `"autorun": "#smoke"` ya da `"autorun": { "tags": ["smoke"], "ids": [..] }` yazılır.

    private enum CodingKeys: String, CodingKey {
        case all, tags, ids
    }

    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            guard let parsed = AutorunSelection(parsing: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: L("'autorun' is empty.")))
            }
            self = parsed
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(all: try container.decodeIfPresent(Bool.self, forKey: .all) ?? false,
                  tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
                  ids: try container.decodeIfPresent([String].self, forKey: .ids) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Uygulama açılınca senaryoları kimse dokunmadan koşturur.
///
/// Üç yerden gelebilir; ilk bulunan geçerlidir:
/// 1. Başlatma argümanı ya da ortam değişkeni (CI): `-MisterOAutorun "#smoke"` / `MISTERO_AUTORUN=#smoke`.
///    `MISTERO_EXIT=1` (ya da `-MisterOExit YES`) koşu bitince uygulamayı kapatır.
/// 2. Kurulumdaki `autorun:` parametresi.
/// 3. Katalog dosyasındaki `"autorun"` alanı: QA ekibi uygulamayı yeniden derlemeden açıp kapatır.
public struct Autorun: Equatable, Sendable {
    public var selection: AutorunSelection
    /// Düşen senaryolar için takip aracında kayıt aç (`issueReporter` verildiyse). Aynı hata ikinci kez
    /// kayıt açmaz.
    public var opensTickets: Bool
    /// Sonuçlar yazılıp gönderildikten sonra uygulamayı kapat; çıkış kodu düşen varsa 1. CI için.
    public var exitsWhenDone: Bool

    public init(_ selection: AutorunSelection, opensTickets: Bool = true, exitsWhenDone: Bool = false) {
        self.selection = selection
        self.opensTickets = opensTickets
        self.exitsWhenDone = exitsWhenDone
    }

    public static func tags(_ tags: String..., opensTickets: Bool = true) -> Autorun {
        Autorun(AutorunSelection(tags: tags), opensTickets: opensTickets)
    }

    public static func ids(_ ids: String..., opensTickets: Bool = true) -> Autorun {
        Autorun(AutorunSelection(ids: ids), opensTickets: opensTickets)
    }

    public static let all = Autorun(.all)

    public static let environmentKey = "MISTERO_AUTORUN"
    public static let exitEnvironmentKey = "MISTERO_EXIT"
    public static let ticketsEnvironmentKey = "MISTERO_TICKETS"
    public static let argumentKey = "MisterOAutorun"
    public static let exitArgumentKey = "MisterOExit"

    /// Başlatma argümanından (`UserDefaults` argüman alanı) ya da ortam değişkeninden; ikisi de yoksa `nil`.
    public static func fromLaunch(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  defaults: UserDefaults = .standard) -> Autorun? {
        let raw = defaults.string(forKey: argumentKey) ?? environment[environmentKey]
        guard let raw, let selection = AutorunSelection(parsing: raw) else { return nil }
        let exits = defaults.object(forKey: exitArgumentKey) != nil
            ? defaults.bool(forKey: exitArgumentKey)
            : ["1", "true", "yes"].contains(environment[exitEnvironmentKey]?.lowercased() ?? "")
        let tickets = !["0", "false", "no"].contains(environment[ticketsEnvironmentKey]?.lowercased() ?? "")
        return Autorun(selection, opensTickets: tickets, exitsWhenDone: exits)
    }
}
