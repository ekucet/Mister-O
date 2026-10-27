import Foundation
import Testing
@testable import MisterOCore

/// Gönderilen istekleri kaydeder, sırayla hazır cevapları döner.
actor FakeTransport {
    private var replies: [Result<Data, IssueReporterError>]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Result<Data, IssueReporterError>]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) throws -> Data {
        requests.append(request)
        return try replies.removeFirst().get()
    }
}

struct IssueReporterTests {
    private let screenshot = BugReport.Attachment(filename: "screenshot.png", mimeType: "image/png",
                                                  data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]))
    private let report = BugReport(title: "Geçersiz e-postayla giriş: beklenen davranış görülmedi",
                                   steps: ["type: email_field -> a@", "tap: login_button"],
                                   expected: "Hata görünmeli", actual: "Ana sayfa açıldı", environment: "iPhone · iOS 27")
    private var reportWithScreenshot: BugReport {
        BugReport(title: report.title, steps: report.steps, expected: report.expected, actual: report.actual,
                  environment: report.environment, attachments: [screenshot])
    }

    private func json(_ data: Data?) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
    }

    private func jira(_ transport: FakeTransport? = nil) -> JiraIssueReporter {
        var reporter = JiraIssueReporter(baseURL: URL(string: "https://firma.atlassian.net")!, projectKey: "QA",
                                         authorization: "Basic abc")
        if let transport {
            reporter.send = { try await transport.send($0) }
        }
        return reporter
    }

    // MARK: - Webhook

    @Test func sendsTheReportAsJSON() throws {
        let reporter = WebhookIssueReporter(url: URL(string: "https://example.com/hook")!,
                                            headers: ["X-Automation-Webhook-Token": "secret"])
        let request = try reporter.request(for: report)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Automation-Webhook-Token") == "secret")
        let body = try json(request.httpBody)
        #expect(body["title"] as? String == report.title)
        #expect(body["steps"] as? [String] == report.steps)
        #expect(body["actual"] as? String == "Ana sayfa açıldı")
        #expect((body["description"] as? String)?.contains("2. tap: login_button") == true)
        #expect((body["attachments"] as? [Any])?.isEmpty == true)
    }

    @Test func sendsTheScreenshotAsBase64() throws {
        let body = try json(try WebhookIssueReporter(url: URL(string: "https://example.com/hook")!)
            .request(for: reportWithScreenshot).httpBody)

        // Eski alanlar aynen durur; ek yalnızca `attachments`'a gelir.
        #expect(Set(body.keys) == ["title", "steps", "expected", "actual", "environment", "description", "attachments"])
        #expect(body["expected"] as? String == "Hata görünmeli")
        #expect(body["environment"] as? String == "iPhone · iOS 27")
        let attachments = try #require(body["attachments"] as? [[String: String]])
        #expect(attachments == [[
            "filename": "screenshot.png", "mimeType": "image/png", "data": screenshot.data.base64EncodedString(),
        ]])
    }

    @Test func canLeaveTheScreenshotOut() throws {
        let reporter = WebhookIssueReporter(url: URL(string: "https://example.com/hook")!, includesAttachments: false)
        let body = try json(try reporter.request(for: reportWithScreenshot).httpBody)
        #expect((body["attachments"] as? [Any])?.isEmpty == true)
    }

    @Test func readsTheTicketFromTheResponse() {
        #expect(WebhookIssueReporter.receipt(from: Data(#"{"key": "QA-12", "url": "https://jira/QA-12"}"#.utf8))
                == IssueReceipt(key: "QA-12", url: URL(string: "https://jira/QA-12")))
        #expect(WebhookIssueReporter.receipt(from: Data(#"{"key": "QA-13", "self": "https://jira/rest/13"}"#.utf8)).url
                == URL(string: "https://jira/rest/13"))
        #expect(WebhookIssueReporter.receipt(from: Data("ok".utf8)) == IssueReceipt(key: nil, url: nil))
    }

    @Test func readsReportsWrittenBeforeAttachments() throws {
        let old = Data(#"{"title": "t", "steps": ["a"], "expected": "e", "actual": "g", "environment": "o"}"#.utf8)
        let decoded = try JSONDecoder().decode(BugReport.self, from: old)
        #expect(decoded == BugReport(title: "t", steps: ["a"], expected: "e", actual: "g", environment: "o"))
        #expect(try JSONDecoder().decode(BugReport.self, from: JSONEncoder().encode(reportWithScreenshot))
                == reportWithScreenshot)
    }

    // MARK: - Jira

    @Test func createsTheJiraIssueWithAnADFDescription() throws {
        let request = try jira().issueRequest(for: reportWithScreenshot)

        #expect(request.url?.absoluteString == "https://firma.atlassian.net/rest/api/3/issue")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic abc")

        let body = try json(request.httpBody)
        #expect(Array(body.keys) == ["fields"])
        let fields = try #require(body["fields"] as? [String: Any])
        #expect(Set(fields.keys) == ["project", "issuetype", "summary", "description"])
        #expect(fields["project"] as? [String: String] == ["key": "QA"])
        #expect(fields["issuetype"] as? [String: String] == ["name": "Bug"])
        #expect(fields["summary"] as? String == report.title)

        let description = try #require(fields["description"] as? [String: Any])
        #expect(description["type"] as? String == "doc")
        #expect(description["version"] as? Int == 1)
        let content = try #require(description["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["heading", "orderedList", "paragraph", "paragraph", "paragraph"])
        #expect(content[0]["attrs"] as? [String: Int] == ["level": 3])

        let items = try #require(content[1]["content"] as? [[String: Any]])
        let stepTexts = items.compactMap { item in
            ((item["content"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?.first?["text"] as? String
        }
        #expect(stepTexts == report.steps)

        let expected = try #require(content[2]["content"] as? [[String: Any]])
        #expect(Set(expected[0].keys) == ["type", "text", "marks"])   // boş alanlar yazılmaz
        #expect(expected[0]["marks"] as? [[String: String]] == [["type": "strong"]])
        #expect(expected.map { $0["text"] as? String } == ["Expected: ", "Hata görünmeli"])
        #expect(expected[1]["marks"] == nil)
    }

    @Test func keepsTheJiraFieldsValid() {
        // Özet tek satır ve en fazla 255 karakter; ADF boş metin ve boş liste kabul etmez.
        #expect(JiraIssueReporter.summary("a\nb") == "a b")
        #expect(JiraIssueReporter.summary(String(repeating: "x", count: 300)).count == 255)

        let bare = BugReport(title: "t", steps: [], expected: "", actual: "g", environment: "o")
        let content = JiraIssueReporter.description(for: bare).content ?? []
        #expect(content[1] == .paragraph([.text("(no steps)")]))
        #expect(content[2] == .paragraph([.text("Expected: ", strong: true), .text("-")]))
    }

    @Test func uploadsAttachmentsAsMultipart() {
        let request = jira().attachmentRequest(for: [screenshot], issueKey: "QA-7", boundary: "B")

        #expect(request.url?.absoluteString == "https://firma.atlassian.net/rest/api/3/issue/QA-7/attachments")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        #expect(request.value(forHTTPHeaderField: "X-Atlassian-Token") == "no-check")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic abc")

        var expected = Data("""
        --B\r
        Content-Disposition: form-data; name="file"; filename="screenshot.png"\r
        Content-Type: image/png\r
        \r

        """.utf8)
        expected.append(screenshot.data)
        expected.append(Data("\r\n--B--\r\n".utf8))
        #expect(request.httpBody == expected)
    }

    @Test func readsTheJiraIssueAndLinksToItsPage() {
        let created = Data(#"{"id": "10000", "key": "QA-7", "self": "https://firma.atlassian.net/rest/api/3/issue/10000"}"#.utf8)
        #expect(jira().receipt(from: created)
                == IssueReceipt(key: "QA-7", url: URL(string: "https://firma.atlassian.net/browse/QA-7")))
        #expect(jira().receipt(from: Data(#"{"id": "1", "self": "https://firma.atlassian.net/rest/api/3/issue/1"}"#.utf8))
                == IssueReceipt(key: nil, url: URL(string: "https://firma.atlassian.net/rest/api/3/issue/1")))
        #expect(jira().receipt(from: Data()) == IssueReceipt(key: nil, url: nil))
    }

    @Test func readsJiraErrors() {
        let body = Data(#"{"errorMessages": ["Proje bulunamadı"], "errors": {"summary": "Gerekli", "issuetype": "Geçersiz"}}"#.utf8)
        #expect(JiraIssueReporter.errorMessage(from: body) == "Proje bulunamadı; issuetype: Geçersiz; summary: Gerekli")
        #expect(JiraIssueReporter.errorMessage(from: Data(#"{"errorMessages": [], "errors": {}}"#.utf8)) == nil)
        #expect(JiraIssueReporter.errorMessage(from: Data("<html>".utf8)) == nil)
        #expect(IssueReporterError.rejected(status: 400, message: "issuetype: Geçersiz").localizedDescription
                == "Couldn't open the ticket: the server returned 400 (issuetype: Geçersiz).")
    }

    @Test func buildsTheBasicAuthorizationValue() {
        #expect(JiraIssueReporter.basicAuthorization(email: "qa@firma.com", apiToken: "tok")
                == "Basic " + Data("qa@firma.com:tok".utf8).base64EncodedString())
    }

    @Test func opensTheJiraIssueThenUploadsTheScreenshot() async throws {
        let transport = FakeTransport([.success(Data(#"{"id": "10000", "key": "QA-7", "self": "x"}"#.utf8)),
                                       .success(Data("[]".utf8))])
        let receipt = try await jira(transport).open(reportWithScreenshot)

        #expect(receipt == IssueReceipt(key: "QA-7", url: URL(string: "https://firma.atlassian.net/browse/QA-7")))
        #expect(await transport.requests.map { $0.url?.path } == ["/rest/api/3/issue", "/rest/api/3/issue/QA-7/attachments"])
    }

    @Test func keepsTheJiraIssueWhenTheUploadFails() async throws {
        let transport = FakeTransport([.success(Data(#"{"key": "QA-8"}"#.utf8)),
                                       .failure(.rejected(status: 413, message: "Dosya çok büyük"))])
        let receipt = try await jira(transport).open(reportWithScreenshot)

        // Kayıt açıldı sayılır; testçi tekrar basıp ikinci kayıt açmasın.
        #expect(receipt.key == "QA-8")
        #expect(receipt.warning == "Attachments weren't uploaded: the server returned 413 (Dosya çok büyük).")
    }

    @Test func skipsTheUploadWithoutAttachments() async throws {
        let transport = FakeTransport([.success(Data(#"{"key": "QA-9"}"#.utf8))])
        _ = try await jira(transport).open(report)
        #expect(await transport.requests.count == 1)
    }

    @Test func reportsJiraRejectingTheIssue() async {
        let transport = FakeTransport([.failure(.rejected(status: 400, message: "issuetype: Geçersiz"))])
        await #expect(throws: IssueReporterError.rejected(status: 400, message: "issuetype: Geçersiz")) {
            try await jira(transport).open(reportWithScreenshot)
        }
        #expect(await transport.requests.count == 1)
    }

    // MARK: - Tekilleştirme

    @Test func fingerprintGoesToTheWebhookAndBecomesAJiraLabel() throws {
        let fingerprinted = BugReport(title: "t", steps: [], expected: "e", actual: "a", environment: "env",
                                      fingerprint: "3fc8")
        let webhook = try json(WebhookIssueReporter(url: URL(string: "https://example.com/hook")!)
            .request(for: fingerprinted).httpBody)
        #expect(webhook["fingerprint"] as? String == "3fc8")

        let fields = try #require(try json(jira().issueRequest(for: fingerprinted).httpBody)["fields"] as? [String: Any])
        #expect(fields["labels"] as? [String] == ["mistero", "mistero-3fc8"])
        let plain = try #require(try json(jira().issueRequest(for: report).httpBody)["fields"] as? [String: Any])
        #expect(plain["labels"] == nil)
    }

    @Test func jiraFindsTheOpenIssueByLabel() async throws {
        let transport = FakeTransport([
            .success(Data(#"{"issues":[{"id":"1","key":"QA-9"}],"isLast":true}"#.utf8)),
            .success(Data(#"{"issues":[],"isLast":true}"#.utf8)),
        ])
        let reporter = jira(transport)

        #expect(try await reporter.existingIssue(fingerprint: "3fc8")
                == IssueReceipt(key: "QA-9", url: URL(string: "https://firma.atlassian.net/browse/QA-9"), isExisting: true))
        #expect(try await reporter.existingIssue(fingerprint: "3fc8") == nil)

        let request = try #require(await transport.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/rest/api/3/search/jql")
        #expect(components.queryItems?.first { $0.name == "jql" }?.value
                == #"project = "QA" AND labels = "mistero-3fc8" AND statusCategory != Done ORDER BY created DESC"#)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic abc")
    }

}
