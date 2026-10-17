import Foundation

/// Senaryo kataloğunun nereden geldiği.
///
///     .remote(URL(string: "https://raw.githubusercontent.com/acme/qa/main/mistero.json")!)
///     .bundled("mistero-scenarios")          // uygulama paketindeki mistero-scenarios.json
///     .inline([Scenario(name: "Giriş", script: "tap: login_button")])
///     .custom(name: "Remote Config") { try await myBackend.scenarios() }
public struct ScenarioFeed: Sendable {
    /// Panelde kaynağı tanıtan kısa ad.
    public var name: String { label() }
    /// Kurulumdan önce oluşturulan `.inline`'ın adı da panelin dilinde görünsün diye geç okunur.
    private let label: @Sendable () -> String
    /// Doluysa son başarılı yükleme diske yazılır ve kaynağa ulaşılamadığında kullanılır.
    public let cacheKey: String?
    let load: @Sendable () async throws -> [Scenario]

    public init(name: String, cacheKey: String? = nil, load: @escaping @Sendable () async throws -> [Scenario]) {
        self.init(label: { name }, cacheKey: cacheKey, load: load)
    }

    private init(label: @escaping @Sendable () -> String, cacheKey: String?,
                 load: @escaping @Sendable () async throws -> [Scenario]) {
        self.label = label
        self.cacheKey = cacheKey
        self.load = load
    }

    /// HTTP(S) üzerinden JSON katalog. Son başarılı yükleme önbelleğe alınır.
    /// Özel bir repoda ise `headers` ile token verilebilir (yalnızca okuma yetkili bir token kullanın).
    public static func remote(_ url: URL, headers: [String: String] = [:]) -> ScenarioFeed {
        ScenarioFeed(name: url.host() ?? url.absoluteString, cacheKey: url.absoluteString) {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ScenarioFeedError.httpStatus(http.statusCode)
            }
            return try ScenarioCatalog.decode(data)
        }
    }

    /// Uygulama paketindeki `<resource>.json`.
    public static func bundled(_ resource: String, in bundle: Bundle = .main) -> ScenarioFeed {
        let url = bundle.url(forResource: resource, withExtension: "json")
        return ScenarioFeed(name: "\(resource).json") {
            guard let url else { throw ScenarioFeedError.missingResource("\(resource).json") }
            return try ScenarioCatalog.decode(Data(contentsOf: url))
        }
    }

    /// Koddaki sabit liste.
    public static func inline(_ scenarios: [Scenario]) -> ScenarioFeed {
        ScenarioFeed(label: { L("In code") }, cacheKey: nil) { ScenarioCatalog.uniquingIDs(scenarios) }
    }

    /// Kendi kaynağınız (Firebase Remote Config, kendi API'niz…). `cacheKey` verirseniz önbelleğe alınır.
    public static func custom(
        name: String,
        cacheKey: String? = nil,
        _ load: @escaping @Sendable () async throws -> [Scenario]
    ) -> ScenarioFeed {
        ScenarioFeed(name: name, cacheKey: cacheKey) { ScenarioCatalog.uniquingIDs(try await load()) }
    }
}

public enum ScenarioFeedError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case missingResource(String)
}

extension ScenarioFeedError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code): L("The server returned %ld.", code)
        case .missingResource(let name): L("%@ isn't in the app bundle.", name)
        }
    }
}

/// Uzak kataloğun son başarılı halini diskte tutar; çevrimdışıyken testçi yine listeyi görür.
public struct ScenarioCache: Sendable {
    struct Entry: Codable {
        let savedAt: Date
        let scenarios: [Scenario]
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MisterO", isDirectory: true)
    }

    func save(_ scenarios: [Scenario], for key: String, at date: Date = Date()) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Entry(savedAt: date, scenarios: scenarios))
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Önbellek en iyi çaba; yazılamazsa yalnızca çevrimdışı yedek olmaz.
        }
    }

    func load(for key: String) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    private func fileURL(for key: String) -> URL {
        // Kararlı dosya adı için FNV-1a (Hasher her açılışta farklı tohum kullanır).
        let hash = key.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        return directory.appendingPathComponent("scenarios-\(String(hash, radix: 16)).json")
    }
}
