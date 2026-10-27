import Foundation

/// Suite bittiğinde sonucu bir yere gönderir (Slack, Teams, kendi sunucunuz…). Kurulumda
/// `resultReporters:` ile verilir; elle "Tümünü çalıştır" da autorun da raporlanır.
public protocol ResultReporter: Sendable {
    func send(_ report: SuiteReport) async throws
}

/// Slack "Incoming Webhook"una (ve aynı biçimi kabul eden Mattermost'a, Discord'un `/slack` adresine) özet
/// metni gönderir: `{ "text": "Mister-O · 4/5 passed …" }`.
public struct SlackResultReporter: ResultReporter {
    public let webhookURL: URL
    /// `true` ise yalnızca düşen senaryo olduğunda yazar.
    public let onlyFailures: Bool

    public init(webhookURL: URL, onlyFailures: Bool = false) {
        self.webhookURL = webhookURL
        self.onlyFailures = onlyFailures
    }

    public func send(_ report: SuiteReport) async throws {
        guard let request = request(for: report) else { return }
        _ = try await IssueHTTP.send(request)
    }

    func request(for report: SuiteReport) -> URLRequest? {
        guard !onlyFailures || report.hasFailures else { return nil }
        var request = URLRequest(url: webhookURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": report.text])
        return request
    }
}

/// Raporun tamamını JSON olarak gönderir (`SuiteReport` alanları: `total`, `passed`, `failed`, `items`…).
public struct WebhookResultReporter: ResultReporter {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    public func send(_ report: SuiteReport) async throws {
        _ = try await IssueHTTP.send(request(for: report))
    }

    func request(for report: SuiteReport) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = report.json
        return request
    }
}
