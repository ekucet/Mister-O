import Foundation

/// Kaydı Jira Cloud REST API v3 ile doğrudan açar ve ekleri (ekran görüntüsü) yükler.
///
/// - Important: Token uygulamanın içine girer. Staging derlemesindeki her şey (binary, ortam değişkeni,
///   Keychain) dışarı çıkarılabilir; token'ı ele geçiren, o kullanıcının Jira'da yapabildiği her şeyi
///   yapabilir. Önerilen yol `WebhookIssueReporter`'dır: webhook yalnızca kayıt açabilir. Bunu
///   kullanacaksanız yalnızca o projede kayıt açabilen ayrı bir hesabın token'ını verin ve
///   `#if STAGING` dışına çıkarmayın.
///
/// 1. `POST /rest/api/3/issue`: özet, ADF açıklama (adımlar, beklenen, gerçekleşen, ortam).
/// 2. `POST /rest/api/3/issue/{key}/attachments`: ekler tek multipart istekte. Yükleme düşerse kayıt yine
///    açılmış sayılır (tekrar denenince ikinci kayıt açılmasın); neden `IssueReceipt.warning`'de görünür.
public struct JiraIssueReporter: IssueReporter {
    public let name: String
    /// `https://firma.atlassian.net`
    public let baseURL: URL
    /// `QA`
    public let projectKey: String
    /// Projedeki adıyla kayıt türü: `Bug`, `Hata`…
    public let issueType: String
    /// `Authorization` başlığının değeri: `JiraIssueReporter.basicAuthorization(email:apiToken:)` ya da `Bearer …`.
    public let authorization: String
    /// İsteği gönderir, 2xx cevabın gövdesini döner; testlerde değiştirilir.
    var send: @Sendable (URLRequest) async throws -> Data = {
        try await IssueHTTP.send($0, message: JiraIssueReporter.errorMessage(from:))
    }

    public init(name: String = "Jira", baseURL: URL, projectKey: String, issueType: String = "Bug",
                authorization: String) {
        self.name = name
        self.baseURL = baseURL
        self.projectKey = projectKey
        self.issueType = issueType
        self.authorization = authorization
    }

    /// Atlassian API token'ı için `Basic base64(email:token)` değeri.
    public static func basicAuthorization(email: String, apiToken: String) -> String {
        "Basic " + Data("\(email):\(apiToken)".utf8).base64EncodedString()
    }

    public func open(_ report: BugReport) async throws -> IssueReceipt {
        let receipt = self.receipt(from: try await send(try issueRequest(for: report)))
        guard !report.attachments.isEmpty else { return receipt }
        guard let key = receipt.key else {
            return IssueReceipt(key: nil, url: receipt.url, warning: L("Attachments weren't uploaded: Jira returned no issue key."))
        }
        do {
            _ = try await send(attachmentRequest(for: report.attachments, issueKey: key))
            return receipt
        } catch {
            let reason = (error as? IssueReporterError)?.reason ?? error.localizedDescription
            return IssueReceipt(key: key, url: receipt.url, warning: L("Attachments weren't uploaded: %@", reason))
        }
    }

    // MARK: - İstekler

    func issueRequest(for report: BugReport) throws -> URLRequest {
        struct Body: Encodable {
            struct Fields: Encodable {
                struct Project: Encodable { let key: String }
                struct IssueType: Encodable { let name: String }
                let project: Project
                let issuetype: IssueType
                let summary: String
                let description: ADFNode
            }
            let fields: Fields
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/api/3/issue"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(fields: .init(
            project: .init(key: projectKey), issuetype: .init(name: issueType),
            summary: Self.summary(report.title), description: Self.description(for: report)
        )))
        return request
    }

    func attachmentRequest(for attachments: [BugReport.Attachment], issueKey: String,
                           boundary: String = "MisterO-\(UUID().uuidString)") -> URLRequest {
        let url = baseURL.appendingPathComponent("rest/api/3/issue").appendingPathComponent(issueKey)
            .appendingPathComponent("attachments")
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Jira, bu başlık olmadan ek yüklemelerini XSRF koruması nedeniyle reddeder.
        request.setValue("no-check", forHTTPHeaderField: "X-Atlassian-Token")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        var body = Data()
        for attachment in attachments {
            let filename = attachment.filename.replacingOccurrences(of: "\"", with: "_")
                .components(separatedBy: .newlines).joined()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
            body.append(Data("Content-Type: \(attachment.mimeType)\r\n\r\n".utf8))
            body.append(attachment.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    // MARK: - Cevaplar

    /// Jira'nın `{ "id", "key", "self" }` cevabı. `self` API adresidir; panel kaydın sayfasına (`/browse/KEY`) gider.
    func receipt(from data: Data) -> IssueReceipt {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let key = json?["key"] as? String, !key.isEmpty else {
            return IssueReceipt(key: nil, url: (json?["self"] as? String).flatMap(URL.init(string:)))
        }
        return IssueReceipt(key: key, url: baseURL.appendingPathComponent("browse").appendingPathComponent(key))
    }

    /// `{ "errorMessages": [..], "errors": { "alan": "neden" } }` → "neden; alan: neden".
    static func errorMessage(from data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let messages = json["errorMessages"] as? [String] ?? []
        let fields = (json["errors"] as? [String: String] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        let all = messages + fields
        return all.isEmpty ? nil : all.joined(separator: "; ")
    }

    // MARK: - Alanlar

    /// Jira özeti tek satır ve en fazla 255 karakter olmalı.
    static func summary(_ title: String) -> String {
        String(title.components(separatedBy: .newlines).joined(separator: " ").prefix(255))
    }

    /// Hata kaydı `BugReport.text` ile aynı düzende ve panelin dilinde, Atlassian Document Format olarak.
    static func description(for report: BugReport) -> ADFNode {
        let steps: ADFNode = report.steps.isEmpty
            ? .paragraph([.text(L("(no steps)"))])
            : ADFNode(type: "orderedList", content: report.steps.map {
                ADFNode(type: "listItem", content: [.paragraph([.text($0)])])
            })
        return ADFNode(type: "doc", version: 1, content: [
            ADFNode(type: "heading", attrs: ["level": 3], content: [.text(L("Steps"))]),
            steps,
            .paragraph([.text(L("Expected") + ": ", strong: true), .text(report.expected)]),
            .paragraph([.text(L("Actual") + ": ", strong: true), .text(report.actual)]),
            .paragraph([.text(L("Environment") + ": ", strong: true), .text(report.environment)]),
        ])
    }
}

/// Atlassian Document Format düğümü; boş alanlar JSON'a yazılmaz.
struct ADFNode: Encodable, Equatable {
    struct Mark: Encodable, Equatable {
        let type: String
    }

    var type: String
    var version: Int?
    var attrs: [String: Int]?
    var text: String?
    var marks: [Mark]?
    var content: [ADFNode]?

    static func paragraph(_ content: [ADFNode]) -> ADFNode {
        ADFNode(type: "paragraph", content: content)
    }

    /// ADF boş metin düğümünü kabul etmez.
    static func text(_ text: String, strong: Bool = false) -> ADFNode {
        ADFNode(type: "text", text: text.isEmpty ? "-" : text, marks: strong ? [Mark(type: "strong")] : nil)
    }
}
