import Foundation
import Testing
@testable import MisterOCore

struct IssueReporterTests {
    private let report = BugReport(title: "Geçersiz e-postayla giriş: beklenen davranış görülmedi",
                                   steps: ["type: email_field -> a@", "tap: login_button"],
                                   expected: "Hata görünmeli", actual: "Ana sayfa açıldı", environment: "iPhone · iOS 27")

    @Test func sendsTheReportAsJSON() throws {
        let reporter = WebhookIssueReporter(url: URL(string: "https://example.com/hook")!,
                                            headers: ["X-Automation-Webhook-Token": "secret"])
        let request = try reporter.request(for: report)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Automation-Webhook-Token") == "secret")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["title"] as? String == report.title)
        #expect(body["steps"] as? [String] == report.steps)
        #expect(body["actual"] as? String == "Ana sayfa açıldı")
        #expect((body["description"] as? String)?.contains("2. tap: login_button") == true)
    }

    @Test func readsTheTicketFromTheResponse() {
        #expect(WebhookIssueReporter.receipt(from: Data(#"{"key": "QA-12", "url": "https://jira/QA-12"}"#.utf8))
                == IssueReceipt(key: "QA-12", url: URL(string: "https://jira/QA-12")))
        #expect(WebhookIssueReporter.receipt(from: Data(#"{"key": "QA-13", "self": "https://jira/rest/13"}"#.utf8)).url
                == URL(string: "https://jira/rest/13"))
        #expect(WebhookIssueReporter.receipt(from: Data("ok".utf8)) == IssueReceipt(key: nil, url: nil))
    }
}
