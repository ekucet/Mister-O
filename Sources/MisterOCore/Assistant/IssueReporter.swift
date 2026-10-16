import Foundation

/// Asistanın bulduğu bir sorunun hata kaydı.
public struct BugReport: Equatable, Codable, Sendable {
    public let title: String
    /// Denenen adımlar sırasıyla; düşen adımın yanında nedeni yazar.
    public let steps: [String]
    public let expected: String
    public let actual: String
    public let environment: String

    public init(title: String, steps: [String], expected: String, actual: String, environment: String) {
        self.title = title
        self.steps = steps
        self.expected = expected
        self.actual = actual
        self.environment = environment
    }

    /// Jira, Slack ya da e-postaya yapıştırılacak düz metin.
    public var text: String {
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return """
        \(title)

        Adımlar:
        \(numbered.isEmpty ? "(adım yok)" : numbered.joined(separator: "\n"))

        Beklenen: \(expected)
        Gerçekleşen: \(actual)
        Ortam: \(environment)
        """
    }
}

/// Açılan kaydın kimliği: "PROJ-123" ve/veya bağlantısı.
public struct IssueReceipt: Equatable, Sendable {
    public let key: String?
    public let url: URL?

    public init(key: String?, url: URL?) {
        self.key = key
        self.url = url
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
/// Gövde: `{ "title", "steps": [..], "expected", "actual", "environment", "description" }`.
/// Cevap JSON'unda `key` ve `url` (ya da Jira'nın `self`) alanları varsa panelde gösterilir.
public struct WebhookIssueReporter: IssueReporter {
    public let name: String
    public let url: URL
    public let headers: [String: String]

    public init(name: String = "Jira", url: URL, headers: [String: String] = [:]) {
        self.name = name
        self.url = url
        self.headers = headers
    }

    public func open(_ report: BugReport) async throws -> IssueReceipt {
        let (data, response) = try await URLSession.shared.data(for: try request(for: report))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw IssueReporterError.httpStatus(http.statusCode)
        }
        return Self.receipt(from: data)
    }

    func request(for report: BugReport) throws -> URLRequest {
        struct Payload: Encodable {
            let title: String
            let steps: [String]
            let expected: String
            let actual: String
            let environment: String
            let description: String
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(Payload(
            title: report.title, steps: report.steps, expected: report.expected, actual: report.actual,
            environment: report.environment, description: report.text
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

public enum IssueReporterError: Error, Equatable, Sendable {
    case httpStatus(Int)
}

extension IssueReporterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code): "Kayıt açılamadı: sunucu \(code) döndü."
        }
    }
}
