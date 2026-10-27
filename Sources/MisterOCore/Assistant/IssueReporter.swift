import Foundation

/// Asistanın bulduğu bir sorunun hata kaydı.
public struct BugReport: Equatable, Codable, Sendable {
    /// Kayda eklenecek dosya; asistan sorunun ekran görüntüsünü (`screenshot.png`) ekler.
    public struct Attachment: Equatable, Codable, Sendable {
        public let filename: String
        public let mimeType: String
        /// JSON'da base64 olarak yazılır.
        public let data: Data

        public init(filename: String, mimeType: String, data: Data) {
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }
    }

    public let title: String
    /// Denenen adımlar sırasıyla; düşen adımın yanında nedeni yazar.
    public let steps: [String]
    public let expected: String
    public let actual: String
    public let environment: String
    public let attachments: [Attachment]
    /// Aynı hatanın sabit kimliği (senaryo + düşen adım). Doluysa aynı hata ikinci kez kayıt açmaz;
    /// Jira'da `mistero-<parmak izi>` etiketi olur, webhook gövdesinde `fingerprint` alanıdır.
    public let fingerprint: String?

    public init(title: String, steps: [String], expected: String, actual: String, environment: String,
                attachments: [Attachment] = [], fingerprint: String? = nil) {
        self.title = title
        self.steps = steps
        self.expected = expected
        self.actual = actual
        self.environment = environment
        self.attachments = attachments
        self.fingerprint = fingerprint
    }

    /// Dile ve süreye bağlı olmayan parmak izi: aynı senaryo aynı adımda düştükçe aynıdır.
    public static func fingerprint(_ parts: String...) -> String {
        let hash = parts.joined(separator: "\u{1F}").utf8
            .reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// Jira, Slack ya da e-postaya yapıştırılacak düz metin.
    public var text: String {
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return """
        \(title)

        \(L("Steps")):
        \(numbered.isEmpty ? L("(no steps)") : numbered.joined(separator: "\n"))

        \(L("Expected")): \(expected)
        \(L("Actual")): \(actual)
        \(L("Environment")): \(environment)
        """
    }
}

extension BugReport {
    /// Ekleri olmadan yazılmış eski kayıtlar da okunabilsin.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try container.decode(String.self, forKey: .title),
                  steps: try container.decode([String].self, forKey: .steps),
                  expected: try container.decode(String.self, forKey: .expected),
                  actual: try container.decode(String.self, forKey: .actual),
                  environment: try container.decode(String.self, forKey: .environment),
                  attachments: try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? [],
                  fingerprint: try container.decodeIfPresent(String.self, forKey: .fingerprint))
    }
}

/// Açılan kaydın kimliği: "PROJ-123" ve/veya bağlantısı.
public struct IssueReceipt: Equatable, Sendable {
    public let key: String?
    public let url: URL?
    /// Kayıt açıldı ama bir şey eksik kaldı ("Ekran görüntüsü eklenemedi: …"); panelde kaydın altında görünür.
    public let warning: String?
    /// Yeni kayıt açılmadı: aynı hata için açık bir kayıt zaten vardı.
    public let isExisting: Bool

    public init(key: String?, url: URL?, warning: String? = nil, isExisting: Bool = false) {
        self.key = key
        self.url = url
        self.warning = warning
        self.isExisting = isExisting
    }
}

/// Sorunları takip aracınızda (Jira, Linear, GitHub Issues…) kayda çevirir. Uygulama kurulumda verir;
/// verilmezse panel hata kaydını kopyalama/paylaşma ile yetinir.
public protocol IssueReporter: Sendable {
    /// Butonda görünen ad: "Kayıt aç (Jira)".
    var name: String { get }
    func open(_ report: BugReport) async throws -> IssueReceipt
}

/// Kaydı bir webhook'a JSON olarak gönderir. Jira Automation'ın "Incoming webhook" tetikleyicisi, Zapier,
/// Make ya da kendi sunucunuz bu JSON'dan kaydı açar; staging uygulamasına Jira API token'ı koymanız gerekmez.
///
/// Gövde: `{ "title", "steps": [..], "expected", "actual", "environment", "description", "attachments": [..],
/// "fingerprint" }`. `fingerprint` aynı hata için aynıdır; sunucu onunla açık kaydı bulup yenisini açmayabilir.
/// `attachments` elemanları `{ "filename", "mimeType", "data" }`, `data` base64'tür.
/// Cevap JSON'unda `key` ve `url` (ya da Jira'nın `self`) alanları varsa panelde gösterilir.
public struct WebhookIssueReporter: IssueReporter {
    public let name: String
    public let url: URL
    public let headers: [String: String]
    /// `false` ise ekran görüntüsü gönderilmez (`attachments` boş gelir); büyük gövdeyi kabul etmeyen
    /// webhook'lar için.
    public let includesAttachments: Bool

    public init(name: String = "Jira", url: URL, headers: [String: String] = [:], includesAttachments: Bool = true) {
        self.name = name
        self.url = url
        self.headers = headers
        self.includesAttachments = includesAttachments
    }

    public func open(_ report: BugReport) async throws -> IssueReceipt {
        Self.receipt(from: try await IssueHTTP.send(try request(for: report)))
    }

    func request(for report: BugReport) throws -> URLRequest {
        struct Payload: Encodable {
            let title: String
            let steps: [String]
            let expected: String
            let actual: String
            let environment: String
            let description: String
            let attachments: [BugReport.Attachment]
            let fingerprint: String?
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(Payload(
            title: report.title, steps: report.steps, expected: report.expected, actual: report.actual,
            environment: report.environment, description: report.text,
            attachments: includesAttachments ? report.attachments : [], fingerprint: report.fingerprint
        ))
        return request
    }

    static func receipt(from data: Data) -> IssueReceipt {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return IssueReceipt(key: nil, url: nil)
        }
        let link = (json["url"] ?? json["self"]) as? String
        return IssueReceipt(key: json["key"] as? String, url: link.flatMap(URL.init(string:)))
    }
}

enum IssueHTTP {
    /// İsteği gönderir; 2xx dışında hata fırlatır. `message`, sunucunun hata gövdesinden okunur bir neden çıkarır.
    static func send(_ request: URLRequest, message: (Data) -> String? = { _ in nil }) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let message = message(data) {
                throw IssueReporterError.rejected(status: http.statusCode, message: message)
            }
            throw IssueReporterError.httpStatus(http.statusCode)
        }
        return data
    }
}

public enum IssueReporterError: Error, Equatable, Sendable {
    case httpStatus(Int)
    /// Sunucu isteği nedenini söyleyerek reddetti (Jira: "issuetype: Specify an issue type").
    case rejected(status: Int, message: String)
}

extension IssueReporterError: LocalizedError {
    public var errorDescription: String? {
        L("Couldn't open the ticket: %@", reason)
    }

    var reason: String {
        switch self {
        case .httpStatus(let code): L("the server returned %ld.", code)
        case .rejected(let code, let message): L("the server returned %ld (%@).", code, message)
        }
    }
}
